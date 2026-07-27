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
    [ValidateRange(1, 1…20872 tokens truncated…     elseif ($item.Label -eq 'TOKEN') {
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
$loadRangeButton.Add_Click({
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
})
$miniButton.Add_Click({
    Set-MiniMode -Enabled (-not $script:isMiniMode)
    Refresh-Display
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
    $form.Dispose()
    if ($null -ne $script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    exit 0
}

[void]$form.ShowDialog()
