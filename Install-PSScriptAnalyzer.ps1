[CmdletBinding()]
param(
    [string]$RequiredVersion = '1.25.0',
    [ValidateRange(1, 5)]
    [int]$Attempts = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RequiredAnalyzer {
    Get-Module PSScriptAnalyzer -ListAvailable |
        Where-Object { $_.Version.ToString() -eq $RequiredVersion } |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

$module = Get-RequiredAnalyzer
if ($null -ne $module) {
    Write-Output $module.Path
    return
}

$lastFailure = $null
for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($null -eq $gallery) {
            Register-PSRepository -Default -ErrorAction Stop
        }
        $previousProtocol = [System.Net.ServicePointManager]::SecurityProtocol
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor
                [System.Net.SecurityProtocolType]::Tls12
            Install-Module PSScriptAnalyzer -RequiredVersion $RequiredVersion `
                -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        }
        finally {
            [System.Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        }
        $module = Get-RequiredAnalyzer
        if ($null -eq $module) {
            throw "PSScriptAnalyzer $RequiredVersion was not available after installation."
        }
        Write-Output $module.Path
        return
    }
    catch {
        $lastFailure = $_.Exception.Message
        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

throw "PSScriptAnalyzer $RequiredVersion could not be prepared after $Attempts attempt(s): $lastFailure"
