Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AnalyticsField {
    param([object]$Row, [string[]]$Names)

    foreach ($name in $Names) {
        $property = @($Row.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1)
        if ($property.Count -gt 0) { return $property[0].Value }
    }
    return $null
}

function ConvertTo-AnalyticsNumber {
    param([object]$Value)

    if ($null -eq $Value) { return [int64]0 }
    if ($Value -is [ValueType]) {
        try { return [int64]$Value } catch { return [int64]0 }
    }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return [int64]0 }
    $text = $text -replace '[,\s]', ''
    [int64]$number = 0
    if ([int64]::TryParse($text, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $number
    }
    return [int64]0
}

function Get-SafeAnalyticsLabel {
    param([object]$Value, [string]$Fallback = 'Unspecified')

    if ($null -eq $Value) { return $Fallback }
    $text = (([string]$Value) -replace '[\r\n\t]+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    if ($text.Length -gt 100) { $text = $text.Substring(0, 100) }
    if ($text -match '^[=+\-@]') { $text = "'$text" }
    return $text
}

function Test-AnalyticsTrue {
    param([object]$Value)

    if ($null -eq $Value) { return $false }
    $text = ([string]$Value).Trim()
    return $text -match '^(?i:true|yes|1|active)$'
}

function ConvertFrom-AnalyticsMap {
    param([object]$Value)

    $results = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Value) { return @() }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq '{}') { return @() }

    try {
        $map = $text | ConvertFrom-Json -ErrorAction Stop
        foreach ($property in $map.PSObject.Properties) {
            $results.Add([pscustomobject]@{
                Name = Get-SafeAnalyticsLabel -Value $property.Name
                Messages = ConvertTo-AnalyticsNumber -Value $property.Value
            })
        }
    }
    catch {
        # Exports may evolve. An unrecognized serialized map is ignored instead
        # of returning its raw text, which could contain an identifier.
    }
    return @($results)
}

function Add-AnalyticsGroupValue {
    param(
        [hashtable]$Groups,
        [string]$Name,
        [string]$Identity,
        [int64]$Messages
    )

    $safeName = Get-SafeAnalyticsLabel -Value $Name
    if (-not $Groups.ContainsKey($safeName)) {
        $Groups[$safeName] = [pscustomobject]@{
            Name = $safeName
            Identities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            Messages = [int64]0
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Identity)) {
        [void]$Groups[$safeName].Identities.Add($Identity)
    }
    $Groups[$safeName].Messages += $Messages
}

function ConvertTo-AnalyticsGroupRows {
    param([hashtable]$Groups)

    return @(
        foreach ($group in $Groups.Values) {
            [pscustomobject][ordered]@{
                Name = $group.Name
                Users = $group.Identities.Count
                Messages = $group.Messages
            }
        }
    ) | Sort-Object -Property @{ Expression = 'Messages'; Descending = $true }, @{ Expression = 'Name'; Descending = $false }
}

function ConvertTo-AnalyticsMapRows {
    param([hashtable]$Values)

    return @(
        foreach ($name in $Values.Keys) {
            [pscustomobject][ordered]@{
                Name = $name
                Messages = [int64]$Values[$name]
            }
        }
    ) | Sort-Object -Property @{ Expression = 'Messages'; Descending = $true }, @{ Expression = 'Name'; Descending = $false }
}

function Import-WorkspaceAnalyticsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    $rows = @(Import-Csv -LiteralPath $Path)
    if ($rows.Count -eq 0) { throw 'The Workspace Analytics CSV has no data rows.' }

    $activeIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $seatGroups = @{}
    $departmentGroups = @{}
    $tools = @{}
    $models = @{}
    [int64]$totalMessages = 0
    [int64]$gptMessages = 0
    [int64]$toolMessages = 0
    [int64]$projectMessages = 0
    $periodStarts = [System.Collections.Generic.List[datetime]]::new()
    $periodEnds = [System.Collections.Generic.List[datetime]]::new()

    for ($index = 0; $index -lt $rows.Count; $index++) {
        $row = $rows[$index]
        $identity = [string](Get-AnalyticsField -Row $row -Names @('public_id', 'account_id', 'email'))
        if ([string]::IsNullOrWhiteSpace($identity)) { $identity = "row-$index" }

        $messages = ConvertTo-AnalyticsNumber (Get-AnalyticsField -Row $row -Names @('messages', 'total_messages'))
        $rowGptMessages = ConvertTo-AnalyticsNumber (Get-AnalyticsField -Row $row -Names @('gpt_messages'))
        $rowToolMessages = ConvertTo-AnalyticsNumber (Get-AnalyticsField -Row $row -Names @('tool_messages'))
        $rowProjectMessages = ConvertTo-AnalyticsNumber (Get-AnalyticsField -Row $row -Names @('project_messages'))
        $totalMessages += $messages
        $gptMessages += $rowGptMessages
        $toolMessages += $rowToolMessages
        $projectMessages += $rowProjectMessages

        $isActive = Test-AnalyticsTrue (Get-AnalyticsField -Row $row -Names @('is_active'))
        if ($isActive -or $messages -gt 0) { [void]$activeIdentities.Add($identity) }

        $seatType = [string](Get-AnalyticsField -Row $row -Names @('seat_type'))
        $department = [string](Get-AnalyticsField -Row $row -Names @('department'))
        Add-AnalyticsGroupValue -Groups $seatGroups -Name $seatType -Identity $identity -Messages $messages
        Add-AnalyticsGroupValue -Groups $departmentGroups -Name $department -Identity $identity -Messages $messages

        foreach ($entry in @(ConvertFrom-AnalyticsMap (Get-AnalyticsField -Row $row -Names @('tool_to_messages')))) {
            if (-not $tools.ContainsKey($entry.Name)) { $tools[$entry.Name] = [int64]0 }
            $tools[$entry.Name] += [int64]$entry.Messages
        }
        foreach ($entry in @(ConvertFrom-AnalyticsMap (Get-AnalyticsField -Row $row -Names @('model_to_messages')))) {
            if (-not $models.ContainsKey($entry.Name)) { $models[$entry.Name] = [int64]0 }
            $models[$entry.Name] += [int64]$entry.Messages
        }

        foreach ($dateSpec in @(
            [pscustomobject]@{ Value = Get-AnalyticsField -Row $row -Names @('period_start'); Target = $periodStarts },
            [pscustomobject]@{ Value = Get-AnalyticsField -Row $row -Names @('period_end'); Target = $periodEnds }
        )) {
            if ($null -eq $dateSpec.Value -or [string]::IsNullOrWhiteSpace([string]$dateSpec.Value)) { continue }
            try { $dateSpec.Target.Add([datetimeoffset]::Parse([string]$dateSpec.Value).LocalDateTime) } catch { }
        }
    }

    $periodStart = if ($periodStarts.Count -gt 0) { @($periodStarts | Sort-Object | Select-Object -First 1)[0] } else { $null }
    $periodEnd = if ($periodEnds.Count -gt 0) { @($periodEnds | Sort-Object -Descending | Select-Object -First 1)[0] } else { $null }
    return [pscustomobject][ordered]@{
        Rows = $rows.Count
        ActiveUsers = $activeIdentities.Count
        TotalMessages = $totalMessages
        GptMessages = $gptMessages
        ToolMessages = $toolMessages
        ProjectMessages = $projectMessages
        PeriodStart = $periodStart
        PeriodEnd = $periodEnd
        SeatTypes = @(ConvertTo-AnalyticsGroupRows -Groups $seatGroups)
        Departments = @(ConvertTo-AnalyticsGroupRows -Groups $departmentGroups)
        Tools = @(ConvertTo-AnalyticsMapRows -Values $tools)
        Models = @(ConvertTo-AnalyticsMapRows -Values $models)
    }
}

Export-ModuleMember -Function Import-WorkspaceAnalyticsReport
