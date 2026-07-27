$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$monitor = Join-Path $scriptDir 'Live-Codex-Usage-GUI.ps1'
$fixtureHome = Join-Path $scriptDir 'tests\fixtures\codex-home'

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

Invoke-MonitorTest -Name 'Token semantics' -Arguments @('-Once') -ExpectedPattern 'Events=2;.*FreshBurn=650;.*NewInput=500'
Invoke-MonitorTest -Name 'Full GUI construction' -Arguments @('-UiSmokeTest') -ExpectedPattern 'GUI controls constructed successfully'
Invoke-MonitorTest -Name 'Mini layout toggle' -Arguments @('-MiniSmokeTest') -ExpectedPattern 'Mini mode toggled successfully'
Invoke-MonitorTest -Name 'Mini startup construction' -Arguments @('-UiSmokeTest', '-StartMini') -ExpectedPattern 'GUI controls constructed successfully'
Invoke-MonitorTest -Name 'Integration parsing' -Arguments @('-IntegrationSmokeTest') -ExpectedPattern 'IntegrationCalls=1;.*Local shell:1'
Invoke-MonitorTest -Name 'Private task labels' -Arguments @('-TaskSmokeTest') -ExpectedPattern 'Tasks=1;.*gpt-test' -RejectedPattern 'Confidential acquisition'
Invoke-MonitorTest -Name 'Date-range reload' -Arguments @('-DateRangeSmokeTest') -ExpectedPattern 'DateRange=2026-07-26 to 2026-07-26; Events=2'
Invoke-MonitorTest -Name 'Combined status and quota windows' -Arguments @('-StatusSmokeTest') -ExpectedPattern 'QuotaPercent=95; Status=CRITICAL'
Invoke-MonitorTest -Name 'Startup alert freshness' -Arguments @('-AlertSmokeTest') -ExpectedPattern 'StaleAlert=False; ActiveAlert=True'

Write-Host 'QA passed.'
exit 0
