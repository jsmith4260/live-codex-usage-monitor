@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Live-Codex-Usage-GUI.ps1" -StartMini
endlocal

