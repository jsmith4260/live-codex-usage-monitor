@echo off
setlocal
cd /d "%~dp0"
set SCRIPT=%~dp0Live-Codex-Usage-GUI.ps1

echo Running Live Codex Usage QA...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Once
if errorlevel 1 goto failed

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -UiSmokeTest -NoNotifications -NoSound
if errorlevel 1 goto failed

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -MiniSmokeTest -NoNotifications -NoSound
if errorlevel 1 goto failed

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -UiSmokeTest -StartMini -NoNotifications -NoSound
if errorlevel 1 goto failed

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -IntegrationSmokeTest
if errorlevel 1 goto failed

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -TaskSmokeTest
if errorlevel 1 goto failed

echo QA passed.
pause
exit /b 0

:failed
echo QA failed. Check the output above.
pause
exit /b 1
