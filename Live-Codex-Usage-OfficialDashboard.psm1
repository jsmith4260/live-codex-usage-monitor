Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-OptionalDashboardCount {
    param([object]$Value, [string]$FieldName)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $text = ([string]$Value).Trim().Replace(',', '')
    [Int64]$parsed = 0
    if (-not [Int64]::TryParse($text, [System.Globalization.NumberStyles]::Integer,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed) -or $parsed -lt 0) {
        throw "Official dashboard $FieldName must be a non-negative whole number or blank."
    }
    return $parsed
}

function New-OfficialDashboardSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][datetime]$PeriodStart,
        [Parameter(Mandatory = $true)][datetime]$PeriodEnd,
        [datetime]$ObservedAt = (Get-Date),
        [ValidateSet('7D','1M','Custom')][string]$RangeKind = 'Custom',
        [ValidateSet('Day','Week','Month')][string]$GroupBy = 'Day',
        [object]$Turns = $null,
        [object]$PluginCalls = $null,
        [object]$LinesOfCode = $null,
        [object]$SkillsUsed = $null,
        [object]$CreditsUsed = $null,
        [object]$TokensUsed = $null
    )

    if ($PeriodEnd.Date -lt $PeriodStart.Date) { throw 'Official dashboard period end cannot be before period start.' }
    $values = [ordered]@{
        Turns = ConvertTo-OptionalDashboardCount -Value $Turns -FieldName 'turns'
        PluginCalls = ConvertTo-OptionalDashboardCount -Value $PluginCalls -FieldName 'plugin calls'
        LinesOfCode = ConvertTo-OptionalDashboardCount -Value $LinesOfCode -FieldName 'lines of code'
        SkillsUsed = ConvertTo-OptionalDashboardCount -Value $SkillsUsed -FieldName 'skills used'
        CreditsUsed = ConvertTo-OptionalDashboardCount -Value $CreditsUsed -FieldName 'credits used'
        TokensUsed = ConvertTo-OptionalDashboardCount -Value $TokensUsed -FieldName 'tokens used'
    }
    if (@($values.Values | Where-Object { $null -ne $_ }).Count -eq 0) {
        throw 'Enter at least one aggregate visible in the official dashboard.'
    }
    return [pscustomobject][ordered]@{
        ObservedAt = $ObservedAt.ToUniversalTime().ToString('o')
        PeriodStart = $PeriodStart.Date.ToString('yyyy-MM-dd')
        PeriodEnd = $PeriodEnd.Date.ToString('yyyy-MM-dd')
        RangeKind = $RangeKind
        GroupBy = $GroupBy
        Turns = $values.Turns
        PluginCalls = $values.PluginCalls
        LinesOfCode = $values.LinesOfCode
        SkillsUsed = $values.SkillsUsed
        CreditsUsed = $values.CreditsUsed
        TokensUsed = $values.TokensUsed
    }
}

function New-OfficialDashboardHistory {
    [CmdletBinding()]
    param([object[]]$Snapshots = @())

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-official-dashboard-no-content-no-identifiers'
        Snapshots = @($Snapshots | Sort-Object { [datetime]$_.ObservedAt })
    }
}

function Read-OfficialDashboardHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return (New-OfficialDashboardHistory) }
    $history = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$history.SchemaVersion -ne 1 -or
        [string]$history.PrivacyClass -ne 'aggregate-official-dashboard-no-content-no-identifiers') {
        throw 'The official dashboard history schema or privacy class is unsupported.'
    }
    $validated = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @($history.Snapshots)) {
        $validated.Add((New-OfficialDashboardSnapshot `
            -PeriodStart ([datetime]$row.PeriodStart) -PeriodEnd ([datetime]$row.PeriodEnd) `
            -ObservedAt ([datetime]$row.ObservedAt) -RangeKind ([string]$row.RangeKind) -GroupBy ([string]$row.GroupBy) `
            -Turns $row.Turns -PluginCalls $row.PluginCalls -LinesOfCode $row.LinesOfCode `
            -SkillsUsed $row.SkillsUsed -CreditsUsed $row.CreditsUsed -TokensUsed $row.TokensUsed))
    }
    return (New-OfficialDashboardHistory -Snapshots @($validated))
}

function Write-OfficialDashboardHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$History
    )

    if ([int]$History.SchemaVersion -ne 1 -or
        [string]$History.PrivacyClass -ne 'aggregate-official-dashboard-no-content-no-identifiers') {
        throw 'Refusing to write official dashboard history without its aggregate-only privacy class.'
    }
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $History | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Add-OfficialDashboardSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Snapshot
    )

    $validated = New-OfficialDashboardSnapshot `
        -PeriodStart ([datetime]$Snapshot.PeriodStart) -PeriodEnd ([datetime]$Snapshot.PeriodEnd) `
        -ObservedAt ([datetime]$Snapshot.ObservedAt) -RangeKind ([string]$Snapshot.RangeKind) -GroupBy ([string]$Snapshot.GroupBy) `
        -Turns $Snapshot.Turns -PluginCalls $Snapshot.PluginCalls -LinesOfCode $Snapshot.LinesOfCode `
        -SkillsUsed $Snapshot.SkillsUsed -CreditsUsed $Snapshot.CreditsUsed -TokensUsed $Snapshot.TokensUsed
    $history = Read-OfficialDashboardHistory -Path $Path
    $items = @($history.Snapshots) + @($validated)
    $updated = New-OfficialDashboardHistory -Snapshots $items
    Write-OfficialDashboardHistory -Path $Path -History $updated
    return $updated
}

function Get-OfficialDashboardReconciliation {
    [CmdletBinding()]
    param(
        [object[]]$UsageEvents = @(),
        [object[]]$IntegrationEvents = @(),
        [Parameter(Mandatory = $true)][object]$History
    )

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($snapshot in @($History.Snapshots | Sort-Object { [datetime]$_.ObservedAt } -Descending)) {
        $start = ([datetime]$snapshot.PeriodStart).Date
        $end = ([datetime]$snapshot.PeriodEnd).Date
        $localTurns = @($UsageEvents | Where-Object {
            $null -ne $_ -and $_.PSObject.Properties['At'] -and ([datetime]$_.At).Date -ge $start -and ([datetime]$_.At).Date -le $end
        }).Count
        $localPluginCalls = @($IntegrationEvents | Where-Object {
            $null -ne $_ -and $_.PSObject.Properties['At'] -and ([datetime]$_.At).Date -ge $start -and ([datetime]$_.At).Date -le $end
        }).Count
        $turnVariance = if ($null -eq $snapshot.Turns) { $null } else { [Int64]$localTurns - [Int64]$snapshot.Turns }
        $pluginVariance = if ($null -eq $snapshot.PluginCalls) { $null } else { [Int64]$localPluginCalls - [Int64]$snapshot.PluginCalls }
        $comparable = @(@($turnVariance, $pluginVariance) | Where-Object { $null -ne $_ })
        $status = if ($comparable.Count -eq 0) { 'Official-only metrics' }
        elseif (@($comparable | Where-Object { $_ -ne 0 }).Count -eq 0) { 'Aligned' }
        elseif (@($comparable | Where-Object { $_ -gt 0 }).Count -gt 0) { 'Local higher' }
        else { 'Official higher' }
        $results.Add([pscustomobject][ordered]@{
            ObservedAt = ([datetime]$snapshot.ObservedAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm')
            Period = ('{0} to {1}' -f ([string]$snapshot.PeriodStart), ([string]$snapshot.PeriodEnd))
            OfficialTurns = $snapshot.Turns
            LocalTurns = [Int64]$localTurns
            TurnVariance = $turnVariance
            OfficialPluginCalls = $snapshot.PluginCalls
            LocalPluginCalls = [Int64]$localPluginCalls
            PluginVariance = $pluginVariance
            LinesOfCode = $snapshot.LinesOfCode
            SkillsUsed = $snapshot.SkillsUsed
            CreditsUsed = $snapshot.CreditsUsed
            TokensUsed = $snapshot.TokensUsed
            Status = $status
        })
    }
    return @($results)
}

Export-ModuleMember -Function @(
    'New-OfficialDashboardSnapshot',
    'New-OfficialDashboardHistory',
    'Read-OfficialDashboardHistory',
    'Write-OfficialDashboardHistory',
    'Add-OfficialDashboardSnapshot',
    'Get-OfficialDashboardReconciliation'
)
