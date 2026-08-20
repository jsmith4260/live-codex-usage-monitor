$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$monitor = Join-Path $scriptDir 'Live-Codex-Usage-GUI.ps1'
$fixtureHome = Join-Path $scriptDir 'tests\fixtures\codex-home'
$analyticsFixture = Join-Path $scriptDir 'tests\fixtures\workspace-analytics-users.csv'
$personalAnalyticsFixture = Join-Path $scriptDir 'tests\fixtures\personal-usage-summary.csv'
$complianceFixture = Join-Path $scriptDir 'tests\fixtures\compliance-export.jsonl'
$personalActivityFixture = Join-Path $scriptDir 'tests\fixtures\personal-activity-export.jsonl'
$complianceMapping = Join-Path $scriptDir 'tests\fixtures\compliance-mapping.json'
$complianceConverter = Join-Path $scriptDir 'Convert-Enterprise-ComplianceExport.ps1'
$complianceModule = Join-Path $scriptDir 'Live-Codex-Usage-Compliance.psm1'
$enterpriseModule = Join-Path $scriptDir 'Live-Codex-Usage-Enterprise.psm1'
$costModule = Join-Path $scriptDir 'Live-Codex-Usage-Cost.psm1'
$efficiencyModule = Join-Path $scriptDir 'Live-Codex-Usage-Efficiency.psm1'
$rateCardPath = Join-Path $scriptDir 'config\usage-rates.json'
$reconciliationModule = Join-Path $scriptDir 'Live-Codex-Usage-Reconciliation.psm1'
$officialFixture = Join-Path $scriptDir 'tests\fixtures\official-usage-snapshot.csv'
$storeModule = Join-Path $scriptDir 'Live-Codex-Usage-Store.psm1'
$guardModule = Join-Path $scriptDir 'Live-Codex-Usage-Guard.psm1'
$instanceModule = Join-Path $scriptDir 'Live-Codex-Usage-Instance.psm1'
$privacyModule = Join-Path $scriptDir 'Live-Codex-Usage-Privacy.psm1'
$personalModule = Join-Path $scriptDir 'Live-Codex-Usage-Personal.psm1'
$officialDashboardModule = Join-Path $scriptDir 'Live-Codex-Usage-OfficialDashboard.psm1'
$reportModule = Join-Path $scriptDir 'Live-Codex-Usage-Reports.psm1'
$rtkModule = Join-Path $scriptDir 'Live-Codex-Usage-RTK.psm1'
$startHereLauncher = Join-Path $scriptDir 'START-HERE.cmd'
$standardCmdLauncher = Join-Path $scriptDir 'Start-Live-Codex-Usage.cmd'
$miniCmdLauncher = Join-Path $scriptDir 'Start-Live-Codex-Usage-Mini.cmd'

Write-Host 'Running Live Codex Usage QA...'

function Invoke-MonitorTest {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$ExpectedPattern = '',
        [string]$RejectedPattern = '',
        [string]$CodexHomeOverride = ''
    )

    Write-Host "  $Name"
    $testCodexHome = if ([string]::IsNullOrWhiteSpace($CodexHomeOverride)) {
        $fixtureHome
    }
    else {
        $CodexHomeOverride
    }
    $common = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $monitor,
        '-CodexHome', $testCodexHome, '-HistoryHours', '87600',
        '-NoNotifications', '-NoSound', '-DisablePersistence', '-DisableRtkIntegration'
    )
    $previousErrorAction = $ErrorActionPreference
    try {
        # Native stderr is test output here; inspect the child exit code ourselves.
        $ErrorActionPreference = 'Continue'
        $output = @(& powershell.exe @common @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode.`n$($output -join [Environment]::NewLine)"
    }
    $text = $output -join [Environment]::NewLine
    if ($ExpectedPattern -and $text -notmatch $ExpectedPattern) {
        throw "$Name did not produce expected output '$ExpectedPattern'.`n$text"
    }
    if ($RejectedPattern -and $text -match $RejectedPattern) {
        throw "$Name exposed rejected output '$RejectedPattern'.`n$text"
    }
    if ($text) { Write-Host "    $text" }
}

Invoke-MonitorTest -Name 'Token semantics' -Arguments @('-Once') -ExpectedPattern 'Events=3;.*FreshBurn=650;.*NewInput=500'
Invoke-MonitorTest -Name 'Full GUI construction' -Arguments @('-UiSmokeTest') -ExpectedPattern 'GUI controls constructed successfully'
Invoke-MonitorTest -Name 'Laptop-height dashboard layout' -Arguments @('-UiLayoutSmokeTest') `
    -ExpectedPattern 'Layout=1040-to-1280x720; CardsBehind=True; ControlsClear=True; SectionsSeparated=True; ChatTitle=True; Sources=True; VirtualHeight=1036'
$interactionTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'live-codex-ui-interactions-{0}' -f [guid]::NewGuid().ToString('N')
)
$interactionCodexHome = Join-Path $interactionTestRoot 'codex-home'
try {
    [void](New-Item -ItemType Directory -Path $interactionTestRoot)
    Copy-Item -LiteralPath $fixtureHome -Destination $interactionCodexHome -Recurse
    $interactionAppendPath = @(
        Get-ChildItem -LiteralPath (Join-Path $interactionCodexHome 'sessions') -Recurse -Filter '*.jsonl' -File |
            Sort-Object FullName |
            Select-Object -First 1
    )[0].FullName
    Invoke-MonitorTest -Name 'All main dashboard button interactions' `
        -CodexHomeOverride $interactionCodexHome `
        -Arguments @('-UiInteractionSmokeTest', '-InteractionAppendPath', $interactionAppendPath) `
        -ExpectedPattern 'MainButtons=12; RefreshControl=True; ViewModes=True; Pin=True; FreshReset=True; FreshAppend=True; Dates=True; Export=True; Import=True; ControlCenter=True; DetailsToggle=True; AlertsToggle=True; MiniToggle=True'
}
finally {
    $resolvedInteractionRoot = [System.IO.Path]::GetFullPath($interactionTestRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedInteractionRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedInteractionRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Invoke-MonitorTest -Name 'Mini layout toggle' -Arguments @('-MiniSmokeTest') -ExpectedPattern 'Mini mode toggled successfully'
Invoke-MonitorTest -Name 'Mini startup construction' -Arguments @('-UiSmokeTest', '-StartMini') -ExpectedPattern 'GUI controls constructed successfully'
Invoke-MonitorTest -Name 'Integration parsing' -Arguments @('-IntegrationSmokeTest') -ExpectedPattern 'IntegrationCalls=1;.*Local shell:1'
Invoke-MonitorTest -Name 'Actual chat titles and token sources' -Arguments @('-TaskSmokeTest') -ExpectedPattern 'Tasks=2;.*Improve onboarding flow.*Codex Desktop.*Investigate build latency.*Codex CLI' -RejectedPattern 'Confidential|acquisition'
$hiddenIndexTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'live-codex-hidden-index-{0}' -f [guid]::NewGuid().ToString('N')
)
$hiddenIndexCodexHome = Join-Path $hiddenIndexTestRoot 'codex-home'
try {
    [void](New-Item -ItemType Directory -Path $hiddenIndexTestRoot)
    Copy-Item -LiteralPath $fixtureHome -Destination $hiddenIndexCodexHome -Recurse
    $hiddenIndexPath = Join-Path $hiddenIndexCodexHome 'session_index.jsonl'
    $hiddenIndexFile = Get-Item -LiteralPath $hiddenIndexPath
    $hiddenIndexFile.Attributes = $hiddenIndexFile.Attributes -bor [System.IO.FileAttributes]::Hidden
    Invoke-MonitorTest -Name 'Hidden Codex title index' -CodexHomeOverride $hiddenIndexCodexHome `
        -Arguments @('-TaskSmokeTest') `
        -ExpectedPattern 'Tasks=2;.*Improve onboarding flow.*Investigate build latency'
}
finally {
    $resolvedHiddenIndexRoot = [System.IO.Path]::GetFullPath($hiddenIndexTestRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedHiddenIndexRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedHiddenIndexRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Invoke-MonitorTest -Name 'Chat-title visibility Settings toggle' -Arguments @('-TitleVisibilitySmokeTest') `
    -ExpectedPattern 'TitleVisibility=OnOff; Visible=True; Hidden=True; Restored=True'
Invoke-MonitorTest -Name 'Prompt-title visibility Settings toggle' -Arguments @('-TitleVisibilitySmokeTest', '-ShowPromptTaskTitles') `
    -ExpectedPattern 'TitleVisibility=OnOff; Visible=True; Hidden=True; Restored=True'
Invoke-MonitorTest -Name 'Date-range reload' -Arguments @('-DateRangeSmokeTest') -ExpectedPattern 'DateRange=2026-07-25 to 2026-07-25; Events=1'
Invoke-MonitorTest -Name 'Command-line date range' -Arguments @('-Once', '-FromDate', '2026-07-26', '-ToDate', '2026-07-26') -ExpectedPattern 'Events=2;'
Invoke-MonitorTest -Name 'Archived-session discovery' -Arguments @('-ArchivedSmokeTest') -ExpectedPattern 'ArchivedEvents=1; TotalEvents=3'
Invoke-MonitorTest -Name 'Date presets' -Arguments @('-PresetSmokeTest') -ExpectedPattern 'Week=2026-07-21:2026-07-27; MonthDays=30; AllStart=2026-07-25'
Invoke-MonitorTest -Name 'In-memory range cache' -Arguments @('-RangeCacheSmokeTest') -ExpectedPattern 'CacheStable=True; FirstRange=1; SecondRange=2'
Invoke-MonitorTest -Name 'Expanded date-range catalog reload' -Arguments @(
    '-CatalogExpansionSmokeTest', '-FromDate', '2026-07-26', '-ToDate', '2026-07-26'
) -ExpectedPattern 'InitialEvents=2; ExpandedEvents=3; CatalogStart=2026-07-25'
Invoke-MonitorTest -Name 'Combined status and quota windows' -Arguments @('-StatusSmokeTest') -ExpectedPattern 'QuotaPercent=95; Status=CRITICAL'
Invoke-MonitorTest -Name 'Quota reset countdown and pace' -Arguments @('-QuotaResetSmokeTest') -ExpectedPattern 'resets in .*below even pace'
Invoke-MonitorTest -Name 'Usage saver integration' -Arguments @('-EfficiencySmokeTest') `
    -ExpectedPattern 'Cache=68.6%; Schema=Healthy; QuotaWindows=2; Advice=Continue; Compactions=0'
Invoke-MonitorTest -Name 'Startup alert freshness' -Arguments @('-AlertSmokeTest') -ExpectedPattern 'StaleAlert=False; ActiveAlert=True'
Invoke-MonitorTest -Name 'Enterprise analytics import' -Arguments @('-EnterpriseSmokeTest', '-EnterpriseCsvPath', $analyticsFixture) -ExpectedPattern 'Rows=2; ActiveUsers=2; Messages=150; ToolMessages=40; SeatTypes=2' -RejectedPattern 'Alice|Bob|example\.invalid|secret'
Invoke-MonitorTest -Name 'Personal usage dialog construction' -Arguments @('-EnterpriseUiSmokeTest', '-EnterpriseCsvPath', $personalAnalyticsFixture) -ExpectedPattern 'Personal usage dialog constructed successfully; Tabs=3'
Invoke-MonitorTest -Name 'Compliance dialog construction' -Arguments @(
    '-ComplianceUiSmokeTest', '-ComplianceInputPath', $personalActivityFixture,
    '-ComplianceMappingPath', $complianceMapping
) -ExpectedPattern 'Compliance dialog constructed successfully; Tabs=4; Rows=2'
Invoke-MonitorTest -Name 'Control center construction' -Arguments @(
    '-InsightsUiSmokeTest', '-OfficialSnapshotPath', $officialFixture
) -ExpectedPattern 'Control center constructed successfully; Tabs=10; TrendRows=2; Models=2; Instance=INFO'

Write-Host '  Work-PC launcher policy and download-marker handling'
$launcherTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'live-codex-launcher-{0}' -f [guid]::NewGuid().ToString('N')
)
[void](New-Item -ItemType Directory -Path $launcherTestRoot)
try {
    $launcherCopy = Join-Path $launcherTestRoot 'START-HERE.cmd'
    $dummyPowerShellLauncher = Join-Path $launcherTestRoot 'Start-Live-Codex-Usage.ps1'
    Copy-Item -LiteralPath $startHereLauncher -Destination $launcherCopy
    Set-Content -LiteralPath $dummyPowerShellLauncher -Value 'exit 0' -Encoding Ascii
    Set-Content -LiteralPath $dummyPowerShellLauncher -Stream Zone.Identifier `
        -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding Ascii

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        Push-Location -LiteralPath $launcherTestRoot
        try {
            $launcherOutput = @(& $env:ComSpec /d /c '"START-HERE.cmd" --check-only' 2>&1)
            $launcherExit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($launcherExit -ne 0 -or
        ($launcherOutput -join [Environment]::NewLine) -notmatch 'Compatibility check passed') {
        throw "START-HERE compatibility check failed.`n$($launcherOutput -join [Environment]::NewLine)"
    }
    if (@(Get-Item -LiteralPath $dummyPowerShellLauncher -Stream Zone.Identifier `
            -ErrorAction SilentlyContinue).Count -ne 0) {
        throw 'START-HERE did not remove the downloaded-file marker.'
    }

    Set-Content -LiteralPath $dummyPowerShellLauncher -Stream Zone.Identifier `
        -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding Ascii
    $env:LIVE_CODEX_TEST_MANAGED_POLICY = 'AllSigned'
    try {
        $previousErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            Push-Location -LiteralPath $launcherTestRoot
            try {
                $managedOutput = @(& $env:ComSpec /d /c '"START-HERE.cmd" --check-only' 2>&1)
                $managedExit = $LASTEXITCODE
            }
            finally {
                Pop-Location
            }
        }
        finally {
            $ErrorActionPreference = $previousErrorAction
        }
    }
    finally {
        Remove-Item Env:LIVE_CODEX_TEST_MANAGED_POLICY -ErrorAction SilentlyContinue
    }
    $managedText = $managedOutput -join [Environment]::NewLine
    if ($managedExit -ne 40 -or $managedText -notmatch 'AllSigned' -or
        $managedText -notmatch 'IT administrator') {
        throw "START-HERE did not report managed AllSigned policy safely.`n$managedText"
    }
    if (@(Get-Item -LiteralPath $dummyPowerShellLauncher -Stream Zone.Identifier `
            -ErrorAction SilentlyContinue).Count -ne 1) {
        throw 'START-HERE changed a downloaded file before honoring managed AllSigned policy.'
    }

    $standardCmdText = Get-Content -LiteralPath $standardCmdLauncher -Raw
    $miniCmdText = Get-Content -LiteralPath $miniCmdLauncher -Raw
    if ($standardCmdText -notmatch 'START-HERE\.cmd' -or
        $miniCmdText -notmatch 'START-HERE\.cmd.+--mini') {
        throw 'One or more double-click launchers bypass START-HERE.'
    }
}
finally {
    Remove-Item Env:LIVE_CODEX_TEST_MANAGED_POLICY -ErrorAction SilentlyContinue
    $resolvedLauncherRoot = [System.IO.Path]::GetFullPath($launcherTestRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedLauncherRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedLauncherRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '  Per-user single-instance activation and recovery'
Import-Module -Name $instanceModule -Force
$instanceScope = 'fixture-user-{0}' -f [guid]::NewGuid().ToString('N')
$primaryInstance = $null
$secondaryInstance = $null
$recoveredInstance = $null
try {
    $instanceNames = Get-MonitorInstanceObjectNames -ScopeSeed $instanceScope
    if (($instanceNames | ConvertTo-Json) -match [regex]::Escape($instanceScope)) {
        throw 'Single-instance object names exposed the scope seed.'
    }
    $primaryInstance = New-MonitorInstanceCoordinator -ScopeSeed $instanceScope
    $secondaryInstance = New-MonitorInstanceCoordinator -ScopeSeed $instanceScope
    if (-not $primaryInstance.IsPrimary -or $secondaryInstance.IsPrimary -or
        -not $secondaryInstance.ActivationRequested -or
        -not (Test-MonitorInstanceActivation -Coordinator $primaryInstance)) {
        throw 'A second launch did not signal the existing monitor instance.'
    }
    Close-MonitorInstanceCoordinator -Coordinator $secondaryInstance
    $secondaryInstance = $null
    Close-MonitorInstanceCoordinator -Coordinator $primaryInstance
    $primaryInstance = $null
    $recoveredInstance = New-MonitorInstanceCoordinator -ScopeSeed $instanceScope
    if (-not $recoveredInstance.IsPrimary) {
        throw 'Single-instance ownership was not recoverable after shutdown.'
    }
}
finally {
    Close-MonitorInstanceCoordinator -Coordinator $secondaryInstance
    Close-MonitorInstanceCoordinator -Coordinator $primaryInstance
    Close-MonitorInstanceCoordinator -Coordinator $recoveredInstance
}

Write-Host '  Offline rate-card estimates'
Import-Module -Name $costModule -Force
$rateCard = Import-UsageRateCard -Path $rateCardPath
$knownCost = Get-TokenCostEstimate -RateCard $rateCard -Model 'gpt-5.6-sol' `
    -NewInputTokens 1000000 -CachedInputTokens 1000000 -OutputTokens 1000000 -DollarsPerCredit 0.04
if (-not $knownCost.Priced -or $knownCost.EstimatedCredits -ne [decimal]887.5 -or
    $knownCost.ApiEquivalentUsd -ne [decimal]35.5 -or $knownCost.EstimatedActualUsd -ne [decimal]35.5) {
    throw 'Offline rate-card estimate is incorrect.'
}
$unknownCost = Get-TokenCostEstimate -RateCard $rateCard -Model 'unpublished-model' `
    -NewInputTokens 1000 -CachedInputTokens 0 -OutputTokens 1000
if ($unknownCost.Priced -or $unknownCost.EstimatedCredits -ne 0 -or $null -ne $unknownCost.ApiEquivalentUsd -or
    $unknownCost.Note -notmatch 'no default was guessed') {
    throw 'Unknown-model pricing must stay explicitly unpriced.'
}

Write-Host '  Usage saver calculations, schema drift, profiles, policy, and rollback'
Import-Module -Name $efficiencyModule -Force
Import-Module -Name $privacyModule -Force
$efficiencyUsage = @(
    [pscustomobject]@{
        At = [datetime]'2026-07-27T10:00:00'; Session = 'private-a'; Model = 'gpt-5.6-sol'
        Input = 10000; NewInput = 1000; Cached = 9000; Output = 200; Total = 10200
    },
    [pscustomobject]@{
        At = [datetime]'2026-07-27T10:05:00'; Session = 'private-a'; Model = 'gpt-5.6-sol'
        Input = 140000; NewInput = 5000; Cached = 135000; Output = 300; Total = 140300
    },
    [pscustomobject]@{
        At = [datetime]'2026-07-27T10:10:00'; Session = 'private-a'; Model = 'gpt-5.6-sol'
        Input = 150000; NewInput = 6000; Cached = 144000; Output = 350; Total = 150350
    },
    [pscustomobject]@{
        At = [datetime]'2026-07-27T10:15:00'; Session = 'private-a'; Model = 'gpt-5.6-sol'
        Input = 160000; NewInput = 7000; Cached = 153000; Output = 400; Total = 160400
    }
)
$cacheSavings = Get-PromptCacheSavings -RateCard $rateCard -UsageEvents $efficiencyUsage
if ($cacheSavings.CacheHitPercent -lt 90 -or $cacheSavings.CalculatedCreditsAvoided -le 0 -or
    $cacheSavings.SavingsClass -notmatch '^Calculated') {
    throw 'Prompt-cache savings classification or calculation is incorrect.'
}
$freshAdvice = Get-SessionEfficiencyAdvice -UsageEvents $efficiencyUsage -BloatedContextTokens 100000
if ($freshAdvice.StatusCode -ne 'FreshTaskOpportunity' -or $freshAdvice.BreakEvenFutureTurns -gt 4 -or
    $freshAdvice.ExcessReplayTokensPerFutureTurn -le 0) {
    throw 'Fresh-task break-even advice is incorrect.'
}
$schemaTracker = New-CodexSchemaTracker
$validTokenLine = '{"timestamp":"2026-07-27T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":5,"output_tokens":2,"total_tokens":12}}}}'
Add-CodexSchemaObservation -Tracker $schemaTracker -Line $validTokenLine
$healthySchema = Get-CodexSchemaHealth -Tracker $schemaTracker
if ($healthySchema.StatusCode -ne 'Healthy' -or $healthySchema.CompatibilityPercent -ne 100) {
    throw 'Known Codex log schema was not classified as healthy.'
}
$driftTokenLine = '{"timestamp":"2026-07-27T10:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10}}}}'
Add-CodexSchemaObservation -Tracker $schemaTracker -Line $driftTokenLine
$driftSchema = Get-CodexSchemaHealth -Tracker $schemaTracker
if ($driftSchema.StatusCode -ne 'Drift' -or $driftSchema.TokenShapeMismatches -ne 1) {
    throw 'Token schema drift was not detected.'
}
$quotaReset = [datetimeoffset](Get-Date).AddHours(2)
$quotaRows = @(Get-QuotaWindowMetrics -RateLimits ([pscustomobject]@{
    primary = [pscustomobject]@{ used_percent = 25; reset_at = $quotaReset.ToUnixTimeSeconds(); window_minutes = 300 }
    secondary = [pscustomobject]@{ used_percent = 70; reset_at = $quotaReset.AddDays(5).ToUnixTimeSeconds(); window_minutes = 10080 }
}))
if ($quotaRows.Count -ne 2 -or -not $quotaRows[0].Available -or -not $quotaRows[1].Available -or
    $quotaRows[0].UsedPercent -ne 25 -or $quotaRows[1].UsedPercent -ne 70) {
    throw 'Independent quota-window metrics are incorrect.'
}
$compactionUsage = @(
    [pscustomobject]@{ At = [datetime]'2026-07-27T11:00:00'; Session = 'private-b'; Input = 100000; NewInput = 5000 },
    [pscustomobject]@{ At = [datetime]'2026-07-27T11:02:00'; Session = 'private-b'; Input = 40000; NewInput = 4000 }
)
$compactionActivity = @(
    [pscustomobject]@{ At = [datetime]'2026-07-27T11:01:00'; Session = 'private-b'; Label = 'COMPACT' }
)
$compaction = Get-CompactionChurn -UsageEvents $compactionUsage -ActivityEvents $compactionActivity
if ($compaction.Compactions -ne 1 -or $compaction.PairedCompactions -ne 1 -or
    $compaction.AverageContextReductionPercent -ne 60) {
    throw 'Compaction churn pairing or reduction calculation is incorrect.'
}

$efficiencyTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('live-codex-efficiency-{0}' -f [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $efficiencyTestRoot)
try {
    $configPath = Join-Path $efficiencyTestRoot 'config.toml'
    $rollbackPath = Join-Path $efficiencyTestRoot 'rollback.json'
    $policyPath = Join-Path $efficiencyTestRoot 'AGENTS.md'
    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
        'model = "gpt-5.6-sol"'
        'model_reasoning_effort = "high"'
        'model_verbosity = "medium"'
        ''
        '[features]'
        'tool_search = true'
        ''
        '[mcp_servers.one]'
        'enabled = true'
        ''
        '[mcp_servers.two]'
        'enabled = true'
    )
    $configState = Get-CodexEfficiencyConfigState -Path $configPath
    $profilePreview = Get-CodexEfficiencyConfigPreview -ProfileName Saver -Path $configPath
    if ($configState.StatusCode -ne 'Healthy' -or $profilePreview.ChangeCount -ne 2) {
        throw 'Efficiency profile validation or preview is incorrect.'
    }
    $appliedProfile = Set-CodexEfficiencyConfigProfile -ProfileName Saver -Path $configPath `
        -RollbackPath $rollbackPath -Confirm:$false
    if (-not $appliedProfile.Applied -or $appliedProfile.State.ReasoningEffort -ne 'low' -or
        $appliedProfile.State.Verbosity -ne 'low' -or
        (Get-Content -LiteralPath $configPath -Raw) -notmatch '\[features\]') {
        throw 'Efficiency profile did not update only the intended allowlisted settings.'
    }
    $restoredProfile = Restore-CodexEfficiencyConfig -Path $configPath `
        -RollbackPath $rollbackPath -Confirm:$false
    if (-not $restoredProfile.Restored -or $restoredProfile.State.ReasoningEffort -ne 'high' -or
        $restoredProfile.State.Verbosity -ne 'medium') {
        throw 'Allowlisted efficiency configuration rollback is incorrect.'
    }
    Set-Content -LiteralPath $configPath -Encoding UTF8 -Value @(
        'model_reasoning_effort = "high"'
        'model_reasoning_effort = "low"'
        'model_verbosity = "verbose"'
        ''
        '[mcp_servers.one]'
        'enabled = true'
        ''
        '[mcp_servers.two]'
        'enabled = true'
    )
    $brokenConfig = Get-CodexEfficiencyConfigState -Path $configPath
    if ($brokenConfig.StatusCode -ne 'NeedsRepair' -or $brokenConfig.IssueCount -ne 2) {
        throw 'Duplicate or invalid allowlisted configuration was not detected.'
    }
    $repairedConfig = Repair-CodexEfficiencyConfig -Path $configPath `
        -RollbackPath $rollbackPath -Confirm:$false
    if (-not $repairedConfig.Repaired -or $repairedConfig.State.StatusCode -ne 'Healthy' -or
        $repairedConfig.State.ReasoningEffort -ne 'low') {
        throw 'Safe allowlisted configuration repair is incorrect.'
    }
    $surfaceAudit = Get-CodexToolSurfaceAudit -ConfigPath $configPath -IntegrationEvents @(
        [pscustomobject]@{ Kind = 'MCP'; Name = 'private tool'; At = Get-Date }
    )
    if ($surfaceAudit.ConfiguredMcpServers -ne 2 -or $surfaceAudit.ObservedToolCategories -ne 1 -or
        -not $surfaceAudit.ReviewOpportunity) {
        throw 'Aggregate tool-surface audit is incorrect.'
    }
    Set-Content -LiteralPath $policyPath -Value '# Existing personal instructions' -Encoding UTF8
    $installedPolicy = Set-CodexEfficiencyPolicy -Enabled $true -Path $policyPath -Confirm:$false
    $policyText = Get-Content -LiteralPath $policyPath -Raw
    if (-not $installedPolicy.Installed -or $policyText -notmatch 'Existing personal instructions' -or
        ([regex]::Matches($policyText, 'LIVE-CODEX-USAGE-MONITOR:EFFICIENCY-V1 START')).Count -ne 1) {
        throw 'Managed local efficiency policy installation is unsafe or incorrect.'
    }
    $removedPolicy = Set-CodexEfficiencyPolicy -Enabled $false -Path $policyPath -Confirm:$false
    $policyText = Get-Content -LiteralPath $policyPath -Raw
    if ($removedPolicy.Installed -or $policyText -notmatch 'Existing personal instructions' -or
        $policyText -match 'LIVE-CODEX-USAGE-MONITOR:EFFICIENCY-V1') {
        throw 'Managed local efficiency policy removal is unsafe or incorrect.'
    }
    foreach ($privacySafeValue in @(
        $cacheSavings, $freshAdvice, $healthySchema, $driftSchema,
        $compaction, $profilePreview, $surfaceAudit, $installedPolicy
    )) {
        $efficiencyShape = Test-AggregatePrivacyShape -Value $privacySafeValue
        if (-not $efficiencyShape.Passed) {
            throw "Efficiency result violated aggregate privacy: $($efficiencyShape.Violations -join ', ')"
        }
    }
}
finally {
    $resolvedEfficiencyRoot = [System.IO.Path]::GetFullPath($efficiencyTestRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedEfficiencyRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedEfficiencyRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host '  Official-report import, sanitization, freshness, and reconciliation'
Import-Module -Name $reconciliationModule -Force
$official = Import-OfficialUsageSnapshot -Path $officialFixture
if ($official.Rows.Count -ne 2 -or ($official | ConvertTo-Json -Depth 8) -match 'alice|bob|example\.invalid') {
    throw 'Official snapshot import retained an identifier or returned the wrong row count.'
}
$freshness = Get-OfficialSnapshotFreshness -ReportUpdatedAt (Get-Date).AddHours(-13)
if ($freshness.Label -notmatch 'Older than typical' -or $freshness.TypicalRefresh -ne '6-12 hours') {
    throw 'Official snapshot freshness classification is incorrect.'
}
$comparison = @(Compare-OfficialUsageSnapshot -LocalDailyCosts @(
    [pscustomobject]@{ Date = '2026-07-25'; EstimatedCredits = [decimal]10.1 },
    [pscustomobject]@{ Date = '2026-07-26'; EstimatedCredits = [decimal]15.0 }
) -OfficialSnapshot $official)
if ($comparison.Count -ne 2 -or $comparison[0].Status -ne 'Aligned' -or
    $comparison[1].Status -ne 'Official higher') {
    throw 'Official snapshot reconciliation status is incorrect.'
}

Write-Host '  Official dashboard aggregate checkpoint history and reconciliation'
Import-Module -Name $officialDashboardModule -Force
Import-Module -Name $privacyModule -Force
$dashboardHistoryPath = Join-Path ([System.IO.Path]::GetTempPath()) ('live-codex-dashboard-{0}.json' -f [guid]::NewGuid().ToString('N'))
try {
    $dashboardSnapshot = New-OfficialDashboardSnapshot `
        -PeriodStart ([datetime]'2026-07-25') -PeriodEnd ([datetime]'2026-07-26') `
        -ObservedAt ([datetime]'2026-07-27T12:00:00Z') -RangeKind Custom -GroupBy Day `
        -Turns 3 -PluginCalls 1 -LinesOfCode 24 -SkillsUsed 0
    $dashboardHistory = Add-OfficialDashboardSnapshot -Path $dashboardHistoryPath -Snapshot $dashboardSnapshot
    $dashboardJson = Get-Content -LiteralPath $dashboardHistoryPath -Raw
    if (($dashboardJson -match 'secret|session|rollout|sessions[\\/]') -or -not (Test-AggregatePrivacyShape -Value $dashboardHistory).Passed) {
        throw 'Official dashboard history retained an identifier or unsafe field.'
    }
    $dashboardComparison = @(Get-OfficialDashboardReconciliation `
        -UsageEvents @(
            [pscustomobject]@{ At = [datetime]'2026-07-25T12:00:00'; FreshBurn = 1 },
            [pscustomobject]@{ At = [datetime]'2026-07-26T12:00:00'; FreshBurn = 1 },
            [pscustomobject]@{ At = [datetime]'2026-07-26T13:00:00'; FreshBurn = 1 }
        ) `
        -IntegrationEvents @([pscustomobject]@{ At = [datetime]'2026-07-26T14:00:00' }) `
        -History $dashboardHistory)
    if ($dashboardComparison.Count -ne 1 -or $dashboardComparison[0].Status -ne 'Aligned' -or
        $dashboardComparison[0].LinesOfCode -ne 24) {
        throw 'Official dashboard checkpoint reconciliation is incorrect.'
    }
}
finally { Remove-Item -LiteralPath $dashboardHistoryPath -Force -ErrorAction SilentlyContinue }

Write-Host '  Privacy-safe persistent aggregate store'
Import-Module -Name $storeModule -Force
$storeEvents = @(
    [pscustomobject]@{ At = [datetime]'2026-07-25T12:00:00'; Session = 'secret-session'; Model = 'gpt-5.6-sol'; NewInput = 100; Cached = 50; Output = 25; Reasoning = 5; Total = 175 },
    [pscustomobject]@{ At = [datetime]'2026-07-25T13:00:00'; Session = 'another-secret'; Model = 'gpt-5.6-sol'; NewInput = 200; Cached = 70; Output = 40; Reasoning = 10; Total = 310 }
)
$snapshot = New-PrivacySafeAggregateSnapshot -UsageEvents $storeEvents -IntegrationEvents @()
Import-Module -Name $privacyModule -Force
$shape = Test-AggregatePrivacyShape -Value $snapshot
if (-not $shape.Passed -or ($snapshot | ConvertTo-Json -Depth 8) -match 'secret-session|another-secret') {
    throw 'Persistent aggregate store privacy shape is unsafe.'
}
$storePath = Join-Path ([System.IO.Path]::GetTempPath()) ('live-codex-store-{0}.json' -f [guid]::NewGuid().ToString('N'))
try {
    Write-PrivacySafeAggregateStore -Path $storePath -Snapshot $snapshot
    $loadedStore = Read-PrivacySafeAggregateStore -Path $storePath
    if ($loadedStore.Daily.Count -ne 1 -or [int64]$loadedStore.Daily[0].FreshBurn -ne 365) {
        throw 'Persistent aggregate store round trip is incorrect.'
    }
}
finally {
    Remove-Item -LiteralPath $storePath -Force -ErrorAction SilentlyContinue
}

Write-Host '  Usage guard threshold, grace, exact-path enforcement, and affirmative unlock'
Import-Module -Name $guardModule -Force
$guardPolicy = New-UsageGuardPolicy -Enabled $true -Mode Enforced -Metric EstimatedCredits `
    -Threshold 10 -GraceSeconds 5 -ApprovedExecutablePaths @('C:\Approved\codex.exe')
$crossedAt = [datetime]'2026-07-27T12:00:00'
$warning = Test-UsageGuardThreshold -Policy $guardPolicy -CurrentValue 10 -AsOf $crossedAt
$due = Test-UsageGuardThreshold -Policy $guardPolicy -CurrentValue 10 -AsOf $crossedAt.AddSeconds(6)
if (-not $warning.Crossed -or $warning.EnforcementDue -or -not $due.EnforcementDue) {
    throw 'Usage guard grace-period behavior is incorrect.'
}
Lock-UsageGuardPolicy -Policy $guardPolicy -Reason $due.Reason -AsOf $crossedAt.AddSeconds(6) | Out-Null
$stoppedIds = [System.Collections.Generic.List[int]]::new()
$guardResult = Invoke-UsageGuardEnforcement -Policy $guardPolicy `
    -ProcessProvider {
        @(
            [pscustomobject]@{ Id = 101; ProcessName = 'codex'; Path = 'C:\Approved\codex.exe' },
            [pscustomobject]@{ Id = 202; ProcessName = 'codex'; Path = 'C:\Other\codex.exe' }
        )
    } `
    -StopProvider { param($Candidate) $stoppedIds.Add([int]$Candidate.Id) }
if ($guardResult.Stopped -ne 1 -or $stoppedIds.Count -ne 1 -or $stoppedIds[0] -ne 101) {
    throw 'Usage guard did not enforce only the exact approved executable path.'
}
$badUnlockRejected = $false
try { Unlock-UsageGuardPolicy -Policy $guardPolicy -Confirmation 'yes' | Out-Null }
catch { $badUnlockRejected = $true }
if (-not $badUnlockRejected) { throw 'Usage guard accepted a non-affirmative unlock.' }
Unlock-UsageGuardPolicy -Policy $guardPolicy -Confirmation 'REENABLE CODEX' | Out-Null
if ($guardPolicy.Locked) { throw 'Usage guard did not unlock after exact affirmative confirmation.' }
$renewed = Test-UsageGuardThreshold -Policy $guardPolicy -CurrentValue 10 -AsOf (Get-Date)
if ($renewed.Crossed -or $renewed.Reason -notmatch 'renewed until') {
    throw 'Affirmative guard renewal did not suppress re-locking until the renewal boundary.'
}
$offReadiness = Get-UsageGuardReadiness -Policy (New-UsageGuardPolicy) -ProcessProvider { @() }
if ($offReadiness.StatusCode -ne 'Off' -or $offReadiness.StatusLabel -notmatch 'no process can be stopped') {
    throw 'Usage guard readiness did not make the disabled state explicit.'
}
$armedReadiness = Get-UsageGuardReadiness -Policy $guardPolicy -ProcessProvider {
    @([pscustomobject]@{ Id = 303; ProcessName = 'codex'; Path = 'C:\Approved\codex.exe' })
}
if ($armedReadiness.StatusCode -ne 'Armed' -or -not $armedReadiness.ReadyForEnforcement -or
    $armedReadiness.ApprovedPathCount -ne 1 -or $armedReadiness.RunningMatchCount -ne 1) {
    throw 'Usage guard readiness did not report exact-path enforcement readiness.'
}

Write-Host '  RTK local savings parsing, telemetry block, and health detection'
Import-Module -Name $rtkModule -Force
$rtkGainPayload = [pscustomobject]@{
    summary = [pscustomobject]@{
        total_commands = 4; total_input = 1000; total_output = 600; total_saved = 400
        avg_savings_pct = 40.0; total_time_ms = 20; avg_time_ms = 5
    }
    daily = @([pscustomobject]@{
        date = (Get-Date).ToString('yyyy-MM-dd'); commands = 4; input_tokens = 1000
        output_tokens = 600; saved_tokens = 400; savings_pct = 40.0; total_time_ms = 20; avg_time_ms = 5
    })
    weekly = @()
    monthly = @()
} | ConvertTo-Json -Depth 6
$rtkRunner = {
    param($Executable, $Arguments)
    $command = $Arguments -join ' '
    if ($command -eq '--version') {
        return [pscustomobject]@{ ExitCode = 0; Stdout = 'rtk 0.44.0'; Stderr = ''; TimedOut = $false }
    }
    if ($command -eq 'gain --all --format json') {
        return [pscustomobject]@{ ExitCode = 0; Stdout = $rtkGainPayload; Stderr = ''; TimedOut = $false }
    }
    return [pscustomobject]@{ ExitCode = 0; Stdout = 'No parse failures recorded.'; Stderr = ''; TimedOut = $false }
}
$rtkDb = Join-Path ([System.IO.Path]::GetTempPath()) ('rtk-health-{0}.db' -f [guid]::NewGuid().ToString('N'))
try {
    [void](New-Item -ItemType File -Path $rtkDb)
    (Get-Item -LiteralPath $rtkDb).LastWriteTime = (Get-Date).AddMinutes(-1)
    $rtkSnapshot = Get-RtkSavingsSnapshot -RtkPath $monitor -DatabasePath $rtkDb -CommandRunner $rtkRunner
    if ($rtkSnapshot.HealthCode -ne 'Active' -or -not $rtkSnapshot.Working -or
        $rtkSnapshot.SavedTokensEstimate -ne 400 -or $rtkSnapshot.SavingsPercent -ne 40 -or
        -not $rtkSnapshot.TelemetryBlocked -or $rtkSnapshot.OutboundRequestMade) {
        throw 'RTK local savings snapshot is incorrect or violates the zero-outbound contract.'
    }
    (Get-Item -LiteralPath $rtkDb).LastWriteTime = (Get-Date).AddMinutes(-10)
    $bypassed = Get-RtkSavingsSnapshot -RtkPath $monitor -DatabasePath $rtkDb `
        -RecentShellActivityAt (Get-Date) -CommandRunner $rtkRunner
    if ($bypassed.HealthCode -ne 'PossibleBypass' -or $bypassed.Working) {
        throw 'RTK did not identify activity newer than its local tracking history.'
    }
}
finally {
    Remove-Item -LiteralPath $rtkDb -Force -ErrorAction SilentlyContinue
}

Write-Host '  Zero-outbound runtime gate'
$zeroOutboundOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'Test-ZeroOutbound.ps1') 2>&1)
if ($LASTEXITCODE -ne 0 -or ($zeroOutboundOutput -join "`n") -notmatch 'ZeroOutbound=True') {
    throw "Zero-outbound gate failed.`n$($zeroOutboundOutput -join [Environment]::NewLine)"
}

Write-Host '  Enterprise summary privacy'
Import-Module -Name $enterpriseModule -Force
$enterpriseSummary = Import-WorkspaceAnalyticsReport -Path $analyticsFixture
$enterpriseText = $enterpriseSummary | ConvertTo-Json -Depth 8
if ($enterpriseText -match 'Alice|Bob|example\.invalid|user-secret|acct-secret') {
    throw 'Enterprise aggregate summary exposed a direct user identifier.'
}
if ($enterpriseSummary.Tools.Count -ne 3 -or $enterpriseSummary.Models.Count -ne 2) {
    throw 'Enterprise map aggregation did not produce the expected tool/model groups.'
}
$multiEnterprise = Import-WorkspaceAnalyticsReport -Path @($analyticsFixture, $analyticsFixture)
if ($multiEnterprise.SourceReports -ne 2 -or $multiEnterprise.Rows -ne 4 -or
    $multiEnterprise.ActiveUsers -ne 2 -or $multiEnterprise.TotalMessages -ne 300) {
    throw 'Multi-report Workspace Analytics aggregation is incorrect.'
}
$personalSummary = Import-PersonalWorkspaceAnalyticsReport -Path $personalAnalyticsFixture
if ($personalSummary.ActiveUsers -ne 1 -or $personalSummary.TotalMessages -ne 100 -or
    $personalSummary.PersonalScope -ne 'Single user') {
    throw 'Personal usage summary import is incorrect.'
}
$multiUserRejected = $false
try { Import-PersonalWorkspaceAnalyticsReport -Path $analyticsFixture | Out-Null }
catch { $multiUserRejected = ($_.Exception.Message -match 'Personal mode') }
if (-not $multiUserRejected) { throw 'Personal usage import accepted a multi-user report.' }
Import-Module -Name $complianceModule -Force
$personalActivity = Convert-PersonalActivityExport -InputPath $personalActivityFixture -MappingPath $complianceMapping
if ($personalActivity.UniqueUsers -ne 1 -or $personalActivity.OutputRows -ne 2) {
    throw 'Personal activity export import is incorrect.'
}
$multiActivityRejected = $false
try { Convert-PersonalActivityExport -InputPath $complianceFixture -MappingPath $complianceMapping | Out-Null }
catch { $multiActivityRejected = ($_.Exception.Message -match 'Personal mode') }
if (-not $multiActivityRejected) { throw 'Personal activity import accepted a multi-user export.' }

Write-Host '  Personal settings, startup registration, backup/restore, and sanitized diagnostics'
Import-Module -Name $personalModule -Force
$personalTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('live-codex-personal-{0}' -f [guid]::NewGuid().ToString('N'))
$personalStateRoot = Join-Path $personalTestRoot 'state'
$personalBackupRoot = Join-Path $personalTestRoot 'backups'
$personalRestoreRoot = Join-Path $personalTestRoot 'restore'
$personalStartupRoot = Join-Path $personalTestRoot 'startup'
foreach ($folder in @($personalStateRoot,$personalBackupRoot,$personalRestoreRoot,$personalStartupRoot)) {
    [void](New-Item -ItemType Directory -Path $folder)
}
try {
    $personalSettingsPath = Join-Path $personalStateRoot 'personal-settings-v1.json'
    $personalSettings = New-PersonalMonitorSettings
    $personalSettings.StartMinimizedToTray = $true
    $personalSettings.RefreshSeconds = 9
    Export-PersonalMonitorSettings -Settings $personalSettings -Path $personalSettingsPath
    $personalAggregate = New-PrivacySafeAggregateSnapshot -UsageEvents $storeEvents -IntegrationEvents @()
    Write-PrivacySafeAggregateStore -Path (Join-Path $personalStateRoot 'aggregate-v1.json') -Snapshot $personalAggregate
    $personalBackup = Export-PersonalMonitorBackup -StateRoot $personalStateRoot `
        -DestinationDirectory $personalBackupRoot -AppVersion 'test'
    $backupPreview = Get-PersonalMonitorBackupPreview -Path $personalBackup.Path
    if ($backupPreview.Files.Count -ne 2 -or $backupPreview.PrivacyClass -notmatch 'no-raw-logs') {
        throw 'Personal backup preview or allowlist is incorrect.'
    }
    $personalSettings.StartMinimizedToTray = $false
    Export-PersonalMonitorSettings -Settings $personalSettings -Path $personalSettingsPath
    $restoreResult = Import-PersonalMonitorBackup -Path $personalBackup.Path -StateRoot $personalRestoreRoot -Confirm:$false
    $restoredSettings = Import-PersonalMonitorSettings -Path (Join-Path $personalRestoreRoot 'personal-settings-v1.json')
    if (-not $restoreResult.Restored -or -not $restoredSettings.StartMinimizedToTray -or
        [int]$restoredSettings.RefreshSeconds -ne 9) {
        throw 'Personal backup restore did not preserve validated settings.'
    }
    $legacySettingsPath = Join-Path $personalTestRoot 'legacy-personal-settings-v1.json'
    [pscustomobject][ordered]@{
        SchemaVersion = 1
        StartAtSignIn = $false
        StartMinimizedToTray = $false
        LastBackupAt = $null
        LastDiagnosticsAt = $null
    } | ConvertTo-Json | Set-Content -LiteralPath $legacySettingsPath -Encoding UTF8
    $legacySettings = Import-PersonalMonitorSettings -Path $legacySettingsPath
    if ([int]$legacySettings.RefreshSeconds -ne 5) {
        throw 'Legacy personal settings did not receive the safe five-second refresh default.'
    }
    if (-not [bool]$legacySettings.NotificationsEnabled -or [string]$legacySettings.ReportingTimeZone -ne 'Local') {
        throw 'Legacy personal settings did not receive safe reporting and notification defaults.'
    }
    $notificationCommand = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $monitor,
        '-CodexHome', $fixtureHome, '-StateRoot', $personalStateRoot,
        '-WindowsNotifications', 'Off', '-NoSound', '-DisableRtkIntegration'
    )
    $notificationOutput = @(& powershell.exe @notificationCommand 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($notificationOutput -join "`n") -notmatch 'WindowsNotifications=Off; Persisted=True' -or
        (Import-PersonalMonitorSettings -Path $personalSettingsPath).NotificationsEnabled) {
        throw 'PowerShell notification-off preference did not persist correctly.'
    }
    $notificationCommand = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $monitor,
        '-CodexHome', $fixtureHome, '-StateRoot', $personalStateRoot,
        '-WindowsNotifications', 'On', '-NoSound', '-DisableRtkIntegration'
    )
    $notificationOutput = @(& powershell.exe @notificationCommand 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($notificationOutput -join "`n") -notmatch 'WindowsNotifications=On; Persisted=True' -or
        -not (Import-PersonalMonitorSettings -Path $personalSettingsPath).NotificationsEnabled) {
        throw 'PowerShell notification-on preference did not persist correctly.'
    }
    $registration = Set-PersonalStartupRegistration -Enabled $true -LauncherPath $monitor `
        -StartupFolder $personalStartupRoot -Confirm:$false
    if (-not $registration.Registered -or -not $registration.MatchesLauncher) {
        throw 'Personal start-at-sign-in registration was not created correctly.'
    }
    $registration = Set-PersonalStartupRegistration -Enabled $false -LauncherPath $monitor `
        -StartupFolder $personalStartupRoot -Confirm:$false
    if ($registration.Registered) { throw 'Personal start-at-sign-in registration was not removed.' }
    $diagnosticPath = Join-Path $personalTestRoot 'diagnostics.json'
    $diagnosticRows = Get-PersonalMonitorDiagnostics -CodexHome $fixtureHome -StateRoot $personalStateRoot `
        -RtkSnapshot $rtkSnapshot -GuardReadiness $offReadiness `
        -StartupRegistration ([pscustomobject]@{ Registered=$false; MatchesLauncher=$false }) `
        -AppVersion 'test'
    [void](Export-PersonalDiagnosticReport -Rows $diagnosticRows -Path $diagnosticPath -AppVersion 'test')
    $diagnosticText = Get-Content -LiteralPath $diagnosticPath -Raw
    if ($diagnosticText -match [regex]::Escape($fixtureHome) -or $diagnosticText -match 'personal-secret|example\.invalid') {
        throw 'Sanitized personal diagnostics exposed a path or identifier.'
    }
}
finally {
    $resolvedPersonalRoot = [System.IO.Path]::GetFullPath($personalTestRoot)
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedPersonalRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedPersonalRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$reportExport = Join-Path ([System.IO.Path]::GetTempPath()) ('live-codex-report-{0}.json' -f [guid]::NewGuid().ToString('N'))
try {
    Write-Host '  Privacy-safe JSON reporting and time-zone boundaries'
    Import-Module -Name $reportModule -Force
    $reportEvents = @(
        [pscustomobject]@{ At=[datetime]'2026-07-26T23:30:00'; Source='Codex'; Session='secret-session-one'; Model='gpt-test'; FreshBurn=10; NewInput=4; Output=6; Reasoning=0; Cached=2; Total=12 },
        [pscustomobject]@{ At=[datetime]'2026-07-27T00:30:00'; Source='Codex'; Session='secret-session-two'; Model='gpt-test'; FreshBurn=20; NewInput=8; Output=12; Reasoning=0; Cached=4; Total=24 }
    )
    $dailyReport = New-PrivacySafeUsageReport -UsageEvents $reportEvents -GroupBy Daily -TimeZoneId 'UTC'
    $sessionReport = New-PrivacySafeUsageReport -UsageEvents $reportEvents -GroupBy Session -TimeZoneId 'UTC'
    [void](Export-PrivacySafeUsageReport -Report $sessionReport -Path $reportExport)
    $reportText = Get-Content -LiteralPath $reportExport -Raw
    if ($dailyReport.Rows.Count -ne 2 -or $sessionReport.Rows.Count -ne 2 -or
        $reportText -match 'secret-session|rollout-|sessions[\\/]') {
        throw 'Privacy-safe JSON reporting has incorrect aggregation or exposed an identifier.'
    }
}
finally { Remove-Item -LiteralPath $reportExport -Force -ErrorAction SilentlyContinue }

$localExport = Join-Path ([System.IO.Path]::GetTempPath()) ('live-codex-local-{0}.csv' -f [guid]::NewGuid().ToString('N'))
$complianceExport = Join-Path ([System.IO.Path]::GetTempPath()) ('live-codex-compliance-{0}.csv' -f [guid]::NewGuid().ToString('N'))
try {
    Invoke-MonitorTest -Name 'Privacy-safe local CSV export' -Arguments @('-ExportSmokeTest', '-ExportPath', $localExport) -ExpectedPattern 'ExportRows=2; Events=3'
    $localExportText = Get-Content -LiteralPath $localExport -Raw
    if ($localExportText -match 'Confidential|acquisition|archived confidential|rollout-|sessions[\\/]') {
        throw 'Local aggregate CSV exposed task content, a session name, or a source path.'
    }
    $localRows = @(Import-Csv -LiteralPath $localExport)
    if ($localRows.Count -ne 2 -or (@($localRows | Measure-Object -Property Events -Sum)[0].Sum -ne 3)) {
        throw 'Local aggregate CSV totals are incorrect.'
    }

    Write-Host '  Compliance export aggregation and privacy'
    $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $complianceConverter -InputPath $complianceFixture -MappingPath $complianceMapping -OutputPath $complianceExport 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Compliance converter failed.`n$($output -join [Environment]::NewLine)" }
    if (($output -join [Environment]::NewLine) -notmatch 'ComplianceRows=5; InvalidLines=1; OutputRows=3') {
        throw "Compliance converter totals are incorrect.`n$($output -join [Environment]::NewLine)"
    }
    $complianceText = Get-Content -LiteralPath $complianceExport -Raw
    if ($complianceText -match 'Confidential|Sensitive|employee-secret|prompt|response') {
        throw 'Compliance aggregate CSV exposed content or a direct user identifier.'
    }
    $complianceRows = @(Import-Csv -LiteralPath $complianceExport)
    if ($complianceRows.Count -ne 3 -or (@($complianceRows | Measure-Object -Property Events -Sum)[0].Sum -ne 4)) {
        throw 'Compliance aggregate CSV totals are incorrect.'
    }
    if (@($complianceRows | Where-Object { $_.Surface -match '^[=+\-@]' }).Count -gt 0) {
        throw 'Compliance aggregate CSV contains a formula-active dimension.'
    }
}
finally {
    Remove-Item -LiteralPath $localExport -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $complianceExport -Force -ErrorAction SilentlyContinue
}

Write-Host 'QA passed.'
exit 0
