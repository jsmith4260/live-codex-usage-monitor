$scriptDir = Split-Path -Parent $PSCommandPath
$launcher = Join-Path $scriptDir 'Start-Live-Codex-Usage.ps1'
& $launcher -StartMini @args
exit $LASTEXITCODE
