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

$readmePath = Join-Path $scriptDir 'README.md'
$changelogPath = Join-Path $scriptDir 'CHANGELOG.md'
if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) { throw 'README.md is missing.' }
if (-not (Test-Path -LiteralPath $changelogPath -PathType Leaf)) { throw 'CHANGELOG.md is missing.' }
$readmeText = Get-Content -LiteralPath $readmePath -Raw
$changelogText = Get-Content -LiteralPath $changelogPath -Raw
if ($readmeText -notmatch [regex]::Escape("![Version $version]")) {
    throw "README version badge does not match VERSION ($version)."
}
if ($changelogText -notmatch "(?m)^## $([regex]::Escape($version))\s+-\s+") {
    throw "CHANGELOG does not contain a release heading for VERSION ($version)."
}
if ($readmeText -notmatch 'releases/latest/download/live-codex-usage-monitor-windows\.zip') {
    throw 'README does not contain the stable latest Windows release download.'
}

$releaseWorkflowPath = Join-Path $scriptDir '.github\workflows\release.yml'
if (-not (Test-Path -LiteralPath $releaseWorkflowPath -PathType Leaf)) {
    throw 'The tag-driven GitHub Release workflow is missing.'
}
$releaseWorkflowText = Get-Content -LiteralPath $releaseWorkflowPath -Raw
if ($releaseWorkflowText -notmatch 'contents:\s*write' -or
    $releaseWorkflowText -notmatch 'live-codex-usage-monitor-windows\.zip' -or
    $releaseWorkflowText -notmatch 'gh release') {
    throw 'The GitHub Release workflow does not satisfy the stable-download contract.'
}

$localReadmeTargets = [regex]::Matches($readmeText, '\]\((?<target>[^)]+)\)') |
    ForEach-Object { $_.Groups['target'].Value.Trim() } |
    Where-Object {
        $_ -and
        $_ -notmatch '^(?:https?:|mailto:|#)' -and
        $_ -notmatch '^\s*<'
    } |
    ForEach-Object { ($_ -split '#', 2)[0] } |
    Sort-Object -Unique
foreach ($target in $localReadmeTargets) {
    $targetPath = Join-Path $scriptDir ($target -replace '/', '\')
    if (-not (Test-Path -LiteralPath $targetPath)) {
        throw "README local link target is missing: $target"
    }
}

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
    'Live-Codex-Usage-OfficialDashboard.psm1',
    'Live-Codex-Usage-Reports.psm1',
    'Live-Codex-Usage-Compliance.psm1',
    'Live-Codex-Usage-Cost.psm1',
    'Live-Codex-Usage-Efficiency.psm1',
    'Live-Codex-Usage-Guard.psm1',
    'Live-Codex-Usage-Instance.psm1',
    'Live-Codex-Usage-Personal.psm1',
    'Live-Codex-Usage-Privacy.psm1',
    'Live-Codex-Usage-RTK.psm1',
    'Live-Codex-Usage-Reconciliation.psm1',
    'Live-Codex-Usage-Store.psm1',
    'Convert-Enterprise-ComplianceExport.ps1',
    'START-HERE.cmd',
    'Start-Live-Codex-Usage.ps1',
    'Start-Live-Codex-Usage.cmd',
    'Start-Live-Codex-Usage-Mini.ps1',
    'Start-Live-Codex-Usage-Mini.cmd',
    'Test-Live-Codex-Usage.ps1',
    'Test-Live-Codex-Usage.cmd',
    'Test-ZeroOutbound.ps1',
    'Invoke-StaticAnalysis.ps1',
    'README.md',
    'LICENSE',
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
$hashValue = if (Get-Command -Name Get-FileHash -ErrorAction SilentlyContinue) {
    (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
}
else {
    $stream = [System.IO.File]::OpenRead($zipPath)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}
$manifest = '{0} *{1}' -f $hashValue.ToLowerInvariant(), (Split-Path -Leaf $zipPath)
Set-Content -LiteralPath $hashPath -Value $manifest -Encoding Ascii

Write-Output ("Release={0}`nSHA256={1}`nManifest={2}" -f $zipPath, $hashValue.ToLowerInvariant(), $hashPath)
