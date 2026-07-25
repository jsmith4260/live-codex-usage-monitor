$scriptDir = Split-Path -Parent $PSCommandPath
$monitor = Join-Path $scriptDir 'Live-Codex-Usage-GUI.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $monitor @args
