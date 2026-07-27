<#
Live-Codex-Usage-GUI.ps1

Native local Windows dashboard for Codex token events. It is read-only: it
reads local Codex session JSONL files and does not write files, invoke Codex,
call ChatGPT, or contact any network service. It does not display prompt text,
responses, tool arguments, tool output, credentials, or working-directory paths.

Run:
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -StartMini
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -InitialView "All sessions" -HistoryHours 48

Optional QA (no window):
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -Once
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -UiSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -MiniSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -IntegrationSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -TaskSmokeTest
#>
[CmdletBinding()]
param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [ValidateRange(1, 60)]
    [int]$PollSeconds = 5,
    [ValidateRange(1, 168)]
    [int]$HistoryHours = 24,
    [ValidateSet('Follow latest', 'Pinned session', 'All sessions')]
    [string]$InitialView = 'All sessions',
    [switch]$StartMini,
    [ValidateRange(1, 100000000)]
    [int]$WarnNewInputTokens = 25000,
    [ValidateRange(1, 100000000)]
    [int]$WarnMinuteFreshTokens = 50000,
    [ValidateRange(1, 100000000)]
    [int]$WarnContextTokens = 150000,
    [ValidateRange(1, 100000000)]
    [int]$WarnOutputTokens = 5000,
    [ValidateRange(1, 100000000)]
    [int]$WarnReasoningTokens = 5000,
    [switch]$NoNotifications,
    [switch]$NoSound,
    [switch]$Once,
    [switch]$UiSmokeTest,
    [switch]$MiniSmokeTest,
    [switch]$IntegrationSmokeTest,
    [switch]$TaskSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
$sessionRoot = Join-Path $CodexHome 'sessions'
if (-not (Test-Path -LiteralPath $sessionRoot -PathType Container)) {
    throw "Codex session-log folder was not found: $sessionRoot"
}

$script:seen = @{}
$script:activitySeen = @{}
$script:events = [System.Collections.Generic.List[object]]::new()
$script:activityEvents = [System.Collections.Generic.List[object]]::new()
$script:integrationEvents = [System.Collections.Generic.List[object]]::new()
$script:sessionInfo = @{}
$script:lastAlertEventId = ''
$script:latestSource = $null
$script:latestSession = $null
$script:pinnedSource = $null
$script:focusedSession = $null
$script:focusedEventId = $null
$script:viewMode = $InitialView
$script:notifyIcon = $null
$script:isMiniMode = $false
$script:isRefreshing = $false
$script:startedAt = Get-Date

function Format-Tokens {
    param([int64]$Value)
    if ($Value -ge 1000000) { return ('{0:N2}M' -f ($Value / 1000000.0)) }
    if ($Value -ge 1000) { return ('{0:N1}K' -f ($Value / 1000.0)) }
    return ('{0:N0}' -f $Value)
}

function Get-Number {
    param([object]$Value)
    if ($null -eq $Value) { return [int64]0 }
    try { return [int64]$Value } catch { return [int64]0 }
}

function Get-ObjectProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
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

function Get-ShortValue {
    param([object]$Value, [int]$MaxLength = 60)
    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) {
        if ($Value.Length -gt $MaxLength) { return $Value.Substring(0, $MaxLength) + '...' }
        return $Value
    }
    $mode = Get-ObjectProperty -Object $Value -Name 'mode'
    if ($mode) { return Get-ShortValue -Value $mode -MaxLength $MaxLength }
    $type = Get-ObjectProperty -Object $Value -Name 'type'
    if ($type) { return Get-ShortValue -Value $type -MaxLength $MaxLength }
    try {
        $text = $Value | ConvertTo-Json -Compress -Depth 4
        if ($text.Length -gt $MaxLength) { return $text.Substring(0, $MaxLength) + '...' }
        return $text
    }
    catch {
        return [string]$Value
    }
}

function Get-SessionInfoRecord {
    param([string]$SourceFile)
    if (-not $script:sessionInfo.ContainsKey($SourceFile)) {
        $script:sessionInfo[$SourceFile] = [pscustomobject]@{
            Model = ''
            Effort = ''
            ApprovalPolicy = ''
            ApprovalsReviewer = ''
            Sandbox = ''
            ContextWindow = ''
            Title = ''
            UpdatedAt = $null
        }
    }
    return $script:sessionInfo[$SourceFile]
}

function Get-SafeTaskTitle {
    param([object]$Text, [int]$MaxLength = 76)
    if ($null -eq $Text) { return '' }
    $value = [string]$Text
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    $requestMarker = '## My request for Codex:'
    $markerIndex = $value.IndexOf($requestMarker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($markerIndex -ge 0) {
        $value = $value.Substring($markerIndex + $requestMarker.Length)
    }
    $imageIndex = $value.IndexOf('<image ', [System.StringComparison]::OrdinalIgnoreCase)
    if ($imageIndex -ge 0) {
        $value = $value.Substring(0, $imageIndex)
    }
    $value = ($value -replace '\s+', ' ').Trim()
    if ($value.Length -gt $MaxLength) { return $value.Substring(0, $MaxLength - 3) + '...' }
    return $value
}

function Test-IsSyntheticTaskTitle {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return $true }
    if ($Title -match '^# AGENTS\.md instructions') { return $true }
    if ($Title -match '^<environment_context>') { return $true }
    if ($Title -match '^<permissions instructions>') { return $true }
    if ($Title -match '^The following is the Codex agent history') { return $true }
    if ($Title -match '<INSTRUCTIONS>|</INSTRUCTIONS>|<filesystem>|</filesystem>|<workspace_roots>|permission_profile|current_date|timezone') { return $true }
    if ($Title -match '^Message Type:|^Task name:|^Sender:|^Payload:') { return $true }
    return $false
}

function Update-TaskTitleFromLine {
    param([string]$Line, [string]$SourceFile)

    if ($Line -notmatch 'user_message|\"role\":\"user\"') { return }
    $info = Get-SessionInfoRecord -SourceFile $SourceFile
    if (-not [string]::IsNullOrWhiteSpace($info.Title) -and -not (Test-IsSyntheticTaskTitle -Title $info.Title)) { return }

    try { $record = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return }
    $recordType = [string](Get-ObjectProperty -Object $record -Name 'type')
    $payload = Get-ObjectProperty -Object $record -Name 'payload'
    if ($null -eq $payload) { return }

    $title = ''
    $payloadType = [string](Get-ObjectProperty -Object $payload -Name 'type')
    if ($recordType -eq 'event_msg' -and $payloadType -eq 'user_message') {
        $title = Get-SafeTaskTitle (Get-ObjectProperty -Object $payload -Name 'message')
    }
    elseif ($recordType -eq 'response_item') {
        $role = [string](Get-ObjectProperty -Object $payload -Name 'role')
        if ($role -ne 'user') { return }
        $content = Get-ObjectProperty -Object $payload -Name 'content'
        foreach ($item in @($content)) {
            $candidate = Get-SafeTaskTitle (Get-ObjectProperty -Object $item -Name 'text')
            if (-not $candidate) { $candidate = Get-SafeTaskTitle (Get-ObjectProperty -Object $item -Name 'input_text') }
            if ($candidate) { $title = $candidate; break }
        }
    }

    if ($title -and -not (Test-IsSyntheticTaskTitle -Title $title)) { $info.Title = $title }
}

function Update-SessionInfo {
    param([string]$Line, [string]$SourceFile)

    if ($Line -notmatch 'session_meta|turn_context') { return }
    try { $record = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return }
    $recordType = [string](Get-ObjectProperty -Object $record -Name 'type')
    if ($recordType -ne 'session_meta' -and $recordType -ne 'turn_context') { return }
    $payload = Get-ObjectProperty -Object $record -Name 'payload'
    if ($null -eq $payload) { return }

    $info = Get-SessionInfoRecord -SourceFile $SourceFile
    if ($recordType -eq 'session_meta') {
        $info.ContextWindow = Get-ShortValue (Get-ObjectProperty -Object $payload -Name 'context_window')
    }
    else {
        $info.Model = Get-ShortValue (Get-ObjectProperty -Object $payload -Name 'model')
        $info.Effort = Get-ShortValue (Get-ObjectProperty -Object $payload -Name 'effort')
        $info.ApprovalPolicy = Get-ShortValue (Get-ObjectProperty -Object $payload -Name 'approval_policy')
        $info.ApprovalsReviewer = Get-ShortValue (Get-ObjectProperty -Object $payload -Name 'approvals_reviewer')
        $info.Sandbox = Get-ShortValue (Get-ObjectProperty -Object $payload -Name 'sandbox_policy')
    }
    $info.UpdatedAt = Get-Date
}

function Get-LineFingerprint {
    param([string]$Line)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Line)))
    }
    finally {
        $hasher.Dispose()
    }
}

function Get-SessionName {
    param([string]$Path)
    $name = Split-Path -Leaf $Path
    if ($name.EndsWith('.jsonl')) { $name = $name.Substring(0, $name.Length - 6) }
    if ($name.StartsWith('rollout-')) { $name = $name.Substring(8) }
    return $name
}

function Get-ShortSessionName {
    param([string]$Path, [int]$MaxLength = 34)
    $session = Get-SessionName -Path $Path
    if ($session.Length -gt $MaxLength) { return $session.Substring(0, $MaxLength) + '...' }
    return $session
}

function Get-FriendlyTaskLabel {
    param([string]$Path)
    $info = Get-SessionInfoRecord -SourceFile $Path
    if ($info.Title) { return $info.Title }
    $session = Get-SessionName -Path $Path
    if ($session -match '^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})') {
        $dateText = '{0}-{1}-{2} {3}:{4}:{5}' -f $Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5], $Matches[6]
        try {
            $dt = [datetime]::ParseExact($dateText, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
            $prefix = if ($dt.Date -eq (Get-Date).Date) { 'Today' } else { $dt.ToString('MM-dd') }
            return '{0} {1}' -f $prefix, $dt.ToString('HH:mm')
        }
        catch { }
    }
    return Get-ShortSessionName -Path $Path -MaxLength 24
}

function Get-SessionLogFiles {
    [System.IO.Directory]::EnumerateFiles($sessionRoot, '*.jsonl', [System.IO.SearchOption]::AllDirectories) |
        ForEach-Object { [System.IO.FileInfo]$_ }
}

function Get-RecentLogLines {
    param([string]$Path, [int]$MaxBytes = 131072)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $start = [Math]::Max([int64]0, $stream.Length - $MaxBytes)
        [void]$stream.Seek($start, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true, 4096, $true)
        try {
            $text = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    if ($start -gt 0) {
        $firstNewline = $text.IndexOf("`n")
        if ($firstNewline -ge 0) { $text = $text.Substring($firstNewline + 1) }
    }
    return @($text -split "`r?`n")
}

function Get-InitialLogLines {
    param([string]$Path, [int]$MaxLines = 160)

    $lines = [System.Collections.Generic.List[string]]::new()
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true, 4096, $true)
        try {
            while (-not $reader.EndOfStream -and $lines.Count -lt $MaxLines) {
                $lines.Add($reader.ReadLine())
            }
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
    return @($lines)
}

function Get-RiskLabel {
    param([object]$Event)

    $newInput = [Math]::Max([int64]0, $Event.Input - $Event.Cached)
    $freshBurn = $newInput + [int64]$Event.Output + [int64]$Event.Reasoning
    if ($newInput -ge $WarnNewInputTokens) { return 'Fresh input spike' }
    if ($Event.Reasoning -ge $WarnReasoningTokens) { return 'Reasoning spike' }
    if ($Event.Output -ge $WarnOutputTokens) { return 'Output-heavy' }
    if ($Event.Total -ge $WarnContextTokens -and $Event.Cached -ge ($Event.Input * 0.80)) { return 'Mostly cached context' }
    if ($freshBurn -ge $WarnMinuteFreshTokens) { return 'Fresh burn spike' }
    return 'Normal'
}

function Convert-TokenEvent {
    param([string]$Line, [string]$SourceFile)

    if ($Line -notmatch 'token_count') { return $null }
    try { $record = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($null -eq $record.payload -or $record.payload.type -ne 'token_count') { return $null }

    $usage = $record.payload.info.last_token_usage
    if ($null -eq $usage) { return $null }

    $at = Get-Date
    try { $at = [datetimeoffset]::Parse([string]$record.timestamp).LocalDateTime } catch { }

    $input = Get-Number $usage.input_tokens
    $cached = Get-Number $usage.cached_input_tokens
    $output = Get-Number $usage.output_tokens
    $reasoning = Get-Number $usage.reasoning_output_tokens
    $newInput = [Math]::Max([int64]0, $input - $cached)
    $total = Get-Number $usage.total_tokens
    $eventId = Get-LineFingerprint $Line

    $event = [pscustomobject]@{
        EventId   = $eventId
        At        = $at
        Total     = $total
        Input     = $input
        Cached    = $cached
        NewInput  = $newInput
        Output    = $output
        Reasoning = $reasoning
        FreshBurn = $newInput + $output + $reasoning
        Plan      = $record.payload.rate_limits.plan_type
        RateLimits = $record.payload.rate_limits
        Source    = $SourceFile
        Session   = Get-SessionName -Path $SourceFile
    }
    $event | Add-Member -NotePropertyName Risk -NotePropertyValue (Get-RiskLabel -Event $event)
    return $event
}

function Convert-ActivityEvent {
    param([string]$Line, [string]$SourceFile)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    try { $record = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }

    $at = Get-Date
    try { $at = [datetimeoffset]::Parse([string]$record.timestamp).LocalDateTime } catch { }

    $label = 'LOG'
    $detail = 'local rollout event'
    $recordType = [string](Get-ObjectProperty -Object $record -Name 'type')
    $payloadType = ''
    $payload = Get-ObjectProperty -Object $record -Name 'payload'
    if ($null -ne $payload) {
        $payloadType = [string](Get-ObjectProperty -Object $payload -Name 'type')
    }

    if ($recordType -eq 'turn_context') {
        $label = 'CTX'
        $detail = 'context packaged for a turn'
    }
    elseif ($recordType -eq 'event_msg' -and $payloadType -eq 'token_count') {
        $label = 'TOKEN'
        $detail = 'usage counters updated'
    }
    elseif ($recordType -eq 'event_msg' -and $payloadType -eq 'user_message') {
        $label = 'ASK'
        $detail = 'user request received'
    }
    elseif ($recordType -eq 'event_msg' -and ($payloadType -match 'exec|command|run')) {
        $label = 'RUN'
        $detail = "event: $payloadType"
    }
    elseif ($recordType -eq 'event_msg' -and ($payloadType -match 'patch|edit|file')) {
        $label = 'EDIT'
        $detail = "event: $payloadType"
    }
    elseif ($recordType -eq 'event_msg' -and ($payloadType -match 'error|failed|abort')) {
        $label = 'ERR'
        $detail = "event: $payloadType"
    }
    elseif ($recordType -eq 'event_msg' -and $payloadType) {
        $label = 'LOG'
        $detail = "event: $payloadType"
    }
    elseif ($recordType -eq 'response_item' -and ($Line -match 'function_call|tool_call|custom_tool_call')) {
        $label = 'TOOL'
        $detail = 'tool activity recorded'
    }
    elseif ($recordType -eq 'response_item' -and ($Line -match 'message')) {
        $label = 'MSG'
        $detail = 'assistant message recorded'
    }
    elseif ($recordType -eq 'response_item') {
        $label = 'OUT'
        $detail = 'assistant output item recorded'
    }
    elseif ($recordType) {
        $label = 'LOG'
        $detail = "record: $recordType"
    }

    [pscustomobject]@{
        EventId = Get-LineFingerprint $Line
        At      = $at
        Label   = $label
        Detail  = $detail
        Source  = $SourceFile
        Session = Get-SessionName -Path $SourceFile
    }
}

function Get-IntegrationDisplayName {
    param([string]$Kind, [string]$Name)

    if ($Kind -eq 'Web') { return 'Web search' }
    if ($Kind -eq 'MCP') { return $Name }
    if ($Name -eq 'exec' -or $Name -eq 'shell_command' -or $Name -eq 'exec_command') { return 'Local shell' }
    if ($Name -eq 'apply_patch') { return 'File edits' }
    if ($Name -eq 'update_plan') { return 'Plan updates' }
    if ($Name -eq 'wait') { return 'Wait/monitor' }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $Kind }
    return $Name
}

function Convert-IntegrationEvent {
    param([string]$Line, [string]$SourceFile)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    if ($Line -notmatch 'function_call|custom_tool_call|web_search_call|mcp_tool_call_end') { return $null }
    try { $record = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }

    $recordType = [string](Get-ObjectProperty -Object $record -Name 'type')
    $payload = Get-ObjectProperty -Object $record -Name 'payload'
    $item = Get-ObjectProperty -Object $payload -Name 'item'
    $obj = if ($null -ne $item) { $item } else { $payload }
    if ($null -eq $obj) { return $null }

    $payloadType = [string](Get-ObjectProperty -Object $obj -Name 'type')
    $kind = ''
    $rawName = ''
    $display = ''

    if ($recordType -eq 'response_item' -and $payloadType -eq 'function_call') {
        $kind = 'Function'
        $rawName = [string](Get-ObjectProperty -Object $obj -Name 'name')
    }
    elseif ($recordType -eq 'response_item' -and $payloadType -eq 'custom_tool_call') {
        $kind = 'Custom'
        $rawName = [string](Get-ObjectProperty -Object $obj -Name 'name')
    }
    elseif ($recordType -eq 'response_item' -and $payloadType -eq 'web_search_call') {
        $kind = 'Web'
        $rawName = 'web_search'
    }
    elseif ($recordType -eq 'event_msg' -and $payloadType -eq 'mcp_tool_call_end') {
        $kind = 'MCP'
        $app = [string](Get-ObjectProperty -Object $obj -Name 'app_name')
        $action = [string](Get-ObjectProperty -Object $obj -Name 'action_name')
        if (-not $app) { $app = [string](Get-ValueByName -Object $obj -Name 'server') }
        if (-not $action) { $action = [string](Get-ValueByName -Object $obj -Name 'name') }
        if (-not $app) { $app = [string](Get-ValueByName -Object $obj -Name 'connector_id') }
        if ($app -and $action) { $rawName = "$app.$action" }
        elseif ($app) { $rawName = $app }
        elseif ($action) { $rawName = $action }
        else { $rawName = 'MCP/app tool' }
    }
    else {
        return $null
    }

    if ($payloadType -match '_output$') { return $null }
    if ([string]::IsNullOrWhiteSpace($rawName)) { return $null }
    $display = Get-IntegrationDisplayName -Kind $kind -Name $rawName

    $at = Get-Date
    try { $at = [datetimeoffset]::Parse([string]$record.timestamp).LocalDateTime } catch { }

    [pscustomobject]@{
        EventId = Get-LineFingerprint $Line
        At      = $at
        Kind    = $kind
        Name    = $display
        RawName = $rawName
        Source  = $SourceFile
        Session = Get-SessionName -Path $SourceFile
    }
}

function Update-Events {
    $files = Get-SessionLogFiles |
        Where-Object { $_.LastWriteTime -ge (Get-Date).AddHours(-$HistoryHours) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 30

    foreach ($file in $files) {
        Get-InitialLogLines -Path $file.FullName | ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_)) {
                Update-SessionInfo -Line $_ -SourceFile $file.FullName
                Update-TaskTitleFromLine -Line $_ -SourceFile $file.FullName
            }
        }
        Get-RecentLogLines -Path $file.FullName | ForEach-Object {
            $line = $_
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            Update-SessionInfo -Line $line -SourceFile $file.FullName
            Update-TaskTitleFromLine -Line $line -SourceFile $file.FullName

            $activityFingerprint = Get-LineFingerprint $line
            if (-not $script:activitySeen.ContainsKey($activityFingerprint)) {
                $script:activitySeen[$activityFingerprint] = $true
                $activity = Convert-ActivityEvent -Line $line -SourceFile $file.FullName
                if ($null -ne $activity -and $activity.Label -ne 'LOG') {
                    $script:activityEvents.Add($activity)
                }
                $integration = Convert-IntegrationEvent -Line $line -SourceFile $file.FullName
                if ($null -ne $integration) {
                    $script:integrationEvents.Add($integration)
                }
            }

            if ($line -match 'token_count') {
                $fingerprint = Get-LineFingerprint $line
                if ($script:seen.ContainsKey($fingerprint)) { return }
                $script:seen[$fingerprint] = $true
                $event = Convert-TokenEvent -Line $line -SourceFile $file.FullName
                if ($null -ne $event) {
                    $script:events.Add($event)
                }
            }
        }
    }

    $cutoff = (Get-Date).AddHours(-$HistoryHours)
    $kept = @($script:events | Where-Object { $_.At -ge $cutoff })
    $script:events.Clear()
    foreach ($event in $kept) { $script:events.Add($event) }
    $keptActivity = @($script:activityEvents | Where-Object { $_.At -ge $cutoff })
    $script:activityEvents.Clear()
    foreach ($activity in $keptActivity) { $script:activityEvents.Add($activity) }
    $keptIntegrations = @($script:integrationEvents | Where-Object { $_.At -ge $cutoff })
    $script:integrationEvents.Clear()
    foreach ($integration in $keptIntegrations) { $script:integrationEvents.Add($integration) }
    if ($script:seen.Count -gt 10000) {
        $rebuilt = @{}
        foreach ($event in $script:events) { $rebuilt[$event.EventId] = $true }
        $script:seen = $rebuilt
    }
    if ($script:activitySeen.Count -gt 10000) {
        $rebuiltActivity = @{}
        foreach ($activity in $script:activityEvents) { $rebuiltActivity[$activity.EventId] = $true }
        $script:activitySeen = $rebuiltActivity
    }
}

function Reset-MonitorWindow {
    $script:events.Clear()
    $script:activityEvents.Clear()
    $script:integrationEvents.Clear()
    $script:seen.Clear()
    $script:activitySeen.Clear()
    $files = Get-SessionLogFiles |
        Where-Object { $_.LastWriteTime -ge (Get-Date).AddHours(-$HistoryHours) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 30

    foreach ($file in $files) {
        Get-RecentLogLines -Path $file.FullName | ForEach-Object {
            if ($_ -match 'token_count') { $script:seen[(Get-LineFingerprint $_)] = $true }
            $script:activitySeen[(Get-LineFingerprint $_)] = $true
        }
    }
    $script:startedAt = Get-Date
}

function Reload-Logs {
    $script:seen = @{}
    $script:activitySeen = @{}
    $script:events.Clear()
    $script:activityEvents.Clear()
    $script:integrationEvents.Clear()
    $script:sessionInfo = @{}
    $script:latestSource = $null
    $script:latestSession = $null
    $script:focusedSession = $null
    $script:focusedEventId = $null
    Update-Events
    $script:startedAt = Get-Date
}

function Get-DisplayEvents {
    param([string]$Mode)

    $ordered = @($script:events | Sort-Object At -Descending)
    $latest = if ($ordered.Count -gt 0) { $ordered[0] } else { $null }
    if ($null -eq $latest) { return @() }
    $script:latestSource = $latest.Source
    $script:latestSession = $latest.Session
    if ($Mode -eq 'Follow latest') {
        return @($ordered | Where-Object { $_.Session -eq $script:latestSession })
    }
    if ($Mode -eq 'Pinned session') {
        if ($null -eq $script:pinnedSource) { $script:pinnedSource = $script:latestSession }
        return @($ordered | Where-Object { $_.Session -eq $script:pinnedSource })
    }
    return $ordered
}

function Get-DisplayActivity {
    param([string]$Mode)

    $ordered = @($script:activityEvents | Sort-Object At -Descending)
    if ($Mode -eq 'Follow latest' -and $null -ne $script:latestSession) {
        return @($ordered | Where-Object { $_.Session -eq $script:latestSession })
    }
    if ($Mode -eq 'Pinned session') {
        if ($null -eq $script:pinnedSource -and $null -ne $script:latestSession) { $script:pinnedSource = $script:latestSession }
        if ($null -ne $script:pinnedSource) { return @($ordered | Where-Object { $_.Session -eq $script:pinnedSource }) }
    }
    return $ordered
}

function Get-DisplayIntegrations {
    param([string]$Mode)

    $ordered = @($script:integrationEvents | Sort-Object At -Descending)
    if ($Mode -eq 'Follow latest' -and $null -ne $script:latestSession) {
        return @($ordered | Where-Object { $_.Session -eq $script:latestSession })
    }
    if ($Mode -eq 'Pinned session') {
        if ($null -eq $script:pinnedSource -and $null -ne $script:latestSession) { $script:pinnedSource = $script:latestSession }
        if ($null -ne $script:pinnedSource) { return @($ordered | Where-Object { $_.Session -eq $script:pinnedSource }) }
    }
    return $ordered
}

function Get-SumPack {
    param([object[]]$Items)

    [int64]$total = 0
    [int64]$cached = 0
    [int64]$newInput = 0
    [int64]$output = 0
    [int64]$reasoning = 0
    [int64]$freshBurn = 0
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $total += [int64]$item.Total
        $cached += [int64]$item.Cached
        $newInput += [int64]$item.NewInput
        $output += [int64]$item.Output
        $reasoning += [int64]$item.Reasoning
        $freshBurn += [int64]$item.FreshBurn
    }

    return [pscustomobject]@{
        Total = $total
        Cached = $cached
        NewInput = $newInput
        Output = $output
        Reasoning = $reasoning
        FreshBurn = $freshBurn
    }
}

function Get-ContextHealth {
    param([object]$Sum, [int]$EventCount, [int]$SpikeCount)

    if ($EventCount -le 0) { return 'No data' }
    $avgFresh = [int64]($Sum.FreshBurn / [Math]::Max(1, $EventCount))
    $avgContext = [int64]($Sum.Total / [Math]::Max(1, $EventCount))
    $cacheRatio = if ($Sum.Total -gt 0) { $Sum.Cached / [double]$Sum.Total } else { 0 }
    if ($SpikeCount -gt 0 -or $avgFresh -ge $WarnNewInputTokens) { return 'Fresh spike' }
    if ($avgContext -ge $WarnContextTokens -and $cacheRatio -ge 0.75) { return 'Bloated replay' }
    if ($avgContext -ge ($WarnContextTokens * 0.70)) { return 'Growing' }
    return 'Healthy'
}

function Get-QuotaText {
    param([object]$Event)

    if ($null -eq $Event -or $null -eq $Event.RateLimits) {
        return 'Quota: not available in latest token event'
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('primary', 'secondary')) {
        $window = Get-ValueByName -Object $Event.RateLimits -Name $name
        if ($null -eq $window) { continue }
        $used = Get-ValueByName -Object $window -Name 'used_percent'
        if ($null -eq $used) { $used = Get-ValueByName -Object $window -Name 'usage_percent' }
        $reset = Get-ValueByName -Object $window -Name 'reset_at'
        $label = if ($name -eq 'primary') { '5-hour/window' } else { 'weekly/window' }
        if ($null -ne $used) {
            $text = '{0}: {1:N0}%' -f $label, ([double]$used)
            if ($reset) { $text += " reset $reset" }
            $parts.Add($text)
        }
    }
    if ($parts.Count -gt 0) { return 'Quota: ' + ($parts -join ' | ') }

    $plan = Get-ValueByName -Object $Event.RateLimits -Name 'plan_type'
    if ($plan) { return "Quota: no active percentage in latest event | plan $plan" }
    return 'Quota: rate-limit object present, but no percentage/reset fields'
}

function Get-QuotaPercent {
    param([object]$Event)

    if ($null -eq $Event -or $null -eq $Event.RateLimits) { return $null }
    foreach ($name in @('primary', 'secondary')) {
        $window = Get-ValueByName -Object $Event.RateLimits -Name $name
        if ($null -eq $window) { continue }
        $used = Get-ValueByName -Object $window -Name 'used_percent'
        if ($null -eq $used) { $used = Get-ValueByName -Object $window -Name 'usage_percent' }
        if ($null -ne $used) {
            try { return [Math]::Max(0, [Math]::Min(100, [int][double]$used)) } catch { }
        }
    }
    return $null
}

function Get-OverallStatus {
    param([object]$Latest, [object]$Minute, [object[]]$Tasks)

    $quotaPercent = Get-QuotaPercent -Event $Latest
    if ($null -ne $quotaPercent) {
        if ($quotaPercent -ge 90) { return [pscustomobject]@{ Label = 'CRITICAL'; Detail = "quota $quotaPercent%"; Percent = $quotaPercent; Color = [System.Drawing.Color]::Tomato } }
        if ($quotaPercent -ge 75) { return [pscustomobject]@{ Label = 'WARN'; Detail = "quota $quotaPercent%"; Percent = $quotaPercent; Color = [System.Drawing.Color]::Orange } }
        return [pscustomobject]@{ Label = 'OK'; Detail = "quota $quotaPercent%"; Percent = $quotaPercent; Color = [System.Drawing.Color]::Lime }
    }

    $percent = [Math]::Max(0, [Math]::Min(100, [int](($Minute.FreshBurn / [double]$WarnMinuteFreshTokens) * 100)))
    # A historic task health flag must not hold the live status at Critical.
    # Only activity from the current two-minute window can affect the header.
    $activeCutoff = (Get-Date).AddMinutes(-2)
    $activeTasks = @($Tasks | Where-Object { $_.LatestAt -ge $activeCutoff })
    $badTask = @($activeTasks | Where-Object { $_.Health -eq 'Fresh spike' } | Select-Object -First 1)
    $growingTask = @($activeTasks | Where-Object { $_.Health -eq 'Bloated replay' -or $_.Health -eq 'Growing' } | Select-Object -First 1)
    if ($badTask.Count -gt 0 -or $Minute.FreshBurn -ge $WarnMinuteFreshTokens) {
        return [pscustomobject]@{ Label = 'CRITICAL'; Detail = 'fresh burn spike'; Percent = $percent; Color = [System.Drawing.Color]::Tomato }
    }
    if ($growingTask.Count -gt 0 -or ($Minute.FreshBurn -ge ($WarnMinuteFreshTokens * 0.50))) {
        return [pscustomobject]@{ Label = 'WARN'; Detail = 'context growing'; Percent = $percent; Color = [System.Drawing.Color]::Orange }
    }
    return [pscustomobject]@{ Label = 'OK'; Detail = 'fresh burn normal'; Percent = $percent; Color = [System.Drawing.Color]::Lime }
}

function Get-ModelBreakdownText {
    param([object[]]$VisibleEvents)

    if ($VisibleEvents.Count -eq 0) { return 'Models: waiting for token events' }
    $parts = [System.Collections.Generic.List[string]]::new()
    $groups = @($VisibleEvents | Group-Object {
        $info = Get-SessionInfoRecord -SourceFile $_.Source
        if ($info.Model) { $info.Model } else { 'unknown' }
    } | Sort-Object Count -Descending | Select-Object -First 4)
    foreach ($group in $groups) {
        $sum = Get-SumPack -Items @($group.Group)
        $avgFresh = [int64]($sum.FreshBurn / [Math]::Max(1, $group.Count))
        $parts.Add(('{0}: {1} turns, avg fresh {2}, context {3}' -f $group.Name, $group.Count, (Format-Tokens $avgFresh), (Format-Tokens $sum.Total)))
    }
    return 'Models: ' + ($parts -join ' | ')
}

function Get-TimeSummaryText {
    param([object[]]$VisibleEvents)

    if ($VisibleEvents.Count -eq 0) { return 'Time: waiting for token events' }
    $now = Get-Date
    $todayEvents = @($VisibleEvents | Where-Object { $_.At.Date -eq $now.Date })
    $hourEvents = @($VisibleEvents | Where-Object { $_.At -ge $now.AddHours(-1) })
    $today = Get-SumPack -Items $todayEvents
    $hour = Get-SumPack -Items $hourEvents
    $todayAvg = if ($todayEvents.Count -gt 0) { [int64]($today.FreshBurn / $todayEvents.Count) } else { [int64]0 }
    $hourAvg = if ($hourEvents.Count -gt 0) { [int64]($hour.FreshBurn / $hourEvents.Count) } else { [int64]0 }
    return 'Time: today fresh {0} ({1} turns, avg {2}) | last hour fresh {3} ({4} turns, avg {5})' -f (Format-Tokens $today.FreshBurn), $todayEvents.Count, (Format-Tokens $todayAvg), (Format-Tokens $hour.FreshBurn), $hourEvents.Count, (Format-Tokens $hourAvg)
}

function Get-IntegrationBreakdown {
    param([object[]]$VisibleIntegrations)

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($VisibleIntegrations | Group-Object -Property Name)) {
        $items = @($group.Group)
        if ($items.Count -eq 0) { continue }
        $latest = @($items | Sort-Object At -Descending | Select-Object -First 1)[0]
        $kinds = @($items | Select-Object -ExpandProperty Kind -Unique)
        $sessions = @($items | Select-Object -ExpandProperty Session -Unique)
        $rows.Add([pscustomobject]@{
            Name = $group.Name
            Kind = ($kinds -join ',')
            Count = $items.Count
            Sessions = $sessions.Count
            LatestAt = $latest.At
            LatestTask = Get-FriendlyTaskLabel -Path $latest.Source
        })
    }
    return @($rows | Sort-Object LatestAt -Descending | Sort-Object Count -Descending)
}

function Get-IntegrationSummaryText {
    param([object[]]$VisibleIntegrations)

    if ($VisibleIntegrations.Count -eq 0) { return 'Integrations: no tool/plugin/add-in calls in visible window' }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($row in @(Get-IntegrationBreakdown -VisibleIntegrations $VisibleIntegrations | Select-Object -First 5)) {
        $parts.Add(('{0} {1}' -f $row.Name, $row.Count))
    }
    return 'Integrations: ' + ($parts -join ' | ')
}

function Get-TaskBreakdown {
    param([object[]]$VisibleEvents)

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($VisibleEvents | Group-Object -Property Session)) {
        $items = @($group.Group)
        if ($items.Count -eq 0) { continue }
        $latest = @($items | Sort-Object At -Descending | Select-Object -First 1)[0]
        $sourceForTask = $latest.Source
        $sum = Get-SumPack -Items $items
        $info = Get-SessionInfoRecord -SourceFile $sourceForTask
        $status = 'Quiet'
        if ($latest.At -ge (Get-Date).AddMinutes(-2)) { $status = 'Active' }
        elseif ($latest.At -ge (Get-Date).AddMinutes(-20)) { $status = 'Recent' }
        $avgFresh = if ($items.Count -gt 0) { [int64]($sum.FreshBurn / $items.Count) } else { [int64]0 }
        $avgContext = if ($items.Count -gt 0) { [int64]($sum.Total / $items.Count) } else { [int64]0 }
        $spikeCount = @($items | Where-Object { $_.Risk -ne 'Normal' -and $_.Risk -ne 'Mostly cached context' }).Count
        $cacheRatio = if ($sum.Total -gt 0) { [Math]::Round(($sum.Cached / [double]$sum.Total) * 100, 1) } else { 0 }
        $health = Get-ContextHealth -Sum $sum -EventCount $items.Count -SpikeCount $spikeCount
        $rows.Add([pscustomobject]@{
            Source = $sourceForTask
            Session = $group.Name
            Task = Get-FriendlyTaskLabel -Path $sourceForTask
            Model = $info.Model
            Effort = $info.Effort
            ApprovalPolicy = $info.ApprovalPolicy
            ApprovalsReviewer = $info.ApprovalsReviewer
            Sandbox = $info.Sandbox
            ContextWindow = $info.ContextWindow
            FreshBurn = $sum.FreshBurn
            NewInput = $sum.NewInput
            Context = $sum.Total
            AvgFresh = $avgFresh
            AvgContext = $avgContext
            CacheRatio = $cacheRatio
            SpikeCount = $spikeCount
            Health = $health
            Events = $items.Count
            LatestAt = $latest.At
            Status = $status
        })
    }
    return @($rows | Sort-Object LatestAt -Descending)
}

function Get-ExplainText {
    param([object]$Event, [object[]]$VisibleEvents)

    if ($null -eq $Event) { return 'Select a row to explain the spike profile.' }
    $minuteEvents = @($VisibleEvents | Where-Object { $_.At -ge (Get-Date).AddMinutes(-1) })
    $minute = Get-SumPack -Items $minuteEvents
    $share = if ($minute.Total -gt 0) { [Math]::Round(($Event.Total / [double]$minute.Total) * 100, 1) } else { 0 }
    $cachedRatio = if ($Event.Input -gt 0) { [Math]::Round(($Event.Cached / [double]$Event.Input) * 100, 1) } else { 0 }

    return ('{0} | {1} | fresh {2} = new input {3} + output {4} + reasoning {5}. Context total {6}; {7}% of input was cached. This row is {8}% of visible last-60-second context. Session: {9}' -f
        $Event.At.ToString('HH:mm:ss'),
        $Event.Risk,
        (Format-Tokens $Event.FreshBurn),
        (Format-Tokens $Event.NewInput),
        (Format-Tokens $Event.Output),
        (Format-Tokens $Event.Reasoning),
        (Format-Tokens $Event.Total),
        $cachedRatio,
        $share,
        (Get-ShortSessionName -Path $Event.Source -MaxLength 55))
}

function Get-TaskExplainText {
    param([object]$Task)

    if ($null -eq $Task) { return 'Select a task to see model, options, averages, and status.' }
    return ('Task {0} | health {1} | model {2} | effort {3} | avg fresh {4}/turn | avg context {5}/turn | cache {6}% | spikes {7} | events {8} | options: approval {9}, reviewer {10}, sandbox {11}, context window {12}' -f
        $Task.Task,
        $Task.Health,
        $(if ($Task.Model) { $Task.Model } else { 'unknown' }),
        $(if ($Task.Effort) { $Task.Effort } else { 'unknown' }),
        (Format-Tokens $Task.AvgFresh),
        (Format-Tokens $Task.AvgContext),
        $Task.CacheRatio,
        $Task.SpikeCount,
        $Task.Events,
        $(if ($Task.ApprovalPolicy) { $Task.ApprovalPolicy } else { 'unknown' }),
        $(if ($Task.ApprovalsReviewer) { $Task.ApprovalsReviewer } else { 'unknown' }),
        $(if ($Task.Sandbox) { $Task.Sandbox } else { 'unknown' }),
        $(if ($Task.ContextWindow) { $Task.ContextWindow } else { 'unknown' }))
}

function Get-IntegrationExplainText {
    param([object]$Integration)

    if ($null -eq $Integration) { return 'Select an integration row to see call counts.' }
    return ('Integration {0} | kind {1} | calls {2} | visible tasks {3} | latest {4}. Counts are call records only; arguments, prompts, and outputs are not displayed.' -f
        $Integration.Name,
        $Integration.Kind,
        $Integration.Count,
        $Integration.Sessions,
        $Integration.LatestAt.ToString('HH:mm:ss'))
}

function Get-SessionSummaryText {
    param([object[]]$VisibleEvents)

    if ($VisibleEvents.Count -eq 0) { return 'Sessions: waiting for token events' }
    $parts = [System.Collections.Generic.List[string]]::new()
    $groups = @($VisibleEvents | Group-Object -Property Source | Sort-Object Count -Descending | Select-Object -First 4)
    foreach ($group in $groups) {
        $sum = Get-SumPack -Items @($group.Group)
        $parts.Add(('{0}: fresh {1}, context {2}, events {3}' -f (Get-ShortSessionName -Path $group.Name -MaxLength 24), (Format-Tokens $sum.FreshBurn), (Format-Tokens $sum.Total), $group.Count))
    }
    return 'Sessions: ' + ($parts -join ' | ')
}

function Get-GuidanceText {
    param([object]$Event, [object]$Minute, [object[]]$VisibleEvents, [string]$Mode)

    if ($null -eq $Event) { return 'Action: waiting for the next completed Codex turn.' }
    $sessionCount = @($VisibleEvents | Select-Object -ExpandProperty Source -Unique).Count
    if ($Mode -eq 'All sessions' -and $sessionCount -gt 1) {
        return 'Action: multiple sessions are active. Switch to Follow latest or Pinned session when you want to isolate one task.'
    }
    if ($Event.Risk -eq 'Fresh input spike') {
        return 'Action: fresh input jumped. Avoid pasting large content; point Codex at files or ask for a summary-first pass.'
    }
    if ($Event.Risk -eq 'Reasoning spike') {
        return 'Action: reasoning jumped. Keep effort at medium for routine work and split big requests into smaller checkpoints.'
    }
    if ($Event.Risk -eq 'Output-heavy') {
        return 'Action: output jumped. Ask for concise output or have Codex save long results to a file.'
    }
    if ($Minute.FreshBurn -ge $WarnMinuteFreshTokens) {
        return 'Action: the last minute is hot. Pause before sending another large-context prompt.'
    }
    if ($Event.Risk -eq 'Mostly cached context') {
        return 'Action: mostly context replay. If this baseline keeps growing, start a new task with a short handoff summary.'
    }
    return 'Action: looks normal. Watch fresh burn for real new work; context is the replayed task history.'
}

function Should-Alert {
    param([object]$Event, [object]$Minute)
    if ($null -eq $Event) { return $false }
    if ($Event.EventId -eq $script:lastAlertEventId) { return $false }
    if ($Event.NewInput -ge $WarnNewInputTokens) { return $true }
    if ($Event.FreshBurn -ge $WarnMinuteFreshTokens) { return $true }
    if ($Minute.FreshBurn -ge $WarnMinuteFreshTokens) { return $true }
    if ($Event.Reasoning -ge $WarnReasoningTokens) { return $true }
    if ($Event.Output -ge $WarnOutputTokens) { return $true }
    return $false
}

function Send-Alert {
    param([object]$Event, [object]$Minute)

    $script:lastAlertEventId = $Event.EventId
    $message = 'Fresh {0}; new input {1}; last 60s fresh {2}' -f (Format-Tokens $Event.FreshBurn), (Format-Tokens $Event.NewInput), (Format-Tokens $Minute.FreshBurn)
    if (-not $NoSound) {
        [System.Media.SystemSounds]::Exclamation.Play()
    }
    if (-not $NoNotifications -and $null -ne $script:notifyIcon) {
        $script:notifyIcon.BalloonTipTitle = 'Codex usage alert'
        $script:notifyIcon.BalloonTipText = $message
        $script:notifyIcon.ShowBalloonTip(4000)
    }
}

Update-Events

if ($Once) {
    $latest = @($script:events | Sort-Object At -Descending | Select-Object -First 1)
    if ($latest.Count -eq 0) { Write-Output 'No recent token events found.'; exit 0 }
    $event = $latest[0]
    Write-Output ("Events={0}; Latest={1}; FreshBurn={2}; NewInput={3}; Context={4}; Risk={5}" -f $script:events.Count, $event.At.ToString('HH:mm:ss'), (Format-Tokens $event.FreshBurn), (Format-Tokens $event.NewInput), (Format-Tokens $event.Total), $event.Risk)
    exit 0
}

if ($IntegrationSmokeTest) {
    $visible = @(Get-DisplayIntegrations -Mode 'All sessions')
    $top = @(Get-IntegrationBreakdown -VisibleIntegrations $visible | Select-Object -First 5)
    $summary = if ($top.Count -gt 0) {
        ($top | ForEach-Object { '{0}:{1}' -f $_.Name, $_.Count }) -join '; '
    }
    else {
        'none'
    }
    Write-Output ("IntegrationCalls={0}; Top={1}" -f $visible.Count, $summary)
    exit 0
}

if ($TaskSmokeTest) {
    $visible = @(Get-DisplayEvents -Mode 'All sessions')
    $tasks = @(Get-TaskBreakdown -VisibleEvents $visible | Select-Object -First 8)
    $summary = if ($tasks.Count -gt 0) {
        ($tasks | ForEach-Object { '{0} [{1}]' -f $_.Task, $(if ($_.Model) { $_.Model } else { 'unknown' }) }) -join ' | '
    }
    else {
        'none'
    }
    Write-Output ("Tasks={0}; Top={1}" -f $tasks.Count, $summary)
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not $NoNotifications) {
    $script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
    $script:notifyIcon.Text = 'Live Codex Usage'
    $script:notifyIcon.Visible = $true
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Live Codex Usage - Local Logs Only'
$form.Size = New-Object System.Drawing.Size(1320, 980)
$form.MinimumSize = New-Object System.Drawing.Size(1120, 840)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor = [System.Drawing.Color]::Gainsboro

function Add-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$FontSize = 11)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $FontSize)
    $label.ForeColor = [System.Drawing.Color]::Gainsboro
    $label.Anchor = 'Top,Left,Right'
    $form.Controls.Add($label)
    return $label
}

function Add-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = 'Flat'
    $button.UseVisualStyleBackColor = $false
    $button.TextAlign = 'MiddleCenter'
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
    $button.FlatAppearance.BorderSize = 1
    $form.Controls.Add($button)
    return $button
}

$title = Add-Label 'LIVE CODEX USAGE - local logs only' 18 14 760 30 16
$title.ForeColor = [System.Drawing.Color]::Aqua
$statusLabel = Add-Label 'Status: waiting' 856 16 246 26 13
$statusLabel.ForeColor = [System.Drawing.Color]::Khaki
$statusMeter = New-Object System.Windows.Forms.ProgressBar
$statusMeter.Location = New-Object System.Drawing.Point(1118, 18)
$statusMeter.Size = New-Object System.Drawing.Size(160, 20)
$statusMeter.Minimum = 0
$statusMeter.Maximum = 100
$statusMeter.Value = 0
$statusMeter.Style = 'Continuous'
$statusMeter.Anchor = 'Top,Right'
$form.Controls.Add($statusMeter)
$freshLabel = Add-Label 'Fresh burn: waiting for token events' 18 52 1240 32 15
$freshLabel.ForeColor = [System.Drawing.Color]::Lime
$guidanceLabel = Add-Label 'Action: waiting for the next completed Codex turn.' 18 88 1240 26 12
$guidanceLabel.ForeColor = [System.Drawing.Color]::White
$minuteLabel = Add-Label 'Last 60 seconds: waiting for token events' 18 116 1240 25 12
$windowLabel = Add-Label 'Monitor window: 0' 18 144 1240 24 11
$quotaLabel = Add-Label 'Quota: waiting for token event metadata' 18 170 1240 22 10
$quotaLabel.ForeColor = [System.Drawing.Color]::Magenta
$modelSummaryLabel = Add-Label 'Models: waiting for token events' 18 194 1240 22 10
$modelSummaryLabel.ForeColor = [System.Drawing.Color]::Khaki
$timeSummaryLabel = Add-Label 'Time: waiting for token events' 18 218 1240 22 10
$timeSummaryLabel.ForeColor = [System.Drawing.Color]::Khaki
$noteLabel = Add-Label 'Read-only local-log monitor. Cached input is a subset of input. No prompts, responses, tool data, files, or network activity are written or sent.' 18 242 1240 22 10
$noteLabel.ForeColor = [System.Drawing.Color]::DarkGray
$sessionSummaryLabel = Add-Label 'Sessions: waiting for token events' 18 264 1240 22 10
$sessionSummaryLabel.ForeColor = [System.Drawing.Color]::Khaki
$integrationSummaryLabel = Add-Label 'Integrations: waiting for tool/plugin/add-in calls' 18 286 1240 22 10
$integrationSummaryLabel.ForeColor = [System.Drawing.Color]::Khaki

$modeLabel = Add-Label 'View' 18 314 40 26 10
$viewAllButton = Add-Button 'All tasks' 62 310 92 30
$viewLatestButton = Add-Button 'Latest' 164 310 78 30
$viewPinnedButton = Add-Button 'Pinned' 252 310 82 30
$pinButton = Add-Button 'Pin latest' 348 310 100 30
$clearButton = Add-Button 'Start fresh' 458 310 110 30
$reloadButton = Add-Button ("Reload {0}h logs" -f $HistoryHours) 578 310 125 30
$miniButton = Add-Button 'Mini mode' 713 310 105 30
$historyLabel = Add-Label 'Source: local Codex session logs only' 836 314 390 24 10
$historyLabel.ForeColor = [System.Drawing.Color]::DarkGray

$tokenLabel = Add-Label 'Token events' 18 350 820 22 11
$tokenLabel.ForeColor = [System.Drawing.Color]::Aqua
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(18, 376)
$grid.Size = New-Object System.Drawing.Size(815, 290)
$grid.Anchor = 'Top,Bottom,Left'
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.RowHeadersVisible = $false
$grid.BackgroundColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$grid.GridColor = [System.Drawing.Color]::FromArgb(65, 65, 65)
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$grid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gainsboro
$grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 90, 120)
foreach ($name in @('Time','Fresh','New input','Output','Reasoning','Context','Cached','Risk','Task')) {
    [void]$grid.Columns.Add($name, $name)
}
$grid.Columns['Fresh'].FillWeight = 80
$grid.Columns['Risk'].FillWeight = 140
$grid.Columns['Task'].FillWeight = 260
$form.Controls.Add($grid)

$taskLabel = Add-Label 'Task breakdown: double-click a task to pin it' 850 350 438 22 11
$taskLabel.ForeColor = [System.Drawing.Color]::Aqua

$taskGrid = New-Object System.Windows.Forms.DataGridView
$taskGrid.Location = New-Object System.Drawing.Point(850, 376)
$taskGrid.Size = New-Object System.Drawing.Size(438, 290)
$taskGrid.Anchor = 'Top,Bottom,Right'
$taskGrid.ReadOnly = $true
$taskGrid.AllowUserToAddRows = $false
$taskGrid.AllowUserToDeleteRows = $false
$taskGrid.AutoSizeColumnsMode = 'Fill'
$taskGrid.RowHeadersVisible = $false
$taskGrid.BackgroundColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$taskGrid.GridColor = [System.Drawing.Color]::FromArgb(65, 65, 65)
$taskGrid.EnableHeadersVisualStyles = $false
$taskGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$taskGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$taskGrid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$taskGrid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gainsboro
$taskGrid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 90, 120)
foreach ($name in @('Task','Model','Health','Avg fresh','Avg ctx','Cache','Events','Status')) {
    [void]$taskGrid.Columns.Add($name, $name)
}
$taskGrid.Columns['Task'].FillWeight = 260
$taskGrid.Columns['Model'].FillWeight = 95
$taskGrid.Columns['Health'].FillWeight = 95
$taskGrid.Columns['Avg fresh'].FillWeight = 80
$taskGrid.Columns['Avg ctx'].FillWeight = 80
$taskGrid.Columns['Cache'].FillWeight = 70
$taskGrid.Columns['Events'].FillWeight = 60
$taskGrid.Columns['Status'].FillWeight = 70
$form.Controls.Add($taskGrid)

$integrationLabel = Add-Label 'Integrations/add-ins/plugins: waiting for calls' 18 650 620 24 11
$integrationLabel.ForeColor = [System.Drawing.Color]::Aqua

$integrationGrid = New-Object System.Windows.Forms.DataGridView
$integrationGrid.Location = New-Object System.Drawing.Point(18, 678)
$integrationGrid.Size = New-Object System.Drawing.Size(620, 140)
$integrationGrid.Anchor = 'Bottom,Left'
$integrationGrid.ReadOnly = $true
$integrationGrid.AllowUserToAddRows = $false
$integrationGrid.AllowUserToDeleteRows = $false
$integrationGrid.AutoSizeColumnsMode = 'Fill'
$integrationGrid.RowHeadersVisible = $false
$integrationGrid.BackgroundColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$integrationGrid.GridColor = [System.Drawing.Color]::FromArgb(65, 65, 65)
$integrationGrid.EnableHeadersVisualStyles = $false
$integrationGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$integrationGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$integrationGrid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$integrationGrid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gainsboro
$integrationGrid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 90, 120)
foreach ($name in @('Integration','Kind','Calls','Tasks','Latest')) {
    [void]$integrationGrid.Columns.Add($name, $name)
}
$integrationGrid.Columns['Integration'].FillWeight = 180
$integrationGrid.Columns['Kind'].FillWeight = 85
$form.Controls.Add($integrationGrid)

$activityLabel = Add-Label 'Sanitized activity: waiting for rollout events' 660 650 628 24 11
$activityLabel.ForeColor = [System.Drawing.Color]::Aqua

$activityGrid = New-Object System.Windows.Forms.DataGridView
$activityGrid.Location = New-Object System.Drawing.Point(660, 678)
$activityGrid.Size = New-Object System.Drawing.Size(628, 140)
$activityGrid.Anchor = 'Bottom,Left,Right'
$activityGrid.ReadOnly = $true
$activityGrid.AllowUserToAddRows = $false
$activityGrid.AllowUserToDeleteRows = $false
$activityGrid.AutoSizeColumnsMode = 'Fill'
$activityGrid.RowHeadersVisible = $false
$activityGrid.BackgroundColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$activityGrid.GridColor = [System.Drawing.Color]::FromArgb(65, 65, 65)
$activityGrid.EnableHeadersVisualStyles = $false
$activityGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$activityGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$activityGrid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$activityGrid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gainsboro
$activityGrid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 90, 120)
foreach ($name in @('Time','Type','What happened','Session')) {
    [void]$activityGrid.Columns.Add($name, $name)
}
$activityGrid.Columns['Type'].FillWeight = 55
$activityGrid.Columns['What happened'].FillWeight = 230
$activityGrid.Columns['Session'].FillWeight = 190
$form.Controls.Add($activityGrid)

$explainBox = New-Object System.Windows.Forms.TextBox
$explainBox.Location = New-Object System.Drawing.Point(18, 830)
$explainBox.Size = New-Object System.Drawing.Size(1270, 80)
$explainBox.Anchor = 'Bottom,Left,Right'
$explainBox.Multiline = $true
$explainBox.ReadOnly = $true
$explainBox.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)
$explainBox.ForeColor = [System.Drawing.Color]::Gainsboro
$explainBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$explainBox.Text = 'Select a row to explain the spike profile.'
$form.Controls.Add($explainBox)

$script:visibleEvents = @()
$script:visibleActivity = @()
$script:visibleIntegrations = @()
$script:visibleTasks = @()
$script:normalFormSize = New-Object System.Drawing.Size(1320, 980)
$script:normalMinimumSize = New-Object System.Drawing.Size(1120, 840)
$script:normalMiniButtonLocation = $miniButton.Location
$script:fullModeControls = @(
    $modelSummaryLabel, $timeSummaryLabel, $noteLabel, $sessionSummaryLabel,
    $modeLabel, $viewAllButton, $viewLatestButton, $viewPinnedButton, $pinButton, $clearButton, $reloadButton,
    $historyLabel, $tokenLabel, $grid, $taskLabel, $taskGrid,
    $integrationLabel, $integrationGrid, $activityLabel, $activityGrid, $explainBox
)

function Update-ViewButtons {
    foreach ($button in @($viewAllButton, $viewLatestButton, $viewPinnedButton)) {
        $button.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
        $button.ForeColor = [System.Drawing.Color]::White
    }
    if ($script:viewMode -eq 'All sessions') {
        $viewAllButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 170)
    }
    elseif ($script:viewMode -eq 'Follow latest') {
        $viewLatestButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 170)
    }
    elseif ($script:viewMode -eq 'Pinned session') {
        $viewPinnedButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 170)
    }
}

function Set-ViewMode {
    param([string]$Mode, [bool]$Refresh = $true)
    $script:viewMode = $Mode
    $script:focusedSession = $null
    $script:focusedEventId = $null
    Update-ViewButtons
    if ($Refresh) { Refresh-Display }
}

Update-ViewButtons

function Update-ResponsiveLayout {
    if ($script:isMiniMode) { return }

    $margin = 18
    $gap = 16
    $clientW = [Math]::Max(1120, $form.ClientSize.Width)
    $clientH = [Math]::Max(840, $form.ClientSize.Height)
    $contentW = $clientW - ($margin * 2)
    $rightW = [Math]::Max(430, [Math]::Min(620, [int]($contentW * 0.31)))
    $leftW = [Math]::Max(620, $contentW - $gap - $rightW)
    $rightX = $margin + $leftW + $gap
    $statusMeterW = 160
    $statusGap = 16
    $statusLabelW = [Math]::Max(240, $rightW - $statusMeterW - $statusGap)

    # Keep the status text in the right-hand task area so long alerts never run beneath the meter or title.
    $title.Size = New-Object System.Drawing.Size([Math]::Max(400, $rightX - $margin - $gap), 30)
    $statusLabel.Location = New-Object System.Drawing.Point($rightX, 16)
    $statusLabel.Size = New-Object System.Drawing.Size($statusLabelW, 26)
    $statusMeter.Location = New-Object System.Drawing.Point(($rightX + $statusLabelW + $statusGap), 18)
    $statusMeter.Size = New-Object System.Drawing.Size($statusMeterW, 20)

    $explainH = 80
    $explainY = $clientH - $explainH - 22
    $activityH = 140
    $activityY = $explainY - $activityH - 12
    $activityLabelY = $activityY - 28
    $gridY = 376
    $gridH = [Math]::Max(220, $activityLabelY - $gridY - 10)
    $lowerGap = 16
    $integrationW = [Math]::Max(420, [int](($contentW - $lowerGap) * 0.36))
    $activityW = $contentW - $lowerGap - $integrationW
    $activityX = $margin + $integrationW + $lowerGap

    $tokenLabel.Location = New-Object System.Drawing.Point($margin, 350)
    $tokenLabel.Size = New-Object System.Drawing.Size($leftW, 22)
    $grid.Location = New-Object System.Drawing.Point($margin, $gridY)
    $grid.Size = New-Object System.Drawing.Size($leftW, $gridH)

    $taskLabel.Location = New-Object System.Drawing.Point($rightX, 350)
    $taskLabel.Size = New-Object System.Drawing.Size($rightW, 22)
    $taskGrid.Location = New-Object System.Drawing.Point($rightX, $gridY)
    $taskGrid.Size = New-Object System.Drawing.Size($rightW, $gridH)

    $integrationLabel.Location = New-Object System.Drawing.Point($margin, $activityLabelY)
    $integrationLabel.Size = New-Object System.Drawing.Size($integrationW, 24)
    $integrationGrid.Location = New-Object System.Drawing.Point($margin, $activityY)
    $integrationGrid.Size = New-Object System.Drawing.Size($integrationW, $activityH)

    $activityLabel.Location = New-Object System.Drawing.Point($activityX, $activityLabelY)
    $activityLabel.Size = New-Object System.Drawing.Size($activityW, 24)
    $activityGrid.Location = New-Object System.Drawing.Point($activityX, $activityY)
    $activityGrid.Size = New-Object System.Drawing.Size($activityW, $activityH)

    $explainBox.Location = New-Object System.Drawing.Point($margin, $explainY)
    $explainBox.Size = New-Object System.Drawing.Size($contentW, $explainH)
}

function Set-MiniMode {
    param([bool]$Enabled)

    $script:isMiniMode = $Enabled
    foreach ($control in $script:fullModeControls) {
        $control.Visible = -not $Enabled
    }
    if ($Enabled) {
        $form.TopMost = $true
        $form.MinimumSize = New-Object System.Drawing.Size(640, 225)
        $form.Size = New-Object System.Drawing.Size(760, 255)
        $miniButton.Text = 'Full mode'
        $miniButton.Location = New-Object System.Drawing.Point(620, 14)
        $miniButton.Size = New-Object System.Drawing.Size(105, 30)
        $statusLabel.Location = New-Object System.Drawing.Point(420, 16)
        $statusLabel.Size = New-Object System.Drawing.Size(180, 26)
        $statusMeter.Location = New-Object System.Drawing.Point(420, 146)
        $statusMeter.Size = New-Object System.Drawing.Size(300, 20)
        $title.Text = 'CODEX USAGE - mini'
        $freshLabel.Size = New-Object System.Drawing.Size(700, 32)
        $guidanceLabel.Size = New-Object System.Drawing.Size(700, 26)
        $minuteLabel.Size = New-Object System.Drawing.Size(700, 25)
        $windowLabel.Size = New-Object System.Drawing.Size(700, 24)
        $quotaLabel.Size = New-Object System.Drawing.Size(700, 22)
    }
    else {
        $form.TopMost = $false
        $form.MinimumSize = $script:normalMinimumSize
        $form.Size = $script:normalFormSize
        $miniButton.Text = 'Mini mode'
        $miniButton.Location = $script:normalMiniButtonLocation
        $miniButton.Size = New-Object System.Drawing.Size(105, 30)
        $title.Text = 'LIVE CODEX USAGE - local logs only'
        $freshLabel.Size = New-Object System.Drawing.Size(1240, 32)
        $guidanceLabel.Size = New-Object System.Drawing.Size(1240, 26)
        $minuteLabel.Size = New-Object System.Drawing.Size(1240, 25)
        $windowLabel.Size = New-Object System.Drawing.Size(1240, 24)
        $quotaLabel.Size = New-Object System.Drawing.Size(1240, 22)
        Update-ResponsiveLayout
    }
}

function Refresh-Display {
    $script:isRefreshing = $true
    try {
    Update-Events
    Update-ResponsiveLayout
    $mode = [string]$script:viewMode
    $visible = @(Get-DisplayEvents -Mode $mode)
    if ($script:focusedSession) {
        $focusExists = @($visible | Where-Object { $_.Session -eq $script:focusedSession } | Select-Object -First 1).Count -gt 0
        if (-not $focusExists) {
            $script:focusedSession = $null
            $script:focusedEventId = $null
        }
    }
    $allActivity = @(Get-DisplayActivity -Mode $mode)
    $allIntegrations = @(Get-DisplayIntegrations -Mode $mode)
    $activity = if ($script:focusedSession) { @($allActivity | Where-Object { $_.Session -eq $script:focusedSession }) } else { $allActivity }
    $integrations = if ($script:focusedSession) { @($allIntegrations | Where-Object { $_.Session -eq $script:focusedSession }) } else { $allIntegrations }
    $tasks = @(Get-TaskBreakdown -VisibleEvents $visible)
    $script:visibleEvents = $visible
    $script:visibleActivity = $activity
    $script:visibleIntegrations = $integrations
    $script:visibleTasks = $tasks
    $latest = if ($visible.Count -gt 0) { $visible[0] } else { $null }
    $minuteEvents = @($visible | Where-Object { $_.At -ge (Get-Date).AddMinutes(-1) })
    $minute = Get-SumPack -Items $minuteEvents
    $window = Get-SumPack -Items $visible
    $status = Get-OverallStatus -Latest $latest -Minute $minute -Tasks $tasks
    $statusLabel.Text = 'Status: {0} ({1})' -f $status.Label, $status.Detail
    $statusLabel.ForeColor = $status.Color
    try { $statusMeter.Value = [Math]::Max($statusMeter.Minimum, [Math]::Min($statusMeter.Maximum, [int]$status.Percent)) } catch { $statusMeter.Value = 0 }

    if ($null -eq $latest) {
        $freshLabel.Text = 'Fresh burn: waiting for token events'
        $freshLabel.ForeColor = [System.Drawing.Color]::Lime
    }
    else {
        $latestTask = @($tasks | Where-Object { $_.Session -eq $latest.Session } | Select-Object -First 1)
        $avgFreshText = if ($latestTask.Count -gt 0) { Format-Tokens $latestTask[0].AvgFresh } else { 'n/a' }
        $modelText = if ($latestTask.Count -gt 0 -and $latestTask[0].Model) { $latestTask[0].Model } else { 'unknown model' }
        $freshLabel.Text = 'Latest {0}: fresh {1} | task avg {2}/turn | new input {3} | output {4} | reasoning {5} | context {6} | {7} | {8}' -f $latest.At.ToString('HH:mm:ss'), (Format-Tokens $latest.FreshBurn), $avgFreshText, (Format-Tokens $latest.NewInput), (Format-Tokens $latest.Output), (Format-Tokens $latest.Reasoning), (Format-Tokens $latest.Total), $latest.Risk, $modelText
        if ($latest.Risk -eq 'Normal' -or $latest.Risk -eq 'Mostly cached context') {
            $freshLabel.ForeColor = [System.Drawing.Color]::Lime
        }
        else {
            $freshLabel.ForeColor = [System.Drawing.Color]::Tomato
        }
        if (Should-Alert -Event $latest -Minute $minute) {
            Send-Alert -Event $latest -Minute $minute
        }
    }

    $minuteLabel.Text = 'Last 60 seconds - fresh {0} | new input {1} | output {2} | reasoning {3} | context {4} | cached {5}' -f (Format-Tokens $minute.FreshBurn), (Format-Tokens $minute.NewInput), (Format-Tokens $minute.Output), (Format-Tokens $minute.Reasoning), (Format-Tokens $minute.Total), (Format-Tokens $minute.Cached)
    if ($minute.FreshBurn -ge $WarnMinuteFreshTokens) {
        $minuteLabel.ForeColor = [System.Drawing.Color]::Tomato
    }
    else {
        $minuteLabel.ForeColor = [System.Drawing.Color]::Gainsboro
    }
    $guidanceLabel.Text = Get-GuidanceText -Event $latest -Minute $minute -VisibleEvents $visible -Mode $mode
    if ($guidanceLabel.Text -match 'jumped|hot|multiple') {
        $guidanceLabel.ForeColor = [System.Drawing.Color]::Tomato
    }
    elseif ($guidanceLabel.Text -match 'mostly context') {
        $guidanceLabel.ForeColor = [System.Drawing.Color]::Khaki
    }
    else {
        $guidanceLabel.ForeColor = [System.Drawing.Color]::White
    }
    $windowLabel.Text = 'Monitor window - events: {0} | fresh {1} | context {2} | sessions {3} | started {4}' -f $visible.Count, (Format-Tokens $window.FreshBurn), (Format-Tokens $window.Total), (@($visible | Select-Object -ExpandProperty Source -Unique).Count), $script:startedAt.ToString('HH:mm:ss')
    $quotaLabel.Text = Get-QuotaText -Event $latest
    $modelSummaryLabel.Text = Get-ModelBreakdownText -VisibleEvents $visible
    $timeSummaryLabel.Text = Get-TimeSummaryText -VisibleEvents $visible
    $sessionSummaryLabel.Text = Get-SessionSummaryText -VisibleEvents $visible
    $integrationSummaryLabel.Text = Get-IntegrationSummaryText -VisibleIntegrations $integrations

    $grid.Rows.Clear()
    $focusedGridRow = -1
    foreach ($event in $visible | Select-Object -First 100) {
        $rowIndex = $grid.Rows.Add(
            $event.At.ToString('HH:mm:ss'),
            (Format-Tokens $event.FreshBurn),
            (Format-Tokens $event.NewInput),
            (Format-Tokens $event.Output),
            (Format-Tokens $event.Reasoning),
            (Format-Tokens $event.Total),
            (Format-Tokens $event.Cached),
            $event.Risk,
            (Get-FriendlyTaskLabel -Path $event.Source)
        )
        $row = $grid.Rows[$rowIndex]
        $row.Tag = $event
        if ($script:focusedEventId -and $event.EventId -eq $script:focusedEventId) { $focusedGridRow = $rowIndex }
        if ($event.Risk -eq 'Fresh input spike' -or $event.Risk -eq 'Fresh burn spike' -or $event.Risk -eq 'Reasoning spike' -or $event.Risk -eq 'Output-heavy') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Tomato
        }
        elseif ($event.Risk -eq 'Mostly cached context') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Khaki
        }
    }
    if ($focusedGridRow -ge 0 -and $focusedGridRow -lt $grid.Rows.Count) {
        $grid.ClearSelection()
        $grid.Rows[$focusedGridRow].Selected = $true
        try { $grid.FirstDisplayedScrollingRowIndex = $focusedGridRow } catch { }
    }

    $taskLabel.Text = 'Task breakdown - {0} visible task(s). Double-click a row to pin that task.' -f $tasks.Count
    $taskGrid.Rows.Clear()
    $focusedTaskRow = -1
    foreach ($task in $tasks | Select-Object -First 30) {
        $rowIndex = $taskGrid.Rows.Add(
            $task.Task,
            $(if ($task.Model) { $task.Model } else { 'unknown' }),
            $task.Health,
            (Format-Tokens $task.AvgFresh),
            (Format-Tokens $task.AvgContext),
            ('{0}%' -f $task.CacheRatio),
            $task.Events,
            $task.Status
        )
        $row = $taskGrid.Rows[$rowIndex]
        $row.Tag = $task
        if ($script:focusedSession -and $task.Session -eq $script:focusedSession) { $focusedTaskRow = $rowIndex }
        if ($task.Status -eq 'Active') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Lime
        }
        elseif ($task.Health -eq 'Fresh spike') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Tomato
        }
        elseif ($task.Health -eq 'Bloated replay' -or $task.Health -eq 'Growing') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Khaki
        }
        elseif ($task.Status -eq 'Recent') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Khaki
        }
    }
    if ($focusedTaskRow -ge 0 -and $focusedTaskRow -lt $taskGrid.Rows.Count) {
        $taskGrid.ClearSelection()
        $taskGrid.Rows[$focusedTaskRow].Selected = $true
        try { $taskGrid.FirstDisplayedScrollingRowIndex = $focusedTaskRow } catch { }
    }

    $focusLabel = ''
    if ($script:focusedSession) {
        $focusTask = @($tasks | Where-Object { $_.Session -eq $script:focusedSession } | Select-Object -First 1)
        if ($focusTask.Count -gt 0) { $focusLabel = ' for ' + $focusTask[0].Task }
    }
    $integrationLabel.Text = 'Integrations/add-ins/plugins - {0} call(s){1}' -f $integrations.Count, $focusLabel
    $integrationGrid.Rows.Clear()
    foreach ($integration in @(Get-IntegrationBreakdown -VisibleIntegrations $integrations | Select-Object -First 30)) {
        $rowIndex = $integrationGrid.Rows.Add(
            $integration.Name,
            $integration.Kind,
            $integration.Count,
            $integration.Sessions,
            $integration.LatestAt.ToString('HH:mm:ss')
        )
        $row = $integrationGrid.Rows[$rowIndex]
        $row.Tag = $integration
        if ($integration.Kind -eq 'MCP') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Khaki
        }
        elseif ($integration.Name -eq 'Web search') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Aqua
        }
    }

    $activityLabel.Text = 'Sanitized activity - {0} recent events{1}. Types only; no prompt text or tool output.' -f $activity.Count, $focusLabel
    $activityGrid.Rows.Clear()
    foreach ($item in $activity | Select-Object -First 40) {
        $rowIndex = $activityGrid.Rows.Add(
            $item.At.ToString('HH:mm:ss'),
            $item.Label,
            $item.Detail,
            (Get-ShortSessionName -Path $item.Source)
        )
        $row = $activityGrid.Rows[$rowIndex]
        if ($item.Label -eq 'ERR') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Tomato
        }
        elseif ($item.Label -eq 'TOKEN') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Khaki
        }
        elseif ($item.Label -eq 'ASK') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Aqua
        }
    }

    $focusedEvent = @(if ($script:focusedEventId) { $visible | Where-Object { $_.EventId -eq $script:focusedEventId } | Select-Object -First 1 })
    if ($focusedEvent.Count -gt 0) {
        $explainBox.Text = Get-ExplainText -Event $focusedEvent[0] -VisibleEvents $visible
    }
    elseif ($script:focusedSession) {
        $focusedTask = @($tasks | Where-Object { $_.Session -eq $script:focusedSession } | Select-Object -First 1)
        if ($focusedTask.Count -gt 0) {
            $explainBox.Text = Get-TaskExplainText -Task $focusedTask[0]
        }
        elseif ($null -ne $latest) {
            $explainBox.Text = Get-ExplainText -Event $latest -VisibleEvents $visible
        }
    }
    elseif ($null -ne $latest) {
        $explainBox.Text = Get-ExplainText -Event $latest -VisibleEvents $visible
    }
    else {
        $explainBox.Text = 'Select a row to explain the spike profile.'
    }
    }
    finally {
        $script:isRefreshing = $false
    }
}

$grid.Add_SelectionChanged({
    if ($script:isRefreshing) { return }
    if ($grid.SelectedRows.Count -gt 0 -and $null -ne $grid.SelectedRows[0].Tag) {
        $event = $grid.SelectedRows[0].Tag
        $script:focusedSession = [string]$event.Session
        $script:focusedEventId = [string]$event.EventId
        Refresh-Display
    }
})

$viewAllButton.Add_Click({ if (-not $script:isRefreshing) { Set-ViewMode -Mode 'All sessions' } })
$viewLatestButton.Add_Click({ if (-not $script:isRefreshing) { Set-ViewMode -Mode 'Follow latest' } })
$viewPinnedButton.Add_Click({ if (-not $script:isRefreshing) { Set-ViewMode -Mode 'Pinned session' } })
$taskGrid.Add_DoubleClick({
    if ($taskGrid.SelectedRows.Count -gt 0 -and $null -ne $taskGrid.SelectedRows[0].Tag) {
        $script:pinnedSource = [string]$taskGrid.SelectedRows[0].Tag.Session
        Set-ViewMode -Mode 'Pinned session'
    }
})
$taskGrid.Add_SelectionChanged({
    if ($script:isRefreshing) { return }
    if ($taskGrid.SelectedRows.Count -gt 0 -and $null -ne $taskGrid.SelectedRows[0].Tag) {
        $task = $taskGrid.SelectedRows[0].Tag
        $script:focusedSession = [string]$task.Session
        $script:focusedEventId = $null
        Refresh-Display
    }
})
$integrationGrid.Add_SelectionChanged({
    if ($script:isRefreshing) { return }
    if ($integrationGrid.SelectedRows.Count -gt 0 -and $null -ne $integrationGrid.SelectedRows[0].Tag) {
        $explainBox.Text = Get-IntegrationExplainText -Integration $integrationGrid.SelectedRows[0].Tag
    }
})
$pinButton.Add_Click({
    if ($null -ne $script:latestSession) {
        $script:pinnedSource = $script:latestSession
        Set-ViewMode -Mode 'Pinned session'
    }
    else {
        [System.Windows.Forms.MessageBox]::Show('No latest session is available to pin yet.', 'Live Codex Usage') | Out-Null
    }
})
$clearButton.Add_Click({
    Reset-MonitorWindow
    Refresh-Display
})
$reloadButton.Add_Click({
    Reload-Logs
    Refresh-Display
    $explainBox.Text = ('Reloaded the last {0} hours of local Codex session logs.' -f $HistoryHours)
})
$miniButton.Add_Click({
    Set-MiniMode -Enabled (-not $script:isMiniMode)
    Refresh-Display
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollSeconds * 1000
$timer.Add_Tick({ Refresh-Display })
$form.Add_Resize({ Update-ResponsiveLayout })
$form.Add_Shown({
    if ($StartMini -and -not $script:isMiniMode) {
        Set-MiniMode -Enabled $true
    }
    Refresh-Display
    $timer.Start()
})
$form.Add_FormClosed({
    $timer.Stop()
    if ($null -ne $script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
})

if ($UiSmokeTest -or $MiniSmokeTest) {
    Refresh-Display
    if ($StartMini -and -not $script:isMiniMode) {
        Set-MiniMode -Enabled $true
        Refresh-Display
    }
    if ($MiniSmokeTest) {
        Set-MiniMode -Enabled $true
        Refresh-Display
        Set-MiniMode -Enabled $false
        Write-Output 'Mini mode toggled successfully.'
    }
    else {
        Write-Output 'GUI controls constructed successfully.'
    }
    $form.Dispose()
    if ($null -ne $script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    exit 0
}

[void]$form.ShowDialog()
