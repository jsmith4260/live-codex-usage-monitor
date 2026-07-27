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
    [bool]$IncludeArchivedSessions = $true,
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
$sessionRoots = [System.Collections.Generic.List[string]]::new()
foreach ($folderName in @('sessions', 'archived_sessions')) {
    if ($folderName -eq 'archived_sessions' -and -not $IncludeArchivedSessions) { continue }
    $candidate = Join-Path $CodexHome $folderName
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $sessionRoots.Add($candidate)
    }
}

if ($sessionRoots.Count -eq 0) {
    throw "No Codex session-log folder was found under: $CodexHome"
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
        Fresh     = [Math]::Max([int64]0, ((Get-Number $usage.input_tokens) - (Get-Number $usage.cached_input_tokens))) + (Get-Number $usage.output_tokens)
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

function ConvertTo-ResetDateTime {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToLocalTime() }
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).LocalDateTime }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    [int64]$epoch = 0
    if ([int64]::TryParse($text, [ref]$epoch)) {
        try {
            if ([Math]::Abs($epoch) -ge 100000000000) {
                return [datetimeoffset]::FromUnixTimeMilliseconds($epoch).LocalDateTime
            }
            return [datetimeoffset]::FromUnixTimeSeconds($epoch).LocalDateTime
        }
        catch { return $null }
    }

    try { return [datetimeoffset]::Parse($text).LocalDateTime } catch { return $null }
}

function Format-ResetTime {
    param([object]$Value)

    $resetAt = ConvertTo-ResetDateTime -Value $Value
    if ($null -eq $resetAt) { return '' }
    $remaining = $resetAt - (Get-Date)
    if ($remaining.TotalMinutes -le 0) { return 'reset metadata expired' }
    if ($remaining.TotalDays -ge 1) {
        return 'resets in {0}d {1}h' -f [Math]::Floor($remaining.TotalDays), $remaining.Hours
    }
    if ($remaining.TotalHours -ge 1) {
        return 'resets in {0}h {1}m' -f [Math]::Floor($remaining.TotalHours), $remaining.Minutes
    }
    return 'resets in {0}m' -f [Math]::Max(1, [Math]::Ceiling($remaining.TotalMinutes))
}

function Get-LineFingerprint {
    param([string]$Line, [string]$SourceFile = '')
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($SourceFile + [char]0 + $Line)
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
            $resetText = Format-ResetTime -Value $reset
            if ($resetText) { $part += " ($resetText)" }
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
    foreach ($root in $sessionRoots) {
        [System.IO.Directory]::EnumerateFiles(
            $root,
            '*.jsonl',
            [System.IO.SearchOption]::AllDirectories
        ) | ForEach-Object { [System.IO.FileInfo]$_ }
    }
}

$seen = @{}
$events = [System.Collections.Generic.List[object]]::new()
$start = Get-Date

if ($StartFresh) {
    Get-SessionLogFiles |
        ForEach-Object {
            $sessionFile = $_.FullName
            Get-Content -LiteralPath $sessionFile -Tail 100 -ErrorAction SilentlyContinue | ForEach-Object {
                $seen[(Get-LineFingerprint -Line $_ -SourceFile $sessionFile)] = $true
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
            $hash = Get-LineFingerprint -Line $line -SourceFile $file.FullName
            if ($seen.ContainsKey($hash)) { return }
            $seen[$hash] = $true
            $usageEvent = Get-UsageEvent -Line $line -SourceFile $file.FullName
            if ($null -ne $usageEvent) {
                $usageEvent | Add-Member -NotePropertyName EventId -NotePropertyValue $hash
                $events.Add($usageEvent)
            }
        }
    }

    $cutoff = (Get-Date).AddMinutes(-30)
    $events = [System.Collections.Generic.List[object]]@($events | Where-Object { $_.At -ge $cutoff })
    $minuteCutoff = (Get-Date).AddMinutes(-1)
    $recent = @($events | Where-Object { $_.At -ge $minuteCutoff -and $_.Kind -eq 'turn' })
    $allTurns = @($events | Where-Object { $_.Kind -eq 'turn' })
    $last = if ($allTurns.Count -gt 0) { @($allTurns | Sort-Object At)[-1] } else { $null }
    $quotaEvent = @($events | Where-Object { $null -ne $_.RateLimits } | Sort-Object At -Descending | Select-Object -First 1)
    $latestQuota = if ($quotaEvent.Count -gt 0) { $quotaEvent[0].RateLimits } else { $null }
    $minuteMeasure = $recent | Measure-Object -Property Fresh -Sum
    $runningMeasure = $allTurns | Measure-Object -Property Fresh -Sum
    $minuteTotal = if ($null -eq $minuteMeasure -or $null -eq $minuteMeasure.Sum) { [int64]0 } else { [int64]$minuteMeasure.Sum }
    $runningTotal = if ($null -eq $runningMeasure -or $null -eq $runningMeasure.Sum) { [int64]0 } else { [int64]$runningMeasure.Sum }

    Clear-Host
    Write-Host 'LIVE CODEX USAGE - local logs only' -ForegroundColor Cyan
    Write-Host ("Started: {0} | Refresh: {1}s | Events seen: {2}" -f $start.ToString('HH:mm:ss'), $PollSeconds, $events.Count)
    Write-Host ''
    if ($null -eq $last) {
        Write-Host 'Waiting for the next completed Codex turn with a token_count event...' -ForegroundColor Yellow
    } else {
        $turnColor = if ($last.Fresh -ge $WarnTurnTokens) { 'Red' } else { 'Green' }
        $newInput = [Math]::Max([int64]0, ($last.Input - $last.Cached))
        Write-Host ("Latest turn ({0}, {1}): fresh {2} | context {3}" -f $last.At.ToString('HH:mm:ss'), $last.Kind, (Format-Tokens $last.Fresh), (Format-Tokens $last.Total)) -ForegroundColor $turnColor
        Write-Host ("  Input {0} | Cached subset {1} | New input {2} | Output {3} | Reasoning subset {4}" -f (Format-Tokens $last.Input), (Format-Tokens $last.Cached), (Format-Tokens $newInput), (Format-Tokens $last.Output), (Format-Tokens $last.Reasoning))
        Write-Host ("Observed fresh usage in monitor window: {0}" -f (Format-Tokens $runningTotal))
        $minuteColor = if ($minuteTotal -ge $WarnMinuteTokens) { 'Red' } else { 'Green' }
        Write-Host ("Last 60 seconds: {0}" -f (Format-Tokens $minuteTotal)) -ForegroundColor $minuteColor
        if ($last.Fresh -ge $WarnTurnTokens -or $minuteTotal -ge $WarnMinuteTokens) {
            Write-Host 'WARNING: Token burn threshold exceeded. Pause before sending more large-context work.' -ForegroundColor Red
        }
    }
    Write-Host ''
    Write-Host ("Recent token events (latest {0}; all sizes):" -f $ShowEvents) -ForegroundColor Cyan
    @($events | Sort-Object At -Descending | Select-Object -First $ShowEvents) | ForEach-Object {
        $newInput = [Math]::Max([int64]0, ($_.Input - $_.Cached))
        $file = Split-Path -Leaf $_.Source
        $source = if ($file.Length -gt 28) { $file.Substring(0, 28) + '...' } else { $file }
        Write-Host ("  {0} | fresh {1} | context {2} | in {3} (cached {4}, new {5}) | out {6} | {7}" -f $_.At.ToString('HH:mm:ss'), (Format-Tokens $_.Fresh), (Format-Tokens $_.Total), (Format-Tokens $_.Input), (Format-Tokens $_.Cached), (Format-Tokens $newInput), (Format-Tokens $_.Output), $source)
    }
    Write-Host ''
    Write-Host (Get-QuotaLine -RateLimits $latestQuota) -ForegroundColor Magenta
    Write-Host 'Note: cached input is a subset of input, not an additional amount. This is local telemetry, not an OpenAI invoice.' -ForegroundColor DarkGray

    # Keep dedup state bounded during long-running use.
    if ($seen.Count -gt 10000) {
        $seen = @{}
        foreach ($usageEvent in $events) { $seen[$usageEvent.EventId] = $true }
    }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
}
