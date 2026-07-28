[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
Import-Module -Name (Join-Path $scriptDir 'Live-Codex-Usage-Privacy.psm1') -Force

$runtimeFiles = @(
    Get-ChildItem -LiteralPath $scriptDir -File |
        Where-Object {
            $_.Extension -in @('.ps1', '.psm1') -and
            $_.Name -notin @(
                'Test-Live-Codex-Usage.ps1',
                'Test-ZeroOutbound.ps1',
                'Build-Release.ps1',
                'Install-PSScriptAnalyzer.ps1',
                'Invoke-StaticAnalysis.ps1',
                'Live-Codex-Usage-Privacy.psm1'
            )
        } |
        Select-Object -ExpandProperty FullName
)
$result = Test-ZeroOutboundSource -Paths $runtimeFiles
if (-not $result.Passed) {
    $details = $result.Findings | ForEach-Object { '{0}:{1} matched {2}' -f $_.Path, $_.Line, $_.Pattern }
    throw "Zero-outbound gate failed.`n$($details -join [Environment]::NewLine)"
}
Write-Output ('ZeroOutbound=True; FilesChecked={0}' -f $result.FilesChecked)
