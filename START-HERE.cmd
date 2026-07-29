@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

set "MONITOR_ROOT=%~dp0"
set "MONITOR_LAUNCHER=%~dp0Start-Live-Codex-Usage.ps1"
set "MONITOR_MODE="
set "MONITOR_REQUEST=%~1"

if not exist "%MONITOR_LAUNCHER%" goto missing_files

rem PowerShell execution policy does not block an inline command. Use that
rem narrow bootstrap to identify administrator policy and remove only the
rem Internet Zone marker from this release's PowerShell files.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';$root=[IO.Path]::GetFullPath($env:MONITOR_ROOT);$machine=[string](Get-ExecutionPolicy -Scope MachinePolicy);$user=[string](Get-ExecutionPolicy -Scope UserPolicy);$managed=if($machine -ne 'Undefined'){$machine}elseif($user -ne 'Undefined'){$user}else{'Undefined'};$testPolicy=[string]$env:LIVE_CODEX_TEST_MANAGED_POLICY;if($managed -eq 'Undefined' -and $testPolicy -in @('RemoteSigned','AllSigned','Restricted')){$managed=$testPolicy};if($managed -eq 'AllSigned'){[Console]::Error.WriteLine('Your organization enforces the AllSigned PowerShell policy.');exit 40};if($managed -eq 'Restricted'){[Console]::Error.WriteLine('Your organization enforces the Restricted PowerShell policy.');exit 41};$extensions=@('.ps1','.psm1','.psd1');$files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction Stop | Where-Object {$extensions -contains $_.Extension.ToLowerInvariant()});foreach($file in $files){Unblock-File -LiteralPath $file.FullName -ErrorAction Stop};exit 0"
set "PREPARE_EXIT=%ERRORLEVEL%"

if "%PREPARE_EXIT%"=="40" (
    echo.
    echo Live Codex Usage Monitor was not started.
    echo.
    echo Your organization requires every PowerShell script to have an approved
    echo digital signature. This GitHub release is checksummed but is not currently
    echo Authenticode-signed. START-HERE will not weaken or bypass managed policy.
    echo.
    echo Ask your IT administrator to approve or internally sign the package.
    call :show_policies
    call :maybe_pause
    exit /b 40
)
if "%PREPARE_EXIT%"=="41" (
    echo.
    echo Live Codex Usage Monitor was not started.
    echo.
    echo Your organization blocks PowerShell scripts through managed policy.
    echo START-HERE will not weaken or bypass that policy.
    echo.
    echo Ask your IT administrator whether this local monitor can be approved.
    call :show_policies
    call :maybe_pause
    exit /b 41
)
if not "%PREPARE_EXIT%"=="0" goto prepare_failed

if /I "%~1"=="--check-only" goto check_ok
if /I "%~1"=="--mini" set "MONITOR_MODE=-StartMini"

start "" powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%MONITOR_LAUNCHER%" %MONITOR_MODE%
if errorlevel 1 goto launch_failed
exit /b 0

:check_ok
echo Compatibility check passed.
echo Download markers were removed from PowerShell files in this folder.
exit /b 0

:prepare_failed
echo.
echo Live Codex Usage Monitor could not prepare the downloaded PowerShell files.
echo Verify that the folder is writable and that PowerShell 5.1 is available.
call :show_policies
call :maybe_pause
exit /b %PREPARE_EXIT%

:launch_failed
echo.
echo Windows could not create the PowerShell monitor process.
echo Run START-HERE.cmd --check-only from a Command Prompt for diagnostics.
call :maybe_pause
exit /b 2

:missing_files
echo.
echo Live Codex Usage Monitor is incomplete.
echo Missing: "%MONITOR_LAUNCHER%"
echo Download and extract the complete Windows ZIP before starting it.
call :maybe_pause
exit /b 3

:show_policies
echo.
echo Effective PowerShell policies:
powershell.exe -NoLogo -NoProfile -Command "Get-ExecutionPolicy -List | Format-Table -AutoSize"
exit /b 0

:maybe_pause
if /I "%MONITOR_REQUEST%"=="--check-only" exit /b 0
if defined LIVE_CODEX_NO_PAUSE exit /b 0
echo.
pause
exit /b 0
