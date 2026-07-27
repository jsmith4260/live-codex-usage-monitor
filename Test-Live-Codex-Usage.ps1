$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$monitor = Join-Path $scriptDir 'Live-Codex-Usage-GUI.ps1'
$fixtureHome = Join-Path $scriptDir 'tests\fixtures\codex-home'
$analyticsFixture = Join-Path $scriptDir 'tests\fixtures\workspace-analytics-users.csv'
$complianceFixture = Join-Path $scriptDir 'tests\fixtures\compliance-export.jsonl'
$complianceMapping = Join-Path $scriptDir 'tests\fixtures\compliance-mapping.json'
$complianceConverter = Join-Path $scriptDir 'Convert-Enterprise-ComplianceExport.ps1'
$enterpriseModule = Join-Path $scriptDir 'Live-Codex-Usage-Enterprise.psm1'

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
        '-NoNotifications', '-NoSound'
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
Invoke-MonitorTest -Name 'Combined status and quota windows' -Arguments @('-StatusSmokeTest') -ExpectedPattern 'QuotaPercent=95; Status=CRITICAL'
Invoke-MonitorTest -Name 'Quota reset countdown and pace' -Arguments @('-QuotaResetSmokeTest') -ExpectedPattern 'resets in .*below even pace'
Invoke-MonitorTest -Name 'Startup alert freshness' -Arguments @('-AlertSmokeTest') -ExpectedPattern 'StaleAlert=False; ActiveAlert=True'
Invoke-MonitorTest -Name 'Enterprise analytics import' -Arguments @('-EnterpriseSmokeTest', '-EnterpriseCsvPath', $analyticsFixture) -ExpectedPattern 'Rows=2; ActiveUsers=2; Messages=150; ToolMessages=40; SeatTypes=2' -RejectedPattern 'Alice|Bob|example\.invalid|secret'
Invoke-MonitorTest -Name 'Enterprise dialog construction' -Arguments @('-EnterpriseUiSmokeTest', '-EnterpriseCsvPath', $analyticsFixture) -ExpectedPattern 'Enterprise dialog constructed successfully; Tabs=4'

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
