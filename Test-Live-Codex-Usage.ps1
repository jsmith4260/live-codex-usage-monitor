$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$monitor = Join-Path $scriptDir 'Live-Codex-Usage-GUI.ps1'

Write-Host 'Running Live Codex Usage QA...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $monitor -Once
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $monitor -UiSmokeTest -NoNotifications -NoSound
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $monitor -MiniSmokeTest -NoNotifications -NoSound
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $monitor -UiSmokeTest -StartMini -NoNotifications -NoSound
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $monitor -IntegrationSmokeTest
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $monitor -TaskSmokeTest
Write-Host 'QA passed.'
exit 0
