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
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -AllowMultipleInstances

Optional QA (no window):
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -Once
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -UiSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -UiLayoutSmokeTest
  powershell -NoProfile -File .\Live-Codex-Usage-GUI.ps1 -UiInteractionSmokeTest
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
    [string]$StateRoot = '',
    [switch]$DisablePersistence,
    [string]$OfficialSnapshotPath = '',
    [switch]$Once,
    [switch]$UiSmokeTest,
    [switch]$UiLayoutSmokeTest,
    [switch]$UiInteractionSmokeTest,
    [string]$InteractionAppendPath = '',
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
    [switch]$ComplianceUiSmokeTest,
    [string]$ComplianceInputPath = '',
    [string]$ComplianceMappingPath = '',
    [switch]$InsightsUiSmokeTest,
    [switch]$PerformanceSmokeTest,
    [switch]$CatalogExpansionSmokeTest,
    [switch]$EfficiencySmokeTest,
    [string]$RtkExecutablePath = '',
    [switch]$DisableRtkIntegration,
    [switch]$StartMinimizedToTray,
    [switch]$AllowMultipleInstances,
    [ValidateRange(0, 8)]
    [int]$InsightsTabIndex = 0,
    [string]$CaptureScreenshotPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }

$costModule = Join-Path $scriptDir 'Live-Codex-Usage-Cost.psm1'
$efficiencyModule = Join-Path $scriptDir 'Live-Codex-Usage-Efficiency.psm1'
$guardModule = Join-Path $scriptDir 'Live-Codex-Usage-Guard.psm1'
$instanceModule = Join-Path $scriptDir 'Live-Codex-Usage-Instance.psm1'
$personalModule = Join-Path $scriptDir 'Live-Codex-Usage-Personal.psm1'
$privacyModule = Join-Path $scriptDir 'Live-Codex-Usage-Privacy.psm1'
$rtkModule = Join-Path $scriptDir 'Live-Codex-Usage-RTK.psm1'
$reconciliationModule = Join-Path $scriptDir 'Live-Codex-Usage-Reconciliation.psm1'
$storeModule = Join-Path $scriptDir 'Live-Codex-Usage-Store.psm1'
foreach ($modulePath in @(
    $costModule, $efficiencyModule, $guardModule, $instanceModule, $personalModule,
    $privacyModule, $rtkModule, $reconciliationModule, $storeModule
)) {
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "Required module not found: $modulePath" }
    Import-Module -Name $modulePath -Force
}
$script:startupWarnings = [System.Collections.Generic.List[string]]::new()
$script:instanceCoordinator = $null
$script:instanceStatusCode = 'Unavailable'
$automatedMode = @(
    $Once, $UiSmokeTest, $UiLayoutSmokeTest, $UiInteractionSmokeTest, $MiniSmokeTest,
    $IntegrationSmokeTest, $TaskSmokeTest,
    $DateRangeSmokeTest, $StatusSmokeTest, $AlertSmokeTest, $ArchivedSmokeTest,
    $PresetSmokeTest, $RangeCacheSmokeTest, $QuotaResetSmokeTest, $ExportSmokeTest,
    $EnterpriseSmokeTest, $EnterpriseUiSmokeTest, $ComplianceUiSmokeTest,
    $InsightsUiSmokeTest, $PerformanceSmokeTest, $CatalogExpansionSmokeTest,
    $EfficiencySmokeTest
) -contains $true
if ($AllowMultipleInstances) {
    $script:instanceStatusCode = 'Bypassed'
}
elseif ($automatedMode) {
    $script:instanceStatusCode = 'TestBypass'
}
else {
    try {
        $script:instanceCoordinator = New-MonitorInstanceCoordinator
        if (-not $script:instanceCoordinator.IsPrimary) {
            Write-Output 'The existing Live Codex Usage Monitor window was requested.'
            exit 0
        }
        $script:instanceStatusCode = 'Active'
    }
    catch {
        $script:instanceCoordinator = $null
        $script:instanceStatusCode = 'Unavailable'
        $script:startupWarnings.Add('Single-instance coordination is unavailable; this launch will continue.')
    }
}
$script:rateCard = Import-UsageRateCard -Path (Join-Path $scriptDir 'config\usage-rates.json')
$script:statePaths = Get-MonitorStatePaths -Root $StateRoot
$script:appVersion = (Get-Content -LiteralPath (Join-Path $scriptDir 'VERSION') -Raw).Trim()
$script:launcherPath = Join-Path $scriptDir 'Start-Live-Codex-Usage.ps1'
try { $script:costProfile = Import-UsageCostProfile -Path $script:statePaths.CostProfile }
catch {
    $script:costProfile = New-UsageCostProfile
    $script:startupWarnings.Add("Cost settings were reset: $($_.Exception.Message)")
}
try { $script:guardPolicy = Import-UsageGuardPolicy -Path $script:statePaths.GuardPolicy }
catch {
    $script:guardPolicy = New-UsageGuardPolicy
    $script:startupWarnings.Add("Usage guard was disabled: $($_.Exception.Message)")
}
try { $script:personalSettings = Import-PersonalMonitorSettings -Path $script:statePaths.PersonalSettings }
catch {
    $script:personalSettings = New-PersonalMonitorSettings
    $script:startupWarnings.Add("Personal settings were reset: $($_.Exception.Message)")
}
if (-not $PSBoundParameters.ContainsKey('PollSeconds')) {
    $PollSeconds = [int]$script:personalSettings.RefreshSeconds
}
try { $script:startupRegistration = Test-PersonalStartupRegistration -LauncherPath $script:launcherPath }
catch {
    $script:startupRegistration = [pscustomobject]@{
        Registered = $false; MatchesLauncher = $false; RegistrationPath = ''; Status = 'Unavailable'
    }
    $script:startupWarnings.Add("Start-at-sign-in status is unavailable: $($_.Exception.Message)")
}
$script:diagnosticRows = @()
$script:officialSnapshot = $null
$script:officialSnapshotFullName = ''
$script:officialSnapshotSignature = ''
$script:manualOfficialSnapshot = $false
if (-not [string]::IsNullOrWhiteSpace($OfficialSnapshotPath)) {
    $script:officialSnapshot = Import-OfficialUsageSnapshot -Path $OfficialSnapshotPath
    $officialItem = Get-Item -LiteralPath $OfficialSnapshotPath
    $script:officialSnapshotFullName = $officialItem.FullName
    $script:officialSnapshotSignature = '{0}|{1}' -f $officialItem.FullName, $officialItem.LastWriteTimeUtc.Ticks
    $script:manualOfficialSnapshot = $true
}
$script:lastStoreWrite = [datetime]::MinValue
$script:dailyCosts = @()
$script:costEstimate = $null
$script:configuredSpend = $null
$script:guardStatus = $null
$script:lastGuardAlertReason = ''
$script:refreshTimer = $null
try {
    $script:rtkSnapshot = Get-RtkSavingsSnapshot -RtkPath $RtkExecutablePath -Disabled:$DisableRtkIntegration
}
catch {
    $script:rtkSnapshot = Get-RtkSavingsSnapshot -Disabled
    $script:startupWarnings.Add("RTK diagnostics could not start: $($_.Exception.Message)")
}
$script:lastRtkCheck = Get-Date
$script:lastRtkAlertCode = ''
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
$script:schemaTracker = New-CodexSchemaTracker
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
$script:isScanning = $false
$script:mainForm = $null
$script:mainStatusLabel = $null
$script:mainAccentColor = $null
$script:usageRevision = [int64]0
$script:activityRevision = [int64]0
$script:lastRenderKey = ''
$script:lastCostKey = ''
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
$script:catalogRangeStart = $script:rangeStart
$script:catalogRangeEnd = $script:rangeEnd

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
    $info = Get-SessionInfoRecord -SourceFile $SourceFile
    if ($Line -match '"type":"session_meta"') {
        if ($Line -match '"context_window":(?:"([^"]+)"|([0-9]+))') {
            $info.ContextWindow = Get-ShortValue $(if ($Matches[1]) { $Matches[1] } else { $Matches[2] })
        }
    }
    elseif ($Line -match '"type":"turn_context"') {
        if ($Line -match '"model":"([^"]+)"') { $info.Model = Get-ShortValue $Matches[1] }
        if ($Line -match '"effort":"([^"]+)"') { $info.Effort = Get-ShortValue $Matches[1] }
        if ($Line -match '"approval_policy":"([^"]+)"') { $info.ApprovalPolicy = Get-ShortValue $Matches[1] }
        if ($Line -match '"approvals_reviewer":"([^"]+)"') { $info.ApprovalsReviewer = Get-ShortValue $Matches[1] }
        if ($Line -match '"sandbox_policy":(?:"([^"]+)"|\{"type":"([^"]+)")') {
            $info.Sandbox = Get-ShortValue $(if ($Matches[1]) { $Matches[1] } else { $Matches[2] })
        }
    }
    else { return }
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
    $lineStart = 0
    while ($lineStart -lt $combined.Length) {
        $lineEnd = $combined.IndexOf("`n", $lineStart)
        if ($lineEnd -lt 0) { break }
        $lineLength = $lineEnd - $lineStart
        if ($lineLength -gt 0 -and $combined[$lineEnd - 1] -eq "`r") {
            $lineLength--
        }
        if ($lineLength -gt 0) {
            Write-Output $combined.Substring($lineStart, $lineLength)
        }
        $lineStart = $lineEnd + 1
    }
    $state.Remainder = if ($lineStart -lt $combined.Length) {
        $combined.Substring($lineStart)
    }
    else {
        ''
    }
}

function Test-InSelectedRange {
    param([datetime]$At)
    return ($At -ge $script:rangeStart -and $At -le $script:rangeEnd)
}

function Get-LineLocalTimestamp {
    param([string]$Line)

    $marker = '"timestamp":"'
    $valueStart = $Line.IndexOf($marker, [System.StringComparison]::Ordinal)
    if ($valueStart -lt 0) { return $null }
    $valueStart += $marker.Length
    $valueEnd = $Line.IndexOf('"', $valueStart)
    if ($valueEnd -le $valueStart) { return $null }
    try {
        return [datetimeoffset]::Parse(
            $Line.Substring($valueStart, ($valueEnd - $valueStart)),
            [System.Globalization.CultureInfo]::InvariantCulture
        ).LocalDateTime
    }
    catch {
        return $null
    }
}

function Test-LineTimestampInSelectedRange {
    param([string]$Line)

    # Rollout records place an ISO timestamp near the beginning of each JSONL
    # line. Checking that small value before ConvertFrom-Json avoids expensive
    # deserialization of old records in long-running session files that were
    # modified recently. Lines without a readable timestamp remain eligible so
    # forward-compatible records are never silently discarded.
    $at = Get-LineLocalTimestamp -Line $Line
    if ($null -eq $at) { return $true }
    return Test-InSelectedRange -At $at
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
    param([string]$Line, [string]$SourceFile, [string]$EventId = '')

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
    if ([string]::IsNullOrWhiteSpace($EventId)) {
        $EventId = Get-LineFingerprint -Line $Line -SourceFile $SourceFile
    }
    $rateLimits = Get-ObjectProperty -Object $payload -Name 'rate_limits'

    $usageEvent = [pscustomobject]@{
        EventId   = $EventId
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
        Model     = [string]((Get-SessionInfoRecord -SourceFile $SourceFile).Model)
        Provenance = 'Local Codex log'
    }
    $usageEvent | Add-Member -NotePropertyName Risk -NotePropertyValue (Get-RiskLabel -UsageEvent $usageEvent)
    return $usageEvent
}

function Convert-ActivityEvent {
    param([string]$Line, [string]$SourceFile, [string]$EventId = '')

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $at = Get-LineLocalTimestamp -Line $Line
    if ($null -eq $at) { $at = Get-Date }

    $label = 'LOG'
    $detail = 'local rollout event'

    # Activity rows need only a sanitized type and timestamp. Classifying from
    # the compact JSON text avoids deserializing large prompt, response, and
    # tool-output payloads that are intentionally never displayed.
    if ($Line -match '"type"\s*:\s*"(?:compacted|context_compacted|context_compaction|compact)"') {
        $label = 'COMPACT'
        $detail = 'local context compaction recorded'
    }
    elseif ($Line -match '"type":"turn_context"') {
        $label = 'CTX'
        $detail = 'context packaged for a turn'
    }
    elseif ($Line -match '"type":"event_msg"' -and $Line -match '"type":"token_count"') {
        $label = 'TOKEN'
        $detail = 'usage counters updated'
    }
    elseif ($Line -match '"type":"event_msg"' -and $Line -match '"type":"user_message"') {
        $label = 'ASK'
        $detail = 'user request received'
    }
    elseif ($Line -match '"type":"event_msg"' -and $Line -match '"type":"[^"]*(?:exec|command|run)[^"]*"') {
        $label = 'RUN'
        $detail = 'command activity recorded'
    }
    elseif ($Line -match '"type":"event_msg"' -and $Line -match '"type":"[^"]*(?:patch|edit|file)[^"]*"') {
        $label = 'EDIT'
        $detail = 'file activity recorded'
    }
    elseif ($Line -match '"type":"event_msg"' -and $Line -match '"type":"[^"]*(?:error|failed|abort)[^"]*"') {
        $label = 'ERR'
        $detail = 'error activity recorded'
    }
    elseif ($Line -match '"type":"response_item"' -and ($Line -match 'function_call|tool_call|custom_tool_call')) {
        $label = 'TOOL'
        $detail = 'tool activity recorded'
    }
    elseif ($Line -match '"type":"response_item"' -and ($Line -match '"type":"message"')) {
        $label = 'MSG'
        $detail = 'assistant message recorded'
    }
    elseif ($Line -match '"type":"response_item"') {
        $label = 'OUT'
        $detail = 'assistant output item recorded'
    }

    if ([string]::IsNullOrWhiteSpace($EventId)) {
        $EventId = Get-LineFingerprint -Line $Line -SourceFile $SourceFile
    }

    [pscustomobject]@{
        EventId = $EventId
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
    param([string]$Line, [string]$SourceFile, [string]$EventId = '')

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    if ($Line -notmatch 'function_call|custom_tool_call|web_search_call|mcp_tool_call_end') { return $null }
    $kind = ''
    $rawName = ''
    $display = ''

    if ($Line -match '"type":"(?:function_call|custom_tool_call)_output"') {
        return $null
    }
    elseif ($Line -match '"type":"response_item"' -and $Line -match '"type":"function_call"') {
        $kind = 'Function'
        if ($Line -match '"name":"([^"]+)"') { $rawName = $Matches[1] }
    }
    elseif ($Line -match '"type":"response_item"' -and $Line -match '"type":"custom_tool_call"') {
        $kind = 'Custom'
        if ($Line -match '"name":"([^"]+)"') { $rawName = $Matches[1] }
    }
    elseif ($Line -match '"type":"response_item"' -and $Line -match '"type":"web_search_call"') {
        $kind = 'Web'
        $rawName = 'web_search'
    }
    elseif ($Line -match '"type":"event_msg"' -and $Line -match '"type":"mcp_tool_call_end"') {
        $kind = 'MCP'
        $app = ''
        $action = ''
        if ($Line -match '"app_name":"([^"]+)"') { $app = $Matches[1] }
        elseif ($Line -match '"server":"([^"]+)"') { $app = $Matches[1] }
        elseif ($Line -match '"connector_id":"([^"]+)"') { $app = $Matches[1] }
        if ($Line -match '"action_name":"([^"]+)"') { $action = $Matches[1] }
        if ($app -and $action) { $rawName = "$app.$action" }
        elseif ($app) { $rawName = $app }
        elseif ($action) { $rawName = $action }
        else { $rawName = 'MCP/app tool' }
    }
    else {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($rawName)) { return $null }
    $display = Get-IntegrationDisplayName -Kind $kind -Name $rawName

    $at = Get-LineLocalTimestamp -Line $Line
    if ($null -eq $at) { $at = Get-Date }
    if ([string]::IsNullOrWhiteSpace($EventId)) {
        $EventId = Get-LineFingerprint -Line $Line -SourceFile $SourceFile
    }

    [pscustomobject]@{
        EventId = $EventId
        At      = $at
        Kind    = $kind
        Name    = $display
        RawName = $rawName
        Source  = $SourceFile
        Session = Get-SessionName -Path $SourceFile
    }
}

function Update-Events {
    if ($script:isScanning) { return }
    $script:isScanning = $true
    try {
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
            if (($script:scanStats.LinesRead % 10) -eq 0 -and
                $null -ne $script:mainForm -and
                $script:mainForm.IsHandleCreated -and -not $script:mainForm.IsDisposed) {
                if (($script:scanStats.LinesRead % 100) -eq 0 -and $null -ne $script:mainStatusLabel) {
                    $script:mainStatusLabel.Text = 'Status: LOADING LOCAL LOGS ({0:N0} lines scanned)' -f $script:scanStats.LinesRead
                    $script:mainStatusLabel.ForeColor = $script:mainAccentColor
                }
                [System.Windows.Forms.Application]::DoEvents()
            }
            if (-not (Test-LineTimestampInSelectedRange -Line $line)) { return }
            Add-CodexSchemaObservation -Tracker $script:schemaTracker -Line $line
            $classificationText = if ($line.Length -gt 8192) { $line.Substring(0, 8192) } else { $line }
            if ($classificationText -match 'session_meta|turn_context') {
                Update-SessionInfo -Line $classificationText -SourceFile $file.FullName
                $script:usageRevision++
            }
            if ($ShowPromptTaskTitles -and $classificationText -match 'user_message|\"role\":\"user\"') {
                Update-TaskTitleFromLine -Line $line -SourceFile $file.FullName
            }

            # Byte offsets already guarantee at-most-once processing between
            # refreshes. A source-plus-sequence key is sufficient in memory and
            # avoids creating several SHA-256 objects for every JSONL line.
            $eventId = '{0}:{1}' -f $file.FullName, $script:scanStats.LinesRead
            if (-not $script:activitySeen.ContainsKey($eventId)) {
                $script:activitySeen[$eventId] = $true
                $activity = Convert-ActivityEvent -Line $classificationText -SourceFile $file.FullName -EventId $eventId
                if ($null -ne $activity -and $activity.Label -ne 'LOG') {
                    $script:activityEvents.Add($activity)
                    $script:activityRevision++
                }
                $integration = Convert-IntegrationEvent -Line $classificationText -SourceFile $file.FullName -EventId $eventId
                if ($null -ne $integration) {
                    $script:integrationEvents.Add($integration)
                    $script:activityRevision++
                }
            }

            if ($classificationText -match 'token_count') {
                if ($script:seen.ContainsKey($eventId)) { return }
                $script:seen[$eventId] = $true
                $usageEvent = Convert-TokenEvent -Line $line -SourceFile $file.FullName -EventId $eventId
                if ($null -ne $usageEvent) {
                    $script:events.Add($usageEvent)
                    $script:usageRevision++
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
    finally {
        $script:isScanning = $false
    }
}

function Reset-MonitorWindow {
    $script:events.Clear()
    $script:activityEvents.Clear()
    $script:integrationEvents.Clear()
    $script:schemaTracker = New-CodexSchemaTracker
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
    $script:sessionInfo = @{}
    $script:latestSource = $null
    $script:latestSession = $null
    $script:focusedSession = $null
    $script:focusedEventId = $null
    $script:visibleEvents = @()
    $script:visibleActivity = @()
    $script:visibleIntegrations = @()
    $script:visibleTasks = @()
    $script:usageRevision++
    $script:activityRevision++
    $script:lastRenderKey = ''
    $script:lastCostKey = ''
    $script:startedAt = Get-Date
}

function Reload-Logs {
    $script:seen = @{}
    $script:activitySeen = @{}
    $script:fileOffsets = @{}
    $script:events.Clear()
    $script:activityEvents.Clear()
    $script:integrationEvents.Clear()
    $script:schemaTracker = New-CodexSchemaTracker
    $script:sessionInfo = @{}
    $script:latestSource = $null
    $script:latestSession = $null
    $script:focusedSession = $null
    $script:focusedEventId = $null
    $script:scanStats.LinesRead = [int64]0
    $script:usageRevision++
    $script:activityRevision++
    $script:lastRenderKey = ''
    $script:lastCostKey = ''
    Update-Events
    $script:catalogRangeStart = $script:rangeStart
    $script:catalogRangeEnd = $script:rangeEnd
    $script:startedAt = Get-Date
}

function Set-MonitorDateRange {
    param([datetime]$FromDate, [datetime]$ToDate)

    $from = $FromDate.Date
    $to = $ToDate.Date
    if ($from -gt $to) {
        throw 'The From date must be before or equal to the To date.'
    }
    $requestedEnd = $to.AddDays(1).AddTicks(-1)
    $needsCatalogExpansion = (
        $from -lt $script:catalogRangeStart -or
        $requestedEnd -gt $script:catalogRangeEnd
    )
    if ($needsCatalogExpansion) {
        # Records outside the prior catalog were deliberately skipped before
        # JSON parsing. Rescan the union only when the user expands beyond that
        # catalog; ordinary date changes remain an in-memory filter.
        $unionStart = if ($from -lt $script:catalogRangeStart) { $from } else { $script:catalogRangeStart }
        $unionEnd = if ($requestedEnd -gt $script:catalogRangeEnd) { $requestedEnd } else { $script:catalogRangeEnd }
        $script:rangeStart = $unionStart
        $script:rangeEnd = $unionEnd
        Reload-Logs
        $script:catalogRangeStart = $unionStart
        $script:catalogRangeEnd = $unionEnd
    }
    else {
        $script:rangeStart = $from
        $script:rangeEnd = $requestedEnd
        Update-Events
    }
    $script:rangeStart = $from
    $script:rangeEnd = $requestedEnd
    $script:lastRenderKey = ''
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

function Update-OfficialSnapshotFromWatchFolder {
    if ($script:manualOfficialSnapshot) { return }
    $latestFiles = @(Get-LatestOfficialSnapshotFile -Folder $script:statePaths.OfficialReports)
    if ($latestFiles.Count -eq 0) { return }
    $latestFile = $latestFiles[0]
    if ($null -eq $latestFile -or $null -eq $latestFile.PSObject.Properties['FullName']) { return }
    $signature = '{0}|{1}' -f $latestFile.FullName, $latestFile.LastWriteTimeUtc.Ticks
    if ($signature -eq $script:officialSnapshotSignature) { return }
    try {
        $script:officialSnapshot = Import-OfficialUsageSnapshot -Path $latestFile.FullName
        $script:officialSnapshotFullName = $latestFile.FullName
        $script:officialSnapshotSignature = $signature
    }
    catch {
        $script:startupWarnings.Add("Official report '$($latestFile.Name)' was ignored: $($_.Exception.Message)")
        $script:officialSnapshotSignature = $signature
    }
}

function Get-BillingCycleStart {
    param(
        [object]$Profile,
        [datetime]$AsOf = (Get-Date)
    )

    $startDay = [Math]::Max(1, [Math]::Min(28, [int]$Profile.BillingCycleStartDay))
    $candidate = Get-Date -Year $AsOf.Year -Month $AsOf.Month -Day $startDay
    if ($AsOf -lt $candidate) {
        $previous = $candidate.AddMonths(-1)
        $candidate = Get-Date -Year $previous.Year -Month $previous.Month -Day $startDay
    }
    return $candidate
}

function Update-DerivedUsageState {
    param(
        [object[]]$VisibleEvents,
        [string]$CacheKey = ''
    )

    Update-OfficialSnapshotFromWatchFolder
    if ($CacheKey -and $script:lastCostKey -eq $CacheKey -and $null -ne $script:costEstimate) {
        return
    }
    $script:costEstimate = Get-UsageCostEstimate `
        -RateCard $script:rateCard `
        -UsageEvents $VisibleEvents `
        -DefaultModel ([string]$script:costProfile.DefaultModel) `
        -DollarsPerCredit ([decimal]$script:costProfile.DollarsPerCredit) `
        -CreditRateMultiplier ([decimal]$script:costProfile.CreditRateMultiplier)
    $script:dailyCosts = @(Get-DailyUsageCostEstimate `
        -RateCard $script:rateCard `
        -UsageEvents $VisibleEvents `
        -DefaultModel ([string]$script:costProfile.DefaultModel) `
        -DollarsPerCredit ([decimal]$script:costProfile.DollarsPerCredit) `
        -CreditRateMultiplier ([decimal]$script:costProfile.CreditRateMultiplier))

    $cycleStart = Get-BillingCycleStart -Profile $script:costProfile
    $cycleEvents = @($script:events | Where-Object { $_.At -ge $cycleStart })
    $cycleCost = Get-UsageCostEstimate `
        -RateCard $script:rateCard `
        -UsageEvents $cycleEvents `
        -DefaultModel ([string]$script:costProfile.DefaultModel) `
        -DollarsPerCredit ([decimal]$script:costProfile.DollarsPerCredit) `
        -CreditRateMultiplier ([decimal]$script:costProfile.CreditRateMultiplier)
    $script:configuredSpend = Get-ConfiguredSpendEstimate `
        -EstimatedCredits ([decimal]$cycleCost.EstimatedCredits) `
        -Profile $script:costProfile
    $script:lastCostKey = $CacheKey
}

function Update-RtkSavingsState {
    [CmdletBinding()]
    param([switch]$Force)

    if ($DisableRtkIntegration) { return $script:rtkSnapshot }
    $now = Get-Date
    if (-not $Force -and (($now - $script:lastRtkCheck).TotalSeconds -lt 60)) {
        return $script:rtkSnapshot
    }
    $recentShell = @($script:integrationEvents |
        Where-Object { [string]$_.Name -eq 'Local shell' } |
        Sort-Object At -Descending |
        Select-Object -First 1)
    $recentShellAt = if ($recentShell.Count -gt 0) { [datetime]$recentShell[0].At } else { [datetime]::MinValue }
    try {
        $script:rtkSnapshot = Get-RtkSavingsSnapshot `
            -RtkPath $RtkExecutablePath `
            -RecentShellActivityAt $recentShellAt `
            -Now $now
        $script:lastRtkCheck = $now
        $problemCodes = @('NotInstalled','Unavailable','PossibleBypass','Degraded')
        if ([string]$script:rtkSnapshot.HealthCode -in $problemCodes -and
            [string]$script:rtkSnapshot.HealthCode -ne $script:lastRtkAlertCode) {
            $script:lastRtkAlertCode = [string]$script:rtkSnapshot.HealthCode
            if (-not $NoNotifications -and $null -ne $script:notifyIcon) {
                $script:notifyIcon.BalloonTipTitle = 'RTK savings health'
                $script:notifyIcon.BalloonTipText = [string]$script:rtkSnapshot.Message
                $script:notifyIcon.ShowBalloonTip(5000)
            }
        }
        elseif ([string]$script:rtkSnapshot.HealthCode -notin $problemCodes) {
            $script:lastRtkAlertCode = ''
        }
    }
    catch {
        $script:lastRtkCheck = $now
        if (-not $NoNotifications -and $null -ne $script:notifyIcon) {
            $script:notifyIcon.BalloonTipTitle = 'RTK savings health'
            $script:notifyIcon.BalloonTipText = 'RTK local diagnostics failed: ' + $_.Exception.Message
            $script:notifyIcon.ShowBalloonTip(5000)
        }
    }
    return $script:rtkSnapshot
}

function Save-PrivacySafeMonitorHistory {
    if ($DisablePersistence) { return }
    if (((Get-Date) - $script:lastStoreWrite).TotalSeconds -lt 60) { return }
    $incoming = New-PrivacySafeAggregateSnapshot `
        -UsageEvents @($script:events) `
        -IntegrationEvents @($script:integrationEvents)
    $shape = Test-AggregatePrivacyShape -Value $incoming
    if (-not $shape.Passed) {
        throw "Aggregate store privacy check failed: $($shape.Violations -join ', ')"
    }
    $existing = Read-PrivacySafeAggregateStore -Path $script:statePaths.AggregateStore
    $merged = Merge-PrivacySafeAggregateSnapshot -Existing $existing -Incoming $incoming
    Write-PrivacySafeAggregateStore -Path $script:statePaths.AggregateStore -Snapshot $merged
    $script:lastStoreWrite = Get-Date
}

function Save-UsageGuardState {
    if ($DisablePersistence) { return }
    Export-UsageGuardPolicy -Policy $script:guardPolicy -Path $script:statePaths.GuardPolicy
}

function Save-PersonalSettingsState {
    if ($DisablePersistence) { return }
    Export-PersonalMonitorSettings -Settings $script:personalSettings -Path $script:statePaths.PersonalSettings
}

function Update-PersonalDiagnostics {
    try {
        $script:startupRegistration = Test-PersonalStartupRegistration -LauncherPath $script:launcherPath
    }
    catch {
        $script:startupRegistration = [pscustomobject]@{
            Registered = $false; MatchesLauncher = $false; RegistrationPath = ''; Status = 'Unavailable'
        }
    }
    $readiness = Get-UsageGuardReadiness -Policy $script:guardPolicy
    $efficiencyConfig = Get-CodexEfficiencyConfigState
    $efficiencyPolicy = Get-CodexEfficiencyPolicyState
    $schemaHealth = Get-CodexSchemaHealth -Tracker $script:schemaTracker
    $script:diagnosticRows = @(Get-PersonalMonitorDiagnostics `
        -CodexHome $CodexHome `
        -StateRoot $script:statePaths.Root `
        -RtkSnapshot $script:rtkSnapshot `
        -GuardReadiness $readiness `
        -StartupRegistration $script:startupRegistration `
        -EfficiencyConfigState $efficiencyConfig `
        -EfficiencyPolicyState $efficiencyPolicy `
        -SchemaHealth $schemaHealth `
        -PersistenceEnabled (-not $DisablePersistence) `
        -AppVersion $script:appVersion)
    $instanceDiagnostic = switch ($script:instanceStatusCode) {
        'Active' {
            [pscustomobject]@{
                Check = 'Single instance'; Status = 'OK'
                Detail = 'A second launcher restores this current-user monitor.'
            }
        }
        'Bypassed' {
            [pscustomobject]@{
                Check = 'Single instance'; Status = 'INFO'
                Detail = 'Multiple instances were explicitly allowed for this launch.'
            }
        }
        'TestBypass' {
            [pscustomobject]@{
                Check = 'Single instance'; Status = 'INFO'
                Detail = 'Duplicate-launch protection is disabled for deterministic QA.'
            }
        }
        default {
            [pscustomobject]@{
                Check = 'Single instance'; Status = 'WARN'
                Detail = 'Duplicate-launch protection is unavailable for this session.'
            }
        }
    }
    $script:diagnosticRows = @($script:diagnosticRows) + @($instanceDiagnostic)
    $script:personalSettings.LastDiagnosticsAt = (Get-Date).ToString('o')
    Save-PersonalSettingsState
    return @($script:diagnosticRows)
}

function Invoke-UsageGuardCycle {
    $policy = $script:guardPolicy
    if (-not [bool]$policy.Enabled) {
        return [pscustomobject]@{ Label = 'Guard off'; Value = [decimal]0; Stopped = 0; Reason = 'Guard disabled' }
    }

    $todayEvents = @($script:events | Where-Object { $_.At.Date -eq (Get-Date).Date })
    $todaySum = Get-SumPack -Items $todayEvents
    $todayCost = Get-UsageCostEstimate `
        -RateCard $script:rateCard `
        -UsageEvents $todayEvents `
        -DefaultModel ([string]$script:costProfile.DefaultModel) `
        -DollarsPerCredit ([decimal]$script:costProfile.DollarsPerCredit) `
        -CreditRateMultiplier ([decimal]$script:costProfile.CreditRateMultiplier)
    $valueAvailable = $true
    [decimal]$value = 0
    switch ([string]$policy.Metric) {
        'EstimatedCredits' { $value = [decimal]$todayCost.EstimatedCredits }
        'FreshBurn' { $value = [decimal]$todaySum.FreshBurn }
        'ApiEquivalentUsd' {
            if ($null -eq $todayCost.ApiEquivalentUsd) { $valueAvailable = $false }
            else { $value = [decimal]$todayCost.ApiEquivalentUsd }
        }
        'ActualUsd' {
            if ($null -eq $script:configuredSpend -or -not $script:configuredSpend.CashEstimateAvailable) {
                $valueAvailable = $false
            }
            else { $value = [decimal]$script:configuredSpend.EstimatedCycleSpendUsd }
        }
        'QuotaPercent' {
            $latestEvents = @($script:events | Sort-Object At -Descending | Select-Object -First 1)
            if ($latestEvents.Count -eq 0) { $valueAvailable = $false }
            else { $value = [decimal](Get-QuotaPercent -UsageEvent $latestEvents[0]) }
        }
    }
    if (-not $valueAvailable) {
        return [pscustomobject]@{
            Label = 'Guard waiting'; Value = [decimal]0; Stopped = 0
            Reason = "$($policy.Metric) is unavailable from the current local data/settings."
        }
    }

    $evaluation = Test-UsageGuardThreshold -Policy $policy -CurrentValue $value
    if ($evaluation.Crossed -and $evaluation.EnforcementDue -and -not [bool]$policy.Locked) {
        Lock-UsageGuardPolicy -Policy $policy -Reason $evaluation.Reason | Out-Null
        Save-UsageGuardState
    }

    $stopped = 0
    $enforcementError = ''
    if ([bool]$policy.Locked) {
        try {
            $enforcement = Invoke-UsageGuardEnforcement -Policy $policy
            $stopped = [int]$enforcement.Stopped
        }
        catch {
            $enforcementError = $_.Exception.Message
        }
    }
    $reason = if ($enforcementError) { "Enforcement error: $enforcementError" } else { [string]$evaluation.Reason }
    if (($evaluation.Crossed -or [bool]$policy.Locked) -and $reason -ne $script:lastGuardAlertReason) {
        $script:lastGuardAlertReason = $reason
        if (-not $NoSound) { [System.Media.SystemSounds]::Exclamation.Play() }
        if (-not $NoNotifications -and $null -ne $script:notifyIcon) {
            $script:notifyIcon.BalloonTipTitle = 'Codex usage guard'
            $script:notifyIcon.BalloonTipText = $reason
            $script:notifyIcon.ShowBalloonTip(5000)
        }
    }
    $label = if ([bool]$policy.Locked) {
        "LOCKED ($($policy.Mode))"
    }
    elseif ($evaluation.Crossed) {
        "Warning - $($evaluation.RemainingGraceSeconds)s grace"
    }
    elseif ($evaluation.Reason -match 'renewed until') {
        'Renewed'
    }
    else { 'Armed' }
    return [pscustomobject]@{ Label = $label; Value = $value; Stopped = $stopped; Reason = $reason }
}

# Deterministic command-line and construction tests need data before their
# early-exit handlers run. Interactive launches defer the first scan until
# the form's Shown event so a large local log set cannot delay creation of the
# window and make startup appear unresponsive.
$requiresPreloadedEvents = (
    $Once -or $UiSmokeTest -or $UiLayoutSmokeTest -or $UiInteractionSmokeTest -or
    $MiniSmokeTest -or $IntegrationSmokeTest -or
    $TaskSmokeTest -or $DateRangeSmokeTest -or $StatusSmokeTest -or
    $AlertSmokeTest -or $ArchivedSmokeTest -or $PresetSmokeTest -or
    $RangeCacheSmokeTest -or $QuotaResetSmokeTest -or $ExportSmokeTest -or
    $EnterpriseSmokeTest -or $EnterpriseUiSmokeTest -or
    $ComplianceUiSmokeTest -or $InsightsUiSmokeTest -or $PerformanceSmokeTest -or
    $CatalogExpansionSmokeTest -or $EfficiencySmokeTest
)
if ($requiresPreloadedEvents) {
    Update-Events
}

if ($Once) {
    $selectedEvents = @(Get-DisplayEvents -Mode 'All sessions')
    $latest = @($selectedEvents | Select-Object -First 1)
    if ($latest.Count -eq 0) { Write-Output 'No recent token events found.'; exit 0 }
    $usageEvent = $latest[0]
    Write-Output ("Events={0}; Latest={1}; FreshBurn={2}; NewInput={3}; Context={4}; Risk={5}" -f $selectedEvents.Count, $usageEvent.At.ToString('HH:mm:ss'), (Format-Tokens $usageEvent.FreshBurn), (Format-Tokens $usageEvent.NewInput), (Format-Tokens $usageEvent.Total), $usageEvent.Risk)
    exit 0
}

if ($PerformanceSmokeTest) {
    $timings = [ordered]@{}
    $beforeLines = [int64]$script:scanStats.LinesRead
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Update-Events
    $sw.Stop()
    $timings.IncrementalScanMs = $sw.ElapsedMilliseconds
    $timings.NewLines = [int64]$script:scanStats.LinesRead - $beforeLines

    foreach ($phase in @(
        @{ Name = 'UsageViewMs'; Run = { $script:diagnosticUsage = @(Get-DisplayEvents -Mode 'All sessions') } },
        @{ Name = 'ActivityViewMs'; Run = { $script:diagnosticActivity = @(Get-DisplayActivity -Mode 'All sessions') } },
        @{ Name = 'IntegrationViewMs'; Run = { $script:diagnosticIntegrations = @(Get-DisplayIntegrations -Mode 'All sessions') } },
        @{ Name = 'TaskBreakdownMs'; Run = { $script:diagnosticTasks = @(Get-TaskBreakdown -VisibleEvents $script:diagnosticUsage) } },
        @{ Name = 'DerivedCostMs'; Run = { Update-DerivedUsageState -VisibleEvents $script:diagnosticUsage } }
    )) {
        $sw.Restart()
        & $phase.Run
        $sw.Stop()
        $timings[$phase.Name] = $sw.ElapsedMilliseconds
    }
    Write-Output (($timings.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join '; ')
    Write-Output ('Usage={0}; Activity={1}; Integrations={2}; Tasks={3}' -f $script:diagnosticUsage.Count, $script:diagnosticActivity.Count, $script:diagnosticIntegrations.Count, $script:diagnosticTasks.Count)
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

if ($CatalogExpansionSmokeTest) {
    $initialCount = @(Get-DisplayEvents -Mode 'All sessions').Count
    Set-MonitorDateRange -FromDate ([datetime]'2026-07-25') -ToDate ([datetime]'2026-07-26')
    $expandedCount = @(Get-DisplayEvents -Mode 'All sessions').Count
    Write-Output ('InitialEvents={0}; ExpandedEvents={1}; CatalogStart={2}' -f $initialCount, $expandedCount, $script:catalogRangeStart.ToString('yyyy-MM-dd'))
    exit 0
}

if ($EfficiencySmokeTest) {
    $efficiencyEvents = @(Get-DisplayEvents -Mode 'All sessions')
    $efficiencyActivity = @(Get-DisplayActivity -Mode 'All sessions')
    $cache = Get-PromptCacheSavings -RateCard $script:rateCard -UsageEvents $efficiencyEvents `
        -DefaultModel ([string]$script:costProfile.DefaultModel) `
        -DollarsPerCredit ([decimal]$script:costProfile.DollarsPerCredit) `
        -CreditRateMultiplier ([decimal]$script:costProfile.CreditRateMultiplier)
    $advice = Get-SessionEfficiencyAdvice -UsageEvents $efficiencyEvents
    $schema = Get-CodexSchemaHealth -Tracker $script:schemaTracker
    $churn = Get-CompactionChurn -UsageEvents $efficiencyEvents -ActivityEvents $efficiencyActivity
    $latestEfficiencyEvent = @($efficiencyEvents | Sort-Object At -Descending | Select-Object -First 1)
    $quotaWindows = if ($latestEfficiencyEvent.Count -eq 1) {
        @(Get-QuotaWindowMetrics -RateLimits $latestEfficiencyEvent[0].RateLimits)
    }
    else { @() }
    Write-Output ('Cache={0:N1}%; Schema={1}; QuotaWindows={2}; Advice={3}; Compactions={4}' -f `
        $cache.CacheHitPercent, $schema.StatusCode, $quotaWindows.Count, $advice.StatusCode, $churn.Compactions)
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
$initialWidth = [Math]::Min(1380, [Math]::Max(1040, $workingArea.Width - 56))
$initialHeight = [Math]::Min(1020, [Math]::Max(720, $workingArea.Height - 56))
$form.Size = New-Object System.Drawing.Size($initialWidth, $initialHeight)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 720)
$form.StartPosition = 'CenterScreen'
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScroll = $true
$form.KeyPreview = $true
$form.AccessibleName = 'Live Codex Usage Monitor'
$form.AccessibleDescription = 'Private, offline dashboard for aggregate Codex usage from local session logs.'

# Fluent-inspired local theme. Semantic warning colors are reserved for state;
# blue is the only navigation/action accent.
$uiWindow = [System.Drawing.Color]::FromArgb(17, 19, 23)
$uiSurface = [System.Drawing.Color]::FromArgb(27, 31, 36)
$uiSurfaceRaised = [System.Drawing.Color]::FromArgb(34, 39, 46)
$uiBorder = [System.Drawing.Color]::FromArgb(55, 62, 72)
$uiText = [System.Drawing.Color]::FromArgb(242, 244, 247)
$uiTextSecondary = [System.Drawing.Color]::FromArgb(190, 197, 207)
$uiTextMuted = [System.Drawing.Color]::FromArgb(151, 160, 173)
$uiAccent = [System.Drawing.Color]::FromArgb(76, 194, 255)
$uiAccentDark = [System.Drawing.Color]::FromArgb(15, 108, 189)
$uiSuccess = [System.Drawing.Color]::FromArgb(126, 231, 135)
$uiWarning = [System.Drawing.Color]::FromArgb(255, 209, 102)
$uiCritical = [System.Drawing.Color]::FromArgb(255, 123, 114)
$uiSelection = [System.Drawing.Color]::FromArgb(23, 77, 108)

$uiFontFamily = 'Segoe UI'
try {
    $variableFont = New-Object System.Drawing.FontFamily('Segoe UI Variable Text')
    $uiFontFamily = $variableFont.Name
    $variableFont.Dispose()
}
catch {
    # Segoe UI ships with supported Windows releases and is the safe PS 5.1 fallback.
}

function New-UiFont {
    param(
        [single]$Size,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
    )
    return New-Object System.Drawing.Font($uiFontFamily, $Size, $Style)
}

function Add-SurfacePanel {
    param([int]$X, [int]$Y, [int]$Width, [int]$Height, [string]$AccessibleName)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($Width, $Height)
    $panel.BackColor = $uiSurface
    $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $panel.Anchor = 'Top,Left,Right'
    $panel.AccessibleName = $AccessibleName
    $form.Controls.Add($panel)
    return $panel
}

$form.BackColor = $uiWindow
$form.ForeColor = $uiText
$form.Font = New-UiFont 9.5

function Add-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height, [int]$FontSize = 11)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.Font = New-UiFont $FontSize
    $label.ForeColor = $uiTextSecondary
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.AutoEllipsis = $true
    # Main-form layout is recalculated explicitly on resize. Right-anchoring
    # small labels such as VIEW, RANGE, From, and To makes their opaque
    # backgrounds expand over adjacent buttons and date fields.
    $label.Anchor = 'Top,Left'
    $form.Controls.Add($label)
    return $label
}

function Add-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.BackColor = $uiSurfaceRaised
    $button.ForeColor = $uiText
    $button.FlatStyle = 'Flat'
    $button.UseVisualStyleBackColor = $false
    $button.TextAlign = 'MiddleCenter'
    $button.Font = New-UiFont 9
    $button.FlatAppearance.BorderColor = $uiBorder
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(44, 51, 60)
    $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(49, 57, 67)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
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
    $picker.Font = New-UiFont 9
    $picker.BackColor = $uiSurfaceRaised
    $picker.ForeColor = $uiText
    $picker.CalendarMonthBackground = $uiSurfaceRaised
    $picker.CalendarForeColor = $uiText
    $form.Controls.Add($picker)
    return $picker
}

function Set-GridTheme {
    param([System.Windows.Forms.DataGridView]$DataGrid)
    $DataGrid.BackgroundColor = $uiSurface
    $DataGrid.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $DataGrid.GridColor = $uiBorder
    $DataGrid.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $DataGrid.ColumnHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::None
    $DataGrid.EnableHeadersVisualStyles = $false
    $DataGrid.ColumnHeadersDefaultCellStyle.BackColor = $uiSurfaceRaised
    $DataGrid.ColumnHeadersDefaultCellStyle.ForeColor = $uiText
    $DataGrid.ColumnHeadersDefaultCellStyle.Font = New-UiFont 9 ([System.Drawing.FontStyle]::Bold)
    $DataGrid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
    $DataGrid.ColumnHeadersHeight = 34
    $DataGrid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $DataGrid.DefaultCellStyle.BackColor = $uiSurface
    $DataGrid.DefaultCellStyle.ForeColor = $uiTextSecondary
    $DataGrid.DefaultCellStyle.SelectionBackColor = $uiSelection
    $DataGrid.DefaultCellStyle.SelectionForeColor = $uiText
    $DataGrid.DefaultCellStyle.Font = New-UiFont 9
    $DataGrid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 1, 4, 1)
    $DataGrid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30, 35, 41)
    $DataGrid.RowTemplate.Height = 28
    $DataGrid.ShowCellToolTips = $true
}

function Set-TabTheme {
    param([System.Windows.Forms.TabControl]$TabControl)

    $TabControl.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
    $TabControl.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
    $TabControl.Padding = New-Object System.Drawing.Point(12, 5)
    $TabControl.Add_ControlAdded({
        param($sender, $eventArgs)
        if ($sender.TabPages.Count -gt 0) {
            $sender.ItemSize = New-Object System.Drawing.Size(
                [Math]::Max(80, [int](($sender.ClientSize.Width - 4) / $sender.TabPages.Count)),
                28
            )
        }
    })
    $TabControl.Add_DrawItem({
        param($sender, $drawEvent)
        $selected = ($drawEvent.Index -eq $sender.SelectedIndex)
        $bounds = $sender.GetTabRect($drawEvent.Index)
        $background = if ($selected) { $uiSurfaceRaised } else { $uiWindow }
        $foreground = if ($selected) { $uiText } else { $uiTextSecondary }
        $backgroundBrush = New-Object System.Drawing.SolidBrush($background)
        $accentBrush = New-Object System.Drawing.SolidBrush($uiAccent)
        try {
            $drawEvent.Graphics.FillRectangle($backgroundBrush, $bounds)
            if ($selected) {
                $drawEvent.Graphics.FillRectangle($accentBrush, $bounds.X, ($bounds.Bottom - 3), $bounds.Width, 3)
            }
            [System.Windows.Forms.TextRenderer]::DrawText(
                $drawEvent.Graphics,
                $sender.TabPages[$drawEvent.Index].Text,
                $sender.Font,
                $bounds,
                $foreground,
                [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
                    [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                    [System.Windows.Forms.TextFormatFlags]::EndEllipsis
            )
        }
        finally {
            $backgroundBrush.Dispose()
            $accentBrush.Dispose()
        }
    })
}

$heroCard = Add-SurfacePanel 12 12 1296 142 'Current usage overview'
$summaryCard = Add-SurfacePanel 12 164 1296 142 'Usage context and privacy summary'
$commandCard = Add-SurfacePanel 12 316 1296 78 'Monitor controls and date range'

$title = Add-Label 'Live Codex usage' 26 22 650 34 20
$title.Font = New-UiFont 20 ([System.Drawing.FontStyle]::Bold)
$title.ForeColor = $uiText
$title.AccessibleDescription = 'Aggregate local usage. No prompt or response content is displayed.'
$localLabel = Add-Label 'LOCAL LOGS  /  PRIVATE BY DEFAULT' 28 56 620 18 8
$localLabel.Font = New-UiFont 8 ([System.Drawing.FontStyle]::Bold)
$localLabel.ForeColor = $uiAccent
$statusLabel = Add-Label 'Status: waiting' 856 26 246 28 12
$statusLabel.Font = New-UiFont 12 ([System.Drawing.FontStyle]::Bold)
$statusLabel.ForeColor = $uiWarning
$script:mainForm = $form
$script:mainStatusLabel = $statusLabel
$script:mainAccentColor = $uiAccent
$statusMeter = New-Object System.Windows.Forms.Panel
$statusMeter.Location = New-Object System.Drawing.Point(856, 60)
$statusMeter.Size = New-Object System.Drawing.Size(422, 8)
$statusMeter.BackColor = $uiBorder
$statusMeter.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$statusMeter.Anchor = 'Top,Right'
$statusMeter.AccessibleName = 'Overall usage status meter'
$statusMeter.AccessibleDescription = 'Visual meter paired with the adjacent text status and percentage.'
$statusMeterFill = New-Object System.Windows.Forms.Panel
$statusMeterFill.Location = New-Object System.Drawing.Point(0, 0)
$statusMeterFill.Size = New-Object System.Drawing.Size(0, 8)
$statusMeterFill.BackColor = $uiSuccess
$statusMeter.Controls.Add($statusMeterFill)
$form.Controls.Add($statusMeter)
$freshLabel = Add-Label 'Fresh burn: waiting for token events' 26 80 1254 28 14
$freshLabel.Font = New-UiFont 14 ([System.Drawing.FontStyle]::Bold)
$freshLabel.ForeColor = $uiSuccess
$guidanceLabel = Add-Label 'Action: waiting for the next completed Codex turn.' 26 114 1254 24 10
$guidanceLabel.ForeColor = $uiTextSecondary
$minuteLabel = Add-Label 'Last 60 seconds: waiting for token events' 26 176 1254 24 11
$minuteLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
$minuteLabel.ForeColor = $uiText
$windowLabel = Add-Label 'Monitor window: 0' 26 204 735 21 9
$quotaLabel = Add-Label 'Quota: waiting for token event metadata' 782 204 498 21 9
$quotaLabel.ForeColor = $uiTextSecondary
$modelSummaryLabel = Add-Label 'Models: waiting for token events' 26 228 735 21 9
$timeSummaryLabel = Add-Label 'Time: waiting for token events' 782 228 498 21 9
$noteLabel = Add-Label 'Private, offline, and zero-cost monitoring. Cost and downloaded-report status will appear here.' 26 276 1254 20 9
$noteLabel.ForeColor = $uiTextMuted
$sessionSummaryLabel = Add-Label 'Sessions: waiting for token events' 26 252 735 21 9
$integrationSummaryLabel = Add-Label 'Integrations: waiting for tool/plugin/add-in calls' 782 252 498 21 9

$modeLabel = Add-Label 'VIEW' 26 329 40 24 8
$modeLabel.Font = New-UiFont 8 ([System.Drawing.FontStyle]::Bold)
$modeLabel.ForeColor = $uiTextMuted
$viewAllButton = Add-Button '&All tasks' 70 326 94 30
$viewLatestButton = Add-Button '&Follow latest' 174 326 104 30
$viewPinnedButton = Add-Button '&Pinned' 288 326 82 30
$pinButton = Add-Button 'Pi&n latest' 380 326 94 30
$clearButton = Add-Button '&Start fresh' 484 326 100 30
$miniButton = Add-Button '&Mini mode' 594 326 96 30
$enterpriseButton = Add-Button '&Import my data' 700 326 126 30
$controlCenterButton = Add-Button '&Control center' 836 326 138 30

$presetLabel = Add-Label 'RANGE' 26 365 42 24 8
$presetLabel.Font = New-UiFont 8 ([System.Drawing.FontStyle]::Bold)
$presetLabel.ForeColor = $uiTextMuted
$presetBox = New-Object System.Windows.Forms.ComboBox
$presetBox.Location = New-Object System.Drawing.Point(70, 362)
$presetBox.Size = New-Object System.Drawing.Size(130, 28)
$presetBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$presetBox.Font = New-UiFont 9
$presetBox.BackColor = $uiSurfaceRaised
$presetBox.ForeColor = $uiText
[void]$presetBox.Items.AddRange(@('Today', 'Last 7 days', 'Last 30 days', 'All available', 'Custom'))
$presetBox.SelectedItem = 'Custom'
$form.Controls.Add($presetBox)
$fromLabel = Add-Label 'From' 214 365 38 24 9
$fromPicker = Add-DatePicker -Value $script:rangeStart.Date -X 254 -Y 362 -Width 112
$toLabel = Add-Label 'To' 378 365 20 24 9
$initialToDate = if ($script:rangeEnd -eq [datetime]::MaxValue) { (Get-Date).Date } else { $script:rangeEnd.Date }
$toPicker = Add-DatePicker -Value $initialToDate -X 402 -Y 362 -Width 112
$loadRangeButton = Add-Button 'Load &dates' 526 361 100 30
$exportButton = Add-Button 'E&xport CSV' 636 361 100 30
$refreshIntervalLabel = Add-Label 'Refresh s' 750 365 58 24 8
$refreshIntervalLabel.Font = New-UiFont 8 ([System.Drawing.FontStyle]::Bold)
$refreshIntervalLabel.ForeColor = $uiTextMuted
$refreshSecondsBox = New-Object System.Windows.Forms.NumericUpDown
$refreshSecondsBox.Location = New-Object System.Drawing.Point(812, 361)
$refreshSecondsBox.Size = New-Object System.Drawing.Size(64, 30)
$refreshSecondsBox.Minimum = 1
$refreshSecondsBox.Maximum = 60
$refreshSecondsBox.Increment = 1
$refreshSecondsBox.DecimalPlaces = 0
$refreshSecondsBox.Value = $PollSeconds
$refreshSecondsBox.Font = New-UiFont 9
$refreshSecondsBox.BackColor = $uiSurfaceRaised
$refreshSecondsBox.ForeColor = $uiText
$refreshSecondsBox.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
$form.Controls.Add($refreshSecondsBox)
$historyLabel = Add-Label ("Loaded: {0}" -f (Format-DateRange)) 886 365 394 24 9
$historyLabel.ForeColor = $uiTextMuted
foreach ($surfaceLabel in @(
    $title, $localLabel, $statusLabel, $freshLabel, $guidanceLabel,
    $minuteLabel, $windowLabel, $quotaLabel, $modelSummaryLabel, $timeSummaryLabel,
    $noteLabel, $sessionSummaryLabel, $integrationSummaryLabel,
    $modeLabel, $presetLabel, $fromLabel, $toLabel, $refreshIntervalLabel, $historyLabel
)) {
    $surfaceLabel.BackColor = $uiSurface
}

$tokenLabel = Add-Label 'Token events' 18 408 820 24 11
$tokenLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
$tokenLabel.ForeColor = $uiText
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(18, 436)
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
Set-GridTheme $grid
$form.Controls.Add($grid)

$taskLabel = Add-Label 'Task breakdown: double-click a task to pin it' 850 408 438 24 11
$taskLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
$taskLabel.ForeColor = $uiText

$taskGrid = New-Object System.Windows.Forms.DataGridView
$taskGrid.Location = New-Object System.Drawing.Point(850, 436)
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
$taskGrid.Columns['Task'].FillWeight = 220
$taskGrid.Columns['Model'].FillWeight = 95
$taskGrid.Columns['Health'].FillWeight = 95
$taskGrid.Columns['Avg fresh'].FillWeight = 80
$taskGrid.Columns['Avg ctx'].FillWeight = 80
$taskGrid.Columns['Cache'].FillWeight = 70
$taskGrid.Columns['Status'].FillWeight = 80
Set-GridTheme $taskGrid
$taskGrid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(2, 1, 2, 1)
$taskGrid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(2, 0, 2, 0)
$form.Controls.Add($taskGrid)

$integrationLabel = Add-Label 'Integrations/add-ins/plugins: waiting for calls' 18 650 620 24 11
$integrationLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
$integrationLabel.ForeColor = $uiText

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
Set-GridTheme $integrationGrid
$form.Controls.Add($integrationGrid)

$activityLabel = Add-Label 'Sanitized activity: waiting for rollout events' 660 650 628 24 11
$activityLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
$activityLabel.ForeColor = $uiText

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
Set-GridTheme $activityGrid
$form.Controls.Add($activityGrid)

$explainBox = New-Object System.Windows.Forms.TextBox
$explainBox.Location = New-Object System.Drawing.Point(18, 830)
$explainBox.Size = New-Object System.Drawing.Size(1270, 80)
$explainBox.Anchor = 'Bottom,Left,Right'
$explainBox.Multiline = $true
$explainBox.ReadOnly = $true
$explainBox.BackColor = $uiSurface
$explainBox.ForeColor = $uiTextSecondary
$explainBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$explainBox.Font = New-UiFont 10
$explainBox.Text = 'Select a row to explain the spike profile.'
$explainBox.AccessibleName = 'Selected item explanation'
$explainBox.AccessibleDescription = 'Plain-language explanation of the selected usage event, task, or integration.'
$form.Controls.Add($explainBox)

# WinForms places the first controls added at the front of the native z-order.
# These three panels are visual backgrounds, not parents, so they must remain
# behind every label, meter, picker, and button drawn over them. DrawToBitmap
# does not reliably expose this ordering error, which is why the former visual
# smoke capture could look correct while a real Windows desktop looked blank.
foreach ($surface in @($heroCard, $summaryCard, $commandCard)) {
    $surface.SendToBack()
}

$script:visibleEvents = @()
$script:visibleActivity = @()
$script:visibleIntegrations = @()
$script:visibleTasks = @()
$script:normalFormSize = $form.Size
$script:normalFormLocation = $form.Location
$script:normalMinimumSize = New-Object System.Drawing.Size(1040, 720)
$script:normalMiniButtonLocation = $miniButton.Location
$script:interactionTestMode = [bool]$UiInteractionSmokeTest
$script:interactionExportPath = ''
$script:lastInteractionResult = ''
$script:fullModeControls = @(
    $localLabel, $summaryCard, $commandCard,
    $modelSummaryLabel, $timeSummaryLabel, $noteLabel, $sessionSummaryLabel, $integrationSummaryLabel,
    $modeLabel, $viewAllButton, $viewLatestButton, $viewPinnedButton, $pinButton, $clearButton,
    $enterpriseButton, $controlCenterButton, $presetLabel, $presetBox, $fromLabel, $fromPicker, $toLabel, $toPicker, $loadRangeButton, $exportButton,
    $refreshIntervalLabel, $refreshSecondsBox, $historyLabel, $tokenLabel, $grid, $taskLabel, $taskGrid,
    $integrationLabel, $integrationGrid, $activityLabel, $activityGrid, $explainBox
)

$grid.AccessibleName = 'Token events table'
$grid.AccessibleDescription = 'Privacy-safe aggregate token metrics by completed turn. Select a row for an explanation.'
$taskGrid.AccessibleName = 'Task breakdown table'
$taskGrid.AccessibleDescription = 'Aggregate usage health by private task label. Double-click a row to pin that task.'
$integrationGrid.AccessibleName = 'Integration activity table'
$integrationGrid.AccessibleDescription = 'Aggregate counts of integration types without arguments, output, or paths.'
$activityGrid.AccessibleName = 'Sanitized activity table'
$activityGrid.AccessibleDescription = 'Recent activity types and times without prompt text or tool output.'
$fromPicker.AccessibleName = 'Usage range start date'
$fromPicker.AccessibleDescription = 'First local date included when loading usage history.'
$toPicker.AccessibleName = 'Usage range end date'
$toPicker.AccessibleDescription = 'Last local date included when loading usage history.'
$presetBox.AccessibleName = 'Usage date range preset'
$presetBox.AccessibleDescription = 'Choose Today, Last 7 days, Last 30 days, All available, or Custom.'
$loadRangeButton.AccessibleName = 'Load selected date range'
$loadRangeButton.AccessibleDescription = 'Reload aggregate usage events for the dates shown in the From and To controls.'
$exportButton.AccessibleName = 'Export privacy-safe daily summary'
$exportButton.AccessibleDescription = 'Write daily aggregate counts only. Prompt content, paths, task names, and identifiers are excluded.'
$refreshSecondsBox.AccessibleName = 'Refresh interval in seconds'
$refreshSecondsBox.AccessibleDescription = 'Set how often the monitor checks local Codex log files, from 1 to 60 seconds.'
$enterpriseButton.AccessibleName = 'Import my local ChatGPT data'
$enterpriseButton.AccessibleDescription = 'Open a downloaded usage summary or activity export limited to this individual.'
$controlCenterButton.AccessibleName = 'Open insights and controls'
$controlCenterButton.AccessibleDescription = 'Open offline trends, the usage saver, local RTK savings health, spending estimates, downloaded-report comparison, provenance, personal settings, and the opt-in usage guard.'
$miniButton.AccessibleName = 'Toggle compact monitor mode'
$miniButton.AccessibleDescription = 'Switch between the full dashboard and the always-on-top compact status view.'
$viewAllButton.AccessibleName = 'Show all tasks'
$viewAllButton.AccessibleDescription = 'Show aggregate events across every loaded session.'
$viewLatestButton.AccessibleName = 'Follow latest task'
$viewLatestButton.AccessibleDescription = 'Follow the session with the most recent completed turn.'
$viewPinnedButton.AccessibleName = 'Show pinned task'
$viewPinnedButton.AccessibleDescription = 'Show the currently pinned session.'
$pinButton.AccessibleName = 'Pin latest task'
$pinButton.AccessibleDescription = 'Pin the session with the most recent completed turn.'
$clearButton.AccessibleName = 'Start fresh monitoring window'
$clearButton.AccessibleDescription = 'Clear aggregate events from memory and monitor only newly appended local log records.'

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($presetBox, 'Choose a quick range. Custom keeps the calendar selections.')
$toolTip.SetToolTip($loadRangeButton, 'Load the complete selected date range (Ctrl+L).')
$toolTip.SetToolTip($exportButton, 'Export daily aggregates only; no prompts, paths, task names, or identifiers (Ctrl+E).')
$toolTip.SetToolTip($refreshSecondsBox, 'Check local Codex logs every 1 to 60 seconds. Changes apply immediately and persist for this Windows user.')
$toolTip.SetToolTip($enterpriseButton, 'Import a downloaded report limited to your own account; files remain on this PC.')
$toolTip.SetToolTip($controlCenterButton, 'Open offline insights, the usage saver, RTK savings health, cost estimates, downloaded-report comparison, personal settings, and the opt-in usage guard.')
$toolTip.SetToolTip($miniButton, 'Toggle the always-on-top compact view (Ctrl+M).')
$toolTip.SetToolTip($clearButton, 'Discard the in-memory window and watch only newly appended log records.')

$tabOrder = @(
    $viewAllButton, $viewLatestButton, $viewPinnedButton, $pinButton, $clearButton, $miniButton,
    $enterpriseButton, $controlCenterButton, $presetBox, $fromPicker, $toPicker, $loadRangeButton, $exportButton, $refreshSecondsBox,
    $grid, $taskGrid, $integrationGrid, $activityGrid, $explainBox
)
for ($tabIndex = 0; $tabIndex -lt $tabOrder.Count; $tabIndex++) {
    $tabOrder[$tabIndex].TabIndex = $tabIndex
}

function Update-ViewButtons {
    foreach ($button in @($viewAllButton, $viewLatestButton, $viewPinnedButton)) {
        $button.BackColor = $uiSurfaceRaised
        $button.ForeColor = $uiText
        $button.FlatAppearance.BorderColor = $uiBorder
    }
    if ($script:viewMode -eq 'All sessions') {
        $viewAllButton.BackColor = $uiAccentDark
        $viewAllButton.FlatAppearance.BorderColor = $uiAccent
    }
    elseif ($script:viewMode -eq 'Follow latest') {
        $viewLatestButton.BackColor = $uiAccentDark
        $viewLatestButton.FlatAppearance.BorderColor = $uiAccent
    }
    elseif ($script:viewMode -eq 'Pinned session') {
        $viewPinnedButton.BackColor = $uiAccentDark
        $viewPinnedButton.FlatAppearance.BorderColor = $uiAccent
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
    $clientW = [Math]::Max(1000, $form.ClientSize.Width)
    # A 900px virtual canvas keeps the dashboard sections separated on common
    # 1280x720 and 1366x768 work laptops. AutoScroll exposes the lower sections
    # without allowing the 160px token grid to overlap their headings.
    $clientH = [Math]::Max(900, $form.ClientSize.Height)
    $form.AutoScrollMinSize = New-Object System.Drawing.Size(1000, 900)
    $contentW = $clientW - ($margin * 2)
    $rightW = [Math]::Max(360, [Math]::Min(620, [int]($contentW * 0.38)))
    $leftW = [Math]::Max(500, $contentW - $gap - $rightW)
    $rightX = $margin + $leftW + $gap
    $statusW = [Math]::Max(320, [Math]::Min(470, [int]($contentW * 0.38)))
    $statusX = $margin + $contentW - $statusW - 8
    $summaryLeftW = [Math]::Max(520, [int]($contentW * 0.58))
    $summaryRightX = $margin + $summaryLeftW + 20
    $summaryRightW = [Math]::Max(300, $contentW - $summaryLeftW - 28)

    # The three upper surfaces preserve reading order while growing with the window.
    $heroCard.Size = New-Object System.Drawing.Size([Math]::Max(1, $contentW + 12), 142)
    $summaryCard.Size = New-Object System.Drawing.Size([Math]::Max(1, $contentW + 12), 142)
    $commandCard.Size = New-Object System.Drawing.Size([Math]::Max(1, $contentW + 12), 78)
    $title.Size = New-Object System.Drawing.Size([Math]::Max(360, $statusX - 50), 34)
    $localLabel.Size = New-Object System.Drawing.Size([Math]::Max(360, $statusX - 50), 18)
    $statusLabel.Location = New-Object System.Drawing.Point($statusX, 26)
    $statusLabel.Size = New-Object System.Drawing.Size($statusW, 28)
    $statusMeter.Location = New-Object System.Drawing.Point($statusX, 60)
    $statusMeter.Size = New-Object System.Drawing.Size($statusW, 8)
    $freshLabel.Size = New-Object System.Drawing.Size([Math]::Max(1, $contentW - 16), 28)
    $guidanceLabel.Size = New-Object System.Drawing.Size([Math]::Max(1, $contentW - 16), 24)
    $minuteLabel.Size = New-Object System.Drawing.Size([Math]::Max(1, $contentW - 16), 24)
    foreach ($pair in @(
        @($windowLabel, 204), @($modelSummaryLabel, 228), @($sessionSummaryLabel, 252)
    )) {
        $pair[0].Location = New-Object System.Drawing.Point(26, $pair[1])
        $pair[0].Size = New-Object System.Drawing.Size($summaryLeftW, 21)
    }
    foreach ($pair in @(
        @($quotaLabel, 204), @($timeSummaryLabel, 228), @($integrationSummaryLabel, 252)
    )) {
        $pair[0].Location = New-Object System.Drawing.Point($summaryRightX, $pair[1])
        $pair[0].Size = New-Object System.Drawing.Size($summaryRightW, 21)
    }
    $noteLabel.Size = New-Object System.Drawing.Size([Math]::Max(1, $contentW - 16), 20)
    $historyLabel.Location = New-Object System.Drawing.Point(886, 365)
    $historyLabel.Size = New-Object System.Drawing.Size([Math]::Max(100, $contentW - 868), 24)

    $explainH = 80
    $explainY = $clientH - $explainH - 22
    $activityH = 140
    $activityY = $explainY - $activityH - 12
    $activityLabelY = $activityY - 28
    $gridY = 436
    $gridH = [Math]::Max(160, $activityLabelY - $gridY - 10)
    $lowerGap = 16
    $integrationW = [Math]::Max(420, [int](($contentW - $lowerGap) * 0.36))
    $activityW = $contentW - $lowerGap - $integrationW
    $activityX = $margin + $integrationW + $lowerGap

    $tokenLabel.Location = New-Object System.Drawing.Point($margin, 408)
    $tokenLabel.Size = New-Object System.Drawing.Size($leftW, 24)
    $grid.Location = New-Object System.Drawing.Point($margin, $gridY)
    $grid.Size = New-Object System.Drawing.Size($leftW, $gridH)

    $taskLabel.Location = New-Object System.Drawing.Point($rightX, 408)
    $taskLabel.Size = New-Object System.Drawing.Size($rightW, 24)
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

    # Resizing and mini/full transitions must not promote a background surface
    # over its foreground controls.
    foreach ($surface in @($heroCard, $summaryCard, $commandCard)) {
        $surface.SendToBack()
    }
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
        $form.MinimumSize = New-Object System.Drawing.Size(680, 320)
        $form.Size = New-Object System.Drawing.Size(780, 340)
        $heroCard.Location = New-Object System.Drawing.Point(12, 12)
        $heroCard.Size = New-Object System.Drawing.Size(748, 240)
        $miniButton.Text = '&Full mode'
        $miniButton.Location = New-Object System.Drawing.Point(650, 10)
        $miniButton.Size = New-Object System.Drawing.Size(100, 30)
        $title.Location = New-Object System.Drawing.Point(26, 20)
        $title.Size = New-Object System.Drawing.Size(260, 28)
        $title.Font = New-UiFont 15 ([System.Drawing.FontStyle]::Bold)
        $statusLabel.Location = New-Object System.Drawing.Point(300, 22)
        $statusLabel.Size = New-Object System.Drawing.Size(330, 24)
        $statusLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
        $statusMeter.Location = New-Object System.Drawing.Point(26, 56)
        $statusMeter.Size = New-Object System.Drawing.Size(714, 8)
        $title.Text = 'Codex usage - compact'
        $freshLabel.Location = New-Object System.Drawing.Point(26, 78)
        $freshLabel.Size = New-Object System.Drawing.Size(714, 26)
        $freshLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
        $minuteLabel.Location = New-Object System.Drawing.Point(26, 108)
        $minuteLabel.Size = New-Object System.Drawing.Size(714, 24)
        $minuteLabel.Font = New-UiFont 10
        $quotaLabel.Location = New-Object System.Drawing.Point(26, 136)
        $quotaLabel.Size = New-Object System.Drawing.Size(732, 22)
        $guidanceLabel.Location = New-Object System.Drawing.Point(26, 164)
        $guidanceLabel.Size = New-Object System.Drawing.Size(714, 40)
        $guidanceLabel.Font = New-UiFont 10
        $windowLabel.Location = New-Object System.Drawing.Point(26, 206)
        $windowLabel.Size = New-Object System.Drawing.Size(732, 22)
        $windowLabel.Font = New-UiFont 9
    }
    else {
        $form.TopMost = $false
        $form.MinimumSize = $script:normalMinimumSize
        $form.Size = $script:normalFormSize
        if ($wasMini) { $form.Location = $script:normalFormLocation }
        $miniButton.Text = '&Mini mode'
        $miniButton.Location = $script:normalMiniButtonLocation
        $miniButton.Size = New-Object System.Drawing.Size(96, 30)
        $title.Text = 'Live Codex usage'
        $title.Location = New-Object System.Drawing.Point(26, 22)
        $title.Font = New-UiFont 20 ([System.Drawing.FontStyle]::Bold)
        $statusLabel.Font = New-UiFont 12 ([System.Drawing.FontStyle]::Bold)
        $freshLabel.Location = New-Object System.Drawing.Point(26, 80)
        $freshLabel.Size = New-Object System.Drawing.Size(1254, 28)
        $freshLabel.Font = New-UiFont 14 ([System.Drawing.FontStyle]::Bold)
        $guidanceLabel.Location = New-Object System.Drawing.Point(26, 114)
        $guidanceLabel.Size = New-Object System.Drawing.Size(1254, 24)
        $guidanceLabel.Font = New-UiFont 10
        $minuteLabel.Location = New-Object System.Drawing.Point(26, 176)
        $minuteLabel.Size = New-Object System.Drawing.Size(1254, 24)
        $minuteLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
        $windowLabel.Location = New-Object System.Drawing.Point(26, 204)
        $windowLabel.Size = New-Object System.Drawing.Size(735, 21)
        $windowLabel.Font = New-UiFont 9
        $quotaLabel.Location = New-Object System.Drawing.Point(782, 204)
        $quotaLabel.Size = New-Object System.Drawing.Size(498, 21)
        $quotaLabel.Font = New-UiFont 9
        Update-ResponsiveLayout
    }
}

function Get-RenderStateKey {
    $profileKey = '{0}:{1}:{2}:{3}:{4}:{5}' -f `
        $script:costProfile.DefaultModel,
        $script:costProfile.DollarsPerCredit,
        $script:costProfile.IncludedCreditsPerCycle,
        $script:costProfile.FixedCostPerCycleUsd,
        $script:costProfile.BillingCycleStartDay,
        $script:costProfile.CreditRateMultiplier
    $guardKey = '{0}:{1}:{2}:{3}:{4}:{5}' -f `
        $script:guardPolicy.Enabled,
        $script:guardPolicy.Mode,
        $script:guardPolicy.Metric,
        $script:guardPolicy.Threshold,
        $script:guardPolicy.Locked,
        $script:guardPolicy.OverrideUntil
    $rtkKey = '{0}:{1}:{2}:{3}' -f `
        $script:rtkSnapshot.HealthCode,
        $script:rtkSnapshot.TotalCommands,
        $script:rtkSnapshot.SavedTokensEstimate,
        $script:rtkSnapshot.FailureCount
    return @(
        $script:usageRevision,
        $script:activityRevision,
        $script:rangeStart.Ticks,
        $script:rangeEnd.Ticks,
        $script:viewMode,
        [string]$script:focusedSession,
        [string]$script:pinnedSource,
        $script:isMiniMode,
        (Get-Date).ToString('yyyyMMddHHmm'),
        $profileKey,
        $guardKey,
        $rtkKey,
        $script:officialSnapshotSignature
    ) -join '|'
}

function Refresh-Display {
    if ($script:isRefreshing -or $script:isScanning) { return }
    $script:isRefreshing = $true
    try {
    Update-Events
    Update-ResponsiveLayout
    Update-OfficialSnapshotFromWatchFolder
    [void](Update-RtkSavingsState)
    $renderKey = Get-RenderStateKey
    if ($script:lastRenderKey -eq $renderKey) {
        $previousGuardLabel = if ($null -ne $script:guardStatus) { [string]$script:guardStatus.Label } else { '' }
        $previousGuardReason = if ($null -ne $script:guardStatus) { [string]$script:guardStatus.Reason } else { '' }
        $script:guardStatus = Invoke-UsageGuardCycle
        if ($previousGuardLabel -eq [string]$script:guardStatus.Label -and
            $previousGuardReason -eq [string]$script:guardStatus.Reason) {
            return
        }
    }
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
    $costKey = @(
        $script:usageRevision,
        $script:rangeStart.Ticks,
        $script:rangeEnd.Ticks,
        $mode,
        [string]$script:focusedSession,
        $script:costProfile.DefaultModel,
        $script:costProfile.DollarsPerCredit,
        $script:costProfile.IncludedCreditsPerCycle,
        $script:costProfile.FixedCostPerCycleUsd,
        $script:costProfile.BillingCycleStartDay,
        $script:costProfile.CreditRateMultiplier
    ) -join '|'
    Update-DerivedUsageState -VisibleEvents $visible -CacheKey $costKey
    Save-PrivacySafeMonitorHistory
    $script:guardStatus = Invoke-UsageGuardCycle
    $status = Get-OverallStatus -Latest $latest -Minute $minute
    $statusLabel.Text = 'Status: {0} ({1})' -f $status.Label, $status.Detail
    $statusColor = if ($status.Label -eq 'CRITICAL') { $uiCritical } elseif ($status.Label -eq 'WARN') { $uiWarning } else { $uiSuccess }
    $statusLabel.ForeColor = $statusColor
    $meterPercent = [Math]::Max(0, [Math]::Min(100, [int]$status.Percent))
    $statusMeterFill.BackColor = $statusColor
    $statusMeterFill.Size = New-Object System.Drawing.Size([Math]::Floor(($statusMeter.ClientSize.Width * $meterPercent) / 100), $statusMeter.ClientSize.Height)
    if ([bool]$script:guardPolicy.Locked) {
        $statusLabel.Text = 'Status: USAGE GUARD LOCKED ({0})' -f $script:guardPolicy.Mode
        $statusLabel.ForeColor = $uiCritical
        $statusMeterFill.BackColor = $uiCritical
        $statusMeterFill.Size = New-Object System.Drawing.Size($statusMeter.ClientSize.Width, $statusMeter.ClientSize.Height)
    }

    if ($null -eq $latest) {
        $freshLabel.Text = 'Fresh burn: waiting for token events'
        $freshLabel.ForeColor = $uiSuccess
    }
    else {
        $latestTask = @($tasks | Where-Object { $_.Session -eq $latest.Session } | Select-Object -First 1)
        $avgFreshText = if ($latestTask.Count -gt 0) { Format-Tokens $latestTask[0].AvgFresh } else { 'n/a' }
        $modelText = if ($latestTask.Count -gt 0 -and $latestTask[0].Model) { $latestTask[0].Model } else { 'unknown model' }
        $freshLabel.Text = 'Latest {0}: fresh {1} | task avg {2}/turn | new input {3} | output {4} | reasoning {5} | context {6} | {7} | {8}' -f $latest.At.ToString('HH:mm:ss'), (Format-Tokens $latest.FreshBurn), $avgFreshText, (Format-Tokens $latest.NewInput), (Format-Tokens $latest.Output), (Format-Tokens $latest.Reasoning), (Format-Tokens $latest.Total), $latest.Risk, $modelText
        if ($latest.Risk -eq 'Normal' -or $latest.Risk -eq 'Mostly cached context') {
            $freshLabel.ForeColor = $uiSuccess
        }
        else {
            $freshLabel.ForeColor = $uiCritical
        }
        if (Should-Alert -UsageEvent $latest -Minute $minute) {
            Send-Alert -UsageEvent $latest -Minute $minute
        }
    }

    $minuteLabel.Text = 'Last 60 seconds - fresh {0} | new input {1} | output {2} | reasoning {3} | context {4} | cached {5}' -f (Format-Tokens $minute.FreshBurn), (Format-Tokens $minute.NewInput), (Format-Tokens $minute.Output), (Format-Tokens $minute.Reasoning), (Format-Tokens $minute.Total), (Format-Tokens $minute.Cached)
    if ($minute.FreshBurn -ge $WarnMinuteFreshTokens) {
        $minuteLabel.ForeColor = $uiCritical
    }
    else {
        $minuteLabel.ForeColor = $uiText
    }
    $guidanceLabel.Text = Get-GuidanceText -UsageEvent $latest -Minute $minute -VisibleEvents $visible -Mode $mode
    if ($guidanceLabel.Text -match 'jumped|hot|multiple') {
        $guidanceLabel.ForeColor = $uiCritical
    }
    elseif ($guidanceLabel.Text -match 'mostly context') {
        $guidanceLabel.ForeColor = $uiWarning
    }
    else {
        $guidanceLabel.ForeColor = $uiTextSecondary
    }
    $windowLabel.Text = 'Monitor window - events: {0} | fresh {1} | context {2} | sessions {3} | logs {4}/{5} | started {6}' -f $visible.Count, (Format-Tokens $window.FreshBurn), (Format-Tokens $window.Total), (@($visible | Select-Object -ExpandProperty Source -Unique).Count), $script:scanStats.LoadedFiles, $script:scanStats.AvailableFiles, $script:startedAt.ToString('HH:mm:ss')
    $quotaLabel.Text = Get-QuotaText -UsageEvent $latest
    $modelSummaryLabel.Text = Get-ModelBreakdownText -VisibleEvents $visible
    $timeSummaryLabel.Text = Get-TimeSummaryText -VisibleEvents $visible
    $sessionSummaryLabel.Text = Get-SessionSummaryText -VisibleEvents $visible
    $integrationSummaryLabel.Text = Get-IntegrationSummaryText -VisibleIntegrations $integrations
    $historyLabel.Text = 'Loaded: {0}' -f (Format-DateRange)
    $apiText = if ($null -ne $script:costEstimate.ApiEquivalentUsd) {
        'API-equivalent ${0:N2}' -f [decimal]$script:costEstimate.ApiEquivalentUsd
    }
    else { 'API-equivalent unavailable' }
    $cashText = if ($null -ne $script:configuredSpend -and $script:configuredSpend.CashEstimateAvailable) {
        'configured cycle ${0:N2}' -f [decimal]$script:configuredSpend.EstimatedCycleSpendUsd
    }
    else { 'cash estimate needs contract parameters' }
    $officialText = 'downloaded report not imported'
    if ($null -ne $script:officialSnapshot) {
        $freshness = Get-OfficialSnapshotFreshness -ReportUpdatedAt ([datetime]$script:officialSnapshot.ReportUpdatedAt)
        $officialText = 'downloaded report {0}h old' -f $freshness.AgeHours
    }
    $unpricedText = if ([int64]$script:costEstimate.UnpricedTokens -gt 0) {
        ' | unpriced {0}' -f (Format-Tokens ([int64]$script:costEstimate.UnpricedTokens))
    }
    else { '' }
    $warningText = if ($script:startupWarnings.Count -gt 0) { ' | warning: ' + $script:startupWarnings[0] } else { '' }
    $rtkText = 'RTK {0}, saved ~{1}' -f $script:rtkSnapshot.HealthLabel, (Format-Tokens ([int64]$script:rtkSnapshot.SavedTokensEstimate))
    $mainSchemaHealth = Get-CodexSchemaHealth -Tracker $script:schemaTracker
    $schemaText = if ($mainSchemaHealth.StatusCode -eq 'Drift') { 'schema change detected' } else { 'schema compatible' }
    $noteLabel.Text = 'Offline/no paid calls | est {0:N2} credits{1} | {2} | {3} | {4} | {5} | {6} | guard {7}{8}' -f `
        ([decimal]$script:costEstimate.EstimatedCredits), $unpricedText, $apiText, $cashText, $officialText, $rtkText, $schemaText, $script:guardStatus.Label, $warningText
    if ([bool]$script:guardPolicy.Locked -or -not [bool]$script:rtkSnapshot.Working -or
        [int64]$script:costEstimate.UnpricedTokens -gt 0 -or $script:startupWarnings.Count -gt 0 -or
        $mainSchemaHealth.StatusCode -eq 'Drift') {
        $noteLabel.ForeColor = $uiWarning
    }
    else {
        $noteLabel.ForeColor = $uiTextMuted
    }
    if ($script:isMiniMode) {
        $statusLabel.Text = 'Status: {0}  {1}%' -f $status.Label, $status.Percent
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
            $row.DefaultCellStyle.ForeColor = $uiCritical
        }
        elseif ($usageEvent.Risk -eq 'Mostly cached context') {
            $row.DefaultCellStyle.ForeColor = $uiWarning
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
            $row.DefaultCellStyle.ForeColor = $uiSuccess
        }
        elseif ($task.Health -eq 'Fresh spike') {
            $row.DefaultCellStyle.ForeColor = $uiCritical
        }
        elseif ($task.Health -eq 'Bloated replay' -or $task.Health -eq 'Growing') {
            $row.DefaultCellStyle.ForeColor = $uiWarning
        }
        elseif ($task.Status -eq 'Recent') {
            $row.DefaultCellStyle.ForeColor = $uiWarning
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
            $row.DefaultCellStyle.ForeColor = $uiWarning
        }
        elseif ($integration.Name -eq 'Web search') {
            $row.DefaultCellStyle.ForeColor = $uiAccent
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
            $row.DefaultCellStyle.ForeColor = $uiCritical
        }
        elseif ($item.Label -eq 'TOKEN') {
            $row.DefaultCellStyle.ForeColor = $uiWarning
        }
        elseif ($item.Label -eq 'ASK') {
            $row.DefaultCellStyle.ForeColor = $uiAccent
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
    $script:lastRenderKey = Get-RenderStateKey
    }
    finally {
        $script:isRefreshing = $false
    }
}

function Show-EnterpriseAnalyticsDialog {
    param(
        [string[]]$Path = @(),
        [switch]$ConstructionOnly,
        [string]$ScreenshotPath = ''
    )

    $selectedPaths = @($Path | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($selectedPaths.Count -eq 0) {
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $openDialog.Title = 'Import my downloaded usage summary'
            $openDialog.Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
            $openDialog.CheckFileExists = $true
            $openDialog.Multiselect = $true
            if ($openDialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $selectedPaths = @($openDialog.FileNames)
        }
        finally {
            $openDialog.Dispose()
        }
    }

    $enterpriseModule = Join-Path $scriptDir 'Live-Codex-Usage-Enterprise.psm1'
    Import-Module -Name $enterpriseModule -Force
    $summary = Import-PersonalWorkspaceAnalyticsReport -Path $selectedPaths

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'My ChatGPT usage summary'
    $dialog.Size = New-Object System.Drawing.Size(980, 720)
    $dialog.MinimumSize = New-Object System.Drawing.Size(760, 560)
    $dialog.StartPosition = 'CenterParent'
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.BackColor = $uiWindow
    $dialog.ForeColor = $uiText
    $dialog.Font = New-UiFont 9.5
    $dialog.AccessibleName = 'My locally imported ChatGPT usage summary'

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = 'My usage summary'
    $heading.Location = New-Object System.Drawing.Point(18, 16)
    $heading.Size = New-Object System.Drawing.Size(920, 32)
    $heading.Anchor = 'Top,Left,Right'
    $heading.Font = New-UiFont 18 ([System.Drawing.FontStyle]::Bold)
    $heading.ForeColor = $uiText
    $dialog.Controls.Add($heading)

    $overview = New-Object System.Windows.Forms.Label
    $periodText = if ($summary.PeriodStart -and $summary.PeriodEnd) {
        '{0} to {1}' -f $summary.PeriodStart.ToString('yyyy-MM-dd'), $summary.PeriodEnd.ToString('yyyy-MM-dd')
    }
    else { 'period not supplied' }
    $overview.Text = 'Period {0} | downloaded report(s) {1} | messages {2:N0} | GPT {3:N0} | tools {4:N0} | projects {5:N0}' -f `
        $periodText, $summary.SourceReports, $summary.TotalMessages, $summary.GptMessages, $summary.ToolMessages, $summary.ProjectMessages
    $overview.Location = New-Object System.Drawing.Point(18, 56)
    $overview.Size = New-Object System.Drawing.Size(920, 54)
    $overview.Anchor = 'Top,Left,Right'
    $overview.Font = New-UiFont 11
    $overview.ForeColor = $uiText
    $dialog.Controls.Add($overview)

    $privacy = New-Object System.Windows.Forms.Label
    $privacy.Text = 'This view accepts one person only. Names, email addresses, IDs, prompt text, and file content are neither shown nor retained.'
    $privacy.Location = New-Object System.Drawing.Point(18, 112)
    $privacy.Size = New-Object System.Drawing.Size(920, 28)
    $privacy.Anchor = 'Top,Left,Right'
    $privacy.Font = New-UiFont 9
    $privacy.ForeColor = $uiTextMuted
    $dialog.Controls.Add($privacy)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(18, 148)
    $tabs.Size = New-Object System.Drawing.Size(928, 500)
    $tabs.Anchor = 'Top,Bottom,Left,Right'
    $tabs.AccessibleName = 'My imported usage breakdowns'
    Set-TabTheme -TabControl $tabs
    $dialog.Controls.Add($tabs)

    $activityRows = @(
        [pscustomobject]@{ Name = 'All messages'; Messages = [int64]$summary.TotalMessages },
        [pscustomobject]@{ Name = 'GPT messages'; Messages = [int64]$summary.GptMessages },
        [pscustomobject]@{ Name = 'Tool messages'; Messages = [int64]$summary.ToolMessages },
        [pscustomobject]@{ Name = 'Project messages'; Messages = [int64]$summary.ProjectMessages }
    )
    $tabDefinitions = @(
        [pscustomobject]@{ Title = 'Activity'; Rows = $activityRows; Columns = @('Name','Messages') },
        [pscustomobject]@{ Title = 'Tools'; Rows = @($summary.Tools); Columns = @('Name','Messages') },
        [pscustomobject]@{ Title = 'Models'; Rows = @($summary.Models); Columns = @('Name','Messages') }
    )
    foreach ($definition in $tabDefinitions) {
        $tab = New-Object System.Windows.Forms.TabPage
        $tab.Text = $definition.Title
        $tab.BackColor = $uiSurface
        $tab.ForeColor = $uiText
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
        $summaryGrid.AccessibleDescription = 'Personal imported usage aggregates with direct identifiers removed.'
        Set-GridTheme $summaryGrid
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
        Write-Output ('Personal usage dialog constructed successfully; Tabs={0}' -f $tabs.TabPages.Count)
    }
    else {
        [void]$dialog.ShowDialog($form)
    }
    $dialog.Dispose()
}

function Show-ComplianceAnalyticsDialog {
    param(
        [string]$InputPath = '',
        [string]$MappingPath = '',
        [switch]$ConstructionOnly,
        [string]$ScreenshotPath = ''
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $inputDialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $inputDialog.Title = 'Open my downloaded activity export'
            $inputDialog.Filter = 'JSONL files (*.jsonl)|*.jsonl|All files (*.*)|*.*'
            $inputDialog.CheckFileExists = $true
            if ($inputDialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $InputPath = $inputDialog.FileName
        }
        finally { $inputDialog.Dispose() }
    }
    if ([string]::IsNullOrWhiteSpace($MappingPath)) {
        $mappingDialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $mappingDialog.Title = 'Open local export mapping (advanced)'
            $mappingDialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
            $mappingDialog.CheckFileExists = $true
            if ($mappingDialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $MappingPath = $mappingDialog.FileName
        }
        finally { $mappingDialog.Dispose() }
    }

    Import-Module -Name (Join-Path $scriptDir 'Live-Codex-Usage-Compliance.psm1') -Force
    $result = Convert-PersonalActivityExport -InputPath $InputPath -MappingPath $MappingPath

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'My activity summary'
    $dialog.Size = New-Object System.Drawing.Size(980, 700)
    $dialog.MinimumSize = New-Object System.Drawing.Size(760, 560)
    $dialog.StartPosition = 'CenterParent'
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.BackColor = $uiWindow
    $dialog.ForeColor = $uiText
    $dialog.Font = New-UiFont 9.5
    $dialog.AccessibleName = 'My local activity export summary'
    $dialog.AccessibleDescription = 'Content-free aggregate view of a local activity JSONL export for one person.'

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = 'My activity summary'
    $heading.Location = New-Object System.Drawing.Point(20, 18)
    $heading.Size = New-Object System.Drawing.Size(920, 34)
    $heading.Anchor = 'Top,Left,Right'
    $heading.Font = New-UiFont 18 ([System.Drawing.FontStyle]::Bold)
    $heading.ForeColor = $uiText
    $dialog.Controls.Add($heading)

    $overview = New-Object System.Windows.Forms.Label
    $overview.Text = 'Input rows {0:N0} | invalid {1:N0} | aggregate rows {2:N0} | local file only' -f `
        $result.InputRows, $result.InvalidLines, $result.OutputRows
    $overview.Location = New-Object System.Drawing.Point(20, 58)
    $overview.Size = New-Object System.Drawing.Size(920, 26)
    $overview.Anchor = 'Top,Left,Right'
    $overview.Font = New-UiFont 10 ([System.Drawing.FontStyle]::Bold)
    $overview.ForeColor = $uiAccent
    $dialog.Controls.Add($overview)

    $privacy = New-Object System.Windows.Forms.Label
    $privacy.Text = 'Personal mode rejects multi-user exports. Prompt/response content and raw identifiers are discarded.'
    $privacy.Location = New-Object System.Drawing.Point(20, 88)
    $privacy.Size = New-Object System.Drawing.Size(920, 38)
    $privacy.Anchor = 'Top,Left,Right'
    $privacy.Font = New-UiFont 9
    $privacy.ForeColor = $uiTextMuted
    $dialog.Controls.Add($privacy)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(20, 136)
    $tabs.Size = New-Object System.Drawing.Size(928, 500)
    $tabs.Anchor = 'Top,Bottom,Left,Right'
    $tabs.AccessibleName = 'My activity breakdowns'
    Set-TabTheme -TabControl $tabs
    $dialog.Controls.Add($tabs)

    $definitions = @(
        [pscustomobject]@{
            Title = 'Surfaces'
            Rows = @($result.Rows | Group-Object Surface | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Events = [int64](($_.Group | Measure-Object Events -Sum).Sum) }
            } | Sort-Object Events -Descending)
        },
        [pscustomobject]@{
            Title = 'Event types'
            Rows = @($result.Rows | Group-Object EventType | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Events = [int64](($_.Group | Measure-Object Events -Sum).Sum) }
            } | Sort-Object Events -Descending)
        },
        [pscustomobject]@{
            Title = 'Models'
            Rows = @($result.Rows | Group-Object Model | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Events = [int64](($_.Group | Measure-Object Events -Sum).Sum) }
            } | Sort-Object Events -Descending)
        },
        [pscustomobject]@{
            Title = 'Daily'
            Rows = @($result.Rows | Group-Object Date | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Events = [int64](($_.Group | Measure-Object Events -Sum).Sum) }
            } | Sort-Object Name)
        }
    )
    foreach ($definition in $definitions) {
        $tab = New-Object System.Windows.Forms.TabPage
        $tab.Text = $definition.Title
        $tab.BackColor = $uiSurface
        $tab.ForeColor = $uiText
        $tabs.TabPages.Add($tab)
        $grid = New-Object System.Windows.Forms.DataGridView
        $grid.Dock = [System.Windows.Forms.DockStyle]::Fill
        $grid.ReadOnly = $true
        $grid.AllowUserToAddRows = $false
        $grid.AllowUserToDeleteRows = $false
        $grid.RowHeadersVisible = $false
        $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
        $grid.AccessibleName = "$($definition.Title) personal activity table"
        [void]$grid.Columns.Add('Name', $(if ($definition.Title -eq 'Daily') { 'Date' } else { $definition.Title.TrimEnd('s') }))
        [void]$grid.Columns.Add('Events', 'Events')
        Set-GridTheme -DataGrid $grid
        foreach ($row in $definition.Rows) { [void]$grid.Rows.Add($row.Name, $row.Events) }
        $tab.Controls.Add($grid)
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
        Write-Output ('Compliance dialog constructed successfully; Tabs={0}; Rows={1}' -f $tabs.TabPages.Count, $result.OutputRows)
    }
    else {
        [void]$dialog.ShowDialog($form)
    }
    $dialog.Dispose()
}

function Show-PersonalImportDialog {
    param([switch]$ConstructionOnly)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Import my data'
    $dialog.Size = New-Object System.Drawing.Size(660, 350)
    $dialog.MinimumSize = $dialog.Size
    $dialog.MaximumSize = $dialog.Size
    $dialog.StartPosition = 'CenterParent'
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.BackColor = $uiWindow
    $dialog.ForeColor = $uiText
    $dialog.Font = New-UiFont 9.5
    $dialog.AccessibleName = 'Import my local ChatGPT data'
    $choiceButtons = [System.Collections.Generic.List[System.Windows.Forms.Button]]::new()

    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = 'Import my data'
    $heading.Location = New-Object System.Drawing.Point(22, 18)
    $heading.Size = New-Object System.Drawing.Size(600, 34)
    $heading.Font = New-UiFont 18 ([System.Drawing.FontStyle]::Bold)
    $heading.ForeColor = $uiText
    $dialog.Controls.Add($heading)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = 'Choose a downloaded report limited to your own account.'
    $note.Location = New-Object System.Drawing.Point(22, 56)
    $note.Size = New-Object System.Drawing.Size(600, 24)
    $note.ForeColor = $uiAccent
    $dialog.Controls.Add($note)

    function Add-PersonalImportChoice {
        param([string]$Title, [string]$Description, [string]$ButtonText, [int]$Y, [string]$Choice)
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Location = New-Object System.Drawing.Point(22, $Y)
        $panel.Size = New-Object System.Drawing.Size(600, 82)
        $panel.BackColor = $uiSurface
        $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $dialog.Controls.Add($panel)
        $titleLabel = New-Object System.Windows.Forms.Label
        $titleLabel.Text = $Title
        $titleLabel.Location = New-Object System.Drawing.Point(14, 10)
        $titleLabel.Size = New-Object System.Drawing.Size(350, 24)
        $titleLabel.Font = New-UiFont 11 ([System.Drawing.FontStyle]::Bold)
        $titleLabel.ForeColor = $uiText
        $panel.Controls.Add($titleLabel)
        $descriptionLabel = New-Object System.Windows.Forms.Label
        $descriptionLabel.Text = $Description
        $descriptionLabel.Location = New-Object System.Drawing.Point(14, 38)
        $descriptionLabel.Size = New-Object System.Drawing.Size(390, 34)
        $descriptionLabel.ForeColor = $uiTextSecondary
        $panel.Controls.Add($descriptionLabel)
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $ButtonText
        $button.Location = New-Object System.Drawing.Point(420, 23)
        $button.Size = New-Object System.Drawing.Size(160, 34)
        $button.BackColor = $uiSurfaceRaised
        $button.ForeColor = $uiText
        $button.FlatStyle = 'Flat'
        $button.FlatAppearance.BorderColor = $uiBorder
        $button.AccessibleName = $Title
        $button.Add_Click({
            $dialog.Tag = $Choice
            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        }.GetNewClosure())
        $panel.Controls.Add($button)
        $choiceButtons.Add($button)
    }
    Add-PersonalImportChoice -Title 'Usage summary (CSV)' `
        -Description 'Messages, models, and tools from a downloaded summary filtered to you.' `
        -ButtonText '&Choose CSV...' -Y 90 -Choice 'Usage'
    Add-PersonalImportChoice -Title 'Activity export (JSONL)' `
        -Description 'Advanced local event aggregation for your own web and Office activity.' `
        -ButtonText 'Choose &JSONL...' -Y 182 -Choice 'Activity'

    $privacy = New-Object System.Windows.Forms.Label
    $privacy.Text = 'Files stay on this PC. Prompt and response text is not retained.'
    $privacy.Location = New-Object System.Drawing.Point(22, 276)
    $privacy.Size = New-Object System.Drawing.Size(600, 24)
    $privacy.ForeColor = $uiTextMuted
    $dialog.Controls.Add($privacy)
    if ($ConstructionOnly) {
        if ($choiceButtons.Count -ne 2 -or
            @($choiceButtons | Where-Object {
                -not $_.Enabled -or [string]::IsNullOrWhiteSpace([string]$_.AccessibleName)
            }).Count -gt 0) {
            throw 'The personal import chooser does not expose both enabled choices.'
        }
        Write-Output ('Import chooser constructed successfully; Choices={0}' -f $choiceButtons.Count)
        $dialog.Dispose()
        return
    }
    [void]$dialog.ShowDialog($form)
    $choice = [string]$dialog.Tag
    $dialog.Dispose()
    if ($choice -eq 'Usage') { Show-EnterpriseAnalyticsDialog }
    elseif ($choice -eq 'Activity') { Show-ComplianceAnalyticsDialog }
}

function Show-ControlCenterDialog {
    param(
        [switch]$ConstructionOnly,
        [ValidateRange(0, 8)]
        [int]$InitialTabIndex = 0,
        [string]$ScreenshotPath = ''
    )

    $allUsage = @(Get-DisplayEvents -Mode 'All sessions')
    Update-DerivedUsageState -VisibleEvents $allUsage
    $script:guardStatus = Invoke-UsageGuardCycle
    [void](Update-RtkSavingsState -Force)
    $trendRows = @(Get-UsageTrendRows -UsageEvents $allUsage -DailyCosts $script:dailyCosts)
    if (-not $DisablePersistence) {
        try {
            $stored = Read-PrivacySafeAggregateStore -Path $script:statePaths.AggregateStore
            if ($null -ne $stored) {
                $trendByDate = @{}
                foreach ($row in @($stored.Daily)) {
                    $trendByDate[[string]$row.Date] = [pscustomobject][ordered]@{
                        Date = [string]$row.Date
                        FreshBurn = [int64]$row.FreshBurn
                        NewInput = [int64]$row.NewInput
                        Output = [int64]$row.Output
                        CachedInput = [int64]$row.CachedInput
                        Context = [int64]$row.Context
                        CachePercent = if (([int64]$row.NewInput + [int64]$row.CachedInput) -gt 0) {
                            [Math]::Round(([int64]$row.CachedInput / [double]([int64]$row.NewInput + [int64]$row.CachedInput)) * 100, 1)
                        } else { 0 }
                        Events = [int]$row.Events
                        Sessions = [int]$row.Sessions
                        EstimatedCredits = [decimal]0
                        ApiEquivalentUsd = [decimal]0
                        UnpricedTokens = [int64]0
                    }
                }
                foreach ($row in $trendRows) { $trendByDate[[string]$row.Date] = $row }
                $trendRows = @($trendByDate.Values | Sort-Object Date)
            }
        }
        catch {
            $script:startupWarnings.Add("Stored trend history could not be loaded: $($_.Exception.Message)")
        }
    }
    $forecast = Get-UsageForecast -DailyRows $trendRows
    $modelRows = @(Get-ModelUsageBreakdown -UsageEvents $allUsage -CostDetails @($script:costEstimate.Details))
    $allActivity = @(Get-DisplayActivity -Mode 'All sessions')
    $allIntegrations = @(Get-DisplayIntegrations -Mode 'All sessions')
    $cacheEfficiency = Get-PromptCacheSavings `
        -RateCard $script:rateCard `
        -UsageEvents $allUsage `
        -DefaultModel ([string]$script:costProfile.DefaultModel) `
        -DollarsPerCredit ([decimal]$script:costProfile.DollarsPerCredit) `
        -CreditRateMultiplier ([decimal]$script:costProfile.CreditRateMultiplier)
    $sessionAdvice = Get-SessionEfficiencyAdvice -UsageEvents $allUsage `
        -BloatedContextTokens $WarnContextTokens
    $schemaHealth = Get-CodexSchemaHealth -Tracker $script:schemaTracker
    $compactionHealth = Get-CompactionChurn -UsageEvents $allUsage -ActivityEvents $allActivity
    $latestEfficiencyEvent = @($allUsage | Sort-Object At -Descending | Select-Object -First 1)
    $quotaWindows = if ($latestEfficiencyEvent.Count -eq 1) {
        @(Get-QuotaWindowMetrics -RateLimits $latestEfficiencyEvent[0].RateLimits)
    }
    else {
        @(Get-QuotaWindowMetrics -RateLimits $null)
    }
    $codexConfigState = Get-CodexEfficiencyConfigState
    $efficiencyPolicyState = Get-CodexEfficiencyPolicyState
    $toolSurfaceAudit = Get-CodexToolSurfaceAudit -IntegrationEvents $allIntegrations

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Live Codex Usage - Control Center'
    $dialog.Size = New-Object System.Drawing.Size(1120, 800)
    $dialog.MinimumSize = New-Object System.Drawing.Size(920, 660)
    $dialog.StartPosition = 'CenterParent'
    $dialog.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $dialog.BackColor = $uiWindow
    $dialog.ForeColor = $uiText
    $dialog.Font = New-UiFont 9.5
    $dialog.KeyPreview = $true
    $dialog.AccessibleName = 'Usage insights and controls'
    $dialog.AccessibleDescription = 'Offline usage trends, cache and context efficiency, independent quota windows, schema health, local RTK savings, cost estimates, downloaded-report comparison, provenance, personal settings, and opt-in guard settings.'

    function Add-ControlCenterLabel {
        param(
            [System.Windows.Forms.Control]$Parent,
            [string]$Text,
            [int]$X,
            [int]$Y,
            [int]$Width,
            [int]$Height,
            [single]$Size = 10,
            [System.Drawing.Color]$Color = $uiTextSecondary,
            [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular
        )
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Text
        $label.Location = New-Object System.Drawing.Point($X, $Y)
        $label.Size = New-Object System.Drawing.Size($Width, $Height)
        $label.Anchor = 'Top,Left,Right'
        $label.AutoEllipsis = $true
        $label.ForeColor = $Color
        $label.BackColor = [System.Drawing.Color]::Transparent
        $label.Font = New-UiFont $Size $Style
        $Parent.Controls.Add($label)
        return $label
    }

    function Add-ControlCenterButton {
        param(
            [System.Windows.Forms.Control]$Parent,
            [string]$Text,
            [int]$X,
            [int]$Y,
            [int]$Width,
            [int]$Height = 32
        )
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Location = New-Object System.Drawing.Point($X, $Y)
        $button.Size = New-Object System.Drawing.Size($Width, $Height)
        $button.BackColor = $uiSurfaceRaised
        $button.ForeColor = $uiText
        $button.FlatStyle = 'Flat'
        $button.UseVisualStyleBackColor = $false
        $button.FlatAppearance.BorderColor = $uiBorder
        $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(44, 51, 60)
        $button.Cursor = [System.Windows.Forms.Cursors]::Hand
        $button.Font = New-UiFont 9
        $Parent.Controls.Add($button)
        return $button
    }

    function New-ControlCenterGrid {
        param(
            [System.Windows.Forms.Control]$Parent,
            [string[]]$Columns,
            [string]$AccessibleName
        )
        $result = New-Object System.Windows.Forms.DataGridView
        $result.Dock = [System.Windows.Forms.DockStyle]::Fill
        $result.ReadOnly = $true
        $result.AllowUserToAddRows = $false
        $result.AllowUserToDeleteRows = $false
        $result.RowHeadersVisible = $false
        $result.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
        $result.AccessibleName = $AccessibleName
        foreach ($column in $Columns) { [void]$result.Columns.Add($column, $column) }
        Set-GridTheme -DataGrid $result
        $Parent.Controls.Add($result)
        return $result
    }

    $heading = Add-ControlCenterLabel -Parent $dialog -Text 'Usage control center' -X 20 -Y 16 -Width 1060 -Height 36 `
        -Size 20 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $subheading = Add-ControlCenterLabel -Parent $dialog `
        -Text 'Every calculation stays on this PC. No account polling, ChatGPT turn, API request, credit, or paid service is used.' `
        -X 20 -Y 56 -Width 1060 -Height 24 -Size 10 -Color $uiAccent
    $sourceHeading = Add-ControlCenterLabel -Parent $dialog `
        -Text ('LOCAL LOGS | RTK {0} | RATE SNAPSHOT {1} | REPORT {2} | GUARD {3}' -f `
            $script:rtkSnapshot.HealthLabel.ToUpperInvariant(), `
            $script:rateCard.EffectiveDate, `
            $(if ($null -ne $script:officialSnapshot) { 'IMPORTED' } else { 'NOT IMPORTED' }), `
            $script:guardStatus.Label.ToUpperInvariant()) `
        -X 20 -Y 84 -Width 1060 -Height 22 -Size 8 -Color $uiTextMuted -Style ([System.Drawing.FontStyle]::Bold)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(20, 116)
    $tabs.Size = New-Object System.Drawing.Size(1064, 620)
    $tabs.Anchor = 'Top,Bottom,Left,Right'
    $tabs.Font = New-UiFont 9.5
    $tabs.AccessibleName = 'Control center sections'
    Set-TabTheme -TabControl $tabs
    $dialog.Controls.Add($tabs)

    function New-ControlCenterTab {
        param([string]$Title)
        $tab = New-Object System.Windows.Forms.TabPage
        $tab.Text = $Title
        $tab.BackColor = $uiSurface
        $tab.ForeColor = $uiText
        $tab.Padding = New-Object System.Windows.Forms.Padding(12)
        $tabs.TabPages.Add($tab)
        return $tab
    }

    # Trends and forecast
    $trendsTab = New-ControlCenterTab 'Trends'
    $trendSummary = Add-ControlCenterLabel -Parent $trendsTab `
        -Text ('{0:N0} fresh tokens observed | trailing average {1:N0}/observed day | projected month {2:N0}' -f `
            $forecast.ObservedFreshBurn, $forecast.RecentDailyAverage, $forecast.ForecastMonthFreshBurn) `
        -X 14 -Y 14 -Width 1008 -Height 26 -Size 11 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $trendNote = Add-ControlCenterLabel -Parent $trendsTab `
        -Text ('Forecast: {0}. Empty calendar days are not treated as zero-use days.' -f $forecast.Method) `
        -X 14 -Y 44 -Width 1008 -Height 22 -Size 9 -Color $uiTextMuted
    $trendPanel = New-Object System.Windows.Forms.Panel
    $trendPanel.Location = New-Object System.Drawing.Point(14, 76)
    $trendPanel.Size = New-Object System.Drawing.Size(1008, 250)
    $trendPanel.Anchor = 'Top,Left,Right'
    $trendPanel.BackColor = $uiWindow
    $trendPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $trendPanel.AccessibleName = 'Daily fresh token trend chart'
    $trendPanel.AccessibleDescription = 'Daily fresh-token totals. The table below exposes the same values as text.'
    $trendPanel.Tag = @($trendRows | Select-Object -Last 30)
    $trendPanel.Add_Paint({
        param($sender, $paintEvent)
        $rows = @($sender.Tag)
        $graphics = $paintEvent.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $bounds = $sender.ClientRectangle
        $left = 54
        $top = 22
        $right = [Math]::Max($left + 1, $bounds.Width - 20)
        $bottom = [Math]::Max($top + 1, $bounds.Height - 42)
        $axisPen = New-Object System.Drawing.Pen($uiBorder, 1)
        $linePen = New-Object System.Drawing.Pen($uiAccent, 2)
        $pointBrush = New-Object System.Drawing.SolidBrush($uiAccent)
        $textBrush = New-Object System.Drawing.SolidBrush($uiTextMuted)
        $smallFont = New-UiFont 8
        try {
            $graphics.DrawLine($axisPen, $left, $bottom, $right, $bottom)
            $graphics.DrawLine($axisPen, $left, $top, $left, $bottom)
            if ($rows.Count -eq 0) {
                $graphics.DrawString('No trend data in the loaded history.', $smallFont, $textBrush, $left + 12, $top + 12)
                return
            }
            [double]$maximum = 1
            foreach ($row in $rows) { $maximum = [Math]::Max($maximum, [double]$row.FreshBurn) }
            $graphics.DrawString((Format-Tokens ([int64]$maximum)), $smallFont, $textBrush, 4, $top - 6)
            $graphics.DrawString('0', $smallFont, $textBrush, 34, $bottom - 8)
            $points = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
            for ($index = 0; $index -lt $rows.Count; $index++) {
                $x = if ($rows.Count -eq 1) { ($left + $right) / 2 } else {
                    $left + (($right - $left) * ($index / [double]($rows.Count - 1)))
                }
                $y = $bottom - (($bottom - $top) * ([double]$rows[$index].FreshBurn / $maximum))
                $points.Add((New-Object System.Drawing.PointF([single]$x, [single]$y)))
            }
            if ($points.Count -gt 1) { $graphics.DrawLines($linePen, $points.ToArray()) }
            foreach ($point in $points) { $graphics.FillEllipse($pointBrush, $point.X - 3, $point.Y - 3, 6, 6) }
            $graphics.DrawString([string]$rows[0].Date, $smallFont, $textBrush, $left, $bottom + 10)
            if ($rows.Count -gt 1) {
                $lastText = [string]$rows[$rows.Count - 1].Date
                $textSize = $graphics.MeasureString($lastText, $smallFont)
                $graphics.DrawString($lastText, $smallFont, $textBrush, $right - $textSize.Width, $bottom + 10)
            }
        }
        finally {
            $axisPen.Dispose()
            $linePen.Dispose()
            $pointBrush.Dispose()
            $textBrush.Dispose()
            $smallFont.Dispose()
        }
    })
    $trendsTab.Controls.Add($trendPanel)
    $trendGridHost = New-Object System.Windows.Forms.Panel
    $trendGridHost.Location = New-Object System.Drawing.Point(14, 338)
    $trendGridHost.Size = New-Object System.Drawing.Size(1008, 230)
    $trendGridHost.Anchor = 'Top,Bottom,Left,Right'
    $trendsTab.Controls.Add($trendGridHost)
    $trendGrid = New-ControlCenterGrid -Parent $trendGridHost `
        -Columns @('Date','Fresh','New input','Output','Cached','Cache %','Events','Tasks','Credits') `
        -AccessibleName 'Daily usage trend table'
    $trendGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $trendWidths = @(100, 100, 100, 100, 100, 80, 70, 70, 100)
    for ($columnIndex = 0; $columnIndex -lt $trendWidths.Count; $columnIndex++) {
        $trendGrid.Columns[$columnIndex].Width = $trendWidths[$columnIndex]
    }
    foreach ($row in @($trendRows | Sort-Object Date -Descending)) {
        [void]$trendGrid.Rows.Add(
            $row.Date, (Format-Tokens $row.FreshBurn), (Format-Tokens $row.NewInput),
            (Format-Tokens $row.Output), (Format-Tokens $row.CachedInput), ('{0}%' -f $row.CachePercent),
            $row.Events, $row.Sessions, ('{0:N3}' -f [decimal]$row.EstimatedCredits)
        )
    }

    # Time-of-week heatmap
    $heatmapTab = New-ControlCenterTab 'Heatmap'
    $heatmapNote = Add-ControlCenterLabel -Parent $heatmapTab `
        -Text 'Fresh-token activity by local day and hour. Each cell contains a text value; color is only a secondary intensity cue.' `
        -X 14 -Y 14 -Width 1008 -Height 24 -Size 10 -Color $uiTextSecondary
    $heatmapGrid = New-Object System.Windows.Forms.DataGridView
    $heatmapGrid.Location = New-Object System.Drawing.Point(14, 48)
    # Leave enough bottom clearance for the horizontal scrollbar at the
    # minimum supported window size so hours 17-23 remain keyboard/mouse
    # reachable without enlarging the dialog.
    $heatmapGrid.Size = New-Object System.Drawing.Size(1008, 480)
    $heatmapGrid.Anchor = 'Top,Left,Right'
    $heatmapGrid.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $heatmapGrid.ReadOnly = $true
    $heatmapGrid.AllowUserToAddRows = $false
    $heatmapGrid.AllowUserToDeleteRows = $false
    $heatmapGrid.RowHeadersVisible = $false
    $heatmapGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $heatmapGrid.AccessibleName = 'Hourly usage heatmap table'
    [void]$heatmapGrid.Columns.Add('Day', 'Day')
    $heatmapGrid.Columns['Day'].Width = 90
    $heatmapGrid.Columns['Day'].Frozen = $true
    foreach ($hour in 0..23) {
        [void]$heatmapGrid.Columns.Add("H$hour", ('{0:00}' -f $hour))
        $heatmapGrid.Columns["H$hour"].Width = 38
    }
    Set-GridTheme -DataGrid $heatmapGrid
    # Twenty-four compact columns fit at the minimum window width. Full
    # numeric values and event counts remain available in each cell tooltip.
    $heatmapGrid.DefaultCellStyle.Font = New-UiFont 8
    $heatmapGrid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(1, 1, 1, 1)
    $heatmapGrid.ColumnHeadersDefaultCellStyle.Font = New-UiFont 8 ([System.Drawing.FontStyle]::Bold)
    $heatCells = @(Get-HourlyUsageHeatmap -UsageEvents $allUsage)
    function Format-HeatmapTokens {
        param([int64]$Value)
        if ($Value -lt 1000) { return [string]$Value }
        if ($Value -lt 1000000) { return ('{0:0}K' -f ($Value / 1000.0)) }
        if ($Value -lt 10000000) { return ('{0:0.0}M' -f ($Value / 1000000.0)) }
        if ($Value -lt 1000000000) { return ('{0:0}M' -f ($Value / 1000000.0)) }
        return ('{0:0.0}B' -f ($Value / 1000000000.0))
    }
    [double]$heatMaximum = 1
    foreach ($cell in $heatCells) { $heatMaximum = [Math]::Max($heatMaximum, [double]$cell.FreshBurn) }
    foreach ($day in 0..6) {
        $dayCells = @($heatCells | Where-Object { $_.DayNumber -eq $day } | Sort-Object Hour)
        $values = [System.Collections.Generic.List[object]]::new()
        $values.Add(([System.DayOfWeek]$day).ToString())
        foreach ($cell in $dayCells) {
            $values.Add($(if ($cell.FreshBurn -gt 0) { Format-HeatmapTokens $cell.FreshBurn } else { '-' }))
        }
        $rowIndex = $heatmapGrid.Rows.Add($values.ToArray())
        for ($hour = 0; $hour -lt $dayCells.Count; $hour++) {
            $cell = $dayCells[$hour]
            $ratio = [Math]::Max(0, [Math]::Min(1, [double]$cell.FreshBurn / $heatMaximum))
            if ($ratio -gt 0) {
                $blue = [int](48 + (80 * $ratio))
                $heatmapGrid.Rows[$rowIndex].Cells[$hour + 1].Style.BackColor = [System.Drawing.Color]::FromArgb(24, $blue, [int](92 + 80 * $ratio))
            }
            $heatmapGrid.Rows[$rowIndex].Cells[$hour + 1].ToolTipText = '{0} {1:00}:00 - fresh {2:N0}, events {3}' -f `
                $cell.Day, $cell.Hour, $cell.FreshBurn, $cell.Events
        }
    }
    $heatmapTab.Controls.Add($heatmapGrid)

    # Usage saver, dual quota windows, schema compatibility, and safe Codex configuration
    $saverTab = New-ControlCenterTab 'Saver'
    $saverTab.AutoScroll = $true
    $saverTab.AccessibleName = 'Usage saver and efficiency'
    $saverTab.AccessibleDescription = 'Local cache efficiency, independent quota windows, session rollover advice, schema health, compaction health, and confirmed reversible Codex settings.'

    function New-SaverCard {
        param(
            [string]$Title,
            [int]$X,
            [int]$Y,
            [int]$Width,
            [int]$Height,
            [string]$AccessibleDescription
        )
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Location = New-Object System.Drawing.Point($X, $Y)
        $panel.Size = New-Object System.Drawing.Size($Width, $Height)
        $panel.BackColor = $uiWindow
        $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $panel.AccessibleName = $Title
        $panel.AccessibleDescription = $AccessibleDescription
        $saverTab.Controls.Add($panel)
        [void](Add-ControlCenterLabel -Parent $panel -Text $Title.ToUpperInvariant() -X 12 -Y 8 `
            -Width ($Width - 24) -Height 18 -Size 8 -Color $uiTextMuted `
            -Style ([System.Drawing.FontStyle]::Bold))
        return $panel
    }

    function New-QuotaSaverCard {
        param([object]$Window, [int]$X)

        $panel = New-SaverCard -Title ([string]$Window.Label) -X $X -Y 14 -Width 496 -Height 94 `
            -AccessibleDescription 'Independent local rate-limit percentage, reset countdown, and pace. Text duplicates the visual meter.'
        $valueLabel = Add-ControlCenterLabel -Parent $panel -Text '' -X 12 -Y 28 -Width 470 -Height 24 `
            -Size 12 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
        $meter = New-Object System.Windows.Forms.ProgressBar
        $meter.Location = New-Object System.Drawing.Point(12, 54)
        $meter.Size = New-Object System.Drawing.Size(470, 10)
        $meter.Minimum = 0
        $meter.Maximum = 100
        $meter.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $meter.AccessibleName = "$($Window.Label) quota used"
        $panel.Controls.Add($meter)
        $detailLabel = Add-ControlCenterLabel -Parent $panel -Text '' -X 12 -Y 69 -Width 470 -Height 18 `
            -Size 8.5 -Color $uiTextMuted
        if ([bool]$Window.Available) {
            $meter.Value = [Math]::Max(0, [Math]::Min(100, [int][double]$Window.UsedPercent))
            $valueLabel.Text = '{0:N0}% used  |  {1:N0}% remaining' -f `
                [double]$Window.UsedPercent, [double]$Window.RemainingPercent
            $valueLabel.ForeColor = if ([double]$Window.UsedPercent -ge 90) {
                $uiCritical
            }
            elseif ([double]$Window.UsedPercent -ge 75) {
                $uiWarning
            }
            else {
                $uiSuccess
            }
            $quotaDetailParts = @(
                @([string]$Window.ResetLabel, [string]$Window.PaceLabel) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            $detailLabel.Text = $quotaDetailParts -join '  |  '
        }
        else {
            $meter.Value = 0
            $valueLabel.Text = 'Not available in the latest local token event'
            $valueLabel.ForeColor = $uiTextSecondary
            $detailLabel.Text = 'The monitor does not poll an account to fill missing quota metadata.'
        }
        return $panel
    }

    [void](New-QuotaSaverCard -Window $quotaWindows[0] -X 14)
    [void](New-QuotaSaverCard -Window $quotaWindows[1] -X 520)

    $cacheCard = New-SaverCard -Title 'Cache efficiency' -X 14 -Y 120 -Width 496 -Height 132 `
        -AccessibleDescription 'Calculated from local cached and fresh input counters. Kept separate from measured RTK output compression.'
    $cacheHeadline = Add-ControlCenterLabel -Parent $cacheCard `
        -Text ('{0:N1}% cache hit  |  {1} health' -f $cacheEfficiency.CacheHitPercent, $cacheEfficiency.HealthLabel) `
        -X 12 -Y 30 -Width 470 -Height 25 -Size 13 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $cacheTokensLabel = Add-ControlCenterLabel -Parent $cacheCard `
        -Text ('Cached {0}  |  fresh input {1}' -f `
            (Format-Tokens ([int64]$cacheEfficiency.CachedInputTokens)), `
            (Format-Tokens ([int64]$cacheEfficiency.FreshInputTokens))) `
        -X 12 -Y 58 -Width 470 -Height 20 -Size 9 -Color $uiTextSecondary
    $cacheMoney = if ($null -ne $cacheEfficiency.CalculatedApiEquivalentUsdAvoided) {
        '  |  API-equivalent ${0:N2}' -f [decimal]$cacheEfficiency.CalculatedApiEquivalentUsdAvoided
    }
    else {
        '  |  API-equivalent incomplete'
    }
    $cacheSavingsLabel = Add-ControlCenterLabel -Parent $cacheCard `
        -Text ('Calculated cache benefit: {0:N3} credits{1}' -f `
            [decimal]$cacheEfficiency.CalculatedCreditsAvoided, $cacheMoney) `
        -X 12 -Y 82 -Width 470 -Height 20 -Size 9 -Color $uiSuccess
    $cacheClassLabel = Add-ControlCenterLabel -Parent $cacheCard `
        -Text ('Separate actual saver: RTK ~{0} estimated output tokens saved. No totals are combined.' -f `
            (Format-Tokens ([int64]$script:rtkSnapshot.SavedTokensEstimate))) `
        -X 12 -Y 106 -Width 470 -Height 18 -Size 8 -Color $uiTextMuted

    $advisorCard = New-SaverCard -Title 'Fresh-task advisor' -X 520 -Y 120 -Width 496 -Height 132 `
        -AccessibleDescription 'Advisory estimate based only on aggregate input replay and observed fresh-task baselines.'
    $advisorHeadline = Add-ControlCenterLabel -Parent $advisorCard -Text ([string]$sessionAdvice.Action) `
        -X 12 -Y 30 -Width 470 -Height 25 -Size 13 `
        -Color $(if ($sessionAdvice.StatusCode -eq 'FreshTaskOpportunity') { $uiWarning } else { $uiSuccess }) `
        -Style ([System.Drawing.FontStyle]::Bold)
    $advisorMetrics = Add-ControlCenterLabel -Parent $advisorCard `
        -Text ('Recent replay {0}/turn  |  baseline {1}  |  possible excess {2}/future turn' -f `
            (Format-Tokens ([int64]$sessionAdvice.RecentAverageInputTokens)), `
            (Format-Tokens ([int64]$sessionAdvice.BaselineStartInputTokens)), `
            (Format-Tokens ([int64]$sessionAdvice.ExcessReplayTokensPerFutureTurn))) `
        -X 12 -Y 58 -Width 470 -Height 20 -Size 9 -Color $uiTextSecondary
    $advisorDetail = Add-ControlCenterLabel -Parent $advisorCard -Text ([string]$sessionAdvice.Detail) `
        -X 12 -Y 82 -Width 470 -Height 38 -Size 8.5 -Color $uiTextMuted

    $reliabilityCard = New-SaverCard -Title 'Coverage and reliability' -X 14 -Y 264 -Width 496 -Height 132 `
        -AccessibleDescription 'Aggregate schema compatibility and compaction churn checks. No log content or identifiers are retained.'
    $schemaLabel = Add-ControlCenterLabel -Parent $reliabilityCard `
        -Text ('Schema: {0}  |  compatibility {1:N1}%' -f $schemaHealth.Label, $schemaHealth.CompatibilityPercent) `
        -X 12 -Y 30 -Width 470 -Height 22 -Size 10 `
        -Color $(if ($schemaHealth.StatusCode -eq 'Healthy') { $uiSuccess } else { $uiWarning }) `
        -Style ([System.Drawing.FontStyle]::Bold)
    $schemaDetailLabel = Add-ControlCenterLabel -Parent $reliabilityCard -Text ([string]$schemaHealth.Detail) `
        -X 12 -Y 54 -Width 470 -Height 34 -Size 8 -Color $uiTextMuted
    $compactionLabel = Add-ControlCenterLabel -Parent $reliabilityCard `
        -Text ('Compaction: {0}  |  reread spikes {1}' -f `
            $compactionHealth.Label, $compactionHealth.PostCompactionRereadSpikes) `
        -X 12 -Y 91 -Width 470 -Height 20 -Size 9 `
        -Color $(if ($compactionHealth.StatusCode -eq 'Churning') { $uiWarning } else { $uiTextSecondary }) `
        -Style ([System.Drawing.FontStyle]::Bold)
    $compactionDetailLabel = Add-ControlCenterLabel -Parent $reliabilityCard `
        -Text ([string]$compactionHealth.Detail) -X 12 -Y 111 -Width 470 -Height 16 `
        -Size 7.5 -Color $uiTextMuted

    $policyCard = New-SaverCard -Title 'Local output-budget policy' -X 14 -Y 408 -Width 496 -Height 144 `
        -AccessibleDescription 'A short managed AGENTS.md block that encourages targeted searches, narrow reads, quiet tests, RTK, and local-only monitoring.'
    $policyStatusLabel = Add-ControlCenterLabel -Parent $policyCard -Text '' -X 12 -Y 30 -Width 470 -Height 22 `
        -Size 10 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $toolAuditLabel = Add-ControlCenterLabel -Parent $policyCard -Text '' -X 12 -Y 55 -Width 470 -Height 38 `
        -Size 8.5 -Color $uiTextSecondary
    $installPolicyButton = Add-ControlCenterButton -Parent $policyCard -Text 'Install policy' -X 12 -Y 101 -Width 132
    $removePolicyButton = Add-ControlCenterButton -Parent $policyCard -Text 'Remove policy' -X 154 -Y 101 -Width 132
    $policyNote = Add-ControlCenterLabel -Parent $policyCard `
        -Text 'Local, removable, zero-outbound; affirmative click only.' `
        -X 298 -Y 99 -Width 184 -Height 38 -Size 7.5 -Color $uiTextMuted

    $configCard = New-SaverCard -Title 'Codex efficiency profiles' -X 520 -Y 264 -Width 496 -Height 288 `
        -AccessibleDescription 'Validates and changes only allowlisted top-level Codex settings after preview and confirmation, with local rollback.'
    $configStatusLabel = Add-ControlCenterLabel -Parent $configCard -Text '' -X 12 -Y 30 -Width 470 -Height 22 `
        -Size 10 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $configCurrentLabel = Add-ControlCenterLabel -Parent $configCard -Text '' -X 12 -Y 54 -Width 470 -Height 38 `
        -Size 8.5 -Color $uiTextSecondary
    $profileBox = New-Object System.Windows.Forms.ComboBox
    $profileBox.Location = New-Object System.Drawing.Point(12, 98)
    $profileBox.Size = New-Object System.Drawing.Size(140, 28)
    $profileBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $profileBox.BackColor = $uiSurfaceRaised
    $profileBox.ForeColor = $uiText
    $profileBox.Font = New-UiFont 9
    [void]$profileBox.Items.AddRange(@('Saver','Balanced','Quality'))
    $profileBox.SelectedItem = 'Balanced'
    $profileBox.AccessibleName = 'Codex efficiency profile'
    $configCard.Controls.Add($profileBox)
    $previewProfileButton = Add-ControlCenterButton -Parent $configCard -Text 'Preview' -X 162 -Y 96 -Width 92
    $applyProfileButton = Add-ControlCenterButton -Parent $configCard -Text 'Apply profile' -X 264 -Y 96 -Width 104
    $repairConfigButton = Add-ControlCenterButton -Parent $configCard -Text 'Safe repair' -X 378 -Y 96 -Width 104
    $rollbackConfigButton = Add-ControlCenterButton -Parent $configCard -Text 'Rollback last change' -X 12 -Y 138 -Width 160
    $validateConfigButton = Add-ControlCenterButton -Parent $configCard -Text 'Validate now' -X 182 -Y 138 -Width 120
    $configProfileNote = Add-ControlCenterLabel -Parent $configCard `
        -Text 'Profiles change future Codex reasoning/verbosity only. They never invoke Codex. Model selection and automatic compaction are left untouched.' `
        -X 12 -Y 180 -Width 470 -Height 42 -Size 8.5 -Color $uiTextMuted
    $configActionLabel = Add-ControlCenterLabel -Parent $configCard `
        -Text 'No configuration action taken.' -X 12 -Y 228 -Width 470 -Height 42 `
        -Size 8.5 -Color $uiTextSecondary

    function Refresh-SaverControls {
        $currentConfig = Get-CodexEfficiencyConfigState
        $currentPolicy = Get-CodexEfficiencyPolicyState
        $currentAudit = Get-CodexToolSurfaceAudit -IntegrationEvents $allIntegrations
        $configStatusLabel.Text = 'Validation: ' + [string]$currentConfig.StatusLabel
        $configStatusLabel.ForeColor = if ($currentConfig.StatusCode -eq 'NeedsRepair') {
            $uiWarning
        }
        else {
            $uiSuccess
        }
        $modelValue = if ($currentConfig.Model) { $currentConfig.Model } else { 'Codex default/unknown' }
        $effortValue = if ($currentConfig.ReasoningEffort) { $currentConfig.ReasoningEffort } else { 'default' }
        $verbosityValue = if ($currentConfig.Verbosity) { $currentConfig.Verbosity } else { 'default' }
        $configCurrentLabel.Text = 'Model {0}  |  reasoning {1}  |  verbosity {2}  |  issues {3}' -f `
            $modelValue, $effortValue, $verbosityValue, $currentConfig.IssueCount
        $repairConfigButton.Enabled = [bool]$currentConfig.RepairAvailable
        $rollbackConfigButton.Enabled = Test-Path -LiteralPath $script:statePaths.CodexEfficiencyRollback -PathType Leaf
        $policyStatusLabel.Text = [string]$currentPolicy.StatusLabel
        $policyStatusLabel.ForeColor = if ($currentPolicy.StatusCode -eq 'Installed') {
            $uiSuccess
        }
        elseif ($currentPolicy.StatusCode -eq 'NeedsRepair') {
            $uiWarning
        }
        else {
            $uiTextSecondary
        }
        $installPolicyButton.Enabled = -not [bool]$currentPolicy.Installed
        $removePolicyButton.Enabled = [bool]$currentPolicy.Installed
        $toolAuditLabel.Text = 'Tool surface: {0} configured MCP section(s), {1} observed category(s), {2} call(s). {3}' -f `
            $currentAudit.ConfiguredMcpServers, $currentAudit.ObservedToolCategories,
            $currentAudit.ObservedCalls, $currentAudit.Recommendation
    }

    $previewProfileButton.Add_Click({
        try {
            $preview = Get-CodexEfficiencyConfigPreview -ProfileName ([string]$profileBox.SelectedItem)
            $changeText = if ($preview.ChangeCount -eq 0) {
                'No allowlisted setting would change.'
            }
            else {
                (@($preview.Changes) | ForEach-Object {
                    '{0}: {1} -> {2}' -f $_.Setting, $_.CurrentValue, $_.ProposedValue
                }) -join [Environment]::NewLine
            }
            [System.Windows.Forms.MessageBox]::Show(
                ("{0}`n`n{1}`n`nThis is a local preview. No Codex request or paid activity occurs." -f `
                    $preview.Description, $changeText),
                'Efficiency profile preview'
            ) | Out-Null
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to preview profile') | Out-Null }
    })
    $applyProfileButton.Add_Click({
        try {
            $profileName = [string]$profileBox.SelectedItem
            $preview = Get-CodexEfficiencyConfigPreview -ProfileName $profileName
            if ($preview.ChangeCount -eq 0) {
                $configActionLabel.Text = "$profileName is already represented by the allowlisted settings."
                Refresh-SaverControls
                return
            }
            $answer = [System.Windows.Forms.MessageBox]::Show(
                ("Apply the {0} profile to future Codex sessions?`n`nOnly reasoning effort and answer verbosity change. " +
                    'A local allowlisted rollback is saved first. Restarting Codex is recommended. No Codex request is made now.') -f $profileName,
                'Confirm efficiency profile',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $result = Set-CodexEfficiencyConfigProfile -ProfileName $profileName `
                -RollbackPath $script:statePaths.CodexEfficiencyRollback -Confirm:$false
            $configActionLabel.Text = if ($result.Applied) {
                "$profileName applied locally. Restart Codex when convenient; rollback is available."
            }
            else {
                'No configuration change was required.'
            }
            Refresh-SaverControls
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to apply profile') | Out-Null }
    })
    $validateConfigButton.Add_Click({
        try {
            $state = Get-CodexEfficiencyConfigState
            $configActionLabel.Text = 'Validation complete: ' + [string]$state.StatusLabel
            Refresh-SaverControls
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to validate configuration') | Out-Null }
    })
    $repairConfigButton.Add_Click({
        try {
            $state = Get-CodexEfficiencyConfigState
            if (-not $state.RepairAvailable) {
                $configActionLabel.Text = 'No allowlisted configuration issue requires repair.'
                Refresh-SaverControls
                return
            }
            $answer = [System.Windows.Forms.MessageBox]::Show(
                ("Normalize {0} duplicate or invalid allowlisted setting issue(s)?`n`n" +
                    'Unknown configuration sections are preserved. A local allowlisted rollback is saved first.') -f $state.IssueCount,
                'Confirm safe configuration repair',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $result = Repair-CodexEfficiencyConfig `
                -RollbackPath $script:statePaths.CodexEfficiencyRollback -Confirm:$false
            $configActionLabel.Text = if ($result.Repaired) {
                "Safe repair completed for $($result.IssueCount) allowlisted issue(s)."
            }
            else {
                'No repair was required.'
            }
            Refresh-SaverControls
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to repair configuration') | Out-Null }
    })
    $rollbackConfigButton.Add_Click({
        try {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                'Restore the allowlisted Codex efficiency settings saved before the last profile or repair action?',
                'Confirm configuration rollback',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            [void](Restore-CodexEfficiencyConfig -RollbackPath $script:statePaths.CodexEfficiencyRollback -Confirm:$false)
            $configActionLabel.Text = 'Prior allowlisted settings restored locally. Restart Codex when convenient.'
            Refresh-SaverControls
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to restore configuration') | Out-Null }
    })
    $installPolicyButton.Add_Click({
        try {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                ('Install the managed local output-budget policy for future Codex work? ' +
                    'It adds a short removable block encouraging RTK, targeted searches, narrow reads, quiet tests, and no monitor-data transmission.'),
                'Confirm local efficiency policy',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            [void](Set-CodexEfficiencyPolicy -Enabled $true -Confirm:$false)
            Refresh-SaverControls
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to install efficiency policy') | Out-Null }
    })
    $removePolicyButton.Add_Click({
        try {
            $answer = [System.Windows.Forms.MessageBox]::Show(
                'Remove only the managed Live Codex Usage Monitor efficiency-policy block?',
                'Confirm policy removal',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            [void](Set-CodexEfficiencyPolicy -Enabled $false -Confirm:$false)
            Refresh-SaverControls
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to remove efficiency policy') | Out-Null }
    })
    Refresh-SaverControls

    # Local RTK command-output savings and health
    $rtkTab = New-ControlCenterTab 'RTK health'
    $rtkBanner = New-Object System.Windows.Forms.Panel
    $rtkBanner.Location = New-Object System.Drawing.Point(14, 14)
    $rtkBanner.Size = New-Object System.Drawing.Size(1008, 54)
    $rtkBanner.Anchor = 'Top,Left,Right'
    $rtkBanner.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $rtkBanner.BackColor = $uiWindow
    $rtkBanner.AccessibleName = 'RTK health status'
    $rtkTab.Controls.Add($rtkBanner)
    $rtkStatusLabel = Add-ControlCenterLabel -Parent $rtkBanner -Text '' -X 14 -Y 8 -Width 420 -Height 24 `
        -Size 11 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $rtkStatusLabel.AccessibleDescription = 'Text status for local RTK tracking health. Color is only a secondary cue.'
    $rtkFreshnessLabel = Add-ControlCenterLabel -Parent $rtkBanner -Text '' -X 438 -Y 8 -Width 552 -Height 22 `
        -Size 9 -Color $uiTextSecondary
    [void](Add-ControlCenterLabel -Parent $rtkBanner `
        -Text 'Local CLI-output compression only; not Codex quota, billing, ChatGPT turns, or API usage.' `
        -X 14 -Y 31 -Width 976 -Height 18 -Size 8.5 -Color $uiTextMuted)

    function Add-RtkMetricCard {
        param([string]$Title, [int]$X, [string]$AccessibleDescription)
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Location = New-Object System.Drawing.Point($X, 80)
        $panel.Size = New-Object System.Drawing.Size(238, 82)
        $panel.BackColor = $uiWindow
        $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $panel.AccessibleName = $Title
        $panel.AccessibleDescription = $AccessibleDescription
        $rtkTab.Controls.Add($panel)
        [void](Add-ControlCenterLabel -Parent $panel -Text $Title.ToUpperInvariant() -X 12 -Y 10 -Width 210 -Height 18 `
            -Size 8 -Color $uiTextMuted -Style ([System.Drawing.FontStyle]::Bold))
        $valueLabel = Add-ControlCenterLabel -Parent $panel -Text '-' -X 12 -Y 30 -Width 210 -Height 28 `
            -Size 15 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
        [void](Add-ControlCenterLabel -Parent $panel -Text 'All locally tracked RTK history' -X 12 -Y 60 -Width 210 -Height 16 `
            -Size 7.5 -Color $uiTextMuted)
        return $valueLabel
    }

    $rtkSavedValue = Add-RtkMetricCard -Title 'Estimated tokens saved' -X 14 `
        -AccessibleDescription 'Estimated shell-output tokens removed by RTK across all locally retained history.'
    $rtkReductionValue = Add-RtkMetricCard -Title 'Output reduction' -X 264 `
        -AccessibleDescription 'Percentage reduction calculated by RTK from local shell-output byte estimates.'
    $rtkCommandsValue = Add-RtkMetricCard -Title 'Commands tracked' -X 514 `
        -AccessibleDescription 'Number of commands recorded by the local RTK history database.'
    $rtkFailuresValue = Add-RtkMetricCard -Title 'Fallbacks / errors' -X 764 `
        -AccessibleDescription 'RTK parse failures that may have fallen back to unfiltered command output.'

    $rtkGridHost = New-Object System.Windows.Forms.Panel
    $rtkGridHost.Location = New-Object System.Drawing.Point(14, 178)
    $rtkGridHost.Size = New-Object System.Drawing.Size(690, 330)
    $rtkGridHost.Anchor = 'Top,Left'
    $rtkTab.Controls.Add($rtkGridHost)
    $rtkGrid = New-ControlCenterGrid -Parent $rtkGridHost `
        -Columns @('Date','Input est','Emitted est','Saved est','Reduction','Commands') `
        -AccessibleName 'Daily local RTK savings history'
    $rtkGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $rtkWidths = @(105,112,112,112,105,90)
    for ($columnIndex = 0; $columnIndex -lt $rtkWidths.Count; $columnIndex++) {
        $rtkGrid.Columns[$columnIndex].Width = $rtkWidths[$columnIndex]
    }
    $rtkGrid.AccessibleDescription = 'Daily aggregate RTK shell-output estimates. No prompts, command text, arguments, or paths are shown.'

    $rtkDiagnostics = New-Object System.Windows.Forms.TextBox
    $rtkDiagnostics.Location = New-Object System.Drawing.Point(718, 178)
    $rtkDiagnostics.Size = New-Object System.Drawing.Size(304, 330)
    $rtkDiagnostics.Anchor = 'Top,Left,Right'
    $rtkDiagnostics.Multiline = $true
    $rtkDiagnostics.ReadOnly = $true
    $rtkDiagnostics.WordWrap = $true
    $rtkDiagnostics.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $rtkDiagnostics.BackColor = $uiWindow
    $rtkDiagnostics.ForeColor = $uiTextSecondary
    $rtkDiagnostics.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $rtkDiagnostics.Font = New-UiFont 9
    $rtkDiagnostics.AccessibleName = 'Sanitized RTK health diagnostics'
    $rtkTab.Controls.Add($rtkDiagnostics)

    $refreshRtkButton = Add-ControlCenterButton -Parent $rtkTab -Text '&Refresh local metrics' -X 14 -Y 520 -Width 178
    $refreshRtkButton.Anchor = 'Top,Left'
    $rtkDisclaimer = Add-ControlCenterLabel -Parent $rtkTab `
        -Text 'RTK estimates tokens from shell-output bytes. Do not combine these estimates with OpenAI credits, quota, billing, or cash totals.' `
        -X 208 -Y 524 -Width 814 -Height 34 -Size 8.5 -Color $uiTextMuted
    $rtkDisclaimer.Anchor = 'Top,Left,Right'

    function Refresh-RtkTab {
        $snapshot = $script:rtkSnapshot
        $rtkStatusLabel.Text = 'RTK: ' + [string]$snapshot.HealthLabel
        $rtkStatusLabel.ForeColor = switch ([string]$snapshot.HealthCode) {
            { $_ -in @('Unavailable','PossibleBypass','Degraded') } { $uiCritical; break }
            { $_ -in @('NotInstalled','Disabled','Ineffective','ReadyNoData') } { $uiWarning; break }
            default { $uiSuccess }
        }
        $lastMetric = if ($null -eq $snapshot.LastTrackedAt) { 'No local metric recorded' } else {
            'Last local metric {0} ({1:N0} min old)' -f ([datetime]$snapshot.LastTrackedAt).ToString('g'), [double]$snapshot.DataAgeMinutes
        }
        $rtkFreshnessLabel.Text = '{0} | v{1}' -f $lastMetric, $(if ($snapshot.Version) { $snapshot.Version } else { 'unknown' })
        $rtkSavedValue.Text = '~' + (Format-Tokens ([int64]$snapshot.SavedTokensEstimate))
        $rtkReductionValue.Text = '{0:N1}%' -f [double]$snapshot.SavingsPercent
        $rtkCommandsValue.Text = '{0:N0}' -f [int64]$snapshot.TotalCommands
        $rtkFailuresValue.Text = '{0:N0}' -f [int]$snapshot.FailureCount
        $rtkFailuresValue.ForeColor = if ([int]$snapshot.FailureCount -gt 0) { $uiCritical } else { $uiText }

        $rtkGrid.Rows.Clear()
        foreach ($row in @($snapshot.Daily | Sort-Object Date -Descending)) {
            [void]$rtkGrid.Rows.Add(
                $row.Date,
                (Format-Tokens ([int64]$row.InputTokensEstimate)),
                (Format-Tokens ([int64]$row.OutputTokensEstimate)),
                (Format-Tokens ([int64]$row.SavedTokensEstimate)),
                ('{0:N1}%' -f [double]$row.SavingsPercent),
                ('{0:N0}' -f [int64]$row.Commands)
            )
        }
        $shortHealthDetail = switch ([string]$snapshot.HealthCode) {
            'Active' { 'Tracking works and local history is current.' }
            'Idle' { 'Tracking works; no recent update was expected.' }
            'Ineffective' { 'Tracking works; no output reduction yet.' }
            'PossibleBypass' { 'Recent shell activity is newer than RTK.' }
            'Degraded' { 'Parser fallback or failure was recorded.' }
            'NotInstalled' { 'No local RTK executable was detected.' }
            'Unavailable' { 'RTK local metrics could not be read.' }
            'ReadyNoData' { 'RTK is ready; no command is tracked yet.' }
            default { [string]$snapshot.Message }
        }
        $diagnosticLines = @(
            'HEALTH AND COVERAGE'
            ''
            ('Status: ' + [string]$snapshot.HealthLabel)
            ('Detail: ' + $shortHealthDetail)
            ('Version: ' + $(if ($snapshot.Version) { [string]$snapshot.Version } else { 'not detected' }))
            ('History database: ' + $(if ($snapshot.DatabasePath -and (Test-Path -LiteralPath $snapshot.DatabasePath -PathType Leaf)) { 'local file available' } else { 'not found' }))
            ('Parse failures: {0:N0}' -f [int]$snapshot.FailureCount)
            ('Telemetry: blocked')
            ('Network requests by monitor: none')
            ''
            'WHAT FAILURE STATES MEAN'
            'Possible bypass: activity newer than history.'
            'Degraded: parser fallback/failure recorded.'
            'No savings: emitted output was unchanged.'
            ''
            'Token values are RTK byte estimates.'
            'They are not billed tokens or cash savings.'
        )
        $rtkDiagnostics.Lines = [string[]]$diagnosticLines
        try {
            $rtkStatusLabel.AccessibilityNotifyClients([System.Windows.Forms.AccessibleEvents]::NameChange, -1)
        }
        catch { }
    }
    $refreshRtkButton.Add_Click({
        try {
            $refreshRtkButton.Enabled = $false
            [void](Update-RtkSavingsState -Force)
            Refresh-RtkTab
            $sourceHeading.Text = 'LOCAL LOGS | RTK {0} | RATE SNAPSHOT {1} | REPORT {2} | GUARD {3}' -f `
                $script:rtkSnapshot.HealthLabel.ToUpperInvariant(), `
                $script:rateCard.EffectiveDate, `
                $(if ($null -ne $script:officialSnapshot) { 'IMPORTED' } else { 'NOT IMPORTED' }), `
                $script:guardStatus.Label.ToUpperInvariant()
        }
        finally { $refreshRtkButton.Enabled = $true }
    })
    Refresh-RtkTab

    # Cost estimates and local contract parameters
    $costTab = New-ControlCenterTab 'Cost'
    $costSummaryText = 'Selected range: {0:N4} estimated credits | {1} | priced {2} | unpriced {3}' -f `
        [decimal]$script:costEstimate.EstimatedCredits, `
        $(if ($null -ne $script:costEstimate.ApiEquivalentUsd) {
            'API-equivalent ${0:N4}' -f [decimal]$script:costEstimate.ApiEquivalentUsd
        } else { 'API-equivalent unavailable' }), `
        (Format-Tokens $script:costEstimate.PricedTokens), `
        (Format-Tokens $script:costEstimate.UnpricedTokens)
    $costSummary = Add-ControlCenterLabel -Parent $costTab -Text $costSummaryText `
        -X 14 -Y 14 -Width 1008 -Height 26 -Size 11 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $cashSummary = Add-ControlCenterLabel -Parent $costTab `
        -Text $(if ($script:configuredSpend.CashEstimateAvailable) {
            'Configured billing cycle estimate: ${0:N2} ({1:N2} fixed + {2:N2} variable).' -f `
                $script:configuredSpend.EstimatedCycleSpendUsd, $script:configuredSpend.FixedCostPerCycleUsd, $script:configuredSpend.EstimatedVariableUsd
        } else {
            'Configured cash estimate is unavailable until your dollars-per-credit value is supplied.'
        }) `
        -X 14 -Y 44 -Width 1008 -Height 24 -Size 10 -Color $uiAccent
    $costDisclaimer = Add-ControlCenterLabel -Parent $costTab `
        -Text 'Credits use the dated bundled OpenAI rate card. API-equivalent USD is not a bill. Fast/service-tier differences require your multiplier. Unknown models are never guessed.' `
        -X 14 -Y 72 -Width 1008 -Height 36 -Size 9 -Color $uiTextMuted

    $settingsPanel = New-Object System.Windows.Forms.Panel
    $settingsPanel.Location = New-Object System.Drawing.Point(14, 116)
    $settingsPanel.Size = New-Object System.Drawing.Size(420, 440)
    $settingsPanel.Anchor = 'Top,Bottom,Left'
    $settingsPanel.BackColor = $uiWindow
    $settingsPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $costTab.Controls.Add($settingsPanel)
    [void](Add-ControlCenterLabel -Parent $settingsPanel -Text 'Local billing parameters' -X 16 -Y 14 -Width 380 -Height 26 `
        -Size 11 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold))

    function Add-CostNumeric {
        param([string]$Label, [int]$Y, [decimal]$Value, [decimal]$Minimum, [decimal]$Maximum, [int]$Decimals = 2)
        [void](Add-ControlCenterLabel -Parent $settingsPanel -Text $Label -X 16 -Y $Y -Width 210 -Height 22 -Size 9 -Color $uiTextSecondary)
        $numeric = New-Object System.Windows.Forms.NumericUpDown
        $numeric.Location = New-Object System.Drawing.Point(230, ($Y - 3))
        $numeric.Size = New-Object System.Drawing.Size(160, 26)
        $numeric.Minimum = $Minimum
        $numeric.Maximum = $Maximum
        $numeric.DecimalPlaces = $Decimals
        $numeric.Increment = if ($Decimals -gt 0) { [decimal]0.01 } else { [decimal]1 }
        $numeric.Value = [Math]::Max($Minimum, [Math]::Min($Maximum, $Value))
        $numeric.BackColor = $uiSurfaceRaised
        $numeric.ForeColor = $uiText
        $settingsPanel.Controls.Add($numeric)
        return $numeric
    }

    [void](Add-ControlCenterLabel -Parent $settingsPanel -Text 'Fallback model (blank = no guessing)' -X 16 -Y 56 -Width 210 -Height 22 -Size 9)
    $defaultModelBox = New-Object System.Windows.Forms.ComboBox
    $defaultModelBox.Location = New-Object System.Drawing.Point(230, 53)
    $defaultModelBox.Size = New-Object System.Drawing.Size(160, 26)
    $defaultModelBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    [void]$defaultModelBox.Items.Add('')
    foreach ($rateModel in @($script:rateCard.Models)) { [void]$defaultModelBox.Items.Add([string]$rateModel.Id) }
    $defaultModelBox.Text = [string]$script:costProfile.DefaultModel
    $defaultModelBox.BackColor = $uiSurfaceRaised
    $defaultModelBox.ForeColor = $uiText
    $settingsPanel.Controls.Add($defaultModelBox)
    $dollarsPerCreditBox = Add-CostNumeric -Label 'Dollars per credit (-1 unknown)' -Y 96 `
        -Value ([decimal]$script:costProfile.DollarsPerCredit) -Minimum ([decimal]-1) -Maximum ([decimal]10000) -Decimals 4
    $includedCreditsBox = Add-CostNumeric -Label 'Included credits per cycle' -Y 136 `
        -Value ([decimal]$script:costProfile.IncludedCreditsPerCycle) -Minimum 0 -Maximum 1000000000 -Decimals 2
    $fixedCostBox = Add-CostNumeric -Label 'Fixed cost per cycle (USD)' -Y 176 `
        -Value ([decimal]$script:costProfile.FixedCostPerCycleUsd) -Minimum 0 -Maximum 1000000000 -Decimals 2
    $multiplierBox = Add-CostNumeric -Label 'Credit-rate multiplier' -Y 216 `
        -Value ([decimal]$script:costProfile.CreditRateMultiplier) -Minimum ([decimal]0.01) -Maximum 100 -Decimals 2
    $billingDayBox = Add-CostNumeric -Label 'Billing cycle start day' -Y 256 `
        -Value ([decimal]$script:costProfile.BillingCycleStartDay) -Minimum 1 -Maximum 28 -Decimals 0
    $saveCostButton = Add-ControlCenterButton -Parent $settingsPanel -Text '&Save local parameters' -X 16 -Y 306 -Width 190
    $costSavedLabel = Add-ControlCenterLabel -Parent $settingsPanel `
        -Text 'Settings contain no credentials or account identifiers.' -X 16 -Y 350 -Width 380 -Height 46 -Size 9 -Color $uiTextMuted
    $saveCostButton.Add_Click({
        try {
            $profile = New-UsageCostProfile `
                -DefaultModel $defaultModelBox.Text `
                -DollarsPerCredit ([decimal]$dollarsPerCreditBox.Value) `
                -IncludedCreditsPerCycle ([decimal]$includedCreditsBox.Value) `
                -FixedCostPerCycleUsd ([decimal]$fixedCostBox.Value) `
                -CreditRateMultiplier ([decimal]$multiplierBox.Value) `
                -BillingCycleStartDay ([int]$billingDayBox.Value)
            $script:costProfile = $profile
            if (-not $DisablePersistence) {
                Export-UsageCostProfile -Profile $profile -Path $script:statePaths.CostProfile | Out-Null
            }
            Update-DerivedUsageState -VisibleEvents $allUsage
            $costSavedLabel.Text = 'Saved locally at {0}. Close and reopen this view to refresh every summary.' -f (Get-Date).ToString('T')
            $costSavedLabel.ForeColor = $uiSuccess
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to save cost parameters') | Out-Null
        }
    })

    $ratePanel = New-Object System.Windows.Forms.Panel
    $ratePanel.Location = New-Object System.Drawing.Point(448, 116)
    $ratePanel.Size = New-Object System.Drawing.Size(574, 440)
    $ratePanel.Anchor = 'Top,Bottom,Left,Right'
    $costTab.Controls.Add($ratePanel)
    $rateGrid = New-ControlCenterGrid -Parent $ratePanel `
        -Columns @('Model','Input credits/M','Cached credits/M','Output credits/M','API equivalent') `
        -AccessibleName 'Bundled model rate card'
    $rateGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $rateWidths = @(135, 90, 100, 100, 90)
    for ($columnIndex = 0; $columnIndex -lt $rateWidths.Count; $columnIndex++) {
        $rateGrid.Columns[$columnIndex].Width = $rateWidths[$columnIndex]
    }
    foreach ($rateModel in @($script:rateCard.Models)) {
        [void]$rateGrid.Rows.Add(
            $rateModel.Id,
            $rateModel.CreditsPerMillion.Input,
            $rateModel.CreditsPerMillion.CachedInput,
            $rateModel.CreditsPerMillion.Output,
            $(if ($rateModel.ApiEquivalentAvailable) { 'Published' } else { 'Not shown' })
        )
    }

    # Downloaded report comparison
    $reconcileTab = New-ControlCenterTab 'Compare'
    $reconcileHeading = Add-ControlCenterLabel -Parent $reconcileTab `
        -Text "Compare this PC's local Codex estimate with a usage report that you downloaded." `
        -X 14 -Y 14 -Width 1008 -Height 26 -Size 11 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $reconcileNote = Add-ControlCenterLabel -Parent $reconcileTab `
        -Text 'The app never signs in or fetches account data. Downloaded reports may lag 1-24 hours (typically 6-12; service target up to 48), and your ChatGPT/Excel usage can make totals differ.' `
        -X 14 -Y 44 -Width 1008 -Height 42 -Size 9 -Color $uiTextMuted
    $importOfficialButton = Add-ControlCenterButton -Parent $reconcileTab -Text '&Import local report' -X 14 -Y 94 -Width 150
    $watchOfficialButton = Add-ControlCenterButton -Parent $reconcileTab -Text 'Use &watched folder' -X 176 -Y 94 -Width 166
    $officialStatusLabel = Add-ControlCenterLabel -Parent $reconcileTab -Text 'Downloaded report: not imported' `
        -X 356 -Y 98 -Width 666 -Height 28 -Size 9 -Color $uiTextSecondary
    $reconcileGridHost = New-Object System.Windows.Forms.Panel
    $reconcileGridHost.Location = New-Object System.Drawing.Point(14, 138)
    $reconcileGridHost.Size = New-Object System.Drawing.Size(1008, 430)
    $reconcileGridHost.Anchor = 'Top,Bottom,Left,Right'
    $reconcileTab.Controls.Add($reconcileGridHost)
    $reconcileGrid = New-ControlCenterGrid -Parent $reconcileGridHost `
        -Columns @('Date','Local est credits','Reported credits','Variance','Variance %','Coverage %','Status') `
        -AccessibleName 'Local and downloaded daily usage comparison'
    $reconcileGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $reconcileWidths = @(105, 145, 135, 125, 120, 120, 155)
    for ($columnIndex = 0; $columnIndex -lt $reconcileWidths.Count; $columnIndex++) {
        $reconcileGrid.Columns[$columnIndex].Width = $reconcileWidths[$columnIndex]
    }

    function Refresh-ReconciliationGrid {
        $reconcileGrid.Rows.Clear()
        if ($null -eq $script:officialSnapshot) {
            $officialStatusLabel.Text = 'Downloaded report: not imported. Choose a local CSV/JSON or place one in the watched folder.'
            $officialStatusLabel.ForeColor = $uiTextMuted
            return
        }
        $freshness = Get-OfficialSnapshotFreshness -ReportUpdatedAt ([datetime]$script:officialSnapshot.ReportUpdatedAt)
        $officialStatusLabel.Text = '{0} | {1:N1}h old | {2}' -f `
            $script:officialSnapshot.SourceFileName, $freshness.AgeHours, $freshness.Label
        $officialStatusLabel.ForeColor = if ($freshness.AgeHours -gt 48) { $uiCritical } elseif ($freshness.AgeHours -gt 12) { $uiWarning } else { $uiSuccess }
        $comparison = @(Compare-OfficialUsageSnapshot `
            -LocalDailyCosts $script:dailyCosts `
            -OfficialSnapshot $script:officialSnapshot)
        foreach ($row in $comparison) {
            $index = $reconcileGrid.Rows.Add(
                $row.Date,
                ('{0:N4}' -f $row.LocalEstimatedCredits),
                ('{0:N4}' -f $row.OfficialCredits),
                ('{0:N4}' -f $row.VarianceCredits),
                $(if ($null -eq $row.VariancePercent) { '-' } else { '{0:N2}%' -f $row.VariancePercent }),
                $(if ($null -eq $row.CoveragePercent) { '-' } else { '{0:N2}%' -f $row.CoveragePercent }),
                $row.Status
            )
            if ($row.Status -eq 'Aligned') { $reconcileGrid.Rows[$index].DefaultCellStyle.ForeColor = $uiSuccess }
            elseif ($row.Status -ne 'No usage') { $reconcileGrid.Rows[$index].DefaultCellStyle.ForeColor = $uiWarning }
        }
    }

    $importOfficialButton.Add_Click({
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $openDialog.Title = 'Open my downloaded usage report'
            $openDialog.Filter = 'Usage snapshots (*.csv;*.json)|*.csv;*.json|All files (*.*)|*.*'
            $openDialog.CheckFileExists = $true
            if ($openDialog.ShowDialog($dialog) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $script:officialSnapshot = Import-OfficialUsageSnapshot -Path $openDialog.FileName
            $item = Get-Item -LiteralPath $openDialog.FileName
            $script:officialSnapshotFullName = $item.FullName
            $script:officialSnapshotSignature = '{0}|{1}' -f $item.FullName, $item.LastWriteTimeUtc.Ticks
            $script:manualOfficialSnapshot = $true
            Refresh-ReconciliationGrid
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to import downloaded report') | Out-Null
        }
        finally { $openDialog.Dispose() }
    })
    $watchOfficialButton.Add_Click({
        try {
            if (-not (Test-Path -LiteralPath $script:statePaths.OfficialReports -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $script:statePaths.OfficialReports)
            }
            $script:manualOfficialSnapshot = $false
            $script:officialSnapshotSignature = ''
            Update-OfficialSnapshotFromWatchFolder
            Refresh-ReconciliationGrid
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to use watched folder') | Out-Null
        }
    })
    Refresh-ReconciliationGrid

    # Opt-in usage guard and local Codex kill switch
    $guardReadiness = Get-UsageGuardReadiness -Policy $script:guardPolicy
    $guardTab = New-ControlCenterTab 'Usage guard'
    $guardHeading = Add-ControlCenterLabel -Parent $guardTab `
        -Text 'Usage limit and local Codex kill switch' -X 14 -Y 14 -Width 1008 -Height 28 `
        -Size 11 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
    $guardWarning = Add-ControlCenterLabel -Parent $guardTab `
        -Text 'Advisory mode warns only. Enforced mode can terminate an active Codex process after the grace period and may interrupt work. It never blocks ChatGPT web or Office add-ins.' `
        -X 14 -Y 46 -Width 1008 -Height 42 -Size 9 -Color $uiWarning
    $guardStateLabel = Add-ControlCenterLabel -Parent $guardTab `
        -Text ([string]$guardReadiness.StatusLabel) `
        -X 14 -Y 94 -Width 1008 -Height 30 -Size 10 `
        -Color $(if ($script:guardPolicy.Locked) { $uiCritical } elseif ($script:guardPolicy.Enabled) { $uiSuccess } else { $uiTextSecondary }) `
        -Style ([System.Drawing.FontStyle]::Bold)
    $guardStateLabel.AccessibleName = 'Usage guard and kill switch status'
    $guardStateLabel.AccessibleDescription = 'Explicitly states whether process stopping is off, advisory only, armed, in grace, renewed, or locked.'

    $guardSettings = New-Object System.Windows.Forms.Panel
    $guardSettings.Location = New-Object System.Drawing.Point(14, 134)
    $guardSettings.Size = New-Object System.Drawing.Size(1008, 330)
    $guardSettings.Anchor = 'Top,Left,Right'
    $guardSettings.BackColor = $uiWindow
    $guardSettings.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $guardTab.Controls.Add($guardSettings)

    $guardEnabled = New-Object System.Windows.Forms.CheckBox
    $guardEnabled.Text = '&Enable usage limit / kill switch'
    $guardEnabled.Location = New-Object System.Drawing.Point(18, 18)
    $guardEnabled.Size = New-Object System.Drawing.Size(300, 26)
    $guardEnabled.Checked = [bool]$script:guardPolicy.Enabled
    $guardEnabled.ForeColor = $uiText
    $guardEnabled.AccessibleDescription = 'The usage guard is off by default and does nothing until explicitly enabled.'
    $guardSettings.Controls.Add($guardEnabled)

    [void](Add-ControlCenterLabel -Parent $guardSettings -Text 'Mode' -X 18 -Y 58 -Width 190 -Height 22 -Size 9)
    $guardMode = New-Object System.Windows.Forms.ComboBox
    $guardMode.Location = New-Object System.Drawing.Point(210, 55)
    $guardMode.Size = New-Object System.Drawing.Size(210, 26)
    $guardMode.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$guardMode.Items.AddRange(@('Advisory (warn only)','Enforced (can stop Codex)'))
    $guardMode.SelectedIndex = if ([string]$script:guardPolicy.Mode -eq 'Enforced') { 1 } else { 0 }
    $guardMode.BackColor = $uiSurfaceRaised
    $guardMode.ForeColor = $uiText
    $guardSettings.Controls.Add($guardMode)

    [void](Add-ControlCenterLabel -Parent $guardSettings -Text 'Metric' -X 18 -Y 96 -Width 190 -Height 22 -Size 9)
    $guardMetric = New-Object System.Windows.Forms.ComboBox
    $guardMetric.Location = New-Object System.Drawing.Point(210, 93)
    $guardMetric.Size = New-Object System.Drawing.Size(210, 26)
    $guardMetric.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$guardMetric.Items.AddRange(@('EstimatedCredits','FreshBurn','ApiEquivalentUsd','ActualUsd','QuotaPercent'))
    $guardMetric.SelectedItem = [string]$script:guardPolicy.Metric
    $guardMetric.BackColor = $uiSurfaceRaised
    $guardMetric.ForeColor = $uiText
    $guardSettings.Controls.Add($guardMetric)

    [void](Add-ControlCenterLabel -Parent $guardSettings -Text 'Threshold' -X 18 -Y 134 -Width 190 -Height 22 -Size 9)
    $guardThreshold = New-Object System.Windows.Forms.NumericUpDown
    $guardThreshold.Location = New-Object System.Drawing.Point(210, 131)
    $guardThreshold.Size = New-Object System.Drawing.Size(210, 26)
    $guardThreshold.Minimum = [decimal]0.0001
    $guardThreshold.Maximum = [decimal]1000000000
    $guardThreshold.DecimalPlaces = 4
    $guardThreshold.Value = [Math]::Max($guardThreshold.Minimum, [Math]::Min($guardThreshold.Maximum, [decimal]$script:guardPolicy.Threshold))
    $guardThreshold.BackColor = $uiSurfaceRaised
    $guardThreshold.ForeColor = $uiText
    $guardSettings.Controls.Add($guardThreshold)

    [void](Add-ControlCenterLabel -Parent $guardSettings -Text 'Grace seconds' -X 18 -Y 172 -Width 190 -Height 22 -Size 9)
    $guardGrace = New-Object System.Windows.Forms.NumericUpDown
    $guardGrace.Location = New-Object System.Drawing.Point(210, 169)
    $guardGrace.Size = New-Object System.Drawing.Size(210, 26)
    $guardGrace.Minimum = 0
    $guardGrace.Maximum = 3600
    $guardGrace.Value = [int]$script:guardPolicy.GraceSeconds
    $guardGrace.BackColor = $uiSurfaceRaised
    $guardGrace.ForeColor = $uiText
    $guardSettings.Controls.Add($guardGrace)

    [void](Add-ControlCenterLabel -Parent $guardSettings -Text 'Exact approved executable path(s)' -X 458 -Y 18 -Width 500 -Height 22 -Size 9)
    $guardPaths = New-Object System.Windows.Forms.TextBox
    $guardPaths.Location = New-Object System.Drawing.Point(458, 44)
    $guardPaths.Size = New-Object System.Drawing.Size(520, 72)
    $guardPaths.Multiline = $true
    $guardPaths.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $guardPaths.Text = @($script:guardPolicy.ApprovedExecutablePaths) -join [Environment]::NewLine
    $guardPaths.BackColor = $uiSurfaceRaised
    $guardPaths.ForeColor = $uiText
    $guardPaths.AccessibleDescription = 'One exact executable path per line. Enforced mode stops only an exact full-path match.'
    $guardSettings.Controls.Add($guardPaths)
    $browseGuardPath = Add-ControlCenterButton -Parent $guardSettings -Text '&Browse executable' -X 458 -Y 128 -Width 168
    $verifyGuardPath = Add-ControlCenterButton -Parent $guardSettings -Text '&Verify path matches' -X 638 -Y 128 -Width 176
    $saveGuard = Add-ControlCenterButton -Parent $guardSettings -Text '&Save guard settings' -X 18 -Y 226 -Width 190
    $renewGuard = Add-ControlCenterButton -Parent $guardSettings -Text '&Re-enable Codex until midnight' -X 220 -Y 226 -Width 226
    $renewGuard.Enabled = [bool]$script:guardPolicy.Locked
    $guardReadinessLabel = Add-ControlCenterLabel -Parent $guardSettings -Text '' `
        -X 458 -Y 260 -Width 520 -Height 50 -Size 8.5 -Color $uiTextSecondary
    $guardReadinessLabel.AutoEllipsis = $false
    $guardReadinessLabel.AccessibleName = 'Usage guard readiness summary'
    $guardFootnote = Add-ControlCenterLabel -Parent $guardSettings `
        -Text ("Daily metrics reset with the local date. ActualUsd uses the configured billing-cycle estimate." +
            [Environment]::NewLine + 'Enforcement works only while this monitor is running and only for exact approved paths.') `
        -X 458 -Y 174 -Width 520 -Height 78 -Size 9 -Color $uiTextMuted
    $guardFootnote.AutoEllipsis = $false

    function Refresh-GuardReadinessDisplay {
        $guardReadiness = Get-UsageGuardReadiness -Policy $script:guardPolicy
        if ([bool]$script:guardPolicy.Locked) {
            $guardStateLabel.Text = 'LOCKED - Codex requires affirmative re-enable'
            $guardStateLabel.ForeColor = $uiCritical
        }
        elseif ([string]$script:guardStatus.Label -like 'Warning*') {
            $guardStateLabel.Text = 'GRACE - threshold exceeded; ' + [string]$script:guardStatus.Label
            $guardStateLabel.ForeColor = $uiWarning
        }
        elseif ([string]$script:guardStatus.Label -eq 'Renewed') {
            $guardStateLabel.Text = 'RENEWED - enforcement paused until local midnight'
            $guardStateLabel.ForeColor = $uiSuccess
        }
        else {
            $guardStateLabel.Text = [string]$guardReadiness.StatusLabel
            $guardStateLabel.ForeColor = switch ([string]$guardReadiness.StatusCode) {
                'Armed' { $uiSuccess }
                'Advisory' { $uiWarning }
                'NotReady' { $uiCritical }
                default { $uiTextSecondary }
            }
        }
        $guardReadinessLabel.Text = 'Trigger: {0:N4} / {1:N4} {2} | Scope: {3} exact path(s) | Running matches: {4} | Grace: {5}s' -f `
            [decimal]$script:guardStatus.Value, [decimal]$script:guardPolicy.Threshold, [string]$script:guardPolicy.Metric, `
            [int]$guardReadiness.ApprovedPathCount, [int]$guardReadiness.RunningMatchCount, [int]$script:guardPolicy.GraceSeconds
        if ([string]$guardReadiness.StatusCode -eq 'Armed' -and
            -not [bool]$script:startupRegistration.MatchesLauncher) {
            $guardReadinessLabel.Text += [Environment]::NewLine +
                'Guard is not always available because the monitor does not start when you sign in.'
            $guardReadinessLabel.ForeColor = $uiWarning
        }
        else { $guardReadinessLabel.ForeColor = $uiTextSecondary }
        try {
            $guardStateLabel.AccessibilityNotifyClients([System.Windows.Forms.AccessibleEvents]::NameChange, -1)
        }
        catch { }
    }

    $browseGuardPath.Add_Click({
        $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $fileDialog.Title = 'Approve the exact Codex executable'
            $fileDialog.Filter = 'Applications (*.exe)|*.exe'
            $fileDialog.CheckFileExists = $true
            if ($fileDialog.ShowDialog($dialog) -eq [System.Windows.Forms.DialogResult]::OK) {
                $existingPaths = @($guardPaths.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                $guardPaths.Lines = @($existingPaths + $fileDialog.FileName | Sort-Object -Unique)
            }
        }
        finally { $fileDialog.Dispose() }
    })
    $verifyGuardPath.Add_Click({
        try {
            $approvedPaths = @($guardPaths.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $temporaryPolicy = New-UsageGuardPolicy -ApprovedExecutablePaths $approvedPaths
            $readiness = Get-UsageGuardReadiness -Policy $temporaryPolicy
            $guardReadinessLabel.Text = 'Verification only - {0} exact path(s); {1} matching process(es) running. Nothing was stopped.' -f `
                $readiness.ApprovedPathCount, $readiness.RunningMatchCount
            $guardReadinessLabel.ForeColor = if ($readiness.RunningMatchCount -gt 0) { $uiSuccess } else { $uiWarning }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to verify executable paths') | Out-Null
        }
    })
    $saveGuard.Add_Click({
        try {
            if ([bool]$script:guardPolicy.Locked -and -not $guardEnabled.Checked) {
                throw 'Use Renew until midnight before disabling a locked guard.'
            }
            $approvedPaths = @($guardPaths.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $selectedMode = if ($guardMode.SelectedIndex -eq 1) { 'Enforced' } else { 'Advisory' }
            if ($selectedMode -eq 'Enforced' -and $guardEnabled.Checked) {
                $answer = [System.Windows.Forms.MessageBox]::Show(
                    ('Enable enforced mode with metric {0}, threshold {1:N4}, grace {2}s, and {3} exact path(s)? ' +
                        'It can terminate a matching active Codex process.') -f `
                        [string]$guardMetric.SelectedItem, [decimal]$guardThreshold.Value, [int]$guardGrace.Value, $approvedPaths.Count,
                    'Confirm enforced usage guard',
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            }
            $newPolicy = New-UsageGuardPolicy `
                -Enabled ([bool]$guardEnabled.Checked) `
                -Mode $selectedMode `
                -Metric ([string]$guardMetric.SelectedItem) `
                -Threshold ([decimal]$guardThreshold.Value) `
                -GraceSeconds ([int]$guardGrace.Value) `
                -ApprovedExecutablePaths $approvedPaths
            if ([bool]$script:guardPolicy.Locked) {
                $newPolicy.Locked = $true
                $newPolicy.LockedAt = $script:guardPolicy.LockedAt
                $newPolicy.LockReason = $script:guardPolicy.LockReason
                $newPolicy.ThresholdCrossedAt = $script:guardPolicy.ThresholdCrossedAt
            }
            $script:guardPolicy = $newPolicy
            Save-UsageGuardState
            $script:guardStatus = Invoke-UsageGuardCycle
            $renewGuard.Enabled = [bool]$script:guardPolicy.Locked
            Refresh-GuardReadinessDisplay
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to save usage guard') | Out-Null
        }
    })
    $renewGuard.Add_Click({
        $answer = [System.Windows.Forms.MessageBox]::Show(
            'Affirmatively re-enable Codex until local midnight? The configured threshold will be evaluated again tomorrow.',
            'Renew Codex usage',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        try {
            Unlock-UsageGuardPolicy -Policy $script:guardPolicy -Confirmation 'REENABLE CODEX' | Out-Null
            Save-UsageGuardState
            $script:guardStatus = Invoke-UsageGuardCycle
            $renewGuard.Enabled = $false
            Refresh-GuardReadinessDisplay
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to renew Codex usage') | Out-Null
        }
    })
    Refresh-GuardReadinessDisplay

    # Model mix and provenance
    $provenanceTab = New-ControlCenterTab 'Sources'
    $sourceNote = Add-ControlCenterLabel -Parent $provenanceTab `
        -Text 'Source labels keep local estimates and your downloaded reports from being mixed together.' `
        -X 14 -Y 14 -Width 1008 -Height 26 -Size 10 -Color $uiTextSecondary
    $workspaceSourceButton = Add-ControlCenterButton -Parent $provenanceTab -Text 'Open &usage summary' -X 14 -Y 46 -Width 196
    $complianceSourceButton = Add-ControlCenterButton -Parent $provenanceTab -Text 'Open &activity export' -X 222 -Y 46 -Width 196
    $workspaceSourceButton.AccessibleDescription = 'Open one or more local usage-summary CSV reports filtered to this individual.'
    $complianceSourceButton.AccessibleDescription = 'Open a local personal activity JSONL export and advanced field mapping.'
    $workspaceSourceButton.Add_Click({
        try { Show-EnterpriseAnalyticsDialog }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to open my usage summary') | Out-Null }
    })
    $complianceSourceButton.Add_Click({
        try { Show-ComplianceAnalyticsDialog }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to open my activity export') | Out-Null }
    })
    $sourcePanel = New-Object System.Windows.Forms.Panel
    $sourcePanel.Location = New-Object System.Drawing.Point(14, 88)
    $sourcePanel.Size = New-Object System.Drawing.Size(1008, 178)
    $sourcePanel.Anchor = 'Top,Left,Right'
    $provenanceTab.Controls.Add($sourcePanel)
    $sourceGrid = New-ControlCenterGrid -Parent $sourcePanel `
        -Columns @('Source','Status','Observed / effective','What it means') `
        -AccessibleName 'Usage data provenance'
    $sourceGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $sourceWidths = @(170, 190, 190, 430)
    for ($columnIndex = 0; $columnIndex -lt $sourceWidths.Count; $columnIndex++) {
        $sourceGrid.Columns[$columnIndex].Width = $sourceWidths[$columnIndex]
    }
    [void]$sourceGrid.Rows.Add('Local Codex logs','Active',(Get-Date).ToString('g'),'Near-real-time local token and activity records; no outbound request.')
    [void]$sourceGrid.Rows.Add(
        'Local RTK savings',
        [string]$script:rtkSnapshot.HealthLabel,
        $(if ($null -ne $script:rtkSnapshot.LastTrackedAt) { ([datetime]$script:rtkSnapshot.LastTrackedAt).ToString('g') } else { '-' }),
        'Aggregate CLI-output estimates and health from RTK local history; telemetry forced off.'
    )
    [void]$sourceGrid.Rows.Add('Bundled rate card','Estimate',[string]$script:rateCard.EffectiveDate,'Static OpenAI credit rates; unknown models remain unpriced.')
    [void]$sourceGrid.Rows.Add('Aggregate history',$(if ($DisablePersistence) { 'Disabled' } else { 'Local only' }),$script:statePaths.AggregateStore,'Dates and counters only; no prompts, IDs, sessions, or paths inside the file.')
    if ($null -ne $script:officialSnapshot) {
        $officialFreshness = Get-OfficialSnapshotFreshness -ReportUpdatedAt ([datetime]$script:officialSnapshot.ReportUpdatedAt)
        [void]$sourceGrid.Rows.Add('Downloaded usage report',$officialFreshness.Label,$script:officialSnapshot.ReportUpdatedAt.ToString('g'),'Downloaded outside this app, then sanitized and compared locally.')
    }
    else {
        [void]$sourceGrid.Rows.Add('Downloaded usage report','Not imported','-', 'Optional local CSV/JSON; the app never fetches it.')
    }
    $modelPanel = New-Object System.Windows.Forms.Panel
    $modelPanel.Location = New-Object System.Drawing.Point(14, 282)
    # Keep the lower panels inside the tab's minimum client height. Their
    # internal scrollbars then remain visible and operable.
    $modelPanel.Size = New-Object System.Drawing.Size(590, 250)
    $modelPanel.Anchor = 'Top,Left'
    $provenanceTab.Controls.Add($modelPanel)
    $modelGrid = New-ControlCenterGrid -Parent $modelPanel `
        -Columns @('Model','Events','Tasks','Fresh','Context','Credits') `
        -AccessibleName 'Local model usage breakdown'
    $modelGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $modelWidths = @(150, 65, 65, 90, 90, 100)
    for ($columnIndex = 0; $columnIndex -lt $modelWidths.Count; $columnIndex++) {
        $modelGrid.Columns[$columnIndex].Width = $modelWidths[$columnIndex]
    }
    foreach ($row in $modelRows) {
        [void]$modelGrid.Rows.Add(
            $row.Model, $row.Events, $row.Sessions, (Format-Tokens $row.FreshBurn),
            (Format-Tokens $row.Context), ('{0:N4}' -f [decimal]$row.EstimatedCredits)
        )
    }
    $privacyBox = New-Object System.Windows.Forms.ListBox
    $privacyBox.Location = New-Object System.Drawing.Point(620, 282)
    $privacyBox.Size = New-Object System.Drawing.Size(402, 250)
    $privacyBox.Anchor = 'Top,Left'
    $privacyBox.IntegralHeight = $false
    $privacyBox.SelectionMode = [System.Windows.Forms.SelectionMode]::None
    $privacyBox.ScrollAlwaysVisible = $true
    $privacyBox.HorizontalScrollbar = $true
    $privacyBox.BackColor = $uiWindow
    $privacyBox.ForeColor = $uiTextSecondary
    $privacyBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $privacyBox.Font = New-UiFont 9
    $privacyContract = Get-MonitorPrivacyContract
    $privacyLines = @(
        'PRIVACY AND ZERO-COST CONTRACT'
        ''
        $privacyContract.UserPromise
        ''
        'Runtime network access: ' + $privacyContract.RuntimeNetworkAccess
        'Paid service calls: ' + $privacyContract.PaidServiceCalls
        ''
        'Never persisted:'
        ($privacyContract.NeverPersist | ForEach-Object { '  - ' + $_ })
        ''
        'State root:'
        '  ' + $script:statePaths.Root
        ''
        'Watched downloaded-report folder:'
        '  ' + $script:statePaths.OfficialReports
    )
    [void]$privacyBox.Items.AddRange([object[]]$privacyLines)
    $privacyBox.AccessibleName = 'Privacy and zero-cost contract'
    $provenanceTab.Controls.Add($privacyBox)

    # Personal backup, startup, diagnostics, RTK coverage, and guard reliability
    $settingsTab = New-ControlCenterTab 'Settings'
    $settingsTab.AutoScroll = $true
    [void](Add-ControlCenterLabel -Parent $settingsTab -Text 'Personal settings' -X 14 -Y 12 -Width 1008 -Height 28 `
        -Size 11 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold))
    [void](Add-ControlCenterLabel -Parent $settingsTab `
        -Text 'This monitor is for this Windows user only. Backups and diagnostics remain local and contain no raw Codex session logs.' `
        -X 14 -Y 40 -Width 1008 -Height 24 -Size 9 -Color $uiAccent)

    $settingsLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $settingsLayout.Location = New-Object System.Drawing.Point(8, 70)
    $settingsLayout.Size = New-Object System.Drawing.Size(1020, 490)
    $settingsLayout.Anchor = 'Top,Left'
    $settingsLayout.ColumnCount = 2
    $settingsLayout.RowCount = 2
    $settingsLayout.ColumnStyles.Clear()
    $settingsLayout.RowStyles.Clear()
    foreach ($width in @(50,50)) {
        $columnStyle = New-Object System.Windows.Forms.ColumnStyle
        $columnStyle.SizeType = [System.Windows.Forms.SizeType]::Percent
        $columnStyle.Width = $width
        [void]$settingsLayout.ColumnStyles.Add($columnStyle)
    }
    foreach ($height in @(50,50)) {
        $rowStyle = New-Object System.Windows.Forms.RowStyle
        $rowStyle.SizeType = [System.Windows.Forms.SizeType]::Percent
        $rowStyle.Height = $height
        [void]$settingsLayout.RowStyles.Add($rowStyle)
    }
    $settingsTab.Controls.Add($settingsLayout)

    function New-PersonalSettingsSection {
        param([string]$Title, [int]$Column, [int]$Row)
        $panel = New-Object System.Windows.Forms.Panel
        $panel.Dock = [System.Windows.Forms.DockStyle]::Fill
        $panel.Margin = New-Object System.Windows.Forms.Padding(6)
        $panel.BackColor = $uiWindow
        $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $panel.AccessibleName = $Title
        $sectionTitle = Add-ControlCenterLabel -Parent $panel -Text $Title -X 14 -Y 10 -Width 450 -Height 26 `
            -Size 10.5 -Color $uiText -Style ([System.Drawing.FontStyle]::Bold)
        $sectionTitle.UseMnemonic = $false
        $settingsLayout.Controls.Add($panel, $Column, $Row)
        return $panel
    }

    $backupPanel = New-PersonalSettingsSection -Title 'Backup & restore' -Column 0 -Row 0
    $backupStatusLabel = Add-ControlCenterLabel -Parent $backupPanel -Text 'No backup created from this app yet.' `
        -X 14 -Y 42 -Width 458 -Height 42 -Size 9 -Color $uiTextSecondary
    [void](Add-ControlCenterLabel -Parent $backupPanel `
        -Text 'Includes settings and aggregate history only; excludes raw logs, prompts, responses, and imported source files.' `
        -X 14 -Y 84 -Width 458 -Height 40 -Size 8.5 -Color $uiTextMuted)
    $backupNowButton = Add-ControlCenterButton -Parent $backupPanel -Text '&Back up now...' -X 14 -Y 138 -Width 138
    $restoreBackupButton = Add-ControlCenterButton -Parent $backupPanel -Text '&Restore backup...' -X 162 -Y 138 -Width 148
    $openBackupButton = Add-ControlCenterButton -Parent $backupPanel -Text 'Open backup &folder' -X 320 -Y 138 -Width 152

    $startupPanel = New-PersonalSettingsSection -Title 'Start with Windows' -Column 1 -Row 0
    $startAtSignInCheck = New-Object System.Windows.Forms.CheckBox
    $startAtSignInCheck.Text = 'Start Live Codex Usage when I sign in'
    $startAtSignInCheck.Location = New-Object System.Drawing.Point(14, 44)
    $startAtSignInCheck.Size = New-Object System.Drawing.Size(430, 26)
    $startAtSignInCheck.ForeColor = $uiText
    $startupPanel.Controls.Add($startAtSignInCheck)
    $startMinimizedCheck = New-Object System.Windows.Forms.CheckBox
    $startMinimizedCheck.Text = 'Start minimized to the system tray'
    $startMinimizedCheck.Location = New-Object System.Drawing.Point(32, 74)
    $startMinimizedCheck.Size = New-Object System.Drawing.Size(410, 26)
    $startMinimizedCheck.Checked = [bool]$script:personalSettings.StartMinimizedToTray
    $startMinimizedCheck.ForeColor = $uiTextSecondary
    $startupPanel.Controls.Add($startMinimizedCheck)
    $startupStatusLabel = Add-ControlCenterLabel -Parent $startupPanel -Text '' `
        -X 14 -Y 108 -Width 458 -Height 42 -Size 9 -Color $uiTextSecondary
    $saveStartupButton = Add-ControlCenterButton -Parent $startupPanel -Text '&Save startup setting' -X 14 -Y 158 -Width 170
    $startupGuardWarning = Add-ControlCenterLabel -Parent $startupPanel -Text '' `
        -X 198 -Y 154 -Width 274 -Height 54 -Size 8.5 -Color $uiWarning
    $startupGuardWarning.AutoEllipsis = $false

    $diagnosticsPanel = New-PersonalSettingsSection -Title 'Diagnostics & privacy' -Column 0 -Row 1
    $diagnosticsGrid = New-Object System.Windows.Forms.DataGridView
    $diagnosticsGrid.Location = New-Object System.Drawing.Point(14, 42)
    $diagnosticsGrid.Size = New-Object System.Drawing.Size(458, 128)
    $diagnosticsGrid.Anchor = 'Top,Left,Right'
    $diagnosticsGrid.ReadOnly = $true
    $diagnosticsGrid.AllowUserToAddRows = $false
    $diagnosticsGrid.AllowUserToDeleteRows = $false
    $diagnosticsGrid.RowHeadersVisible = $false
    $diagnosticsGrid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    [void]$diagnosticsGrid.Columns.Add('Check','Check')
    [void]$diagnosticsGrid.Columns.Add('Status','Status')
    [void]$diagnosticsGrid.Columns.Add('Detail','Detail')
    $diagnosticsGrid.Columns['Check'].Width = 130
    $diagnosticsGrid.Columns['Status'].Width = 70
    $diagnosticsGrid.Columns['Detail'].Width = 235
    $diagnosticsGrid.AccessibleName = 'Sanitized personal health checks'
    Set-GridTheme -DataGrid $diagnosticsGrid
    $diagnosticsPanel.Controls.Add($diagnosticsGrid)
    $runDiagnosticsButton = Add-ControlCenterButton -Parent $diagnosticsPanel -Text 'Run &health check' -X 14 -Y 180 -Width 150
    $exportDiagnosticsButton = Add-ControlCenterButton -Parent $diagnosticsPanel -Text '&Export sanitized...' -X 174 -Y 180 -Width 164
    $diagnosticsStatusLabel = Add-ControlCenterLabel -Parent $diagnosticsPanel -Text 'No paths, usernames, prompts, or responses are included.' `
        -X 348 -Y 180 -Width 124 -Height 42 -Size 7.5 -Color $uiTextMuted
    $diagnosticsStatusLabel.AutoEllipsis = $false

    $reliabilityPanel = New-PersonalSettingsSection -Title 'RTK coverage & guard reliability' -Column 1 -Row 1
    $personalRtkLabel = Add-ControlCenterLabel -Parent $reliabilityPanel -Text '' `
        -X 14 -Y 44 -Width 458 -Height 54 -Size 9 -Color $uiTextSecondary
    $personalGuardLabel = Add-ControlCenterLabel -Parent $reliabilityPanel -Text '' `
        -X 14 -Y 102 -Width 458 -Height 58 -Size 9 -Color $uiTextSecondary
    $personalRtkLabel.AutoEllipsis = $false
    $personalGuardLabel.AutoEllipsis = $false
    $openRtkHealthButton = Add-ControlCenterButton -Parent $reliabilityPanel -Text 'Open &RTK health' -X 14 -Y 176 -Width 152
    $openUsageGuardButton = Add-ControlCenterButton -Parent $reliabilityPanel -Text 'Open usage &guard' -X 176 -Y 176 -Width 158
    [void](Add-ControlCenterLabel -Parent $reliabilityPanel `
        -Text 'Guard enforcement works only while this monitor is running.' `
        -X 344 -Y 176 -Width 128 -Height 42 -Size 7.5 -Color $uiTextMuted)

    function Refresh-PersonalSettingsTab {
        try { $script:startupRegistration = Test-PersonalStartupRegistration -LauncherPath $script:launcherPath }
        catch {
            $script:startupRegistration = [pscustomobject]@{
                Registered = $false; MatchesLauncher = $false; RegistrationPath = ''; Status = 'Unavailable'
            }
        }
        $startAtSignInCheck.Checked = [bool]$script:startupRegistration.MatchesLauncher
        $startMinimizedCheck.Enabled = $startAtSignInCheck.Checked
        $startupStatusLabel.Text = if ($script:startupRegistration.MatchesLauncher) {
            'Enabled for this Windows account; no administrator permission is required.'
        }
        elseif ($script:startupRegistration.Registered) {
            'A startup entry exists but does not match this installation. Save to repair it.'
        }
        else { 'Off. The monitor will not start automatically when you sign in.' }
        $startupStatusLabel.ForeColor = if ($script:startupRegistration.MatchesLauncher) { $uiSuccess } else { $uiTextSecondary }

        $backupStatusLabel.Text = if ($null -ne $script:personalSettings.LastBackupAt -and
            -not [string]::IsNullOrWhiteSpace([string]$script:personalSettings.LastBackupAt)) {
            'Last backup created {0}. Integrity hashes are verified during restore.' -f ([datetime]$script:personalSettings.LastBackupAt).ToString('g')
        }
        else { 'No backup created from this app yet.' }

        $guardReadiness = Get-UsageGuardReadiness -Policy $script:guardPolicy
        $startupGuardWarning.Text = if ([string]$guardReadiness.StatusCode -eq 'Armed' -and
            -not [bool]$script:startupRegistration.MatchesLauncher) {
            'Guard is not always available because the monitor does not start when you sign in.'
        }
        else { '' }
        $shellCalls = @($script:integrationEvents | Where-Object Name -eq 'Local shell').Count
        $personalRtkLabel.Text = 'RTK: {0}. Tracked commands {1:N0}; local-shell records in loaded Codex history {2:N0}; failures {3:N0}. Savings are byte estimates.' -f `
            $script:rtkSnapshot.HealthLabel, [int64]$script:rtkSnapshot.TotalCommands, $shellCalls, [int]$script:rtkSnapshot.FailureCount
        $personalRtkLabel.ForeColor = if ($script:rtkSnapshot.Working) { $uiSuccess } else { $uiWarning }
        $personalGuardLabel.Text = 'Guard: {0}. Exact paths {1}; current matches {2}. {3}' -f `
            $guardReadiness.StatusLabel, $guardReadiness.ApprovedPathCount, $guardReadiness.RunningMatchCount, `
            $(if ($script:startupRegistration.MatchesLauncher) { 'Start-at-sign-in is enabled.' } else { 'Start-at-sign-in is off.' })
        $personalGuardLabel.ForeColor = if ($guardReadiness.StatusCode -in @('Armed','Advisory')) { $uiWarning } else { $uiTextSecondary }

        if ($script:diagnosticRows.Count -eq 0) { [void](Update-PersonalDiagnostics) }
        $diagnosticsGrid.Rows.Clear()
        foreach ($row in @($script:diagnosticRows)) {
            $index = $diagnosticsGrid.Rows.Add($row.Check, $row.Status, $row.Detail)
            if ($row.Status -in @('Failure','Warning')) { $diagnosticsGrid.Rows[$index].DefaultCellStyle.ForeColor = $uiWarning }
            elseif ($row.Status -eq 'OK') { $diagnosticsGrid.Rows[$index].DefaultCellStyle.ForeColor = $uiSuccess }
        }
        try { $startupStatusLabel.AccessibilityNotifyClients([System.Windows.Forms.AccessibleEvents]::NameChange, -1) } catch { }
    }

    $startAtSignInCheck.Add_CheckedChanged({
        $startMinimizedCheck.Enabled = $startAtSignInCheck.Checked
        if (-not $startAtSignInCheck.Checked) { $startMinimizedCheck.Checked = $false }
    })
    $saveStartupButton.Add_Click({
        try {
            $script:startupRegistration = Set-PersonalStartupRegistration `
                -Enabled ([bool]$startAtSignInCheck.Checked) `
                -LauncherPath $script:launcherPath
            $script:personalSettings.StartAtSignIn = [bool]$script:startupRegistration.MatchesLauncher
            $script:personalSettings.StartMinimizedToTray = [bool]$startMinimizedCheck.Checked
            Save-PersonalSettingsState
            $script:diagnosticRows = @()
            Refresh-PersonalSettingsTab
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to save startup setting') | Out-Null }
    })
    $backupNowButton.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        try {
            $folderDialog.Description = 'Choose a local folder for the personal monitor backup'
            if (Test-Path -LiteralPath $script:statePaths.Backups -PathType Container) {
                $folderDialog.SelectedPath = $script:statePaths.Backups
            }
            if ($folderDialog.ShowDialog($dialog) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $backup = Export-PersonalMonitorBackup -StateRoot $script:statePaths.Root `
                -DestinationDirectory $folderDialog.SelectedPath -AppVersion $script:appVersion
            $script:personalSettings.LastBackupAt = $backup.CreatedAt.ToString('o')
            Save-PersonalSettingsState
            $backupStatusLabel.Text = 'Backup created and verified: ' + (Split-Path -Leaf $backup.Path)
            $backupStatusLabel.ForeColor = $uiSuccess
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to create backup') | Out-Null }
        finally { $folderDialog.Dispose() }
    })
    $restoreBackupButton.Add_Click({
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $openDialog.Title = 'Restore a personal monitor backup'
            $openDialog.Filter = 'Live Codex backup (*.zip)|*.zip'
            $openDialog.CheckFileExists = $true
            if ($openDialog.ShowDialog($dialog) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $preview = Get-PersonalMonitorBackupPreview -Path $openDialog.FileName
            $answer = [System.Windows.Forms.MessageBox]::Show(
                ('Restore backup from {0:g} (version {1}) containing {2}? ' +
                    'An automatic pre-restore backup will be created first.') -f `
                    $preview.CreatedAt, $(if ($preview.AppVersion) { $preview.AppVersion } else { 'unknown' }), ($preview.Files -join ', '),
                'Confirm personal restore',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            $result = Import-PersonalMonitorBackup -Path $openDialog.FileName `
                -StateRoot $script:statePaths.Root `
                -PreRestoreBackupDirectory $script:statePaths.Backups `
                -AppVersion $script:appVersion -Confirm:$false
            $script:personalSettings = Import-PersonalMonitorSettings -Path $script:statePaths.PersonalSettings
            $script:guardPolicy = Import-UsageGuardPolicy -Path $script:statePaths.GuardPolicy
            $script:costProfile = Import-UsageCostProfile -Path $script:statePaths.CostProfile
            $refreshSecondsBox.Value = [decimal][int]$script:personalSettings.RefreshSeconds
            $script:lastCostKey = ''
            $script:diagnosticRows = @()
            Refresh-PersonalSettingsTab
            [System.Windows.Forms.MessageBox]::Show(
                ('Restored {0} file(s). Active settings, including the refresh interval, were reloaded.' -f $result.Files),
                'Personal backup restored'
            ) | Out-Null
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to restore backup') | Out-Null }
        finally { $openDialog.Dispose() }
    })
    $openBackupButton.Add_Click({
        try {
            if (-not (Test-Path -LiteralPath $script:statePaths.Backups -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $script:statePaths.Backups)
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $script:statePaths.Backups)
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to open backup folder') | Out-Null }
    })
    $runDiagnosticsButton.Add_Click({
        [void](Update-RtkSavingsState -Force)
        $script:diagnosticRows = @()
        Refresh-PersonalSettingsTab
    })
    $exportDiagnosticsButton.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        try {
            $saveDialog.Title = 'Export sanitized personal diagnostics'
            $saveDialog.Filter = 'JSON files (*.json)|*.json'
            $saveDialog.FileName = 'live-codex-diagnostics-{0}.json' -f (Get-Date).ToString('yyyyMMdd-HHmmss')
            if ($saveDialog.ShowDialog($dialog) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            if ($script:diagnosticRows.Count -eq 0) { [void](Update-PersonalDiagnostics) }
            [void](Export-PersonalDiagnosticReport -Rows $script:diagnosticRows -Path $saveDialog.FileName -AppVersion $script:appVersion)
            $diagnosticsStatusLabel.Text = 'Sanitized diagnostics exported locally.'
            $diagnosticsStatusLabel.ForeColor = $uiSuccess
        }
        catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to export diagnostics') | Out-Null }
        finally { $saveDialog.Dispose() }
    })
    $openRtkHealthButton.Add_Click({ $tabs.SelectedIndex = 3 })
    $openUsageGuardButton.Add_Click({ $tabs.SelectedIndex = 6 })
    Refresh-PersonalSettingsTab

    $tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::FillToRight

    $dialog.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $_.SuppressKeyPress = $true
            $dialog.Close()
        }
    })
    $tabs.SelectedIndex = [Math]::Min($InitialTabIndex, $tabs.TabPages.Count - 1)

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
        $instanceDiagnosticRows = @($script:diagnosticRows | Where-Object { $_.Check -eq 'Single instance' })
        if ($instanceDiagnosticRows.Count -ne 1) {
            throw 'The sanitized single-instance diagnostic row is missing.'
        }
        Write-Output ('Control center constructed successfully; Tabs={0}; TrendRows={1}; Models={2}; Instance={3}' -f `
            $tabs.TabPages.Count, $trendRows.Count, $modelRows.Count, $instanceDiagnosticRows[0].Status)
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
        $script:lastInteractionResult = 'DatesLoaded'
    }
    catch {
        if ($script:interactionTestMode) { throw }
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to load dates') | Out-Null
    }
    finally {
        $form.UseWaitCursor = $false
        $loadRangeButton.Enabled = $true
    }
}

function Set-MonitorRefreshInterval {
    param([ValidateRange(1, 60)][int]$Seconds)

    if ($null -eq $script:refreshTimer) {
        throw 'The monitor refresh timer is not available.'
    }
    $script:refreshTimer.Interval = $Seconds * 1000
    $script:personalSettings.RefreshSeconds = $Seconds
    Save-PersonalSettingsState
    $historyLabel.Text = 'Refresh every {0}s | Loaded: {1}' -f $Seconds, (Format-DateRange)
    $explainBox.Text = 'Local log refresh interval changed to {0} second(s). This does not call ChatGPT or create usage.' -f $Seconds
    $script:lastInteractionResult = 'RefreshChanged'
}

function Invoke-LocalSummaryExport {
    param([string]$DestinationPath = '')

    $saveDialog = $null
    try {
        if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
            $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveDialog.Title = 'Export privacy-safe daily usage summary'
            $saveDialog.Filter = 'CSV files (*.csv)|*.csv'
            $saveDialog.DefaultExt = 'csv'
            $saveDialog.AddExtension = $true
            $saveDialog.OverwritePrompt = $true
            $saveDialog.FileName = 'codex-usage-summary-{0}-{1}.csv' -f $script:rangeStart.ToString('yyyyMMdd'), $(if ($script:rangeEnd -eq [datetime]::MaxValue) { (Get-Date).ToString('yyyyMMdd') } else { $script:rangeEnd.ToString('yyyyMMdd') })
            if ($saveDialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
            $DestinationPath = $saveDialog.FileName
        }
        $rows = @(Export-LocalUsageSummary -Path $DestinationPath -UsageEvents $script:visibleEvents -IntegrationEvents $script:visibleIntegrations)
        $explainBox.Text = 'Exported {0} daily aggregate row(s). The CSV excludes prompts, responses, task names, session IDs, source paths, tool arguments, and tool output.' -f $rows.Count
    }
    catch {
        if ($script:interactionTestMode) { throw }
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to export summary') | Out-Null
    }
    finally {
        if ($null -ne $saveDialog) { $saveDialog.Dispose() }
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

if ($ComplianceUiSmokeTest) {
    if ([string]::IsNullOrWhiteSpace($ComplianceInputPath) -or
        [string]::IsNullOrWhiteSpace($ComplianceMappingPath)) {
        throw '-ComplianceUiSmokeTest requires -ComplianceInputPath and -ComplianceMappingPath.'
    }
    Show-ComplianceAnalyticsDialog `
        -InputPath $ComplianceInputPath `
        -MappingPath $ComplianceMappingPath `
        -ConstructionOnly `
        -ScreenshotPath $CaptureScreenshotPath
    $form.Dispose()
    if ($null -ne $script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    exit 0
}

if ($InsightsUiSmokeTest) {
    Show-ControlCenterDialog -ConstructionOnly -InitialTabIndex $InsightsTabIndex -ScreenshotPath $CaptureScreenshotPath
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
    $freshStartedAt = $script:startedAt.ToString('HH:mm:ss')
    $historyLabel.Text = 'Fresh window started {0} - waiting for the next completed turn' -f $freshStartedAt
    $explainBox.Text = 'Fresh monitoring window started at {0}. Existing log files were not deleted; only events completed after this time will appear.' -f $freshStartedAt
    $script:lastInteractionResult = 'FreshStarted'
})
$loadRangeButton.Add_Click({ Invoke-LoadSelectedRange })
$exportButton.Add_Click({
    if ($script:interactionTestMode) {
        Invoke-LocalSummaryExport -DestinationPath $script:interactionExportPath
    }
    else {
        Invoke-LocalSummaryExport
    }
    $script:lastInteractionResult = 'ExportCompleted'
})
$enterpriseButton.Add_Click({
    try {
        if ($script:interactionTestMode) {
            Show-PersonalImportDialog -ConstructionOnly
            $script:lastInteractionResult = 'ImportReady'
        }
        else {
            Show-PersonalImportDialog
        }
    }
    catch {
        if ($script:interactionTestMode) { throw }
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to import my data') | Out-Null
    }
})
$controlCenterButton.Add_Click({
    try {
        if ($script:interactionTestMode) {
            Show-ControlCenterDialog -ConstructionOnly
            $script:lastInteractionResult = 'ControlCenterReady'
        }
        else {
            Show-ControlCenterDialog
            Refresh-Display
        }
    }
    catch {
        if ($script:interactionTestMode) { throw }
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to open control center') | Out-Null
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
$refreshSecondsBox.Add_ValueChanged({
    try {
        Set-MonitorRefreshInterval -Seconds ([int]$refreshSecondsBox.Value)
    }
    catch {
        if ($script:interactionTestMode) { throw }
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to change refresh interval') | Out-Null
    }
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
    elseif ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::I) {
        $_.SuppressKeyPress = $true
        $controlCenterButton.PerformClick()
    }
    elseif ($_.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        $_.SuppressKeyPress = $true
        Refresh-Display
    }
})

$script:trayMenu = $null
if ($null -ne $script:notifyIcon) {
    $script:trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $showItem = $script:trayMenu.Items.Add('Show dashboard')
    $miniItem = $script:trayMenu.Items.Add('Show mini mode')
    $insightsItem = $script:trayMenu.Items.Add('Open control center')
    [void]$script:trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $exitItem = $script:trayMenu.Items.Add('Exit monitor')
    $showItem.Add_Click({
        $form.ShowInTaskbar = $true
        $form.Show()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.Activate()
    })
    $miniItem.Add_Click({
        $form.ShowInTaskbar = $true
        $form.Show()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        Set-MiniMode -Enabled $true
        Refresh-Display
        $form.Activate()
    })
    $insightsItem.Add_Click({
        $form.Show()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $controlCenterButton.PerformClick()
    })
    $exitItem.Add_Click({ $form.Close() })
    $script:notifyIcon.ContextMenuStrip = $script:trayMenu
    $script:notifyIcon.Add_DoubleClick({
        $form.ShowInTaskbar = $true
        $form.Show()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.Activate()
    })
}

$instanceActivationTimer = $null
if ($null -ne $script:instanceCoordinator) {
    $instanceActivationTimer = New-Object System.Windows.Forms.Timer
    $instanceActivationTimer.Interval = 250
    $instanceActivationTimer.Add_Tick({
        if (-not (Test-MonitorInstanceActivation -Coordinator $script:instanceCoordinator)) { return }
        $form.ShowInTaskbar = $true
        $form.Show()
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        $visibleOwnedForms = @($form.OwnedForms | Where-Object { $_.Visible })
        $activationTarget = $form
        if ($visibleOwnedForms.Count -gt 0) {
            $activationTarget = $visibleOwnedForms[$visibleOwnedForms.Count - 1]
        }
        $activationTarget.BringToFront()
        $activationTarget.Activate()
    })
    $instanceActivationTimer.Start()
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $PollSeconds * 1000
$script:refreshTimer = $timer
$timer.Add_Tick({
    try {
        Refresh-Display
    }
    catch {
        $statusLabel.Text = 'Status: ERROR (log refresh failed)'
        $statusLabel.ForeColor = $uiCritical
        $explainBox.Text = $_.Exception.Message
    }
})
$startupRestoreTimer = New-Object System.Windows.Forms.Timer
$startupRestoreTimer.Interval = 1000
$startupRestoreTimer.Add_Tick({
    $startupRestoreTimer.Stop()
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
})
$form.Add_Resize({
    Update-ResponsiveLayout
})
$startupRefresh = [System.Windows.Forms.MethodInvoker]{
    try {
        Refresh-Display
    }
    catch {
        $statusLabel.Text = 'Status: ERROR (initial local-log scan failed)'
        $statusLabel.ForeColor = $uiCritical
        $explainBox.Text = $_.Exception.Message
    }
    finally {
        if ($StartMinimizedToTray -and $null -ne $script:notifyIcon) {
            $form.Hide()
            $form.ShowInTaskbar = $false
        }
        else {
            # Keep the window available while the first local-only scan runs,
            # then restore it in case a launcher briefly changed its state.
            $form.Show()
            $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            $form.Activate()
            $startupRestoreTimer.Start()
        }
        $timer.Start()
    }
}
$form.Add_Shown({
    if ($automatedMode) { return }
    if ($StartMinimizedToTray -and $null -ne $script:notifyIcon) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
        $form.ShowInTaskbar = $false
    }
    if ($StartMini -and -not $script:isMiniMode) {
        Set-MiniMode -Enabled $true
    }
    # Queue the CPU-bound first refresh after Shown returns. This lets Windows
    # paint and expose the form immediately instead of waiting for large local
    # log sets to finish before the dashboard becomes visible.
    [void]$form.BeginInvoke($startupRefresh)
})
$form.Add_FormClosed({
    $timer.Stop()
    $script:refreshTimer = $null
    $startupRestoreTimer.Stop()
    $startupRestoreTimer.Dispose()
    if ($null -ne $instanceActivationTimer) {
        $instanceActivationTimer.Stop()
        $instanceActivationTimer.Dispose()
    }
    if ($null -ne $script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    if ($null -ne $script:trayMenu) { $script:trayMenu.Dispose() }
})

if ($UiSmokeTest -or $UiLayoutSmokeTest -or $UiInteractionSmokeTest -or $MiniSmokeTest) {
    Refresh-Display
    if ($StartMini -and -not $script:isMiniMode) {
        Set-MiniMode -Enabled $true
        Refresh-Display
    }
    if ($UiLayoutSmokeTest) {
        # Reproduce the work-PC path: create at a compact width and then widen
        # the form. The former Right anchors expanded small opaque labels over
        # the controls immediately to their right.
        $form.ClientSize = New-Object System.Drawing.Size(1040, 720)
        Update-ResponsiveLayout
        $form.ClientSize = New-Object System.Drawing.Size(1280, 720)
        Update-ResponsiveLayout
        $surfacePairs = @(
            @($heroCard, $title),
            @($heroCard, $statusMeter),
            @($summaryCard, $minuteLabel),
            @($commandCard, $viewAllButton),
            @($commandCard, $presetBox)
        )
        foreach ($pair in $surfacePairs) {
            $surfaceIndex = $form.Controls.GetChildIndex($pair[0])
            $foregroundIndex = $form.Controls.GetChildIndex($pair[1])
            if ($surfaceIndex -le $foregroundIndex) {
                throw "Dashboard surface '$($pair[0].AccessibleName)' covers a foreground control."
            }
        }
        foreach ($pair in @(
            @($modeLabel, $viewAllButton),
            @($presetLabel, $presetBox),
            @($fromLabel, $fromPicker),
            @($toLabel, $toPicker),
            @($refreshIntervalLabel, $refreshSecondsBox)
        )) {
            if ($pair[0].Bounds.IntersectsWith($pair[1].Bounds)) {
                throw "Dashboard label '$($pair[0].Text)' overlaps '$($pair[1].AccessibleName)'."
            }
        }
        if (($integrationLabel.Top - $grid.Bottom) -lt 10 -or
            ($activityLabel.Top - $taskGrid.Bottom) -lt 10 -or
            ($integrationGrid.Top - $integrationLabel.Bottom) -lt 4 -or
            ($activityGrid.Top - $activityLabel.Bottom) -lt 4 -or
            ($explainBox.Top - $integrationGrid.Bottom) -lt 10 -or
            $form.AutoScrollMinSize.Height -lt ($explainBox.Bottom + 20)) {
            throw 'Dashboard sections overlap or are outside the short-screen scroll canvas.'
        }
        Write-Output 'Layout=1040-to-1280x720; CardsBehind=True; ControlsClear=True; SectionsSeparated=True; VirtualHeight=900'
    }
    elseif ($UiInteractionSmokeTest) {
        $interactionExport = Join-Path ([System.IO.Path]::GetTempPath()) (
            'live-codex-interactions-{0}.csv' -f [guid]::NewGuid().ToString('N')
        )
        try {
            $form.Show()
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:events.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$script:latestSession)) {
                throw 'Main-button interaction test requires loaded token events and a latest session.'
            }

            $viewLatestButton.PerformClick()
            if ($script:viewMode -ne 'Follow latest') { throw 'Follow latest button did not change the view.' }
            $viewAllButton.PerformClick()
            if ($script:viewMode -ne 'All sessions') { throw 'All tasks button did not change the view.' }

            $expectedPinnedSession = [string]$script:latestSession
            $pinButton.PerformClick()
            if ($script:viewMode -ne 'Pinned session' -or $script:pinnedSource -ne $expectedPinnedSession) {
                throw 'Pin latest button did not pin the latest session.'
            }
            $viewAllButton.PerformClick()
            $viewPinnedButton.PerformClick()
            if ($script:viewMode -ne 'Pinned session') { throw 'Pinned button did not change the view.' }

            $viewAllButton.PerformClick()
            $fromPicker.Value = [datetime]'2026-07-25'
            $toPicker.Value = [datetime]'2026-07-25'
            $loadRangeButton.PerformClick()
            if ($script:lastInteractionResult -ne 'DatesLoaded' -or
                $script:rangeStart.Date -ne [datetime]'2026-07-25' -or
                $script:rangeEnd.Date -ne [datetime]'2026-07-25' -or
                $script:visibleEvents.Count -ne 1 -or -not $loadRangeButton.Enabled) {
                throw ('Load dates button failed. Result={0}; Start={1}; End={2}; Visible={3}; Enabled={4}' -f `
                    $script:lastInteractionResult, $script:rangeStart.ToString('yyyy-MM-dd'),
                    $script:rangeEnd.ToString('yyyy-MM-dd'), $script:visibleEvents.Count, $loadRangeButton.Enabled)
            }

            $script:interactionExportPath = $interactionExport
            $exportButton.PerformClick()
            if ($script:lastInteractionResult -ne 'ExportCompleted' -or
                -not (Test-Path -LiteralPath $interactionExport -PathType Leaf) -or
                @(Import-Csv -LiteralPath $interactionExport).Count -ne 1) {
                throw 'Export CSV button did not create the expected privacy-safe summary.'
            }

            $enterpriseButton.PerformClick()
            if ($script:lastInteractionResult -ne 'ImportReady') {
                throw 'Import my data button did not construct its two-choice dialog.'
            }
            $controlCenterButton.PerformClick()
            if ($script:lastInteractionResult -ne 'ControlCenterReady') {
                throw 'Control center button did not construct its workspace.'
            }

            $refreshSecondsBox.Value = 7
            if ($script:lastInteractionResult -ne 'RefreshChanged' -or
                $script:refreshTimer.Interval -ne 7000 -or
                [int]$script:personalSettings.RefreshSeconds -ne 7 -or
                $historyLabel.Text -notmatch '^Refresh every 7s') {
                throw 'Refresh interval control did not apply the selected seconds immediately.'
            }

            $miniButton.PerformClick()
            if (-not $script:isMiniMode -or $miniButton.Text -notmatch 'Full mode') {
                throw 'Mini mode button did not enter compact mode.'
            }
            $miniButton.PerformClick()
            if ($script:isMiniMode -or $miniButton.Text -notmatch 'Mini mode') {
                throw 'Mini mode button did not return to the full dashboard.'
            }

            $usageRevisionBeforeReset = [int64]$script:usageRevision
            $activityRevisionBeforeReset = [int64]$script:activityRevision
            $today = (Get-Date).Date
            Set-MonitorDateRange -FromDate $today -ToDate $today
            Refresh-Display
            $clearButton.PerformClick()
            if ($script:lastInteractionResult -ne 'FreshStarted' -or
                $script:events.Count -ne 0 -or $script:activityEvents.Count -ne 0 -or
                $script:integrationEvents.Count -ne 0 -or $script:visibleEvents.Count -ne 0 -or
                $script:usageRevision -le $usageRevisionBeforeReset -or
                $script:activityRevision -le $activityRevisionBeforeReset -or
                $script:fileOffsets.Count -lt 1 -or
                $historyLabel.Text -notmatch '^Fresh window started \d{2}:\d{2}:\d{2}' -or
                $explainBox.Text -notmatch 'Existing log files were not deleted') {
                throw 'Start fresh button did not reset state and provide visible confirmation.'
            }

            $freshAppendVerified = $false
            if (-not [string]::IsNullOrWhiteSpace($InteractionAppendPath)) {
                $resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
                $resolvedAppendPath = [System.IO.Path]::GetFullPath($InteractionAppendPath)
                $codexPrefix = $resolvedCodexHome.TrimEnd('\') + '\'
                if (-not $resolvedAppendPath.StartsWith(
                    $codexPrefix,
                    [System.StringComparison]::OrdinalIgnoreCase
                ) -or -not (Test-Path -LiteralPath $resolvedAppendPath -PathType Leaf)) {
                    throw 'Interaction append path must be an existing test log inside the supplied CodexHome.'
                }
                $appendTimestamp = (Get-Date).ToString('o')
                $appendLine = '{{"timestamp":"{0}","type":"event_msg","payload":{{"type":"token_count","info":{{"last_token_usage":{{"input_tokens":333,"cached_input_tokens":111,"output_tokens":22,"reasoning_output_tokens":7,"total_tokens":355}}}}}}}}' -f $appendTimestamp
                Add-Content -LiteralPath $resolvedAppendPath -Value $appendLine -Encoding UTF8
                Refresh-Display
                if ($script:events.Count -ne 1 -or $script:visibleEvents.Count -ne 1 -or
                    [int64]$script:visibleEvents[0].NewInput -ne 222 -or
                    [int64]$script:visibleEvents[0].FreshBurn -ne 244) {
                    throw 'Start fresh did not detect the next appended completed token event.'
                }
                $freshAppendVerified = $true
            }

            $mainButtons = @(
                $viewAllButton, $viewLatestButton, $viewPinnedButton, $pinButton, $clearButton,
                $miniButton, $enterpriseButton, $controlCenterButton, $loadRangeButton, $exportButton
            )
            if (@($mainButtons | Where-Object { -not $_.Enabled }).Count -gt 0) {
                throw 'One or more main dashboard buttons remained disabled after interaction QA.'
            }
            if (-not $refreshSecondsBox.Enabled) {
                throw 'Refresh interval control remained disabled after interaction QA.'
            }
            Write-Output ('MainButtons=10; RefreshControl=True; ViewModes=True; Pin=True; FreshReset=True; FreshAppend={0}; Dates=True; Export=True; Import=True; ControlCenter=True; MiniToggle=True' -f $freshAppendVerified)
        }
        finally {
            $script:interactionExportPath = ''
            $form.Hide()
            Remove-Item -LiteralPath $interactionExport -Force -ErrorAction SilentlyContinue
        }
    }
    elseif ($MiniSmokeTest) {
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
            # DrawToBitmap paints overlapping sibling controls in the opposite
            # order from the native desktop. Temporarily invert only the three
            # background surfaces so the QA artifact matches the real window;
            # the z-order regression test above validates the native ordering.
            foreach ($surface in @($heroCard, $summaryCard, $commandCard)) {
                $surface.BringToFront()
            }
            $form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)))
            $bitmap.Save($CaptureScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            foreach ($surface in @($heroCard, $summaryCard, $commandCard)) {
                $surface.SendToBack()
            }
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

try {
    [void]$form.ShowDialog()
}
finally {
    Close-MonitorInstanceCoordinator -Coordinator $script:instanceCoordinator
    $script:instanceCoordinator = $null
}
