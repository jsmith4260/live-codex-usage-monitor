@echo off
setlocal
cd /d "%~dp0"
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Live-Codex-Usage-GUI.ps1"
endlocal
