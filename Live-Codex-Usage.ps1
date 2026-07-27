<#
Live-Codex-Usage.ps1

Local-only monitor for Codex JSONL usage events. It reads only token_count
records from the local Codex session logs; it does not send data anywhere and
does not save prompts, tool input, or transcript content.

Examples:
  powershell -NoProfile -File .\Live-Codex-Usage.ps1
  powershell -NoProfile -File .\Live-Codex-Usage.ps1 -PollSeconds 5 -WarnTurnTokens 250000 -WarnMinuteTokens 500000
  powershell -NoProfile -File .\Live-Codex-Usage.ps1 -StartFresh

Press Ctrl+C to stop.
#>
[CmdletBinding()]
param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [ValidateRange(1, 60)]
    [int]$PollSeconds = 5,
    [ValidateRange(1, 100000000)]
    [int]$WarnTurnTokens = 250000,
    [ValidateRange(1, 100000000)]
    [int]$WarnMinuteTokens = 500000,
    [ValidateRange(1, 100)]
    [int]$ShowEvents = 25,
    [switch]$StartFresh,
    [switch]$Once,
    [switch]$Help
)

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sessionRoot = Join-Path $CodexHome 'sessions'

if (-not (Test-Path -LiteralPath $sessionRoot -PathType Container)) {
    throw "Codex session-log folder was not found: $sessionRoot"
}

function Get-ValueByName {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string] -and $Object -isnot [pscustomobject]) {
        foreach ($item in $Object) {
            $found = Get-ValueByName -Object $item -Name $Name
            if ($null -ne $found) { return $found }
        }
        return $null
    }
    if ($Object -is [pscustomobject]) {
        foreach ($property in $Object.PSObject.Properties) {
            if ($property.Name -eq $Name) { return $property.Value }
        }
        foreach ($property in $Object.PSObject.Properties) {
            $found = Get-ValueByName -Object $property.Value -Name $Name
            if ($null -ne $found) { return $found }
        }
    }
    return $null
}

function Get-Number {
    param([object]$Value)
    if ($null -eq $Value) { return [int64]0 }
    try { return [int64]$Value } catch { return [int64]0 }
}

function Get-UsageEvent {
    param([string]$Line, [string]$SourceFile)
    if ($Line -notmatch 'token_count') { return $null }
    try { $record = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }

    if ($null -eq $record.payload -or $record.payload.type -ne 'token_count') { return $null }

    # Prefer last_token_usage: it is a per-turn delta, unlike cumulative totals.
    $usage = $record.payload.info.last_token_usage
    $kind = 'turn'
    if ($null -eq $usage) {
        $usage = $record.payload.info.total_token_usage
        $kind = 'cumulative snapshot'
    }
    if ($null -eq $usage) { return $null }

    $timestamp = $record.timestamp
    $observed = Get-Date
    if ($timestamp) {
        try { $observed = [datetimeoffset]::Parse([string]$timestamp).LocalDateTime } catch { }
    }

    [pscustomobject]@{
        At        = $observed
        Kind      = $kind
        Input     = Get-Number $usage.input_tokens
        Cached    = Get-Number $usage.cached_input_tokens
        Output    = Get-Number $usage.output_tokens
        Reasoning = Get-Number $usage.reasoning_output_tokens
        Total     = Get-Number $usage.total_tokens
        RateLimits = $record.payload.rate_limits
        Source    = $SourceFile
    }
}

function Format-Tokens {
    param([int64]$Value)
    if ($Value -ge 1000000) { return ('{0:N2}M' -f ($Value / 1000000.0)) }
    if ($Value -ge 1000) { return ('{0:N1}K' -f ($Value / 1000.0)) }
    return ('{0:N0}' -f $Value)
}

function Get-LineFingerprint {
    param([string]$Line)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Line)
        return [Convert]::ToBase64String($hasher.ComputeHash($bytes))
    }
    finally {
        $hasher.Dispose()
    }
}

function Get-QuotaLine {
    param([object]$RateLimits)
    if ($null -eq $RateLimits) { return 'Quota: waiting for a rate-limit update' }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('primary', 'secondary')) {
        $window = Get-ValueByName -Object $RateLimits -Name $name
        if ($null -eq $window) { continue }
        $used = Get-ValueByName -Object $window -Name 'used_percent'
        if ($null -eq $used) { $used = Get-ValueByName -Object $window -Name 'usage_percent' }
        $reset = Get-ValueByName -Object $window -Name 'reset_at'
        $label = if ($name -eq 'primary') { 'Session' } else { 'Weekly' }
        if ($null -ne $used) {
            $part = '{0}: {1:N0}%' -f $label, ([double]$used)
            if ($reset) { $part += " (reset $reset)" }
            $parts.Add($part)
        }
    }
    if ($parts.Count -eq 0) {
        $plan = Get-ValueByName -Object $RateLimits -Name 'plan_type'
        $credits = Get-ValueByName -Object $RateLimits -Name 'credits'
        $balance = if ($null -ne $credits) { Get-ValueByName -Object $credits -Name 'balance' } else { $null }
        $suffix = ''
        if ($plan) { $suffix += " Plan: $plan." }
        if ($null -ne $balance) { $suffix += " Credits: $balance." }
        return 'Quota: no active rate-limit percentage in this event.' + $suffix
    }
    return 'Quota: ' + ($parts -join ' | ')
}

function Get-SessionLogFiles {
    # Use .NET enumeration rather than Get-ChildItem. In this managed profile,
    # the PowerShell provider does not enumerate these hidden session files.
    [System.IO.Directory]::EnumerateFiles(
        $sessionRoot,
        '*.jsonl',
        [System.IO.SearchOption]::AllDirectories
    ) | ForEach-Object { [System.IO.FileInfo]$_ }
}

$seen = @{}
$events = [System.Collections.Generic.List[object]]::new()
$latestQuota = $null
$start = Get-Date

if ($StartFresh) {
    Get-SessionLogFiles |
        ForEach-Object {
            Get-Content -LiteralPath $_.FullName -Tail 100 -ErrorAction SilentlyContinue | ForEach-Object {
                $seen[(Get-LineFingerprint $_)] = $true
            }
        }
}

Write-Host 'Live Codex usage monitor started. Ctrl+C stops it.' -ForegroundColor Cyan
Write-Host "Polling local logs every $PollSeconds seconds; no content is stored or sent." -ForegroundColor DarkCyan

while ($true) {
    $files = Get-SessionLogFiles |
        Where-Object { $_.LastWriteTime -ge (Get-Date).AddMinutes(-20) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 8

    foreach ($file in $files) {
        Get-Content -LiteralPath $file.FullName -Tail 150 -ErrorAction SilentlyContinue | ForEach-Object {
            $line = $_
            if ($line -notmatch 'token_count') { return }
            $hash = Get-LineFingerprint $line
            if ($seen.ContainsKey($hash)) { return }
            $seen[$hash] = $true
            $event = Get-UsageEvent -Line $line -SourceFile $file.FullName
            if ($null -ne $event) {
                $events.Add($event)
                if ($null -ne $event.RateLimits) { $latestQuota = $event.RateLimits }
            }
        }
    }

    $cutoff = (Get-Date).AddMinutes(-30)
    $events = [System.Collections.Generic.List[object]]@($events | Where-Object { $_.At -ge $cutoff })
    $minuteCutoff = (Get-Date).AddMinutes(-1)
    $recent = @($events | Where-Object { $_.At -ge $minuteCutoff -and $_.Kind -eq 'turn' })
    $allTurns = @($events | Where-Object { $_.Kind -eq 'turn' })
    $last = if ($allTurns.Count -gt 0) { @($allTurns | Sort-Object At)[-1] } else { $null }
    $minuteMeasure = $recent | Measure-Object -Property Total -Sum
    $runningMeasure = $allTurns | Measure-Object -Property Total -Sum
    $minuteTotal = if ($null -eq $minuteMeasure -or $null -eq $minuteMeasure.Sum) { [int64]0 } else { [int64]$minuteMeasure.Sum }
    $runningTotal = if ($null -eq $runningMeasure -or $null -eq $runningMeasure.Sum) { [int64]0 } else { [int64]$runningMeasure.Sum }

    Clear-Host
    Write-Host 'LIVE CODEX USAGE - local logs only' -ForegroundColor Cyan
    Write-Host ("Started: {0} | Refresh: {1}s | Events seen: {2}" -f $start.ToString('HH:mm:ss'), $PollSeconds, $events.Count)
    Write-Host ''
    if ($null -eq $last) {
        Write-Host 'Waiting for the next completed Codex turn with a token_count event...' -ForegroundColor Yellow
    } else {
        $turnColor = if ($last.Total -ge $WarnTurnTokens) { 'Red' } else { 'Green' }
        $newInput = [Math]::Max([int64]0, ($last.Input - $last.Cached))
        Write-Host ("Latest turn ({0}, {1}): {2}" -f $last.At.ToString('HH:mm:ss'), $last.Kind, (Format-Tokens $last.Total)) -ForegroundColor $turnColor
        Write-Host ("  Input {0} | Cached subset {1} | New input {2} | Output {3} | Reasoning {4}" -f (Format-Tokens $last.Input), (Format-Tokens $last.Cached), (Format-Tokens $newInput), (Format-Tokens $last.Output), (Format-Tokens $last.Reasoning))
        Write-Host ("Observed in monitor window: {0}" -f (Format-Tokens $runningTotal))
        $minuteColor = if ($minuteTotal -ge $WarnMinuteTokens) { 'Red' } else { 'Green' }
        Write-Host ("Last 60 seconds: {0}" -f (Format-Tokens $minuteTotal)) -ForegroundColor $minuteColor
        if ($last.Total -ge $WarnTurnTokens -or $minuteTotal -ge $WarnMinuteTokens) {
            Write-Host 'WARNING: Token burn threshold exceeded. Pause before sending more large-context work.' -ForegroundColor Red
        }
    }
    Write-Host ''
    Write-Host ("Recent token events (latest {0}; all sizes):" -f $ShowEvents) -ForegroundColor Cyan
    @($events | Sort-Object At -Descending | Select-Object -First $ShowEvents) | ForEach-Object {
        $newInput = [Math]::Max([int64]0, ($_.Input - $_.Cached))
        $file = Split-Path -Leaf $_.Source
        $source = if ($file.Length -gt 28) { $file.Substring(0, 28) + '...' } else { $file }
        Write-Host ("  {0} | total {1} | in {2} (cached {3}, new {4}) | out {5} | {6}" -f $_.At.ToString('HH:mm:ss'), (Format-Tokens $_.Total), (Format-Tokens $_.Input), (Format-Tokens $_.Cached), (Format-Tokens $newInput), (Format-Tokens $_.Output), $source)
    }
    Write-Host ''
    Write-Host (Get-QuotaLine -RateLimits $latestQuota) -ForegroundColor Magenta
    Write-Host 'Note: cached input is a subset of input, not an additional amount. This is local telemetry, not an OpenAI invoice.' -ForegroundColor DarkGray

    # Keep dedup state bounded during long-running use.
    if ($seen.Count -gt 10000) { $seen = @{} }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
}
