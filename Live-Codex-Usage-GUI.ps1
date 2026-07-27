<#
Live-Codex-Usage-GUI.ps1

Native local Windows dashboard for Codex token events. It reads local Codex
session JSONL files and writes only when the user explicitly exports an
aggregate report. It does not invoke Codex, call ChatGPT, or contact any network
service. It does not display prompt text,
responses, tool arguments, tool output, credentials, or working-directory paths.

Run:
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -StartMini
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -InitialView "All sessions" -HistoryHours 48
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -ShowPromptTaskTitles

Optional QA (no window):
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -Once
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -UiSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -MiniSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -IntegrationSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -TaskSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -DateRangeSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -StatusSmokeTest
#>
[CmdletBinding()]
param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [ValidateRange(1, 60)]
    [int]$PollSeconds = 5,
    [ValidateRange(1, 87600)]
    [int]$HistoryHours = 24,
    [string]$FromDate = '',
    [string]$ToDate = '',
    [bool]$IncludeArchivedSessions = $true,
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
    [switch]$ShowPromptTaskTitles,
    [switch]$NoNotifications,
    [switch]$NoSound,
    [switch]$Once,
    [switch]$UiSmokeTest,
    [switch]$MiniSmokeTest,
    [switch]$IntegrationSmokeTest,
    [switch]$TaskSmokeTest,
    [switch]$DateRangeSmokeTest,
    [switch]$StatusSmokeTest,
    [switch]$AlertSmokeTest,
    [switch]$ArchivedSmokeTest,
    [switch]$PresetSmokeTest,
    [switch]$RangeCacheSmokeTest,
    [switch]$QuotaResetSmokeTest,
    [switch]$ExportSmokeTest,
    [string]$ExportPath = '',
    [switch]$EnterpriseSmokeTest,
    [string]$EnterpriseCsvPath = '',
    [switch]$EnterpriseUiSmokeTest,
    [string]$CaptureScreenshotPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }
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

$script:seen = @{}
$script:activitySeen = @{}
$script:fileOffsets = @{}
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
$script:rangeStart = (Get-Date).AddHours(-$HistoryHours)
$script:rangeEnd = [datetime]::MaxValue
$script:scanStats = [pscustomobject]@{
    AvailableFiles = 0
    LoadedFiles = 0
    LinesRead = [int64]0
}

if (-not [string]::IsNullOrWhiteSpace($FromDate)) {
    try { $script:rangeStart = [datetime]::Parse($FromDate).Date }
    catch { throw "Invalid -FromDate value '$FromDate'. Use YYYY-MM-DD." }
}
if (-not [string]::IsNullOrWhiteSpace($ToDate)) {
    try { $script:rangeEnd = [datetime]::Parse($ToDate).Date.AddDays(1).AddTicks(-1) }
    catch { throw "Invalid -ToDate value '$ToDate'. Use YYYY-MM-DD." }
}
if ($script:rangeStart -gt $script:rangeEnd) {
    throw 'The From date must be before or equal to the To date.'
}

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
    if ($Title -match '^<[^>]+>') { return $true }
    if ($Title -match '^# AGENTS\.md instructions') { return $true }
    if ($Title -match '^<environment_context>') { return $true }
    if ($Title -match '^<permissions instructions>') { return $true }
    if ($Title -match '^The following is the Codex agent history') { return $true }
    if ($Title -match '<INSTRUCTIONS>|</INSTRUCTIONS>|<filesystem>|</filesystem>|<workspace_roots>|permission_profile|recommended_plugins|current_date|timezone') { return $true }
    if ($Title -match '^Message Type:|^Task name:|^Sender:|^Payload:') { return $true }
    return $false
}

function Update-TaskTitleFromLine {
    param([string]$Line, [string]$SourceFile)

    if (-not $ShowPromptTaskTitles) { return }
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
    param([string]$Line, [string]$SourceFile = '')
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $identity = $SourceFile + [char]0 + $Line
        return [Convert]::ToBase64String($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($identity)))
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
    foreach ($root in $sessionRoots) {
        [System.IO.Directory]::EnumerateFiles($root, '*.jsonl', [System.IO.SearchOption]::AllDirectories) |
            ForEach-Object { [System.IO.FileInfo]$_ }
    }
}

function Get-NewLogLines {
    param([string]$Path)

    if (-not $script:fileOffsets.ContainsKey($Path)) {
        $script:fileOffsets[$Path] = [pscustomobject]@{
            Offset = [int64]0
            Remainder = ''
        }
    }
    $state = $script:fileOffsets[$Path]
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -lt $state.Offset) {
            $state.Offset = [int64]0
            $state.Remainder = ''
        }
        [void]$stream.Seek([int64]$state.Offset, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true, 4096, $true)
        try {
            $text = $reader.ReadToEnd()
            $newOffset = $stream.Position
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    $state.Offset = [int64]$newOffset
    if ([string]::IsNullOrEmpty($text)) { return @() }
    $combined = [string]$state.Remainder + $text
    $parts = @($combined -split "`r?`n")
    if ($combined.EndsWith("`n")) {
        $state.Remainder = ''
        if ($parts.Count -gt 0 -and $parts[-1] -eq '') {
            $parts = @($parts | Select-Object -First ($parts.Count - 1))
        }
    }
    else {
        $state.Remainder = if ($parts.Count -gt 0) { [string]$parts[-1] } else { $combined }
        if ($parts.Count -gt 1) {
            $parts = @($parts | Select-Object -First ($parts.Count - 1))
        }
        else {
            $parts = @()
        }
    }
    return $parts
}

function Test-InSelectedRange {
    param([datetime]$At)
    return ($At -ge $script:rangeStart -and $At -le $script:rangeEnd)
}

function Format-DateRange {
    $endText = if ($script:rangeEnd -eq [datetime]::MaxValue) { 'Now' } else { $script:rangeEnd.ToString('yyyy-MM-dd') }
    return '{0} to {1}' -f $script:rangeStart.ToString('yyyy-MM-dd'), $endText
}

function Get-AvailableDateBounds {
    $dates = [System.Collections.Generic.List[datetime]]::new()
    foreach ($file in @(Get-SessionLogFiles)) {
        $candidate = $null
        if ($file.FullName -match '[\\/](?:sessions|archived_sessions)[\\/](\d{4})[\\/](\d{2})[\\/](\d{2})[\\/]') {
            $candidate = '{0}-{1}-{2}' -f $Matches[1], $Matches[2], $Matches[3]
        }
        elseif ($file.Name -match 'rollout-(\d{4})-(\d{2})-(\d{2})') {
            $candidate = '{0}-{1}-{2}' -f $Matches[1], $Matches[2], $Matches[3]
        }
        if ($candidate) {
            try {
                $dates.Add([datetime]::ParseExact($candidate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture))
                continue
            }
            catch { }
        }
        $dates.Add($file.LastWriteTime.Date)
    }
    $start = if ($dates.Count -gt 0) { @($dates | Sort-Object | Select-Object -First 1)[0] } else { (Get-Date).Date }
    return [pscustomobject]@{ Start = $start.Date; End = (Get-Date).Date }
}

function Get-DatePresetRange {
    param(
        [ValidateSet('Today', 'Last 7 days', 'Last 30 days', 'All available')]
        [string]$Preset,
        [datetime]$Today = (Get-Date).Date
    )

    $end = $Today.Date
    switch ($Preset) {
        'Today' { $start = $end }
        'Last 7 days' { $start = $end.AddDays(-6) }
        'Last 30 days' { $start = $end.AddDays(-29) }
        'All available' {
            $bounds = Get-AvailableDateBounds
            $start = $bounds.Start
            $end = $bounds.End
        }
    }
    return [pscustomobject]@{ Start = $start.Date; End = $end.Date }
}

function Get-RiskLabel {
    param([object]$UsageEvent)

    $newInput = [Math]::Max([int64]0, $UsageEvent.Input - $UsageEvent.Cached)
    # reasoning_output_tokens is a subset of output_tokens, not an additional charge.
    $freshBurn = $newInput + [int64]$UsageEvent.Output
    if ($newInput -ge $WarnNewInputTokens) { return 'Fresh input spike' }
    if ($UsageEvent.Reasoning -ge $WarnReasoningTokens) { return 'Reasoning spike' }
    if ($UsageEvent.Output -ge $WarnOutputTokens) { return 'Output-heavy' }
    if ($UsageEvent.Total -ge $WarnContextTokens -and $UsageEvent.Cached -ge ($UsageEvent.Input * 0.80)) { return 'Mostly cached context' }
    if ($freshBurn -ge $WarnMinuteFreshTokens) { return 'Fresh burn spike' }
    return 'Normal'
}

function Convert-TokenEvent {
    param([string]$Line, [string]$SourceFile)

    if ($Line -notmatch 'token_count') { return $null }
    try { $record = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    $payload = Get-ObjectProperty -Object $record -Name 'payload'
    if ($null -eq $payload -or (Get-ObjectProperty -Object $payload -Name 'type') -ne 'token_count') { return $null }
    $info = Get-ObjectProperty -Object $payload -Name 'info'
    $usage = Get-ObjectProperty -Object $info -Name 'last_token_usage'
    if ($null -eq $usage) { return $null }

    $at = Get-Date
    try { $at = [datetimeoffset]::Parse([string](Get-ObjectProperty -Object $record -Name 'timestamp')).LocalDateTime } catch { }

    $inputTokens = Get-Number (Get-ObjectProperty -Object $usage -Name 'input_tokens')
    $cached = Get-Number (Get-ObjectProperty -Object $usage -Name 'cached_input_tokens')
    $output = Get-Number (Get-ObjectProperty -Object $usage -Name 'output_tokens')
    $reasoning = Get-Number (Get-ObjectProperty -Object $usage -Name 'reasoning_output_tokens')
    $newInput = [Math]::Max([int64]0, $inputTokens - $cached)
    $total = Get-Number (Get-ObjectProperty -Object $usage -Name 'total_tokens')
    $eventId = Get-LineFingerprint -Line $Line -SourceFile $SourceFile
    $rateLimits = Get-ObjectProperty -Object $payload -Name 'rate_limits'

    $usageEvent = [pscustomobject]@{
        EventId   = $eventId
        At        = $at
        Total     = $total
        Input     = $inputTokens
        Cached    = $cached
        NewInput  = $newInput
        Output    = $output
        Reasoning = $reasoning
        FreshBurn = $newInput + $output
        Plan      = Get-ObjectProperty -Object $rateLimits -Name 'plan_type'
        RateLimits = $rateLimits
        Source    = $SourceFile
        Session   = Get-SessionName -Path $SourceFile
    }
    $usageEvent | Add-Member -NotePropertyName Risk -NotePropertyValue (Get-RiskLabel -UsageEvent $usageEvent)
    return $usageEvent
}

function Convert-ActivityEvent {
    param([string]$Line, [string]$SourceFile)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    try { $record = $Line | ConvertFrom-Json -ErrorAction Stop } catch { return $null }

    $at = Get-Date
    try { $at = [datetimeoffset]::Parse([string](Get-ObjectProperty -Object $record -Name 'timestamp')).LocalDateTime } catch { }

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
        EventId = Get-LineFingerprint -Line $Line -SourceFile $SourceFile
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
    try { $at = [datetimeoffset]::Parse([string](Get-ObjectProperty -Object $record -Name 'timestamp')).LocalDateTime } catch { }

    [pscustomobject]@{
        EventId = Get-LineFingerprint -Line $Line -SourceFile $SourceFile
        At      = $at
        Kind    = $kind
        Name    = $display
        RawName = $rawName
        Source  = $SourceFile
        Session = Get-SessionName -Path $SourceFile
    }
}

function Update-Events {
    $availableFiles = @(Get-SessionLogFiles)
    $files = @($availableFiles |
        Where-Object { $_.LastWriteTime -ge $script:rangeStart } |
        Sort-Object LastWriteTime)
    $script:scanStats.AvailableFiles = $availableFiles.Count
    $script:scanStats.LoadedFiles = $files.Count

    foreach ($file in $files) {
        Get-NewLogLines -Path $file.FullName | ForEach-Object {
            $line = $_
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            $script:scanStats.LinesRead++
            Update-SessionInfo -Line $line -SourceFile $file.FullName
            Update-TaskTitleFromLine -Line $line -SourceFile $file.FullName

            $activityFingerprint = Get-LineFingerprint -Line $line -SourceFile $file.FullName
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
                $fingerprint = Get-LineFingerprint -Line $line -SourceFile $file.FullName
                if ($script:seen.ContainsKey($fingerprint)) { return }
                $script:seen[$fingerprint] = $true
                $usageEvent = Convert-TokenEvent -Line $line -SourceFile $file.FullName
                if ($null -ne $usageEvent) {
                    $script:events.Add($usageEvent)
                }
            }
        }
    }

    if ($script:seen.Count -gt 10000) {
        $rebuilt = @{}
        foreach ($usageEvent in $script:events) { $rebuilt[$usageEvent.EventId] = $true }
        $script:seen = $rebuilt
    }
    if ($script:activitySeen.Count -gt 10000) {
        $rebuiltActivity = @{}
        foreach ($activity in $script:activityEvents) { $rebuiltActivity[$activity.EventId] = $true }
        foreach ($integration in $script:integrationEvents) { $rebuiltActivity[$integration.EventId] = $true }
        $script:activitySeen = $rebuiltActivity
    }
}

function Reset-MonitorWindow {
    $script:events.Clear()
    $script:activityEvents.Clear()
    $script:integrationEvents.Clear()
    $script:seen.Clear()
    $script:activitySeen.Clear()
    $script:fileOffsets = @{}
    $script:scanStats.LinesRead = [int64]0
    $files = @(Get-SessionLogFiles)
    foreach ($file in $files) {
        $script:fileOffsets[$file.FullName] = [pscustomobject]@{
            Offset = [int64]$file.Length
            Remainder = ''
        }
    }
    $script:scanStats.AvailableFiles = $files.Count
    $script:scanStats.LoadedFiles = 0
    $script:startedAt = Get-Date
}

function Reload-Logs {
    $script:seen = @{}
    $script:activitySeen = @{}
    $script:fileOffsets = @{}
    $script:events.Clear()
    $script:activityEvents.Clear()
    $script:integrationEvents.Clear()
    $script:sessionInfo = @{}
    $script:latestSource = $null
    $script:latestSession = $null
    $script:focusedSession = $null
    $script:focusedEventId = $null
    $script:scanStats.LinesRead = [int64]0
    Update-Events
    $script:startedAt = Get-Date
}

function Set-MonitorDateRange {
    param([datetime]$FromDate, [datetime]$ToDate)

    $from = $FromDate.Date
    $to = $ToDate.Date
    if ($from -gt $to) {
        throw 'The From date must be before or equal to the To date.'
    }
    $script:rangeStart = $from
    $script:rangeEnd = $to.AddDays(1).AddTicks(-1)
    # Update-Events reuses the already parsed in-memory catalog and scans only
    # files that were not needed by the previous, narrower range.
    Update-Events
}

function Get-DisplayEvents {
    param([string]$Mode)

    $ordered = @($script:events | Where-Object { Test-InSelectedRange -At $_.At } | Sort-Object At -Descending)
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

    $ordered = @($script:activityEvents | Where-Object { Test-InSelectedRange -At $_.At } | Sort-Object At -Descending)
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

    $ordered = @($script:integrationEvents | Where-Object { Test-InSelectedRange -At $_.At } | Sort-Object At -Descending)
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

function Get-LocalDailySummary {
    param(
        [object[]]$UsageEvents,
        [object[]]$IntegrationEvents
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($UsageEvents | Group-Object { $_.At.Date } | Sort-Object Name)) {
        $items = @($group.Group)
        if ($items.Count -eq 0) { continue }
        $day = $items[0].At.Date
        $sum = Get-SumPack -Items $items
        $integrationCount = @($IntegrationEvents | Where-Object { $_.At.Date -eq $day }).Count
        $rows.Add([pscustomobject][ordered]@{
            Date = $day.ToString('yyyy-MM-dd')
            Events = $items.Count
            Sessions = @($items | Select-Object -ExpandProperty Session -Unique).Count
            FreshBurn = $sum.FreshBurn
            NewInput = $sum.NewInput
            Output = $sum.Output
            ReasoningSubset = $sum.Reasoning
            Context = $sum.Total
            CachedInput = $sum.Cached
            IntegrationCalls = $integrationCount
        })
    }
    return @($rows)
}

function Export-LocalUsageSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [object[]]$UsageEvents = $null,
        [object[]]$IntegrationEvents = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Choose an output CSV path.' }
    if ($null -eq $UsageEvents) { $UsageEvents = @(Get-DisplayEvents -Mode 'All sessions') }
    if ($null -eq $IntegrationEvents) { $IntegrationEvents = @(Get-DisplayIntegrations -Mode 'All sessions') }
    $rows = @(Get-LocalDailySummary -UsageEvents $UsageEvents -IntegrationEvents $IntegrationEvents)
    if ($rows.Count -eq 0) { throw 'There are no token events in the selected date range to export.' }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "The output folder does not exist: $parent"
    }
    $rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    return $rows
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

function Get-QuotaPaceText {
    param([object]$Window, [double]$UsedPercent)

    $resetAt = ConvertTo-ResetDateTime -Value (Get-ValueByName -Object $Window -Name 'reset_at')
    $windowMinutes = Get-ValueByName -Object $Window -Name 'window_minutes'
    if ($null -eq $windowMinutes) { $windowMinutes = Get-ValueByName -Object $Window -Name 'limit_window_minutes' }
    if ($null -eq $resetAt -or $null -eq $windowMinutes) { return '' }
    try { $duration = [double]$windowMinutes } catch { return '' }
    if ($duration -le 0) { return '' }

    $startAt = $resetAt.AddMinutes(-$duration)
    $elapsed = ((Get-Date) - $startAt).TotalMinutes
    if ($elapsed -lt 0 -or $elapsed -gt $duration) { return '' }
    $expected = [Math]::Max(0, [Math]::Min(100, ($elapsed / $duration) * 100))
    $difference = [Math]::Round($UsedPercent - $expected)
    if ([Math]::Abs($difference) -lt 5) { return 'near even pace' }
    if ($difference -gt 0) { return "$difference pts above even pace" }
    return ('{0} pts below even pace' -f [Math]::Abs($difference))
}

function Get-QuotaText {
    param([object]$UsageEvent)

    if ($null -eq $UsageEvent -or $null -eq $UsageEvent.RateLimits) {
        return 'Quota: not available in latest token event'
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('primary', 'secondary')) {
        $window = Get-ValueByName -Object $UsageEvent.RateLimits -Name $name
        if ($null -eq $window) { continue }
        $used = Get-ValueByName -Object $window -Name 'used_percent'
        if ($null -eq $used) { $used = Get-ValueByName -Object $window -Name 'usage_percent' }
        $reset = Get-ValueByName -Object $window -Name 'reset_at'
        $label = if ($name -eq 'primary') { '5-hour/window' } else { 'weekly/window' }
        if ($null -ne $used) {
            $text = '{0}: {1:N0}%' -f $label, ([double]$used)
            $resetText = Format-ResetTime -Value $reset
            if ($resetText) { $text += " ($resetText)" }
            $paceText = Get-QuotaPaceText -Window $window -UsedPercent ([double]$used)
            if ($paceText) { $text += ", $paceText" }
            $parts.Add($text)
        }
    }
    if ($parts.Count -gt 0) { return 'Quota: ' + ($parts -join ' | ') }

    $plan = Get-ValueByName -Object $UsageEvent.RateLimits -Name 'plan_type'
    if ($plan) { return "Quota: no active percentage in latest event | plan $plan" }
    return 'Quota: rate-limit object present, but no percentage/reset fields'
}

function Get-QuotaPercent {
    param([object]$UsageEvent)

    if ($null -eq $UsageEvent -or $null -eq $UsageEvent.RateLimits) { return $null }
    $values = [System.Collections.Generic.List[int]]::new()
    foreach ($name in @('primary', 'secondary')) {
        $window = Get-ValueByName -Object $UsageEvent.RateLimits -Name $name
        if ($null -eq $window) { continue }
        $used = Get-ValueByName -Object $window -Name 'used_percent'
        if ($null -eq $used) { $used = Get-ValueByName -Object $window -Name 'usage_percent' }
        if ($null -ne $used) {
            try { $values.Add([Math]::Max(0, [Math]::Min(100, [int][double]$used))) } catch { }
        }
    }
    if ($values.Count -gt 0) { return @($values | Measure-Object -Maximum)[0].Maximum }
    return $null
}

function Get-OverallStatus {
    param([object]$Latest, [object]$Minute)

    $quotaPercent = Get-QuotaPercent -UsageEvent $Latest
    $livePercent = [Math]::Max(0, [Math]::Min(100, [int](($Minute.FreshBurn / [double]$WarnMinuteFreshTokens) * 100)))
    $percent = if ($null -eq $quotaPercent) { $livePercent } else { [Math]::Max($livePercent, $quotaPercent) }
    $activeCutoff = (Get-Date).AddMinutes(-2)
    $latestIsActive = ($null -ne $Latest -and $Latest.At -ge $activeCutoff)
    $latestCritical = ($latestIsActive -and $Latest.Risk -in @('Fresh input spike', 'Fresh burn spike', 'Reasoning spike', 'Output-heavy'))
    $liveCritical = ($latestCritical -or $Minute.FreshBurn -ge $WarnMinuteFreshTokens)
    $liveWarning = ($Minute.FreshBurn -ge ($WarnMinuteFreshTokens * 0.50) -or ($latestIsActive -and $Latest.Risk -eq 'Mostly cached context'))
    $quotaCritical = ($null -ne $quotaPercent -and $quotaPercent -ge 90)
    $quotaWarning = ($null -ne $quotaPercent -and $quotaPercent -ge 75)
    $details = [System.Collections.Generic.List[string]]::new()

    if ($liveCritical) { $details.Add('fresh burn spike') }
    elseif ($liveWarning) { $details.Add('fresh burn elevated') }
    if ($null -ne $quotaPercent) { $details.Add("quota $quotaPercent%") }

    if ($liveCritical -or $quotaCritical) {
        return [pscustomobject]@{ Label = 'CRITICAL'; Detail = ($details -join ', '); Percent = $percent; Color = [System.Drawing.Color]::Tomato }
    }
    if ($liveWarning -or $quotaWarning) {
        return [pscustomobject]@{ Label = 'WARN'; Detail = ($details -join ', '); Percent = $percent; Color = [System.Drawing.Color]::Orange }
    }
    if ($details.Count -eq 0) { $details.Add('fresh burn normal') }
    elseif (-not $liveWarning) { $details.Insert(0, 'fresh burn normal') }
    return [pscustomobject]@{ Label = 'OK'; Detail = ($details -join ', '); Percent = $percent; Color = [System.Drawing.Color]::Lime }
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
    param([object]$UsageEvent, [object[]]$VisibleEvents)

    if ($null -eq $UsageEvent) { return 'Select a row to explain the spike profile.' }
    $minuteEvents = @($VisibleEvents | Where-Object { $_.At -ge (Get-Date).AddMinutes(-1) })
    $minute = Get-SumPack -Items $minuteEvents
    $share = if ($minute.Total -gt 0) { [Math]::Round(($UsageEvent.Total / [double]$minute.Total) * 100, 1) } else { 0 }
    $cachedRatio = if ($UsageEvent.Input -gt 0) { [Math]::Round(($UsageEvent.Cached / [double]$UsageEvent.Input) * 100, 1) } else { 0 }

    return ('{0} | {1} | fresh {2} = new input {3} + output {4}; reasoning {5} is included in output. Context total {6}; {7}% of input was cached. This row is {8}% of visible last-60-second context. Session: {9}' -f
        $UsageEvent.At.ToString('HH:mm:ss'),
        $UsageEvent.Risk,
        (Format-Tokens $UsageEvent.FreshBurn),
        (Format-Tokens $UsageEvent.NewInput),
        (Format-Tokens $UsageEvent.Output),
        (Format-Tokens $UsageEvent.Reasoning),
        (Format-Tokens $UsageEvent.Total),
        $cachedRatio,
        $share,
        (Get-ShortSessionName -Path $UsageEvent.Source -MaxLength 55))
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
    param([object]$UsageEvent, [object]$Minute, [object[]]$VisibleEvents, [string]$Mode)

    if ($null -eq $UsageEvent) { return 'Action: waiting for the next completed Codex turn.' }
    $sessionCount = @($VisibleEvents | Select-Object -ExpandProperty Source -Unique).Count
    if ($Mode -eq 'All sessions' -and $sessionCount -gt 1) {
        return 'Action: multiple sessions are active. Switch to Follow latest or Pinned session when you want to isolate one task.'
    }
    if ($UsageEvent.Risk -eq 'Fresh input spike') {
        return 'Action: fresh input jumped. Avoid pasting large content; point Codex at files or ask for a summary-first pass.'
    }
    if ($UsageEvent.Risk -eq 'Reasoning spike') {
        return 'Action: reasoning jumped. Keep effort at medium for routine work and split big requests into smaller checkpoints.'
    }
    if ($UsageEvent.Risk -eq 'Output-heavy') {
        return 'Action: output jumped. Ask for concise output or have Codex save long results to a file.'
    }
    if ($Minute.FreshBurn -ge $WarnMinuteFreshTokens) {
        return 'Action: the last minute is hot. Pause before sending another large-context prompt.'
    }
    if ($UsageEvent.Risk -eq 'Mostly cached context') {
        return 'Action: mostly context replay. If this baseline keeps growing, start a new task with a short handoff summary.'
    }
    return 'Action: looks normal. Watch fresh burn for real new work; context is the replayed task history.'
}

function Should-Alert {
    param([object]$UsageEvent, [object]$Minute)
    if ($null -eq $UsageEvent) { return $false }
    if ($UsageEvent.At -lt (Get-Date).AddMinutes(-2)) { return $false }
    if ($UsageEvent.EventId -eq $script:lastAlertEventId) { return $false }
    if ($UsageEvent.NewInput -ge $WarnNewInputTokens) { return $true }
    if ($UsageEvent.FreshBurn -ge $WarnMinuteFreshTokens) { return $true }
    if ($Minute.FreshBurn -ge $WarnMinuteFreshTokens) { return $true }
    if ($UsageEvent.Reasoning -ge $WarnReasoningTokens) { return $true }
    if ($UsageEvent.Output -ge $WarnOutputTokens) { return $true }
    return $false
}

function Send-Alert {
    param([object]$UsageEvent, [object]$Minute)

    $script:lastAlertEventId = $UsageEvent.EventId
    $message = 'Fresh {0}; new input {1}; last 60s fresh {2}' -f (Format-Tokens $UsageEvent.FreshBurn), (Format-Tokens $UsageEvent.NewInput), (Format-Tokens $Minute.FreshBurn)
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
    $selectedEvents = @(Get-DisplayEvents -Mode 'All sessions')
    $latest = @($selectedEvents | Select-Object -First 1)
    if ($latest.Count -eq 0) { Write-Output 'No recent token events found.'; exit 0 }
    $usageEvent = $latest[0]
    Write-Output ("Events={0}; Latest={1}; FreshBurn={2}; NewInput={3}; Context={4}; Risk={5}" -f $selectedEvents.Count, $usageEvent.At.ToString('HH:mm:ss'), (Format-Tokens $usageEvent.FreshBurn), (Format-Tokens $usageEvent.NewInput), (Format-Tokens $usageEvent.Total), $usageEvent.Risk)
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

if ($DateRangeSmokeTest) {
    $ordered = @(Get-DisplayEvents -Mode 'All sessions' | Sort-Object At)
    if ($ordered.Count -eq 0) { throw 'Date-range smoke test requires at least one token event.' }
    $testDate = $ordered[0].At.Date
    Set-MonitorDateRange -FromDate $testDate -ToDate $testDate
    Write-Output ('DateRange={0}; Events={1}' -f (Format-DateRange), @(Get-DisplayEvents -Mode 'All sessions').Count)
    exit 0
}

if ($AlertSmokeTest) {
    $latest = @($script:events | Sort-Object At -Descending | Select-Object -First 1)
    if ($latest.Count -eq 0) { throw 'Alert smoke test requires at least one token event.' }
    $minute = Get-SumPack -Items @($latest)
    $staleAlert = Should-Alert -UsageEvent $latest[0] -Minute $minute
    $activeEvent = $latest[0].PSObject.Copy()
    $activeEvent.At = Get-Date
    $activeEvent.NewInput = $WarnNewInputTokens
    $activeAlert = Should-Alert -UsageEvent $activeEvent -Minute $minute
    Write-Output ('StaleAlert={0}; ActiveAlert={1}' -f $staleAlert, $activeAlert)
    exit 0
}

if ($ArchivedSmokeTest) {
    $archived = @($script:events | Where-Object { $_.Source -match '[\\/]archived_sessions[\\/]' })
    Write-Output ('ArchivedEvents={0}; TotalEvents={1}' -f $archived.Count, $script:events.Count)
    exit 0
}

if ($PresetSmokeTest) {
    $anchor = [datetime]'2026-07-27'
    $week = Get-DatePresetRange -Preset 'Last 7 days' -Today $anchor
    $month = Get-DatePresetRange -Preset 'Last 30 days' -Today $anchor
    $all = Get-DatePresetRange -Preset 'All available' -Today $anchor
    Write-Output ('Week={0}:{1}; MonthDays={2}; AllStart={3}' -f $week.Start.ToString('yyyy-MM-dd'), $week.End.ToString('yyyy-MM-dd'), (($month.End - $month.Start).Days + 1), $all.Start.ToString('yyyy-MM-dd'))
    exit 0
}

if ($RangeCacheSmokeTest) {
    $linesBefore = $script:scanStats.LinesRead
    Set-MonitorDateRange -FromDate ([datetime]'2026-07-25') -ToDate ([datetime]'2026-07-25')
    $firstCount = @(Get-DisplayEvents -Mode 'All sessions').Count
    Set-MonitorDateRange -FromDate ([datetime]'2026-07-26') -ToDate ([datetime]'2026-07-26')
    $secondCount = @(Get-DisplayEvents -Mode 'All sessions').Count
    $cacheStable = ($script:scanStats.LinesRead -eq $linesBefore)
    Write-Output ('CacheStable={0}; FirstRange={1}; SecondRange={2}; LinesRead={3}' -f $cacheStable, $firstCount, $secondCount, $script:scanStats.LinesRead)
    exit 0
}

if ($QuotaResetSmokeTest) {
    $resetAt = (Get-Date).AddMinutes(90)
    $epoch = [datetimeoffset]$resetAt
    $window = [pscustomobject]@{
        used_percent = 60
        reset_at = $epoch.ToUnixTimeSeconds()
        window_minutes = 300
    }
    $usageEvent = [pscustomobject]@{
        RateLimits = [pscustomobject]@{ primary = $window }
    }
    Write-Output (Get-QuotaText -UsageEvent $usageEvent)
    exit 0
}

if ($ExportSmokeTest) {
    if ([string]::IsNullOrWhiteSpace($ExportPath)) { throw '-ExportSmokeTest requires -ExportPath.' }
    $rows = @(Export-LocalUsageSummary -Path $ExportPath)
    Write-Output ('ExportRows={0}; Events={1}; Path={2}' -f $rows.Count, (@($rows | Measure-Object -Property Events -Sum)[0].Sum), $ExportPath)
    exit 0
}

if ($EnterpriseSmokeTest) {
    if ([string]::IsNullOrWhiteSpace($EnterpriseCsvPath)) { throw '-EnterpriseSmokeTest requires -EnterpriseCsvPath.' }
    $enterpriseModule = Join-Path $scriptDir 'Live-Codex-Usage-Enterprise.psm1'
    Import-Module -Name $enterpriseModule -Force
    $summary = Import-WorkspaceAnalyticsReport -Path $EnterpriseCsvPath
    Write-Output ('Rows={0}; ActiveUsers={1}; Messages={2}; ToolMessages={3}; SeatTypes={4}' -f $summary.Rows, $summary.ActiveUsers, $summary.TotalMessages, $summary.ToolMessages, $summary.SeatTypes.Count)
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

if ($StatusSmokeTest) {
    $latest = @($script:events | Sort-Object At -Descending | Select-Object -First 1)
    if ($latest.Count -eq 0) { throw 'Status smoke test requires at least one token event.' }
    $minute = Get-SumPack -Items @($latest)
    $status = Get-OverallStatus -Latest $latest[0] -Minute $minute
    Write-Output ('QuotaPercent={0}; Status={1}; Detail={2}' -f (Get-QuotaPercent -UsageEvent $latest[0]), $status.Label, $status.Detail)
    exit 0
}

if (-not $NoNotifications) {
    $script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
    $script:notifyIcon.Text = 'Live Codex Usage'
    $script:notifyIcon.Visible = $true
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Live Codex Usage - Local Logs Only'
$workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$initialWidth = [Math]::Min(1320, [Math]::Max(820, $workingArea.Width - 40))
$initialHeight = [Math]::Min(980, [Math]::Max(640, $workingArea.Height - 40))
$form.Size = New-Object System.Drawing.Size($initialWidth, $initialHeight)
$form.MinimumSize = New-Object System.Drawing.Size(820, 640)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScroll = $true
$form.KeyPreview = $true
$form.AccessibleName = 'Live Codex Usage Monitor'
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
    $label.AutoEllipsis = $true
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

function Add-DatePicker {
    param([datetime]$Value, [int]$X, [int]$Y, [int]$Width)
    $picker = New-Object System.Windows.Forms.DateTimePicker
    $picker.Location = New-Object System.Drawing.Point($X, $Y)
    $picker.Size = New-Object System.Drawing.Size($Width, 28)
    $picker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $picker.CustomFormat = 'yyyy-MM-dd'
    $picker.Value = $Value
    $picker.MaxDate = (Get-Date).Date
    $picker.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Controls.Add($picker)
    return $picker
}

$title = Add-Label 'LIVE CODEX USAGE - local logs only' 18 14 760 30 16
$title.ForeColor = [System.Drawing.Color]::Aqua
$statusLabel = Add-Label 'Status: waiting' 856 16 246 26 13
$statusLabel.ForeColor = [System.Drawing.Color]::Khaki
$statusMeter = New-Object System.Windows.Forms.Panel
$statusMeter.Location = New-Object System.Drawing.Point(1118, 18)
$statusMeter.Size = New-Object System.Drawing.Size(160, 20)
$statusMeter.BackColor = [System.Drawing.Color]::FromArgb(70, 70, 70)
$statusMeter.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$statusMeter.Anchor = 'Top,Right'
$statusMeter.AccessibleName = 'Overall usage status meter'
$statusMeterFill = New-Object System.Windows.Forms.Panel
$statusMeterFill.Location = New-Object System.Drawing.Point(0, 0)
$statusMeterFill.Size = New-Object System.Drawing.Size(0, 18)
$statusMeterFill.BackColor = [System.Drawing.Color]::Lime
$statusMeter.Controls.Add($statusMeterFill)
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
$noteLabel = Add-Label 'Offline local-log monitor. Only explicit aggregate CSV exports write files; prompts, responses, tool data, paths, and network data are never exported or sent.' 18 242 1240 22 10
$noteLabel.ForeColor = [System.Drawing.Color]::DarkGray
$sessionSummaryLabel = Add-Label 'Sessions: waiting for token events' 18 264 1240 22 10
$sessionSummaryLabel.ForeColor = [System.Drawing.Color]::Khaki
$integrationSummaryLabel = Add-Label 'Integrations: waiting for tool/plugin/add-in calls' 18 286 1240 22 10
$integrationSummaryLabel.ForeColor = [System.Drawing.Color]::Khaki

$modeLabel = Add-Label 'View' 18 314 40 26 10
$viewAllButton = Add-Button 'All tasks' 62 310 92 30
$viewLatestButton = Add-Button 'Latest' 164 310 78 30
$viewPinnedButton = Add-Button 'Pinned' 252 310 82 30
$pinButton = Add-Button 'Pin latest' 344 310 90 30
$clearButton = Add-Button 'Start fresh' 444 310 100 30
$miniButton = Add-Button 'Mini mode' 554 310 95 30
$enterpriseButton = Add-Button 'Enterprise' 659 310 130 30

$presetLabel = Add-Label 'Range' 18 350 42 24 9
$presetBox = New-Object System.Windows.Forms.ComboBox
$presetBox.Location = New-Object System.Drawing.Point(62, 347)
$presetBox.Size = New-Object System.Drawing.Size(130, 28)
$presetBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$presetBox.Font = New-Object System.Drawing.Font('Segoe UI', 9)
[void]$presetBox.Items.AddRange(@('Today', 'Last 7 days', 'Last 30 days', 'All available', 'Custom'))
$presetBox.SelectedItem = 'Custom'
$form.Controls.Add($presetBox)
$fromLabel = Add-Label 'From' 206 350 38 24 9
$fromPicker = Add-DatePicker -Value $script:rangeStart.Date -X 246 -Y 347 -Width 110
$toLabel = Add-Label 'To' 366 350 20 24 9
$initialToDate = if ($script:rangeEnd -eq [datetime]::MaxValue) { (Get-Date).Date } else { $script:rangeEnd.Date }
$toPicker = Add-DatePicker -Value $initialToDate -X 388 -Y 347 -Width 110
$loadRangeButton = Add-Button 'Load dates' 508 346 96 30
$exportButton = Add-Button 'Export CSV' 614 346 96 30
$historyLabel = Add-Label ("Loaded: {0}" -f (Format-DateRange)) 720 350 568 24 9
$historyLabel.ForeColor = [System.Drawing.Color]::DarkGray

$tokenLabel = Add-Label 'Token events' 18 386 820 22 11
$tokenLabel.ForeColor = [System.Drawing.Color]::Aqua
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(18, 412)
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

$taskLabel = Add-Label 'Task breakdown: double-click a task to pin it' 850 386 438 22 11
$taskLabel.ForeColor = [System.Drawing.Color]::Aqua

$taskGrid = New-Object System.Windows.Forms.DataGridView
$taskGrid.Location = New-Object System.Drawing.Point(850, 412)
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
foreach ($name in @('Task','Model','Health','Avg fresh','Avg ctx','Cache','Status')) {
    [void]$taskGrid.Columns.Add($name, $name)
}
$taskGrid.Columns['Task'].FillWeight = 260
$taskGrid.Columns['Model'].FillWeight = 95
$taskGrid.Columns['Health'].FillWeight = 95
$taskGrid.Columns['Avg fresh'].FillWeight = 80
$taskGrid.Columns['Avg ctx'].FillWeight = 80
$taskGrid.Columns['Cache'].FillWeight = 70
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
$script:normalFormSize = $form.Size
$script:normalFormLocation = $form.Location
$script:normalMinimumSize = New-Object System.Drawing.Size(820, 640)
$script:normalMiniButtonLocation = $miniButton.Location
$script:fullModeControls = @(
    $modelSummaryLabel, $timeSummaryLabel, $noteLabel, $sessionSummaryLabel, $integrationSummaryLabel,
    $modeLabel, $viewAllButton, $viewLatestButton, $viewPinnedButton, $pinButton, $clearButton,
    $enterpriseButton, $presetLabel, $presetBox, $fromLabel, $fromPicker, $toLabel, $toPicker, $loadRangeButton, $exportButton,
    $historyLabel, $tokenLabel, $grid, $taskLabel, $taskGrid,
    $integrationLabel, $integrationGrid, $activityLabel, $activityGrid, $explainBox
)

$grid.AccessibleName = 'Token events table'
$taskGrid.AccessibleName = 'Task breakdown table'
$integrationGrid.AccessibleName = 'Integration activity table'
$activityGrid.AccessibleName = 'Sanitized activity table'
$fromPicker.AccessibleName = 'Usage range start date'
$toPicker.AccessibleName = 'Usage range end date'
$presetBox.AccessibleName = 'Usage date range preset'
$loadRangeButton.AccessibleName = 'Load selected date range'
$exportButton.AccessibleName = 'Export privacy-safe daily summary'
$enterpriseButton.AccessibleName = 'Import Workspace Analytics CSV'
$miniButton.AccessibleName = 'Toggle compact monitor mode'

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($presetBox, 'Choose a quick range. Custom keeps the calendar selections.')
$toolTip.SetToolTip($loadRangeButton, 'Load the complete selected date range (Ctrl+L).')
$toolTip.SetToolTip($exportButton, 'Export daily aggregates only; no prompts, paths, task names, or identifiers (Ctrl+E).')
$toolTip.SetToolTip($enterpriseButton, 'Open an aggregate Workspace Analytics CSV from ChatGPT Enterprise or Edu.')
$toolTip.SetToolTip($miniButton, 'Toggle the always-on-top compact view (Ctrl+M).')
$toolTip.SetToolTip($clearButton, 'Discard the in-memory window and watch only newly appended log records.')

$tabOrder = @(
    $viewAllButton, $viewLatestButton, $viewPinnedButton, $pinButton, $clearButton, $miniButton,
    $enterpriseButton, $presetBox, $fromPicker, $toPicker, $loadRangeButton, $exportButton,
    $grid, $taskGrid, $integrationGrid, $activityGrid, $explainBox
)
for ($tabIndex = 0; $tabIndex -lt $tabOrder.Count; $tabIndex++) {
    $tabOrder[$tabIndex].TabIndex = $tabIndex
}

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
    $clientH = [Math]::Max(940, $form.ClientSize.Height)
    $contentW = $clientW - ($margin * 2)
    $rightW = [Math]::Max(480, [Math]::Min(650, [int]($contentW * 0.38)))
    $leftW = [Math]::Max(560, $contentW - $gap - $rightW)
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
    $gridY = 412
    $gridH = [Math]::Max(220, $activityLabelY - $gridY - 10)
    $lowerGap = 16
    $integrationW = [Math]::Max(420, [int](($contentW - $lowerGap) * 0.36))
    $activityW = $contentW - $lowerGap - $integrationW
    $activityX = $margin + $integrationW + $lowerGap

    $tokenLabel.Location = New-Object System.Drawing.Point($margin, 386)
    $tokenLabel.Size = New-Object System.Drawing.Size($leftW, 22)
    $grid.Location = New-Object System.Drawing.Point($margin, $gridY)
    $grid.Size = New-Object System.Drawing.Size($leftW, $gridH)

    $taskLabel.Location = New-Object System.Drawing.Point($rightX, 386)
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
    $historyLabel.Size = New-Object System.Drawing.Size([Math]::Max(260, $contentW - 702), 24)
}

function Set-MiniMode {
    param([bool]$Enabled)

    $wasMini = $script:isMiniMode
    if ($Enabled -and -not $wasMini) {
        $script:normalFormSize = $form.Size
        $script:normalFormLocation = $form.Location
    }
    $script:isMiniMode = $Enabled
    foreach ($control in $script:fullModeControls) {
        $control.Visible = -not $Enabled
    }
    if ($Enabled) {
        $form.TopMost = $true
        $form.MinimumSize = New-Object System.Drawing.Size(680, 260)
        $form.Size = New-Object System.Drawing.Size(780, 280)
        $miniButton.Text = 'Full mode'
        $miniButton.Location = New-Object System.Drawing.Point(650, 10)
        $miniButton.Size = New-Object System.Drawing.Size(100, 30)
        $title.Location = New-Object System.Drawing.Point(18, 12)
        $title.Size = New-Object System.Drawing.Size(260, 28)
        $statusLabel.Location = New-Object System.Drawing.Point(292, 14)
        $statusLabel.Size = New-Object System.Drawing.Size(340, 24)
        $statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11)
        $statusMeter.Location = New-Object System.Drawing.Point(18, 45)
        $statusMeter.Size = New-Object System.Drawing.Size(732, 12)
        $title.Text = 'CODEX USAGE - mini'
        $freshLabel.Location = New-Object System.Drawing.Point(18, 64)
        $freshLabel.Size = New-Object System.Drawing.Size(732, 26)
        $freshLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11)
        $minuteLabel.Location = New-Object System.Drawing.Point(18, 94)
        $minuteLabel.Size = New-Object System.Drawing.Size(732, 24)
        $minuteLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        $quotaLabel.Location = New-Object System.Drawing.Point(18, 122)
        $quotaLabel.Size = New-Object System.Drawing.Size(732, 22)
        $guidanceLabel.Location = New-Object System.Drawing.Point(18, 150)
        $guidanceLabel.Size = New-Object System.Drawing.Size(732, 40)
        $guidanceLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
        $windowLabel.Location = New-Object System.Drawing.Point(18, 198)
        $windowLabel.Size = New-Object System.Drawing.Size(732, 22)
        $windowLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    }
    else {
        $form.TopMost = $false
        $form.MinimumSize = $script:normalMinimumSize
        $form.Size = $script:normalFormSize
        if ($wasMini) { $form.Location = $script:normalFormLocation }
        $miniButton.Text = 'Mini mode'
        $miniButton.Location = $script:normalMiniButtonLocation
        $miniButton.Size = New-Object System.Drawing.Size(95, 30)
        $title.Text = 'LIVE CODEX USAGE - local logs only'
        $title.Location = New-Object System.Drawing.Point(18, 14)
        $statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 13)
        $freshLabel.Location = New-Object System.Drawing.Point(18, 52)
        $freshLabel.Size = New-Object System.Drawing.Size(1240, 32)
        $freshLabel.Font = New-Object System.Drawing.Font('Segoe UI', 15)
        $guidanceLabel.Location = New-Object System.Drawing.Point(18, 88)
        $guidanceLabel.Size = New-Object System.Drawing.Size(1240, 26)
        $guidanceLabel.Font = New-Object System.Drawing.Font('Segoe UI', 12)
        $minuteLabel.Location = New-Object System.Drawing.Point(18, 116)
        $minuteLabel.Size = New-Object System.Drawing.Size(1240, 25)
        $minuteLabel.Font = New-Object System.Drawing.Font('Segoe UI', 12)
        $windowLabel.Location = New-Object System.Drawing.Point(18, 144)
        $windowLabel.Size = New-Object System.Drawing.Size(1240, 24)
        $windowLabel.Font = New-Object System.Drawing.Font('Segoe UI', 11)
        $quotaLabel.Location = New-Object System.Drawing.Point(18, 170)
        $quotaLabel.Size = New-Object System.Drawing.Size(1240, 22)
        $quotaLabel.Font = New-Object System.Drawing.Font('Segoe UI', 10)
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
    $activity = @(if ($script:focusedSession) { $allActivity | Where-Object { $_.Session -eq $script:focusedSession } } else { $allActivity })
    $integrations = @(if ($script:focusedSession) { $allIntegrations | Where-Object { $_.Session -eq $script:focusedSession } } else { $allIntegrations })
    $tasks = @(Get-TaskBreakdown -VisibleEvents $visible)
    $script:visibleEvents = $visible
    $script:visibleActivity = $activity
    $script:visibleIntegrations = $integrations
    $script:visibleTasks = $tasks
    $latest = if ($visible.Count -gt 0) { $visible[0] } else { $null }
    $minuteEvents = @($visible | Where-Object { $_.At -ge (Get-Date).AddMinutes(-1) })
    $minute = Get-SumPack -Items $minuteEvents
    $window = Get-SumPack -Items $visible
    $status = Get-OverallStatus -Latest $latest -Minute $minute
    $statusLabel.Text = 'Status: {0} ({1})' -f $status.Label, $status.Detail
    $statusLabel.ForeColor = $status.Color
    $meterPercent = [Math]::Max(0, [Math]::Min(100, [int]$status.Percent))
    $statusMeterFill.BackColor = $status.Color
    $statusMeterFill.Size = New-Object System.Drawing.Size([Math]::Floor(($statusMeter.ClientSize.Width * $meterPercent) / 100), $statusMeter.ClientSize.Height)

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
        if (Should-Alert -UsageEvent $latest -Minute $minute) {
            Send-Alert -UsageEvent $latest -Minute $minute
        }
    }

    $minuteLabel.Text = 'Last 60 seconds - fresh {0} | new input {1} | output {2} | reasoning {3} | context {4} | cached {5}' -f (Format-Tokens $minute.FreshBurn), (Format-Tokens $minute.NewInput), (Format-Tokens $minute.Output), (Format-Tokens $minute.Reasoning), (Format-Tokens $minute.Total), (Format-Tokens $minute.Cached)
    if ($minute.FreshBurn -ge $WarnMinuteFreshTokens) {
        $minuteLabel.ForeColor = [System.Drawing.Color]::Tomato
    }
    else {
        $minuteLabel.ForeColor = [System.Drawing.Color]::Gainsboro
    }
    $guidanceLabel.Text = Get-GuidanceText -UsageEvent $latest -Minute $minute -VisibleEvents $visible -Mode $mode
    if ($guidanceLabel.Text -match 'jumped|hot|multiple') {
        $guidanceLabel.ForeColor = [System.Drawing.Color]::Tomato
    }
    elseif ($guidanceLabel.Text -match 'mostly context') {
        $guidanceLabel.ForeColor = [System.Drawing.Color]::Khaki
    }
    else {
        $guidanceLabel.ForeColor = [System.Drawing.Color]::White
    }
    $windowLabel.Text = 'Monitor window - events: {0} | fresh {1} | context {2} | sessions {3} | logs {4}/{5} | started {6}' -f $visible.Count, (Format-Tokens $window.FreshBurn), (Format-Tokens $window.Total), (@($visible | Select-Object -ExpandProperty Source -Unique).Count), $script:scanStats.LoadedFiles, $script:scanStats.AvailableFiles, $script:startedAt.ToString('HH:mm:ss')
    $quotaLabel.Text = Get-QuotaText -UsageEvent $latest
    $modelSummaryLabel.Text = Get-ModelBreakdownText -VisibleEvents $visible
    $timeSummaryLabel.Text = Get-TimeSummaryText -VisibleEvents $visible
    $sessionSummaryLabel.Text = Get-SessionSummaryText -VisibleEvents $visible
    $integrationSummaryLabel.Text = Get-IntegrationSummaryText -VisibleIntegrations $integrations
    $historyLabel.Text = 'Loaded: {0}' -f (Format-DateRange)
    if ($script:isMiniMode) {
        $statusLabel.Text = '{0}  {1}%' -f $status.Label, $status.Percent
        if ($null -eq $latest) {
            $freshLabel.Text = 'Latest: waiting for a completed Codex turn'
        }
        else {
            $freshLabel.Text = 'Latest {0}  |  fresh {1}  |  context {2}  |  {3}' -f $latest.At.ToString('HH:mm:ss'), (Format-Tokens $latest.FreshBurn), (Format-Tokens $latest.Total), $latest.Risk
        }
        $minuteLabel.Text = '60s  |  fresh {0}  |  new {1}  |  output {2}  |  reasoning {3}' -f (Format-Tokens $minute.FreshBurn), (Format-Tokens $minute.NewInput), (Format-Tokens $minute.Output), (Format-Tokens $minute.Reasoning)
        $windowLabel.Text = 'Range {0}  |  {1} events  |  {2} tasks  |  updated {3}' -f (Format-DateRange), $visible.Count, $tasks.Count, (Get-Date).ToString('HH:mm:ss')
    }

    $grid.Rows.Clear()
    $focusedGridRow = -1
    foreach ($usageEvent in $visible | Select-Object -First 100) {
        $rowIndex = $grid.Rows.Add(
            $usageEvent.At.ToString('HH:mm:ss'),
            (Format-Tokens $usageEvent.FreshBurn),
            (Format-Tokens $usageEvent.NewInput),
            (Format-Tokens $usageEvent.Output),
            (Format-Tokens $usageEvent.Reasoning),
            (Format-Tokens $usageEvent.Total),
            (Format-Tokens $usageEvent.Cached),
            $usageEvent.Risk,
            (Get-FriendlyTaskLabel -Path $usageEvent.Source)
        )
        $row = $grid.Rows[$rowIndex]
        $row.Tag = $usageEvent
        if ($script:focusedEventId -and $usageEvent.EventId -eq $script:focusedEventId) { $focusedGridRow = $rowIndex }
        if ($usageEvent.Risk -eq 'Fresh input spike' -or $usageEvent.Risk -eq 'Fresh burn spike' -or $usageEvent.Risk -eq 'Reasoning spike' -or $usageEvent.Risk -eq 'Output-heavy') {
            $row.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Tomato
        }
        elseif ($usageEvent.Risk -eq 'Mostly cached context') {
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
        $explainBox.Text = Get-ExplainText -UsageEvent $focusedEvent[0] -VisibleEvents $visible
    }
    elseif ($script:focusedSession) {
        $focusedTask = @($tasks | Where-Object { $_.Session -eq $script:focusedSession } | Select-Object -First 1)
        if ($focusedTask.Count -gt 0) {
            $explainBox.Text = Get-TaskExplainText -Task $focusedTask[0]
        }
        elseif ($null -ne $latest) {
            $explainBox.Text = Get-ExplainText -UsageEvent $latest -VisibleEvents $visible
        }
    }
    elseif ($null -ne $latest) {
        $explainBox.Text = Get-ExplainText -UsageEvent $latest -VisibleEvents $visible
    }
    else {
        $explainBox.Text = 'Select a row to explain the spike profile.'
    }
    }
    finally {
        $script:isRefreshing = $false
    }
}

function Show-EnterpriseAnalyticsDialog {
    param(
        [string]$Path = '',
        [switch]$ConstructionOnly,
        [string]$ScreenshotPath = ''
    )

    $selectedPath = $Path
    if ([string]::IsNullOrWhiteSpace($selectedPath)) {
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $openDialog.Title = 'Open Workspace Analytics user CSV'
            $openDialog.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
            $openDialog.CheckFileExists = $true
            $openDialog.Multiselect = $false
            if ($openDialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $selectedPath = $openDialog.FileName
        }
        finally {
            $openDialog.Dispose()
        }
    }

    $enterpriseModule = Join-Path $scriptDir 'Live-Codex-Usage-Enterprise.psm1'
    Import-Module -Name $enterpriseModule -Force
    $summary = Import-WorkspaceAnalyticsReport -Path $selectedPath

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Enterprise Workspace Analytics - Aggregate View'
    $dialog.Size = New-Object System.Drawing.Size(980, 720)
    $dialog.MinimumSize = New-Object System.Drawing.Size(760, 560)
    $dialog.StartPosition = 'CenterParent'
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $dialog.ForeColor = [System.Drawing.Color]::Gainsboro
    $dialog.AccessibleName = 'Enterprise Workspace Analytics aggregate view'

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = 'WORKSPACE ANALYTICS - aggregate only'
    $heading.Location = New-Object System.Drawing.Point(18, 16)
    $heading.Size = New-Object System.Drawing.Size(920, 32)
    $heading.Anchor = 'Top,Left,Right'
    $heading.Font = New-Object System.Drawing.Font('Segoe UI', 16)
    $heading.ForeColor = [System.Drawing.Color]::Aqua
    $dialog.Controls.Add($heading)

    $overview = New-Object System.Windows.Forms.Label
    $periodText = if ($summary.PeriodStart -and $summary.PeriodEnd) {
        '{0} to {1}' -f $summary.PeriodStart.ToString('yyyy-MM-dd'), $summary.PeriodEnd.ToString('yyyy-MM-dd')
    }
    else { 'period not supplied' }
    $overview.Text = 'Period {0} | rows {1} | active users {2} | messages {3:N0} | GPT {4:N0} | tools {5:N0} | projects {6:N0}' -f $periodText, $summary.Rows, $summary.ActiveUsers, $summary.TotalMessages, $summary.GptMessages, $summary.ToolMessages, $summary.ProjectMessages
    $overview.Location = New-Object System.Drawing.Point(18, 56)
    $overview.Size = New-Object System.Drawing.Size(920, 54)
    $overview.Anchor = 'Top,Left,Right'
    $overview.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    $overview.ForeColor = [System.Drawing.Color]::White
    $dialog.Controls.Add($overview)

    $privacy = New-Object System.Windows.Forms.Label
    $privacy.Text = 'Names, email addresses, public IDs, account IDs, prompt text, and file content are neither shown nor retained by this view.'
    $privacy.Location = New-Object System.Drawing.Point(18, 112)
    $privacy.Size = New-Object System.Drawing.Size(920, 28)
    $privacy.Anchor = 'Top,Left,Right'
    $privacy.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $privacy.ForeColor = [System.Drawing.Color]::DarkGray
    $dialog.Controls.Add($privacy)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(18, 148)
    $tabs.Size = New-Object System.Drawing.Size(928, 500)
    $tabs.Anchor = 'Top,Bottom,Left,Right'
    $tabs.AccessibleName = 'Workspace Analytics breakdowns'
    $dialog.Controls.Add($tabs)

    $tabDefinitions = @(
        [pscustomobject]@{ Title = 'Seat types'; Rows = @($summary.SeatTypes); Columns = @('Name','Users','Messages') },
        [pscustomobject]@{ Title = 'Departments'; Rows = @($summary.Departments); Columns = @('Name','Users','Messages') },
        [pscustomobject]@{ Title = 'Tools'; Rows = @($summary.Tools); Columns = @('Name','Messages') },
        [pscustomobject]@{ Title = 'Models'; Rows = @($summary.Models); Columns = @('Name','Messages') }
    )
    foreach ($definition in $tabDefinitions) {
        $tab = New-Object System.Windows.Forms.TabPage
        $tab.Text = $definition.Title
        $tab.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $tab.ForeColor = [System.Drawing.Color]::Gainsboro
        $tabs.TabPages.Add($tab)

        $summaryGrid = New-Object System.Windows.Forms.DataGridView
        $summaryGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
        $summaryGrid.ReadOnly = $true
        $summaryGrid.AllowUserToAddRows = $false
        $summaryGrid.AllowUserToDeleteRows = $false
        $summaryGrid.RowHeadersVisible = $false
        $summaryGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
        $summaryGrid.BackgroundColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $summaryGrid.GridColor = [System.Drawing.Color]::FromArgb(65, 65, 65)
        $summaryGrid.EnableHeadersVisualStyles = $false
        $summaryGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
        $summaryGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
        $summaryGrid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
        $summaryGrid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::Gainsboro
        $summaryGrid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 90, 120)
        $summaryGrid.AccessibleName = "$($definition.Title) aggregate table"
        foreach ($column in $definition.Columns) { [void]$summaryGrid.Columns.Add($column, $column) }
        foreach ($row in $definition.Rows) {
            $values = foreach ($column in $definition.Columns) { $row.$column }
            [void]$summaryGrid.Rows.Add([object[]]$values)
        }
        $tab.Controls.Add($summaryGrid)
    }

    if ($ConstructionOnly) {
        if (-not [string]::IsNullOrWhiteSpace($ScreenshotPath)) {
            $captureParent = Split-Path -Parent $ScreenshotPath
            if ($captureParent -and -not (Test-Path -LiteralPath $captureParent -PathType Container)) {
                throw "Screenshot folder does not exist: $captureParent"
            }
            $dialog.Show()
            [System.Windows.Forms.Application]::DoEvents()
            $bitmap = New-Object System.Drawing.Bitmap($dialog.ClientSize.Width, $dialog.ClientSize.Height)
            try {
                $dialog.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)))
                $bitmap.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $bitmap.Dispose()
                $dialog.Hide()
            }
        }
        Write-Output ('Enterprise dialog constructed successfully; Tabs={0}' -f $tabs.TabPages.Count)
    }
    else {
        [void]$dialog.ShowDialog($form)
    }
    $dialog.Dispose()
}

function Invoke-LoadSelectedRange {
    if ($script:isRefreshing) { return }
    try {
        $loadRangeButton.Enabled = $false
        $form.UseWaitCursor = $true
        $historyLabel.Text = 'Loading selected dates...'
        [System.Windows.Forms.Application]::DoEvents()
        Set-MonitorDateRange -FromDate $fromPicker.Value -ToDate $toPicker.Value
        Refresh-Display
        $explainBox.Text = 'Loaded complete local Codex logs for {0}.' -f (Format-DateRange)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to load dates') | Out-Null
    }
    finally {
        $form.UseWaitCursor = $false
        $loadRangeButton.Enabled = $true
    }
}

function Invoke-LocalSummaryExport {
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    try {
        $saveDialog.Title = 'Export privacy-safe daily usage summary'
        $saveDialog.Filter = 'CSV files (*.csv)|*.csv'
        $saveDialog.DefaultExt = 'csv'
        $saveDialog.AddExtension = $true
        $saveDialog.OverwritePrompt = $true
        $saveDialog.FileName = 'codex-usage-summary-{0}-{1}.csv' -f $script:rangeStart.ToString('yyyyMMdd'), $(if ($script:rangeEnd -eq [datetime]::MaxValue) { (Get-Date).ToString('yyyyMMdd') } else { $script:rangeEnd.ToString('yyyyMMdd') })
        if ($saveDialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $rows = @(Export-LocalUsageSummary -Path $saveDialog.FileName -UsageEvents $script:visibleEvents -IntegrationEvents $script:visibleIntegrations)
        $explainBox.Text = 'Exported {0} daily aggregate row(s). The CSV excludes prompts, responses, task names, session IDs, source paths, tool arguments, and tool output.' -f $rows.Count
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to export summary') | Out-Null
    }
    finally {
        $saveDialog.Dispose()
    }
}

if ($EnterpriseUiSmokeTest) {
    if ([string]::IsNullOrWhiteSpace($EnterpriseCsvPath)) { throw '-EnterpriseUiSmokeTest requires -EnterpriseCsvPath.' }
    Show-EnterpriseAnalyticsDialog -Path $EnterpriseCsvPath -ConstructionOnly -ScreenshotPath $CaptureScreenshotPath
    $form.Dispose()
    if ($null -ne $script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    exit 0
}

$grid.Add_SelectionChanged({
    if ($script:isRefreshing) { return }
    if ($grid.SelectedRows.Count -gt 0 -and $null -ne $grid.SelectedRows[0].Tag) {
        $usageEvent = $grid.SelectedRows[0].Tag
        $script:focusedSession = [string]$usageEvent.Session
        $script:focusedEventId = [string]$usageEvent.EventId
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
$loadRangeButton.Add_Click({ Invoke-LoadSelectedRange })
$exportButton.Add_Click({ Invoke-LocalSummaryExport })
$enterpriseButton.Add_Click({
    try {
        Show-EnterpriseAnalyticsDialog
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to import Workspace Analytics') | Out-Null
    }
})
$script:isApplyingPreset = $false
$presetBox.Add_SelectedIndexChanged({
    if ($script:isApplyingPreset -or [string]$presetBox.SelectedItem -eq 'Custom') { return }
    try {
        $script:isApplyingPreset = $true
        $range = Get-DatePresetRange -Preset ([string]$presetBox.SelectedItem)
        $fromPicker.Value = $range.Start
        $toPicker.Value = $range.End
    }
    finally {
        $script:isApplyingPreset = $false
    }
    Invoke-LoadSelectedRange
})
$fromPicker.Add_ValueChanged({
    if (-not $script:isApplyingPreset) { $presetBox.SelectedItem = 'Custom' }
})
$toPicker.Add_ValueChanged({
    if (-not $script:isApplyingPreset) { $presetBox.SelectedItem = 'Custom' }
})
$miniButton.Add_Click({
    Set-MiniMode -Enabled (-not $script:isMiniMode)
    Refresh-Display
})
$form.Add_KeyDown({
    if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::L) {
        $_.SuppressKeyPress = $true
        Invoke-LoadSelectedRange
    }
    elseif ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::E) {
        $_.SuppressKeyPress = $true
        Invoke-LocalSummaryExport
    }
    elseif ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::M) {
        $_.SuppressKeyPress = $true
        $miniButton.PerformClick()
    }
    elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        $_.SuppressKeyPress = $true
        Refresh-Display
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollSeconds * 1000
$timer.Add_Tick({
    try {
        Refresh-Display
    }
    catch {
        $statusLabel.Text = 'Status: ERROR (log refresh failed)'
        $statusLabel.ForeColor = [System.Drawing.Color]::Tomato
        $explainBox.Text = $_.Exception.Message
    }
})
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
    if (-not [string]::IsNullOrWhiteSpace($CaptureScreenshotPath)) {
        $captureParent = Split-Path -Parent $CaptureScreenshotPath
        if ($captureParent -and -not (Test-Path -LiteralPath $captureParent -PathType Container)) {
            throw "Screenshot folder does not exist: $captureParent"
        }
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        $bitmap = New-Object System.Drawing.Bitmap($form.ClientSize.Width, $form.ClientSize.Height)
        try {
            $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)))
            $bitmap.Save($CaptureScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $bitmap.Dispose()
            $form.Hide()
        }
        Write-Output "Screenshot captured: $CaptureScreenshotPath"
    }
    $form.Dispose()
    if ($null -ne $script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    exit 0
}

[void]$form.ShowDialog()
