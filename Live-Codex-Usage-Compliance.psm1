Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ComplianceValueAtPath {
    param([object]$Object, [string]$Path)

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Path)) { return $null }
    $current = $Object
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) { return $null }
        $property = @($current.PSObject.Properties | Where-Object { $_.Name -ieq $segment } | Select-Object -First 1)
        if ($property.Count -eq 0) { return $null }
        $current = $property[0].Value
    }
    return $current
}

function Get-SafeComplianceDimension {
    param([object]$Value, [string]$Fallback = 'Unspecified')

    if ($null -eq $Value) { return $Fallback }
    $text = (([string]$Value) -replace '[\r\n\t]+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    if ($text.Length -gt 100) { $text = $text.Substring(0, 100) }
    # Prevent an exported dimension from becoming a formula when the CSV is
    # opened in Excel or another spreadsheet application.
    if ($text -match '^[=+\-@]') { return "'$text" }
    return $text
}

function Convert-ComplianceExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$MappingPath,
        [string]$OutputPath = ''
    )

    $mapping = Get-Content -LiteralPath $MappingPath -Raw | ConvertFrom-Json -ErrorAction Stop
    foreach ($required in @('timestamp', 'event_type', 'surface', 'user_id')) {
        if ($null -eq $mapping.PSObject.Properties[$required] -or [string]::IsNullOrWhiteSpace([string]$mapping.$required)) {
            throw "Mapping file is missing required dot path: $required"
        }
    }

    $groups = @{}
    [int64]$inputRows = 0
    [int64]$invalidLines = 0
    foreach ($line in Get-Content -LiteralPath $InputPath -ReadCount 1) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $inputRows++
        try { $record = $line | ConvertFrom-Json -ErrorAction Stop }
        catch { $invalidLines++; continue }

        $timestampValue = Get-ComplianceValueAtPath -Object $record -Path ([string]$mapping.timestamp)
        try { $day = [datetimeoffset]::Parse([string]$timestampValue).LocalDateTime.Date }
        catch { $invalidLines++; continue }
        $eventType = Get-SafeComplianceDimension (Get-ComplianceValueAtPath -Object $record -Path ([string]$mapping.event_type))
        $surface = Get-SafeComplianceDimension (Get-ComplianceValueAtPath -Object $record -Path ([string]$mapping.surface))
        $userId = [string](Get-ComplianceValueAtPath -Object $record -Path ([string]$mapping.user_id))
        $model = 'Unspecified'
        if ($null -ne $mapping.PSObject.Properties['model'] -and -not [string]::IsNullOrWhiteSpace([string]$mapping.model)) {
            $model = Get-SafeComplianceDimension (Get-ComplianceValueAtPath -Object $record -Path ([string]$mapping.model))
        }

        $key = '{0}|{1}|{2}|{3}' -f $day.ToString('yyyy-MM-dd'), $surface, $eventType, $model
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{
                Date = $day.ToString('yyyy-MM-dd')
                Surface = $surface
                EventType = $eventType
                Model = $model
                Count = [int64]0
                Users = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            }
        }
        $groups[$key].Count++
        if (-not [string]::IsNullOrWhiteSpace($userId)) {
            # The raw identifier exists only in this in-memory set. It is never
            # copied into an output object or written to disk.
            [void]$groups[$key].Users.Add($userId)
        }
    }

    $rows = @(
        foreach ($group in $groups.Values) {
            [pscustomobject][ordered]@{
                Date = $group.Date
                Surface = $group.Surface
                EventType = $group.EventType
                Model = $group.Model
                Events = $group.Count
                UniqueUsers = $group.Users.Count
            }
        }
    ) | Sort-Object Date, Surface, EventType, Model

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw "The output folder does not exist: $parent"
        }
        $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    }

    return [pscustomobject]@{
        InputRows = $inputRows
        InvalidLines = $invalidLines
        OutputRows = @($rows).Count
        Rows = @($rows)
    }
}

Export-ModuleMember -Function Convert-ComplianceExport
