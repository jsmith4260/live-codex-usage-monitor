Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MonitorPrivacyContract {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        RuntimeNetworkAccess = 'Forbidden'
        PaidServiceCalls = 'Forbidden'
        LocalInputs = @(
            'Existing Codex JSONL logs',
            'Local RTK aggregate savings and health counters',
            'User-selected local personal usage summaries',
            'User-selected local personal activity exports',
            'User-selected local downloaded usage reports'
        )
        NeverPersist = @(
            'Prompt text',
            'Response text',
            'Tool arguments or output',
            'Credentials or cookies',
            'Email addresses or account IDs',
            'Session names or source paths'
        )
        PersistentDataClass = 'Aggregate counters, dates, model labels, and provenance only'
        UserPromise = 'Monitoring itself creates no ChatGPT turns, tokens, credits, API calls, or other paid usage.'
    }
}

function New-UsageProvenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Local Codex log', 'Local RTK savings', 'Imported official report', 'Imported Workspace Analytics', 'Imported Compliance export', 'Bundled rate card')]
        [string]$SourceKind,
        [Parameter(Mandatory = $true)]
        [datetime]$ObservedAt,
        [string]$Freshness = '',
        [string]$Detail = ''
    )

    return [pscustomobject][ordered]@{
        SourceKind = $SourceKind
        ObservedAt = $ObservedAt
        Freshness = $Freshness
        Detail = $Detail
        OutboundRequestMade = $false
    }
}

function Get-MonitorStatePaths {
    [CmdletBinding()]
    param([string]$Root = '')

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $base = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($base)) {
            throw 'Windows LocalApplicationData is unavailable; supply an explicit state root.'
        }
        $Root = Join-Path $base 'LiveCodexUsageMonitor'
    }
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    return [pscustomobject][ordered]@{
        Root = $resolvedRoot
        AggregateStore = Join-Path $resolvedRoot 'aggregate-v1.json'
        GuardPolicy = Join-Path $resolvedRoot 'guard-policy-v1.json'
        CostProfile = Join-Path $resolvedRoot 'cost-profile-v1.json'
        PersonalSettings = Join-Path $resolvedRoot 'personal-settings-v1.json'
        Backups = Join-Path $resolvedRoot 'backups'
        Diagnostics = Join-Path $resolvedRoot 'diagnostics'
        OfficialReports = Join-Path $resolvedRoot 'official-reports'
    }
}

function Test-ZeroOutboundSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    $patterns = @(
        '\bInvoke-WebRequest\b',
        '\bInvoke-RestMethod\b',
        '\bStart-BitsTransfer\b',
        '\bSystem\.Net\.Http',
        '\bHttpClient\b',
        '\bWebClient\b',
        '\bWebRequest\b',
        '\bSockets?\.TcpClient\b',
        '\baccount/usage/read\b',
        '\baccount/rateLimits/read\b',
        '(?m)^\s*(curl|curl\.exe|wget|wget\.exe)\b'
    )
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $path) {
            $lineNumber++
            foreach ($pattern in $patterns) {
                if ($line -match $pattern) {
                    $findings.Add([pscustomobject]@{
                        Path = $path
                        Line = $lineNumber
                        Pattern = $pattern
                    })
                }
            }
        }
    }
    return [pscustomobject][ordered]@{
        Passed = ($findings.Count -eq 0)
        FilesChecked = @($Paths).Count
        Findings = @($findings)
    }
}

function Test-AggregatePrivacyShape {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Value)

    $forbiddenNames = @(
        'Prompt', 'Response', 'MessageText', 'Content', 'Arguments', 'ToolOutput',
        'Email', 'UserId', 'AccountId', 'Session', 'Source', 'Path', 'WorkingDirectory'
    )
    $violations = [System.Collections.Generic.List[string]]::new()

    function Visit-PrivacyValue {
        param([object]$Node, [string]$Location)
        if ($null -eq $Node) { return }
        if ($Node -is [string] -or $Node -is [ValueType]) { return }
        if ($Node -is [System.Collections.IDictionary]) {
            foreach ($key in $Node.Keys) {
                if ($forbiddenNames -contains [string]$key) { $violations.Add("$Location.$key") }
                Visit-PrivacyValue -Node $Node[$key] -Location "$Location.$key"
            }
            return
        }
        if ($Node -is [System.Collections.IEnumerable]) {
            $index = 0
            foreach ($item in $Node) {
                Visit-PrivacyValue -Node $item -Location "$Location[$index]"
                $index++
            }
            return
        }
        foreach ($property in $Node.PSObject.Properties) {
            if ($forbiddenNames -contains $property.Name) { $violations.Add("$Location.$($property.Name)") }
            Visit-PrivacyValue -Node $property.Value -Location "$Location.$($property.Name)"
        }
    }

    Visit-PrivacyValue -Node $Value -Location '$'
    return [pscustomobject][ordered]@{
        Passed = ($violations.Count -eq 0)
        Violations = @($violations | Sort-Object -Unique)
    }
}

Export-ModuleMember -Function @(
    'Get-MonitorPrivacyContract',
    'Get-MonitorStatePaths',
    'New-UsageProvenance',
    'Test-ZeroOutboundSource',
    'Test-AggregatePrivacyShape'
)
