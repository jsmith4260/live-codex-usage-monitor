Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-PrivacySafeAggregateSnapshot {
    [CmdletBinding()]
    param(
        [object[]]$UsageEvents,
        [object[]]$IntegrationEvents,
        [datetime]$GeneratedAt = (Get-Date)
    )

    $daily = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($UsageEvents | Group-Object { $_.At.Date } | Sort-Object Name)) {
        $items = @($group.Group)
        [Int64]$newInput = 0
        [Int64]$cached = 0
        [Int64]$output = 0
        [Int64]$reasoning = 0
        [Int64]$context = 0
        foreach ($item in $items) {
            $newInput += [Int64]$item.NewInput
            $cached += [Int64]$item.Cached
            $output += [Int64]$item.Output
            $reasoning += [Int64]$item.Reasoning
            $context += [Int64]$item.Total
        }
        $date = ([datetime]$items[0].At).Date
        $models = @($items | ForEach-Object {
            if ($_.PSObject.Properties['Model'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Model)) {
                [string]$_.Model
            }
            else { 'unknown' }
        } | Sort-Object -Unique)
        $daily.Add([pscustomobject][ordered]@{
            Date = $date.ToString('yyyy-MM-dd')
            Events = $items.Count
            Sessions = @($items | Select-Object -ExpandProperty Session -Unique).Count
            Models = @($models)
            NewInput = $newInput
            CachedInput = $cached
            Output = $output
            ReasoningSubset = $reasoning
            Context = $context
            FreshBurn = $newInput + $output
            IntegrationCalls = @($IntegrationEvents | Where-Object { $_.At.Date -eq $date }).Count
        })
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-no-content-no-identifiers'
        GeneratedAt = $GeneratedAt.ToString('o')
        Daily = @($daily)
    }
}

function Merge-PrivacySafeAggregateSnapshot {
    [CmdletBinding()]
    param(
        [object]$Existing,
        [Parameter(Mandatory = $true)]
        [object]$Incoming
    )

    $byDate = @{}
    if ($null -ne $Existing -and $null -ne $Existing.PSObject.Properties['Daily']) {
        foreach ($row in @($Existing.Daily)) { $byDate[[string]$row.Date] = $row }
    }
    foreach ($row in @($Incoming.Daily)) { $byDate[[string]$row.Date] = $row }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-no-content-no-identifiers'
        GeneratedAt = (Get-Date).ToString('o')
        Daily = @($byDate.Values | Sort-Object Date)
    }
}

function Read-PrivacySafeAggregateStore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $store = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$store.SchemaVersion -ne 1 -or
        [string]$store.PrivacyClass -ne 'aggregate-no-content-no-identifiers') {
        throw 'The aggregate store schema or privacy class is unsupported.'
    }
    return $store
}

function Write-PrivacySafeAggregateStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Snapshot
    )

    if ([int]$Snapshot.SchemaVersion -ne 1 -or
        [string]$Snapshot.PrivacyClass -ne 'aggregate-no-content-no-identifiers') {
        throw 'Refusing to write a store without the aggregate-only privacy class.'
    }
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and
        -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Get-UsageForecast {
    [CmdletBinding()]
    param(
        [object[]]$DailyRows,
        [datetime]$AsOf = (Get-Date).Date
    )

    $monthStart = Get-Date -Year $AsOf.Year -Month $AsOf.Month -Day 1
    $monthEnd = $monthStart.AddMonths(1).AddDays(-1)
    $monthRows = @($DailyRows | Where-Object {
        $date = [datetime]::Parse([string]$_.Date)
        $date -ge $monthStart -and $date -le $AsOf
    })
    $recent = @($monthRows | Sort-Object Date -Descending | Select-Object -First 7)
    [decimal]$observed = 0
    foreach ($row in $monthRows) { $observed += [decimal]$row.FreshBurn }
    [decimal]$recentTotal = 0
    foreach ($row in $recent) { $recentTotal += [decimal]$row.FreshBurn }
    $dailyAverage = if ($recent.Count -gt 0) { $recentTotal / [decimal]$recent.Count } else { [decimal]0 }
    $remainingDays = [Math]::Max(0, ($monthEnd - $AsOf.Date).Days)
    return [pscustomobject][ordered]@{
        AsOf = $AsOf.Date.ToString('yyyy-MM-dd')
        ObservedFreshBurn = [Int64]$observed
        RecentDailyAverage = [Int64]$dailyAverage
        RemainingDays = $remainingDays
        ForecastMonthFreshBurn = [Int64]($observed + ($dailyAverage * $remainingDays))
        Method = 'Observed month-to-date plus trailing 7 observed-day average'
    }
}

function Get-UsageTrendRows {
    [CmdletBinding()]
    param(
        [object[]]$UsageEvents,
        [object[]]$DailyCosts = @()
    )

    $costByDate = @{}
    foreach ($cost in @($DailyCosts)) { $costByDate[[string]$cost.Date] = $cost }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($UsageEvents | Group-Object { $_.At.Date } | Sort-Object Name)) {
        $items = @($group.Group)
        $date = ([datetime]$items[0].At).ToString('yyyy-MM-dd')
        [Int64]$newInput = 0
        [Int64]$cached = 0
        [Int64]$output = 0
        [Int64]$context = 0
        foreach ($item in $items) {
            $newInput += [Int64]$item.NewInput
            $cached += [Int64]$item.Cached
            $output += [Int64]$item.Output
            $context += [Int64]$item.Total
        }
        $cost = if ($costByDate.ContainsKey($date)) { $costByDate[$date] } else { $null }
        $rows.Add([pscustomobject][ordered]@{
            Date = $date
            FreshBurn = $newInput + $output
            NewInput = $newInput
            Output = $output
            CachedInput = $cached
            Context = $context
            CachePercent = if (($newInput + $cached) -gt 0) {
                [Math]::Round(($cached / [double]($newInput + $cached)) * 100, 1)
            } else { 0 }
            Events = $items.Count
            Sessions = @($items | Select-Object -ExpandProperty Session -Unique).Count
            EstimatedCredits = if ($null -ne $cost) { [decimal]$cost.EstimatedCredits } else { [decimal]0 }
            ApiEquivalentUsd = if ($null -ne $cost) { [decimal]$cost.ApiEquivalentUsd } else { [decimal]0 }
            UnpricedTokens = if ($null -ne $cost) { [Int64]$cost.UnpricedTokens } else { [Int64]0 }
        })
    }
    return @($rows)
}

function Get-HourlyUsageHeatmap {
    [CmdletBinding()]
    param([object[]]$UsageEvents)

    $buckets = @{}
    foreach ($event in @($UsageEvents)) {
        if ($null -eq $event) { continue }
        $at = [datetime]$event.At
        $key = '{0}|{1}' -f [int]$at.DayOfWeek, $at.Hour
        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = [pscustomobject]@{ Events = [int]0; FreshBurn = [int64]0 }
        }
        $buckets[$key].Events++
        $buckets[$key].FreshBurn += [int64]$event.FreshBurn
    }
    $cells = [System.Collections.Generic.List[object]]::new()
    foreach ($day in 0..6) {
        foreach ($hour in 0..23) {
            $key = '{0}|{1}' -f $day, $hour
            $bucket = if ($buckets.ContainsKey($key)) { $buckets[$key] } else {
                [pscustomobject]@{ Events = [int]0; FreshBurn = [int64]0 }
            }
            $cells.Add([pscustomobject][ordered]@{
                DayNumber = $day
                Day = ([System.DayOfWeek]$day).ToString()
                Hour = $hour
                Events = $bucket.Events
                FreshBurn = $bucket.FreshBurn
            })
        }
    }
    return @($cells)
}

function Get-ModelUsageBreakdown {
    [CmdletBinding()]
    param(
        [object[]]$UsageEvents,
        [object[]]$CostDetails = @()
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($UsageEvents | Group-Object {
        if ($_.PSObject.Properties['Model'] -and -not [string]::IsNullOrWhiteSpace([string]$_.Model)) {
            [string]$_.Model
        } else { 'unknown' }
    })) {
        $items = @($group.Group)
        [Int64]$fresh = 0
        [Int64]$context = 0
        foreach ($item in $items) {
            $fresh += [Int64]$item.FreshBurn
            $context += [Int64]$item.Total
        }
        $modelCosts = @($CostDetails | Where-Object { [string]$_.Model -ieq [string]$group.Name })
        [decimal]$credits = 0
        [decimal]$apiUsd = 0
        foreach ($cost in $modelCosts) {
            $credits += [decimal]$cost.EstimatedCredits
            $apiUsd += [decimal]$cost.ApiEquivalentUsd
        }
        $rows.Add([pscustomobject][ordered]@{
            Model = [string]$group.Name
            Events = $items.Count
            Sessions = @($items | Select-Object -ExpandProperty Session -Unique).Count
            FreshBurn = $fresh
            Context = $context
            EstimatedCredits = [Math]::Round($credits, 4)
            ApiEquivalentUsd = [Math]::Round($apiUsd, 4)
        })
    }
    return @($rows | Sort-Object FreshBurn -Descending)
}

Export-ModuleMember -Function @(
    'New-PrivacySafeAggregateSnapshot',
    'Merge-PrivacySafeAggregateSnapshot',
    'Read-PrivacySafeAggregateStore',
    'Write-PrivacySafeAggregateStore',
    'Get-UsageForecast',
    'Get-UsageTrendRows',
    'Get-HourlyUsageHeatmap',
    'Get-ModelUsageBreakdown'
)
