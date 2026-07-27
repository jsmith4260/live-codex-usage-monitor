<#
Converts a locally exported Compliance Logs JSONL file into content-free daily
aggregates. Field locations are supplied in a mapping JSON file because the
authenticated Enterprise/Edu schema can evolve independently of this project.

This script does not call a network service and does not write raw events.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$MappingPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $scriptDir 'Live-Codex-Usage-Compliance.psm1') -Force

$result = Convert-ComplianceExport -InputPath $InputPath -MappingPath $MappingPath -OutputPath $OutputPath
Write-Output ('ComplianceRows={0}; InvalidLines={1}; OutputRows={2}; Output={3}' -f $result.InputRows, $result.InvalidLines, $result.OutputRows, $OutputPath)
