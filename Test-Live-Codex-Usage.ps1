$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$monitor = Join-Path $scriptDir 'Live-Codex-Usage-GUI.ps1'
$fixtureHome = Join-Path $scriptDir 'tests\fixtures\codex-home'
$analyticsFixture = Join-Path $scriptDir 'tests\fixtures\workspace-analytics-users.csv'
$complianceFixture = Join-Path $scriptDir 'tests\fixtures\compliance-export.jsonl'
$complianceMapping = Join-Path $scriptDir 'tests\fixtures\compliance-mapping.json'
$complianceConverter = Join-Path $scriptDir 'Convert-Enterprise-ComplianceExport.ps1'
$enterpriseModule = Join-Path $scriptDir 'Live-Codex-Usage-Enterprise.psm1'
$costModule = Join-Path $scriptDir 'Live-Codex-Usage-Cost.psm1'
$rateCardPath = Join-Path $scriptDir 'config\usage-rates.json'
$reconciliationModule = Join-Path $scriptDir 'Live-Codex-Usage-Reconciliation.psm1'
$officialFixture = Join-Path $scriptDir 'tests\fixtures\official-usage-snapshot.csv'
$storeModule = Join-Path $scriptDir 'Live-Codex-Usage-Store.psm1'
$guardModule = Join-Path $scriptDir 'Live-Codex-Usage-Guard.psm1'
$privacyModule = Join-Path $scriptDir 'Live-Codex-Usage-Privacy.psm1'

Write-Host 'Running Live Codex Usage QA...'

function Invoke-MonitorTest {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$ExpectedPattern = '',
        [string]$RejectedPattern = ''
    )

    Write-Host "  $Name"
    $common = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $monitor,
        '-CodexHome', $fixtureHome, '-HistoryHours', '87600',
        '-NoNotifications', '-NoSound', '-DisablePersistence'
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
Invoke-MonitorTest -Name 'Mini layout toggle' -Arguments @('-MiniSmokeTest') -ExpectedPattern 'Mini mode toggled successfully'
Invoke-MonitorTest -Name 'Mini startup construction' -Arguments @('-UiSmokeTest', '-StartMini') -ExpectedPattern 'GUI controls constructed successfully'
Invoke-MonitorTest -Name 'Integration parsing' -Arguments @('-IntegrationSmokeTest') -ExpectedPattern 'IntegrationCalls=1;.*Local shell:1'
Invoke-MonitorTest -Name 'Private task labels' -Arguments @('-TaskSmokeTest') -ExpectedPattern 'Tasks=2;.*gpt-test.*gpt-archived-test' -RejectedPattern 'Confidential|acquisition'
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
Invoke-MonitorTest -Name 'Startup alert freshness' -Arguments @('-AlertSmokeTest') -ExpectedPattern 'StaleAlert=False; ActiveAlert=True'
Invoke-MonitorTest -Name 'Enterprise analytics import' -Arguments @('-EnterpriseSmokeTest', '-EnterpriseCsvPath', $analyticsFixture) -ExpectedPattern 'Rows=2; ActiveUsers=2; Messages=150; ToolMessages=40; SeatTypes=2' -RejectedPattern 'Alice|Bob|example\.invalid|secret'
Invoke-MonitorTest -Name 'Enterprise dialog construction' -Arguments @('-EnterpriseUiSmokeTest', '-EnterpriseCsvPath', $analyticsFixture) -ExpectedPattern 'Enterprise dialog constructed successfully; Tabs=4'
Invoke-MonitorTest -Name 'Compliance dialog construction' -Arguments @(
    '-ComplianceUiSmokeTest', '-ComplianceInputPath', $complianceFixture,
    '-ComplianceMappingPath', $complianceMapping
) -ExpectedPattern 'Compliance dialog constructed successfully; Tabs=4; Rows=3'
Invoke-MonitorTest -Name 'Control center construction' -Arguments @(
    '-InsightsUiSmokeTest', '-OfficialSnapshotPath', $officialFixture
) -ExpectedPattern 'Control center constructed successfully; Tabs=6; TrendRows=2; Models=2'

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
