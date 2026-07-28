Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-UsageGuardPolicy {
    [CmdletBinding()]
    param(
        [bool]$Enabled = $false,
        [ValidateSet('Advisory', 'Enforced')]
        [string]$Mode = 'Advisory',
        [ValidateSet('EstimatedCredits', 'FreshBurn', 'ApiEquivalentUsd', 'ActualUsd', 'QuotaPercent')]
        [string]$Metric = 'EstimatedCredits',
        [decimal]$Threshold = 100,
        [ValidateRange(0, 3600)]
        [int]$GraceSeconds = 30,
        [string[]]$ApprovedExecutablePaths = @()
    )

    if ($Threshold -le 0) { throw 'The usage guard threshold must be greater than zero.' }
    $paths = @($ApprovedExecutablePaths | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    } | ForEach-Object {
        [System.IO.Path]::GetFullPath([string]$_)
    } | Sort-Object -Unique)
    if ($Enabled -and $Mode -eq 'Enforced' -and $paths.Count -eq 0) {
        throw 'Enforced mode requires at least one exact, user-approved Codex executable path.'
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        Enabled = $Enabled
        Mode = $Mode
        Metric = $Metric
        Threshold = $Threshold
        GraceSeconds = $GraceSeconds
        ApprovedExecutablePaths = @($paths)
        Locked = $false
        ThresholdCrossedAt = $null
        LockedAt = $null
        LockReason = ''
        LastAffirmativeUnlockAt = $null
        OverrideUntil = $null
    }
}

function Import-UsageGuardPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-UsageGuardPolicy
    }
    $policy = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$policy.SchemaVersion -ne 1) { throw 'Unsupported usage guard policy schema.' }
    if ([string]$policy.Mode -notin @('Advisory', 'Enforced')) { throw 'Invalid usage guard mode.' }
    if ([string]$policy.Metric -notin @('EstimatedCredits', 'FreshBurn', 'ApiEquivalentUsd', 'ActualUsd', 'QuotaPercent')) {
        throw 'Invalid usage guard metric.'
    }
    if ([decimal]$policy.Threshold -le 0) { throw 'Invalid usage guard threshold.' }
    if ([bool]$policy.Enabled -and [string]$policy.Mode -eq 'Enforced' -and @($policy.ApprovedExecutablePaths).Count -eq 0) {
        throw 'Enforced guard policy has no approved executable paths.'
    }
    return $policy
}

function Export-UsageGuardPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and
        -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Policy | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Test-UsageGuardThreshold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][decimal]$CurrentValue,
        [datetime]$AsOf = (Get-Date)
    )

    if (-not [bool]$Policy.Enabled) {
        return [pscustomobject]@{
            Crossed = $false; EnforcementDue = $false; RemainingGraceSeconds = 0; Reason = 'Guard disabled'
        }
    }
    if ($null -ne $Policy.PSObject.Properties['OverrideUntil'] -and
        $null -ne $Policy.OverrideUntil -and
        -not [string]::IsNullOrWhiteSpace([string]$Policy.OverrideUntil)) {
        $overrideUntil = [datetime]::Parse([string]$Policy.OverrideUntil)
        if ($AsOf -lt $overrideUntil) {
            return [pscustomobject]@{
                Crossed = $false; EnforcementDue = $false
                RemainingGraceSeconds = [int][Math]::Ceiling(($overrideUntil - $AsOf).TotalSeconds)
                Reason = ('Affirmatively renewed until {0}' -f $overrideUntil.ToString('g'))
            }
        }
        $Policy.OverrideUntil = $null
    }
    $crossed = $CurrentValue -ge [decimal]$Policy.Threshold
    if (-not $crossed) {
        $Policy.ThresholdCrossedAt = $null
        return [pscustomobject]@{
            Crossed = $false; EnforcementDue = $false; RemainingGraceSeconds = 0
            Reason = ('{0} {1:N4} is below threshold {2:N4}' -f $Policy.Metric, $CurrentValue, $Policy.Threshold)
        }
    }
    if ($null -eq $Policy.ThresholdCrossedAt -or [string]::IsNullOrWhiteSpace([string]$Policy.ThresholdCrossedAt)) {
        $Policy.ThresholdCrossedAt = $AsOf.ToString('o')
    }
    $crossedAt = [datetime]::Parse([string]$Policy.ThresholdCrossedAt)
    $elapsed = [Math]::Max(0, ($AsOf - $crossedAt).TotalSeconds)
    $remaining = [Math]::Max(0, [int][Math]::Ceiling([int]$Policy.GraceSeconds - $elapsed))
    return [pscustomobject]@{
        Crossed = $true
        EnforcementDue = ($remaining -eq 0)
        RemainingGraceSeconds = $remaining
        Reason = ('{0} {1:N4} reached threshold {2:N4}' -f $Policy.Metric, $CurrentValue, $Policy.Threshold)
    }
}

function Lock-UsageGuardPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][string]$Reason,
        [datetime]$AsOf = (Get-Date)
    )

    $Policy.Locked = $true
    $Policy.LockedAt = $AsOf.ToString('o')
    $Policy.LockReason = $Reason
    return $Policy
}

function Unlock-UsageGuardPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][string]$Confirmation,
        [datetime]$AsOf = (Get-Date),
        [datetime]$OverrideUntil = [datetime]::MinValue
    )

    if ($Confirmation -cne 'REENABLE CODEX') {
        throw 'Affirmative unlock requires the exact confirmation REENABLE CODEX.'
    }
    $Policy.Locked = $false
    $Policy.LockedAt = $null
    $Policy.LockReason = ''
    $Policy.ThresholdCrossedAt = $null
    $Policy.LastAffirmativeUnlockAt = $AsOf.ToString('o')
    if ($OverrideUntil -eq [datetime]::MinValue) {
        $OverrideUntil = $AsOf.Date.AddDays(1)
    }
    if ($OverrideUntil -le $AsOf) { throw 'The renewal end time must be in the future.' }
    if ($null -eq $Policy.PSObject.Properties['OverrideUntil']) {
        $Policy | Add-Member -NotePropertyName OverrideUntil -NotePropertyValue $OverrideUntil.ToString('o')
    }
    else {
        $Policy.OverrideUntil = $OverrideUntil.ToString('o')
    }
    return $Policy
}

function Get-ApprovedGuardProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [scriptblock]$ProcessProvider
    )

    if ($null -eq $ProcessProvider) {
        $ProcessProvider = {
            $rows = [System.Collections.Generic.List[object]]::new()
            foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
                $path = ''
                try { $path = [string]$process.Path } catch { }
                if ([string]::IsNullOrWhiteSpace($path)) { continue }
                $rows.Add([pscustomobject]@{
                    Id = $process.Id
                    ProcessName = $process.ProcessName
                    Path = $path
                })
            }
            return @($rows)
        }
    }
    $approved = @{}
    foreach ($path in @($Policy.ApprovedExecutablePaths)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
            $approved[[System.IO.Path]::GetFullPath([string]$path).ToLowerInvariant()] = $true
        }
    }
    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in @(& $ProcessProvider)) {
        if ($null -eq $candidate -or [string]::IsNullOrWhiteSpace([string]$candidate.Path)) { continue }
        $fullPath = [System.IO.Path]::GetFullPath([string]$candidate.Path).ToLowerInvariant()
        if ($approved.ContainsKey($fullPath)) { $matches.Add($candidate) }
    }
    return @($matches)
}

function Invoke-UsageGuardEnforcement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [scriptblock]$ProcessProvider,
        [scriptblock]$StopProvider
    )

    if (-not [bool]$Policy.Enabled -or -not [bool]$Policy.Locked) {
        return [pscustomobject]@{ Examined = 0; Stopped = 0; Mode = [string]$Policy.Mode }
    }
    if ([string]$Policy.Mode -ne 'Enforced') {
        return [pscustomobject]@{ Examined = 0; Stopped = 0; Mode = 'Advisory' }
    }
    if (@($Policy.ApprovedExecutablePaths).Count -eq 0) {
        throw 'Enforced guard has no exact approved executable paths.'
    }
    if ($null -eq $StopProvider) {
        $StopProvider = {
            param($Candidate)
            Stop-Process -Id ([int]$Candidate.Id) -Force -ErrorAction Stop
        }
    }
    $matches = @(Get-ApprovedGuardProcesses -Policy $Policy -ProcessProvider $ProcessProvider)
    $stopped = 0
    foreach ($candidate in $matches) {
        & $StopProvider $candidate
        $stopped++
    }
    return [pscustomobject]@{
        Examined = $matches.Count
        Stopped = $stopped
        Mode = 'Enforced'
    }
}

Export-ModuleMember -Function @(
    'New-UsageGuardPolicy',
    'Import-UsageGuardPolicy',
    'Export-UsageGuardPolicy',
    'Test-UsageGuardThreshold',
    'Lock-UsageGuardPolicy',
    'Unlock-UsageGuardPolicy',
    'Get-ApprovedGuardProcesses',
    'Invoke-UsageGuardEnforcement'
)
