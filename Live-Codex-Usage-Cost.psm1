Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-InvariantDecimal {
    param(
        [object]$Value,
        [decimal]$Default = 0
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Default }
    $parsed = [decimal]0
    if ([decimal]::TryParse(
            [string]$Value,
            [System.Globalization.NumberStyles]::Number,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function Import-UsageRateCard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Usage rate card not found: $Path"
    }
    $card = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $card -or $null -eq $card.Models -or @($card.Models).Count -eq 0) {
        throw 'The usage rate card must contain at least one model.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$card.EffectiveDate)) {
        throw 'The usage rate card must include EffectiveDate.'
    }
    return $card
}

function Resolve-UsageRateModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RateCard,
        [string]$Model
    )

    if ([string]::IsNullOrWhiteSpace($Model)) { return $null }
    $candidate = $Model.Trim()
    foreach ($entry in @($RateCard.Models)) {
        if ([string]$entry.Id -ieq $candidate) { return $entry }
        foreach ($alias in @($entry.Aliases)) {
            if ([string]$alias -ieq $candidate) { return $entry }
        }
    }
    return $null
}

function Get-TokenCostEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RateCard,
        [string]$Model,
        [Int64]$NewInputTokens,
        [Int64]$CachedInputTokens,
        [Int64]$OutputTokens,
        [decimal]$DollarsPerCredit = -1,
        [decimal]$CreditRateMultiplier = 1
    )

    if ($CreditRateMultiplier -le 0) { throw 'CreditRateMultiplier must be greater than zero.' }
    $newInput = [Math]::Max([Int64]0, $NewInputTokens)
    $cached = [Math]::Max([Int64]0, $CachedInputTokens)
    $output = [Math]::Max([Int64]0, $OutputTokens)
    $matched = Resolve-UsageRateModel -RateCard $RateCard -Model $Model
    if ($null -eq $matched) {
        return [pscustomobject][ordered]@{
            Model = if ([string]::IsNullOrWhiteSpace($Model)) { 'unknown' } else { $Model }
            Priced = $false
            NewInputTokens = $newInput
            CachedInputTokens = $cached
            OutputTokens = $output
            EstimatedCredits = [decimal]0
            CreditRateMultiplier = $CreditRateMultiplier
            ApiEquivalentUsd = $null
            ApiEquivalentAvailable = $false
            EstimatedActualUsd = $null
            RateEffectiveDate = [string]$RateCard.EffectiveDate
            RateSource = [string]$RateCard.SourceUrl
            Note = 'No bundled rate matched this model; no default was guessed.'
        }
    }

    $creditInput = Get-InvariantDecimal $matched.CreditsPerMillion.Input
    $creditCached = Get-InvariantDecimal $matched.CreditsPerMillion.CachedInput
    $creditOutput = Get-InvariantDecimal $matched.CreditsPerMillion.Output
    $apiEquivalentAvailable = (
        $null -ne $matched.PSObject.Properties['ApiEquivalentAvailable'] -and
        [bool]$matched.ApiEquivalentAvailable
    )

    $credits = ((
        ([decimal]$newInput * $creditInput) +
        ([decimal]$cached * $creditCached) +
        ([decimal]$output * $creditOutput)
    ) / [decimal]1000000) * $CreditRateMultiplier
    $apiUsd = $null
    if ($apiEquivalentAvailable) {
        $usdInput = Get-InvariantDecimal $matched.ApiUsdPerMillion.Input
        $usdCached = Get-InvariantDecimal $matched.ApiUsdPerMillion.CachedInput
        $usdOutput = Get-InvariantDecimal $matched.ApiUsdPerMillion.Output
        $apiUsd = (
            ([decimal]$newInput * $usdInput) +
            ([decimal]$cached * $usdCached) +
            ([decimal]$output * $usdOutput)
        ) / [decimal]1000000
    }
    $actualUsd = $null
    if ($DollarsPerCredit -ge 0) {
        $actualUsd = [Math]::Round(($credits * $DollarsPerCredit), 6)
    }

    return [pscustomobject][ordered]@{
        Model = [string]$matched.Id
        Priced = $true
        NewInputTokens = $newInput
        CachedInputTokens = $cached
        OutputTokens = $output
        EstimatedCredits = [Math]::Round($credits, 6)
        CreditRateMultiplier = $CreditRateMultiplier
        ApiEquivalentUsd = if ($null -ne $apiUsd) { [Math]::Round([decimal]$apiUsd, 6) } else { $null }
        ApiEquivalentAvailable = $apiEquivalentAvailable
        EstimatedActualUsd = $actualUsd
        RateEffectiveDate = [string]$RateCard.EffectiveDate
        RateSource = [string]$RateCard.SourceUrl
        Note = 'Offline estimate from bundled rates; not an invoice or account balance.'
    }
}

function Get-UsageCostEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RateCard,
        [object[]]$UsageEvents,
        [string]$DefaultModel = '',
        [decimal]$DollarsPerCredit = -1,
        [decimal]$CreditRateMultiplier = 1
    )

    [decimal]$credits = 0
    [decimal]$apiUsd = 0
    $apiEquivalentComplete = $true
    [decimal]$actualUsd = 0
    [Int64]$pricedTokens = 0
    [Int64]$unpricedTokens = 0
    $unpricedModels = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $details = [System.Collections.Generic.List[object]]::new()

    foreach ($event in @($UsageEvents)) {
        if ($null -eq $event) { continue }
        $model = ''
        if ($event.PSObject.Properties['Model']) { $model = [string]$event.Model }
        if ([string]::IsNullOrWhiteSpace($model)) { $model = $DefaultModel }
        $newInput = if ($event.PSObject.Properties['NewInput']) {
            [Int64]$event.NewInput
        }
        else {
            [Math]::Max([Int64]0, ([Int64]$event.Input - [Int64]$event.Cached))
        }
        $estimate = Get-TokenCostEstimate `
            -RateCard $RateCard `
            -Model $model `
            -NewInputTokens $newInput `
            -CachedInputTokens ([Int64]$event.Cached) `
            -OutputTokens ([Int64]$event.Output) `
            -DollarsPerCredit $DollarsPerCredit `
            -CreditRateMultiplier $CreditRateMultiplier
        $details.Add($estimate)
        $eventTokens = $estimate.NewInputTokens + $estimate.CachedInputTokens + $estimate.OutputTokens
        if ($estimate.Priced) {
            $credits += [decimal]$estimate.EstimatedCredits
            if ($estimate.ApiEquivalentAvailable) {
                $apiUsd += [decimal]$estimate.ApiEquivalentUsd
            }
            else {
                $apiEquivalentComplete = $false
            }
            if ($null -ne $estimate.EstimatedActualUsd) {
                $actualUsd += [decimal]$estimate.EstimatedActualUsd
            }
            $pricedTokens += $eventTokens
        }
        else {
            $unpricedTokens += $eventTokens
            $apiEquivalentComplete = $false
            [void]$unpricedModels.Add([string]$estimate.Model)
        }
    }

    return [pscustomobject][ordered]@{
        EstimatedCredits = [Math]::Round($credits, 4)
        ApiEquivalentUsd = if ($apiEquivalentComplete) { [Math]::Round($apiUsd, 4) } else { $null }
        ApiEquivalentComplete = $apiEquivalentComplete
        EstimatedActualUsd = if ($DollarsPerCredit -ge 0) { [Math]::Round($actualUsd, 4) } else { $null }
        PricedTokens = $pricedTokens
        UnpricedTokens = $unpricedTokens
        UnpricedModels = @($unpricedModels | Sort-Object)
        RateEffectiveDate = [string]$RateCard.EffectiveDate
        RateSource = [string]$RateCard.SourceUrl
        CreditRateMultiplier = $CreditRateMultiplier
        Details = @($details)
    }
}

function Get-DailyUsageCostEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RateCard,
        [object[]]$UsageEvents,
        [string]$DefaultModel = '',
        [decimal]$DollarsPerCredit = -1,
        [decimal]$CreditRateMultiplier = 1
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($group in @($UsageEvents | Group-Object { $_.At.Date } | Sort-Object Name)) {
        $estimate = Get-UsageCostEstimate `
            -RateCard $RateCard `
            -UsageEvents @($group.Group) `
            -DefaultModel $DefaultModel `
            -DollarsPerCredit $DollarsPerCredit `
            -CreditRateMultiplier $CreditRateMultiplier
        $rows.Add([pscustomobject][ordered]@{
            Date = ([datetime]$group.Group[0].At).ToString('yyyy-MM-dd')
            EstimatedCredits = $estimate.EstimatedCredits
            ApiEquivalentUsd = $estimate.ApiEquivalentUsd
            EstimatedActualUsd = $estimate.EstimatedActualUsd
            PricedTokens = $estimate.PricedTokens
            UnpricedTokens = $estimate.UnpricedTokens
            UnpricedModels = ($estimate.UnpricedModels -join ', ')
        })
    }
    return @($rows)
}

function New-UsageCostProfile {
    [CmdletBinding()]
    param(
        [string]$DefaultModel = '',
        [decimal]$DollarsPerCredit = -1,
        [decimal]$IncludedCreditsPerCycle = 0,
        [decimal]$FixedCostPerCycleUsd = 0,
        [decimal]$CreditRateMultiplier = 1,
        [ValidateRange(1, 28)]
        [int]$BillingCycleStartDay = 1
    )

    if ($DollarsPerCredit -lt -1) { throw 'DollarsPerCredit must be -1 (unknown) or zero/greater.' }
    if ($IncludedCreditsPerCycle -lt 0 -or $FixedCostPerCycleUsd -lt 0) {
        throw 'Included credits and fixed cycle cost cannot be negative.'
    }
    if ($CreditRateMultiplier -le 0) { throw 'Credit rate multiplier must be greater than zero.' }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        DefaultModel = $DefaultModel
        DollarsPerCredit = $DollarsPerCredit
        IncludedCreditsPerCycle = $IncludedCreditsPerCycle
        FixedCostPerCycleUsd = $FixedCostPerCycleUsd
        CreditRateMultiplier = $CreditRateMultiplier
        BillingCycleStartDay = $BillingCycleStartDay
        Note = 'Local parameters only. No account or billing service is queried.'
    }
}

function Import-UsageCostProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return New-UsageCostProfile }
    $profile = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$profile.SchemaVersion -ne 1) { throw 'Unsupported usage cost profile schema.' }
    $multiplier = if ($null -ne $profile.PSObject.Properties['CreditRateMultiplier']) {
        [decimal]$profile.CreditRateMultiplier
    } else { [decimal]1 }
    return New-UsageCostProfile `
        -DefaultModel ([string]$profile.DefaultModel) `
        -DollarsPerCredit ([decimal]$profile.DollarsPerCredit) `
        -IncludedCreditsPerCycle ([decimal]$profile.IncludedCreditsPerCycle) `
        -FixedCostPerCycleUsd ([decimal]$profile.FixedCostPerCycleUsd) `
        -CreditRateMultiplier $multiplier `
        -BillingCycleStartDay ([int]$profile.BillingCycleStartDay)
}

function Export-UsageCostProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Profile,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $validated = New-UsageCostProfile `
        -DefaultModel ([string]$Profile.DefaultModel) `
        -DollarsPerCredit ([decimal]$Profile.DollarsPerCredit) `
        -IncludedCreditsPerCycle ([decimal]$Profile.IncludedCreditsPerCycle) `
        -FixedCostPerCycleUsd ([decimal]$Profile.FixedCostPerCycleUsd) `
        -CreditRateMultiplier ([decimal]$Profile.CreditRateMultiplier) `
        -BillingCycleStartDay ([int]$Profile.BillingCycleStartDay)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and
        -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $validated | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
    return $validated
}

function Get-ConfiguredSpendEstimate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][decimal]$EstimatedCredits,
        [Parameter(Mandatory = $true)][object]$Profile
    )

    $billableCredits = [Math]::Max([decimal]0, $EstimatedCredits - [decimal]$Profile.IncludedCreditsPerCycle)
    $variable = $null
    $total = $null
    if ([decimal]$Profile.DollarsPerCredit -ge 0) {
        $variable = [Math]::Round($billableCredits * [decimal]$Profile.DollarsPerCredit, 4)
        $total = [Math]::Round([decimal]$Profile.FixedCostPerCycleUsd + [decimal]$variable, 4)
    }
    return [pscustomobject][ordered]@{
        EstimatedCredits = [Math]::Round($EstimatedCredits, 4)
        IncludedCredits = [decimal]$Profile.IncludedCreditsPerCycle
        EstimatedBillableCredits = [Math]::Round($billableCredits, 4)
        DollarsPerCredit = [decimal]$Profile.DollarsPerCredit
        EstimatedVariableUsd = $variable
        FixedCostPerCycleUsd = [decimal]$Profile.FixedCostPerCycleUsd
        EstimatedCycleSpendUsd = $total
        CashEstimateAvailable = ($null -ne $total)
        Note = if ($null -ne $total) {
            'Calculated only from local counters and user-supplied billing parameters.'
        } else {
            'Actual cash estimate unavailable until dollars per credit is supplied.'
        }
    }
}

Export-ModuleMember -Function @(
    'Import-UsageRateCard',
    'Resolve-UsageRateModel',
    'Get-TokenCostEstimate',
    'Get-UsageCostEstimate',
    'Get-DailyUsageCostEstimate',
    'New-UsageCostProfile',
    'Import-UsageCostProfile',
    'Export-UsageCostProfile',
    'Get-ConfiguredSpendEstimate'
)
