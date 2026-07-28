Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RecordValue {
    param(
        [object]$Record,
        [string[]]$Names
    )

    if ($null -eq $Record) { return $null }
    foreach ($name in $Names) {
        $property = @($Record.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1)
        if ($property.Count -gt 0 -and $null -ne $property[0].Value -and
            -not [string]::IsNullOrWhiteSpace([string]$property[0].Value)) {
            return $property[0].Value
        }
    }
    return $null
}

function ConvertTo-SnapshotDecimal {
    param(
        [object]$Value,
        [string]$FieldName
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return [decimal]0 }
    $text = ([string]$Value).Trim().Replace(',', '')
    $parsed = [decimal]0
    if (-not [decimal]::TryParse(
            $text,
            [System.Globalization.NumberStyles]::Number,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)) {
        throw "Official snapshot field '$FieldName' is not numeric."
    }
    if ($parsed -lt 0) { throw "Official snapshot field '$FieldName' cannot be negative." }
    return $parsed
}

function Import-OfficialUsageSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Official usage snapshot not found: $Path"
    }
    $file = Get-Item -LiteralPath $Path
    $extension = $file.Extension.ToLowerInvariant()
    if ($extension -eq '.csv') {
        $records = @(Import-Csv -LiteralPath $file.FullName)
    }
    elseif ($extension -eq '.json') {
        $json = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $json.PSObject.Properties['Records']) { $records = @($json.Records) }
        else { $records = @($json) }
    }
    else {
        throw 'Official usage snapshots must be CSV or JSON.'
    }
    if ($records.Count -eq 0) { throw 'The official usage snapshot contains no rows.' }

    $sanitized = [System.Collections.Generic.List[object]]::new()
    $reportedUpdates = [System.Collections.Generic.List[datetime]]::new()
    foreach ($record in $records) {
        $rawDate = Get-RecordValue -Record $record -Names @('Date', 'UsageDate', 'usage_date', 'BucketDate', 'bucket_date', 'StartDate')
        if ($null -eq $rawDate) { throw 'Each official snapshot row must include Date.' }
        $date = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$rawDate, [ref]$date)) {
            throw "Official snapshot Date '$rawDate' is invalid."
        }
        $surface = [string](Get-RecordValue -Record $record -Names @('Surface', 'Product', 'Feature', 'Source'))
        if ([string]::IsNullOrWhiteSpace($surface)) { $surface = 'All supported surfaces' }
        if ($surface -match '^[=+\-@]') { $surface = "'$surface" }

        $credits = ConvertTo-SnapshotDecimal `
            -Value (Get-RecordValue -Record $record -Names @('OfficialCredits', 'Credits', 'credits_used', 'ConsumedCredits')) `
            -FieldName 'OfficialCredits'
        $newInput = ConvertTo-SnapshotDecimal `
            -Value (Get-RecordValue -Record $record -Names @('OfficialNewInput', 'NewInput', 'input_tokens', 'InputTokens')) `
            -FieldName 'OfficialNewInput'
        $cached = ConvertTo-SnapshotDecimal `
            -Value (Get-RecordValue -Record $record -Names @('OfficialCachedInput', 'CachedInput', 'cached_input_tokens', 'CachedInputTokens')) `
            -FieldName 'OfficialCachedInput'
        $output = ConvertTo-SnapshotDecimal `
            -Value (Get-RecordValue -Record $record -Names @('OfficialOutput', 'Output', 'output_tokens', 'OutputTokens')) `
            -FieldName 'OfficialOutput'
        if ($credits -eq 0 -and $newInput -eq 0 -and $cached -eq 0 -and $output -eq 0) {
            throw 'Each official snapshot row must contain at least one non-zero usage metric.'
        }
        $reportedUpdate = Get-RecordValue -Record $record -Names @('ReportUpdatedAt', 'UpdatedAt', 'source_updated_at', 'DataThrough')
        if ($null -ne $reportedUpdate) {
            $parsedUpdate = [datetime]::MinValue
            if ([datetime]::TryParse([string]$reportedUpdate, [ref]$parsedUpdate)) {
                $reportedUpdates.Add($parsedUpdate)
            }
        }
        $sanitized.Add([pscustomobject][ordered]@{
            Date = $date.Date
            Surface = $surface
            OfficialCredits = $credits
            OfficialNewInput = $newInput
            OfficialCachedInput = $cached
            OfficialOutput = $output
        })
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($sanitized | Group-Object { '{0}|{1}' -f $_.Date.ToString('yyyy-MM-dd'), $_.Surface } | Sort-Object Name)) {
        $items = @($group.Group)
        $rows.Add([pscustomobject][ordered]@{
            Date = $items[0].Date.ToString('yyyy-MM-dd')
            Surface = $items[0].Surface
            OfficialCredits = [Math]::Round([decimal](($items | Measure-Object -Property OfficialCredits -Sum).Sum), 6)
            OfficialNewInput = [Int64](($items | Measure-Object -Property OfficialNewInput -Sum).Sum)
            OfficialCachedInput = [Int64](($items | Measure-Object -Property OfficialCachedInput -Sum).Sum)
            OfficialOutput = [Int64](($items | Measure-Object -Property OfficialOutput -Sum).Sum)
        })
    }
    $reportUpdatedAt = if ($reportedUpdates.Count -gt 0) {
        @($reportedUpdates | Sort-Object -Descending | Select-Object -First 1)[0]
    }
    else { $file.LastWriteTime }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        SourceKind = 'Official report imported from local disk'
        SourceFileName = $file.Name
        ImportedAt = Get-Date
        ReportUpdatedAt = $reportUpdatedAt
        Rows = @($rows)
    }
}

function Get-OfficialSnapshotFreshness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$ReportUpdatedAt,
        [datetime]$Now = (Get-Date)
    )

    $age = $Now - $ReportUpdatedAt
    if ($age.TotalMinutes -lt 0) { $age = [timespan]::Zero }
    $label = if ($age.TotalHours -le 12) {
        'Within typical official refresh window'
    }
    elseif ($age.TotalHours -le 24) {
        'Older than typical; still within documented refresh range'
    }
    elseif ($age.TotalHours -le 48) {
        'Delayed; within the documented service target'
    }
    else {
        'Stale; replace with a newer downloaded report'
    }
    return [pscustomobject][ordered]@{
        Age = $age
        AgeHours = [Math]::Round($age.TotalHours, 1)
        Label = $label
        TypicalRefresh = '6-12 hours'
        DocumentedRange = '1-24 hours'
        ServiceTarget = 'up to 48 hours'
    }
}

function Compare-OfficialUsageSnapshot {
    [CmdletBinding()]
    param(
        [object[]]$LocalDailyCosts,
        [Parameter(Mandatory = $true)]
        [object]$OfficialSnapshot,
        [decimal]$TolerancePercent = 2
    )

    $localByDate = @{}
    foreach ($row in @($LocalDailyCosts)) {
        if ($null -eq $row) { continue }
        $key = [string]$row.Date
        if (-not $localByDate.ContainsKey($key)) { $localByDate[$key] = [decimal]0 }
        $localByDate[$key] += [decimal]$row.EstimatedCredits
    }
    $officialByDate = @{}
    foreach ($row in @($OfficialSnapshot.Rows)) {
        $key = [string]$row.Date
        if (-not $officialByDate.ContainsKey($key)) { $officialByDate[$key] = [decimal]0 }
        $officialByDate[$key] += [decimal]$row.OfficialCredits
    }

    $keys = @($localByDate.Keys + $officialByDate.Keys | Sort-Object -Unique)
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($date in $keys) {
        $local = if ($localByDate.ContainsKey($date)) { $localByDate[$date] } else { [decimal]0 }
        $official = if ($officialByDate.ContainsKey($date)) { $officialByDate[$date] } else { [decimal]0 }
        $variance = $local - $official
        $variancePercent = if ($official -gt 0) {
            [Math]::Round(([decimal]$variance / $official) * 100, 2)
        }
        else { $null }
        $coverage = if ($official -gt 0) {
            [Math]::Round(([decimal]$local / $official) * 100, 2)
        }
        else { $null }
        $status = if ($official -eq 0 -and $local -gt 0) {
            'Local only'
        }
        elseif ($local -eq 0 -and $official -gt 0) {
            'Official only'
        }
        elseif ($official -eq 0 -and $local -eq 0) {
            'No usage'
        }
        elseif ([Math]::Abs([double]$variancePercent) -le [double]$TolerancePercent) {
            'Aligned'
        }
        elseif ($variance -gt 0) {
            'Local higher'
        }
        else {
            'Official higher'
        }
        $result.Add([pscustomobject][ordered]@{
            Date = $date
            LocalEstimatedCredits = [Math]::Round($local, 6)
            OfficialCredits = [Math]::Round($official, 6)
            VarianceCredits = [Math]::Round($variance, 6)
            VariancePercent = $variancePercent
            CoveragePercent = $coverage
            Status = $status
        })
    }
    return @($result)
}

function Get-LatestOfficialSnapshotFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Folder)

    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return $null }
    return @(Get-ChildItem -LiteralPath $Folder -File |
        Where-Object { $_.Extension -in @('.csv', '.json') -and $_.Name -notmatch 'template' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1)
}

Export-ModuleMember -Function @(
    'Import-OfficialUsageSnapshot',
    'Get-OfficialSnapshotFreshness',
    'Compare-OfficialUsageSnapshot',
    'Get-LatestOfficialSnapshotFile'
)
