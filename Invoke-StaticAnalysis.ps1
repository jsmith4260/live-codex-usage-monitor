[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ModulePath,
    [switch]$Detailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
Import-Module -Name $ModulePath -Force

$files = Get-ChildItem -LiteralPath $scriptDir -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.psm1') -and $_.FullName -notmatch '[\\/]artifacts[\\/]' }
$results = @(
    $files | ForEach-Object {
        Invoke-ScriptAnalyzer -Path $_.FullName -Recurse:$false
    }
)

$results |
    Group-Object Severity, RuleName |
    Sort-Object Count -Descending |
    Select-Object Count, Name |
    Format-Table -AutoSize
Write-Output ('AnalyzerFindings={0}; Errors={1}; Warnings={2}' -f $results.Count, @($results | Where-Object Severity -eq 'Error').Count, @($results | Where-Object Severity -eq 'Warning').Count)
if ($Detailed) {
    $results |
        Where-Object { $_.Severity -ne 'Information' } |
        Select-Object Severity, RuleName, ScriptName, Line, Message |
        Format-List
}

if (@($results | Where-Object Severity -eq 'Error').Count -gt 0) { exit 1 }
