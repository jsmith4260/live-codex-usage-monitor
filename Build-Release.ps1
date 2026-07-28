[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $scriptDir 'artifacts'
}
$versionPath = Join-Path $scriptDir 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) { throw 'VERSION file is missing.' }
$version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION is not semantic: $version" }

$parseErrors = [System.Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $scriptDir -Recurse -File | Where-Object {
    $_.Extension -in @('.ps1', '.psm1') -and $_.FullName -notmatch '[\\/]artifacts[\\/]'
}) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($parseError in $errors) {
        $parseErrors.Add(('{0}:{1}: {2}' -f $file.FullName, $parseError.Extent.StartLineNumber, $parseError.Message))
    }
}
if ($parseErrors.Count -gt 0) { throw ($parseErrors -join [Environment]::NewLine) }

if (-not $SkipTests) {
    & (Join-Path $scriptDir 'Test-Live-Codex-Usage.ps1')
    if ($LASTEXITCODE -ne 0) { throw "QA failed with exit code $LASTEXITCODE." }
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $OutputDirectory)
}
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path
$zipPath = Join-Path $resolvedOutput "live-codex-usage-monitor-$version.zip"
$hashPath = "$zipPath.sha256"

$releaseItems = @(
    'Live-Codex-Usage-GUI.ps1',
    'Live-Codex-Usage.ps1',
    'Live-Codex-Usage-Enterprise.psm1',
    'Live-Codex-Usage-Compliance.psm1',
    'Live-Codex-Usage-Cost.psm1',
    'Live-Codex-Usage-Guard.psm1',
    'Live-Codex-Usage-Privacy.psm1',
    'Live-Codex-Usage-RTK.psm1',
    'Live-Codex-Usage-Reconciliation.psm1',
    'Live-Codex-Usage-Store.psm1',
    'Convert-Enterprise-ComplianceExport.ps1',
    'Start-Live-Codex-Usage.ps1',
    'Start-Live-Codex-Usage.cmd',
    'Start-Live-Codex-Usage-Mini.ps1',
    'Start-Live-Codex-Usage-Mini.cmd',
    'Test-Live-Codex-Usage.ps1',
    'Test-Live-Codex-Usage.cmd',
    'Test-ZeroOutbound.ps1',
    'Invoke-StaticAnalysis.ps1',
    'README.md',
    'SECURITY.md',
    'CHANGELOG.md',
    'VERSION',
    'docs',
    'config',
    'tests'
)
$releasePaths = foreach ($item in $releaseItems) {
    $path = Join-Path $scriptDir $item
    if (-not (Test-Path -LiteralPath $path)) { throw "Release input is missing: $item" }
    $path
}

Compress-Archive -LiteralPath $releasePaths -DestinationPath $zipPath -CompressionLevel Optimal -Force
$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
$manifest = '{0} *{1}' -f $hash.Hash.ToLowerInvariant(), (Split-Path -Leaf $zipPath)
Set-Content -LiteralPath $hashPath -Value $manifest -Encoding Ascii

Write-Output ("Release={0}`nSHA256={1}`nManifest={2}" -f $zipPath, $hash.Hash.ToLowerInvariant(), $hashPath)
