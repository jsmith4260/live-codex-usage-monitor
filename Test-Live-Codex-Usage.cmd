@echo off
setlocal
cd /d "%~dp0"
set SCRIPT=%~dp0Test-Live-Codex-Usage.ps1

echo Running Live Codex Usage QA...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
if errorlevel 1 goto failed

echo QA passed.
pause
exit /b 0

:failed
echo QA failed. Check the output above.
pause
exit /b 1
