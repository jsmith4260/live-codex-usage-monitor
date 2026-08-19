Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-UsageReportTimeZone {
    [CmdletBinding()]
    param([string]$TimeZoneId = 'Local')
    if ([string]::IsNullOrWhiteSpace($TimeZoneId) -or $TimeZoneId -eq 'Local') { return [TimeZoneInfo]::Local }
    if ($TimeZoneId -eq 'UTC') { return [TimeZoneInfo]::Utc }
    try { return [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId) }
    catch { throw "The selected reporting time zone is unavailable: $TimeZoneId" }
}

function Get-UsageReportPeriod {
    param([datetime]$At, [ValidateSet('Daily','Weekly','Monthly','Session')][string]$GroupBy, [TimeZoneInfo]$TimeZone)
    $local = [TimeZoneInfo]::ConvertTime($At, $TimeZone)
    switch ($GroupBy) {
        'Daily' { return $local.ToString('yyyy-MM-dd') }
        'Monthly' { return $local.ToString('yyyy-MM') }
        'Weekly' {
            $delta = (([int]$local.DayOfWeek + 6) % 7)
            return $local.Date.AddDays(-$delta).ToString('yyyy-MM-dd')
        }
        default { return '' }
    }
}

function Get-ReportInt64 {
    param([object]$Value)
    if ($null -eq $Value) { return [int64]0 }
    try { return [int64]$Value } catch { return [int64]0 }
}

function New-PrivacySafeUsageReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$UsageEvents,
        [ValidateSet('Daily','Weekly','Monthly','Session')][string]$GroupBy = 'Daily',
        [string]$TimeZoneId = 'Local'
    )
    $zone = Resolve-UsageReportTimeZone -TimeZoneId $TimeZoneId
    $groups = @{}
    foreach ($event in @($UsageEvents)) {
        if ($null -eq $event -or $null -eq $event.At) { continue }
        $period = Get-UsageReportPeriod -At ([datetime]$event.At) -GroupBy $GroupBy -TimeZone $zone
        if ($GroupBy -eq 'Session') { $period = [string]$event.Session }
        $key = '{0}|{1}' -f [string]$event.Source, $period
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [ordered]@{ Source=[string]$event.Source; Period=$period; Events=0; FreshBurn=[int64]0; NewInput=[int64]0; Output=[int64]0; Reasoning=[int64]0; Cached=[int64]0; Context=[int64]0; Models=[System.Collections.Generic.HashSet[string]]::new() }
        }
        $row = $groups[$key]
        $row.Events++
        foreach ($name in @('FreshBurn','NewInput','Output','Reasoning','Cached','Total')) {
            $target = if ($name -eq 'Total') { 'Context' } else { $name }
            $row[$target] = [int64]$row[$target] + (Get-ReportInt64 -Value $event.$name)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$event.Model)) { [void]$row.Models.Add([string]$event.Model) }
    }
    $sessionNames = @($groups.Values | Where-Object { $GroupBy -eq 'Session' } | Sort-Object @{Expression={ $_.Period };Descending=$true})
    $sessionMap = @{}
    for ($index = 0; $index -lt $sessionNames.Count; $index++) { $sessionMap[$sessionNames[$index].Period] = 'Session {0}' -f ($index + 1) }
    $rows = foreach ($row in $groups.Values) {
        [pscustomobject][ordered]@{
            Source=$row.Source
            Period=$(if ($GroupBy -eq 'Session') { $sessionMap[$row.Period] } else { $row.Period })
            Events=$row.Events
            FreshBurn=$row.FreshBurn
            NewInput=$row.NewInput
            Output=$row.Output
            Reasoning=$row.Reasoning
            Cached=$row.Cached
            Context=$row.Context
            Models=@($row.Models | Sort-Object)
        }
    }
    return [pscustomobject][ordered]@{
        SchemaVersion=1
        PrivacyClass='aggregate-no-content-no-titles-no-paths-no-session-identifiers'
        GroupBy=$GroupBy
        TimeZoneId=$zone.Id
        Rows=@($rows | Sort-Object Period,Source)
    }
}

function Export-PrivacySafeUsageReport {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Report, [Parameter(Mandatory = $true)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Path $parent) }
    $Report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Report
}

Export-ModuleMember -Function @('Resolve-UsageReportTimeZone','New-PrivacySafeUsageReport','Export-PrivacySafeUsageReport')
