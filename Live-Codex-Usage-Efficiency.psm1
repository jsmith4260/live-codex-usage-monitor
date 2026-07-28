Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:managedConfigKeys = @(
    'model_reasoning_effort',
    'model_verbosity',
    'model_auto_compact_token_limit'
)
$script:policyStartMarker = '<!-- LIVE-CODEX-USAGE-MONITOR:EFFICIENCY-V1 START -->'
$script:policyEndMarker = '<!-- LIVE-CODEX-USAGE-MONITOR:EFFICIENCY-V1 END -->'

function Get-EfficiencyNumber {
    param([object]$Value)

    if ($null -eq $Value) { return [int64]0 }
    try { return [int64]$Value } catch { return [int64]0 }
}

function Get-EfficiencyDecimal {
    param([object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [decimal]0
    }
    $parsed = [decimal]0
    if ([decimal]::TryParse(
            [string]$Value,
            [System.Globalization.NumberStyles]::Number,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsed)) {
        return $parsed
    }
    return [decimal]0
}

function Get-EfficiencyProperty {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-EfficiencyNestedValue {
    param([object]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IEnumerable] -and
        $Object -isnot [string] -and $Object -isnot [pscustomobject]) {
        foreach ($item in $Object) {
            $value = Get-EfficiencyNestedValue -Object $item -Name $Name
            if ($null -ne $value) { return $value }
        }
        return $null
    }
    if ($Object -is [pscustomobject]) {
        foreach ($property in $Object.PSObject.Properties) {
            if ($property.Name -eq $Name) { return $property.Value }
        }
        foreach ($property in $Object.PSObject.Properties) {
            $value = Get-EfficiencyNestedValue -Object $property.Value -Name $Name
            if ($null -ne $value) { return $value }
        }
    }
    return $null
}

function Get-MedianNumber {
    param([object[]]$Values)

    $numbers = @($Values | ForEach-Object { [double]$_ } | Sort-Object)
    if ($numbers.Count -eq 0) { return [double]0 }
    $middle = [int][Math]::Floor($numbers.Count / 2)
    if (($numbers.Count % 2) -eq 1) { return [double]$numbers[$middle] }
    return ([double]$numbers[$middle - 1] + [double]$numbers[$middle]) / 2
}

function New-CodexSchemaTracker {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-schema-counters-no-content-no-identifiers'
        TotalLines = [int64]0
        TypedLines = [int64]0
        KnownRecords = [int64]0
        UnknownRecords = [int64]0
        MissingTypeRecords = [int64]0
        MalformedRecords = [int64]0
        TokenRecords = [int64]0
        TokenShapeMismatches = [int64]0
        RateLimitShapeMismatches = [int64]0
        CompactionRecords = [int64]0
    }
}

function Add-CodexSchemaObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Tracker,
        [Parameter(Mandatory = $true)][string]$Line
    )

    $Tracker.TotalLines = [int64]$Tracker.TotalLines + 1
    $trimmed = $Line.Trim()
    if ($trimmed.Length -lt 2 -or $trimmed[0] -ne '{' -or $trimmed[$trimmed.Length - 1] -ne '}') {
        $Tracker.MalformedRecords = [int64]$Tracker.MalformedRecords + 1
        return
    }

    $outerType = ''
    if ($Line -match '^\s*\{(?:(?!"type"\s*:).)*"type"\s*:\s*"([^"]+)"') {
        $outerType = [string]$Matches[1]
        $Tracker.TypedLines = [int64]$Tracker.TypedLines + 1
    }
    else {
        $Tracker.MissingTypeRecords = [int64]$Tracker.MissingTypeRecords + 1
    }

    $knownOuterTypes = @(
        'session_meta',
        'turn_context',
        'event_msg',
        'response_item',
        'compacted',
        'ghost_snapshot'
    )
    if ($outerType) {
        if ($outerType -in $knownOuterTypes) {
            $Tracker.KnownRecords = [int64]$Tracker.KnownRecords + 1
        }
        else {
            $Tracker.UnknownRecords = [int64]$Tracker.UnknownRecords + 1
        }
    }

    if ($Line -match '"type"\s*:\s*"token_count"') {
        $Tracker.TokenRecords = [int64]$Tracker.TokenRecords + 1
        $requiredUsageFields = @(
            '"last_token_usage"',
            '"input_tokens"',
            '"cached_input_tokens"',
            '"output_tokens"',
            '"total_tokens"'
        )
        foreach ($field in $requiredUsageFields) {
            if ($Line -notmatch [regex]::Escape($field)) {
                $Tracker.TokenShapeMismatches = [int64]$Tracker.TokenShapeMismatches + 1
                break
            }
        }
        if ($Line -match '"rate_limits"' -and
            $Line -notmatch '"primary"' -and $Line -notmatch '"secondary"') {
            $Tracker.RateLimitShapeMismatches = [int64]$Tracker.RateLimitShapeMismatches + 1
        }
    }

    if ($Line -match '"type"\s*:\s*"(?:compacted|context_compacted|context_compaction|compact)"') {
        $Tracker.CompactionRecords = [int64]$Tracker.CompactionRecords + 1
    }
}

function Get-CodexSchemaHealth {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Tracker)

    $typed = [int64]$Tracker.TypedLines
    $known = [int64]$Tracker.KnownRecords
    $compatibility = if ($typed -gt 0) {
        [Math]::Round(($known / [double]$typed) * 100, 1)
    }
    else { [double]0 }
    $criticalMismatch = (
        [int64]$Tracker.TokenShapeMismatches -gt 0 -or
        [int64]$Tracker.MalformedRecords -gt 0
    )
    $drift = (
        $criticalMismatch -or
        [int64]$Tracker.UnknownRecords -gt 0 -or
        [int64]$Tracker.MissingTypeRecords -gt 0 -or
        [int64]$Tracker.RateLimitShapeMismatches -gt 0
    )

    if ([int64]$Tracker.TotalLines -eq 0) {
        $statusCode = 'NoData'
        $label = 'Waiting for local log records'
        $detail = 'No schema observations are loaded.'
    }
    elseif ($drift) {
        $statusCode = 'Drift'
        $label = 'Schema change detected'
        $detail = ('{0:N0} unknown, {1:N0} missing type, {2:N0} malformed, {3:N0} token-shape mismatch, {4:N0} quota-shape mismatch.' -f `
            [int64]$Tracker.UnknownRecords, [int64]$Tracker.MissingTypeRecords,
            [int64]$Tracker.MalformedRecords, [int64]$Tracker.TokenShapeMismatches,
            [int64]$Tracker.RateLimitShapeMismatches)
    }
    else {
        $statusCode = 'Healthy'
        $label = 'Compatible with schema v1'
        $detail = ('{0:N0} local records checked; {1:N0} token records matched expected counters.' -f `
            [int64]$Tracker.TotalLines, [int64]$Tracker.TokenRecords)
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-schema-health-no-content-no-identifiers'
        StatusCode = $statusCode
        Label = $label
        Detail = $detail
        CompatibilityPercent = $compatibility
        TotalRecords = [int64]$Tracker.TotalLines
        UnknownRecords = [int64]$Tracker.UnknownRecords
        TokenShapeMismatches = [int64]$Tracker.TokenShapeMismatches
        CompactionRecords = [int64]$Tracker.CompactionRecords
    }
}

function Resolve-EfficiencyRateModel {
    param([object]$RateCard, [string]$Model)

    if ($null -eq $RateCard -or [string]::IsNullOrWhiteSpace($Model)) { return $null }
    foreach ($entry in @($RateCard.Models)) {
        if ([string]$entry.Id -ieq $Model) { return $entry }
        foreach ($alias in @($entry.Aliases)) {
            if ([string]$alias -ieq $Model) { return $entry }
        }
    }
    return $null
}

function Get-PromptCacheSavings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$RateCard,
        [object[]]$UsageEvents,
        [string]$DefaultModel = '',
        [decimal]$DollarsPerCredit = -1,
        [decimal]$CreditRateMultiplier = 1
    )

    if ($CreditRateMultiplier -le 0) {
        throw 'CreditRateMultiplier must be greater than zero.'
    }
    [int64]$cachedTokens = 0
    [int64]$freshInputTokens = 0
    [int64]$unpricedCachedTokens = 0
    [decimal]$creditSavings = 0
    [decimal]$apiSavings = 0
    $apiComplete = $true

    foreach ($usageItem in @($UsageEvents)) {
        if ($null -eq $usageItem) { continue }
        $cached = [Math]::Max([int64]0, (Get-EfficiencyNumber (Get-EfficiencyProperty $usageItem 'Cached')))
        $fresh = Get-EfficiencyProperty $usageItem 'NewInput'
        if ($null -eq $fresh) {
            $fresh = [Math]::Max(
                [int64]0,
                (Get-EfficiencyNumber (Get-EfficiencyProperty $usageItem 'Input')) - $cached
            )
        }
        $cachedTokens += $cached
        $freshInputTokens += [Math]::Max([int64]0, [int64]$fresh)
        if ($cached -eq 0) { continue }

        $model = [string](Get-EfficiencyProperty $usageItem 'Model')
        if ([string]::IsNullOrWhiteSpace($model)) { $model = $DefaultModel }
        $rate = Resolve-EfficiencyRateModel -RateCard $RateCard -Model $model
        if ($null -eq $rate) {
            $unpricedCachedTokens += $cached
            $apiComplete = $false
            continue
        }
        $creditInput = Get-EfficiencyDecimal $rate.CreditsPerMillion.Input
        $creditCached = Get-EfficiencyDecimal $rate.CreditsPerMillion.CachedInput
        $creditDifference = [Math]::Max([decimal]0, $creditInput - $creditCached)
        $creditSavings += (([decimal]$cached * $creditDifference) / [decimal]1000000) * $CreditRateMultiplier

        $apiAvailable = (
            $null -ne $rate.PSObject.Properties['ApiEquivalentAvailable'] -and
            [bool]$rate.ApiEquivalentAvailable
        )
        if ($apiAvailable) {
            $apiInput = Get-EfficiencyDecimal $rate.ApiUsdPerMillion.Input
            $apiCached = Get-EfficiencyDecimal $rate.ApiUsdPerMillion.CachedInput
            $apiDifference = [Math]::Max([decimal]0, $apiInput - $apiCached)
            $apiSavings += ([decimal]$cached * $apiDifference) / [decimal]1000000
        }
        else {
            $apiComplete = $false
        }
    }

    $inputTotal = $cachedTokens + $freshInputTokens
    $cachePercent = if ($inputTotal -gt 0) {
        [Math]::Round(($cachedTokens / [double]$inputTotal) * 100, 1)
    }
    else { [double]0 }
    $cashSavings = if ($DollarsPerCredit -ge 0) {
        [Math]::Round($creditSavings * $DollarsPerCredit, 4)
    }
    else { $null }
    $health = if ($inputTotal -eq 0) {
        'No data'
    }
    elseif ($cachePercent -ge 70) {
        'Strong'
    }
    elseif ($cachePercent -ge 40) {
        'Moderate'
    }
    else {
        'Low'
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-cache-efficiency-no-content-no-identifiers'
        CachedInputTokens = $cachedTokens
        FreshInputTokens = $freshInputTokens
        CacheHitPercent = $cachePercent
        HealthLabel = $health
        CalculatedCreditsAvoided = [Math]::Round($creditSavings, 4)
        CalculatedApiEquivalentUsdAvoided = if ($apiComplete) {
            [Math]::Round($apiSavings, 4)
        }
        else { $null }
        CalculatedConfiguredUsdAvoided = $cashSavings
        UnpricedCachedTokens = $unpricedCachedTokens
        RateEffectiveDate = [string]$RateCard.EffectiveDate
        SavingsClass = 'Calculated from local cached-input counters and bundled rate differentials'
    }
}

function Get-SessionEfficiencyAdvice {
    [CmdletBinding()]
    param(
        [object[]]$UsageEvents,
        [string]$CurrentSession = '',
        [int64]$BloatedContextTokens = 150000
    )

    $events = @($UsageEvents | Where-Object { $null -ne $_ } | Sort-Object At)
    if ($events.Count -eq 0) {
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            PrivacyClass = 'aggregate-session-advice-no-content-no-identifiers'
            StatusCode = 'NoData'
            Action = 'Wait for completed turns'
            Detail = 'No local token events are available for session-efficiency guidance.'
            RecentAverageInputTokens = [int64]0
            BaselineStartInputTokens = [int64]0
            ExcessReplayTokensPerFutureTurn = [int64]0
            BreakEvenFutureTurns = $null
            Confidence = 'None'
        }
    }
    if ([string]::IsNullOrWhiteSpace($CurrentSession)) {
        $CurrentSession = [string]$events[$events.Count - 1].Session
    }
    $current = @($events | Where-Object { [string]$_.Session -eq $CurrentSession } | Sort-Object At)
    if ($current.Count -eq 0) { $current = @($events | Select-Object -Last 1) }
    $recent = @($current | Select-Object -Last ([Math]::Min(3, $current.Count)))

    [int64]$recentInputTotal = 0
    foreach ($usageItem in $recent) {
        $recentInputTotal += Get-EfficiencyNumber (Get-EfficiencyProperty $usageItem 'Input')
    }
    $recentAverage = [int64]($recentInputTotal / [Math]::Max(1, $recent.Count))

    $sessionStarts = [System.Collections.Generic.List[double]]::new()
    foreach ($group in @($events | Group-Object Session)) {
        $first = @($group.Group | Sort-Object At | Select-Object -First 1)
        if ($first.Count -eq 1) {
            $sessionStarts.Add([double](Get-EfficiencyNumber (Get-EfficiencyProperty $first[0] 'Input')))
        }
    }
    $baseline = [int64](Get-MedianNumber -Values @($sessionStarts))
    if ($baseline -le 0) {
        $baseline = Get-EfficiencyNumber (Get-EfficiencyProperty $current[0] 'Input')
    }
    $excess = [Math]::Max([int64]0, $recentAverage - $baseline)
    $breakEven = if ($excess -gt 0) {
        [Math]::Min(99, [int][Math]::Ceiling($baseline / [double]$excess))
    }
    else { $null }
    $considerFresh = (
        $current.Count -ge 3 -and
        $recentAverage -ge [Math]::Max([int64]($BloatedContextTokens * 0.70), [int64]($baseline * 2)) -and
        $null -ne $breakEven -and $breakEven -le 4
    )

    if ($considerFresh) {
        $statusCode = 'FreshTaskOpportunity'
        $action = 'Consider a fresh task'
        $detail = ('Recent input replay averages {0:N0} tokens. A fresh task is estimated to break even after about {1} future turn(s).' -f `
            $recentAverage, $breakEven)
    }
    else {
        $statusCode = 'Continue'
        $action = 'Continue current task'
        $detail = if ($null -eq $breakEven) {
            'Recent replay is not materially above the observed fresh-task baseline.'
        }
        else {
            'A fresh task is unlikely to repay its cold-start context within the next few turns.'
        }
    }
    $confidence = if ($events.Count -ge 8 -and $sessionStarts.Count -ge 2) {
        'High'
    }
    elseif ($events.Count -ge 3) {
        'Moderate'
    }
    else {
        'Low'
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-session-advice-no-content-no-identifiers'
        StatusCode = $statusCode
        Action = $action
        Detail = $detail
        RecentAverageInputTokens = $recentAverage
        BaselineStartInputTokens = $baseline
        ExcessReplayTokensPerFutureTurn = $excess
        BreakEvenFutureTurns = $breakEven
        Confidence = $confidence
    }
}

function Get-CompactionChurn {
    [CmdletBinding()]
    param(
        [object[]]$UsageEvents,
        [object[]]$ActivityEvents
    )

    $usage = @($UsageEvents | Where-Object { $null -ne $_ } | Sort-Object At)
    $compactions = @($ActivityEvents | Where-Object {
        $null -ne $_ -and [string](Get-EfficiencyProperty $_ 'Label') -eq 'COMPACT'
    } | Sort-Object At)
    [int]$paired = 0
    [int]$rereadSpikes = 0
    [double]$reductionTotal = 0
    $medianFresh = Get-MedianNumber -Values @($usage | ForEach-Object {
        Get-EfficiencyNumber (Get-EfficiencyProperty $_ 'NewInput')
    })

    foreach ($compaction in $compactions) {
        $session = [string](Get-EfficiencyProperty $compaction 'Session')
        $at = [datetime](Get-EfficiencyProperty $compaction 'At')
        $before = @($usage | Where-Object {
            [string]$_.Session -eq $session -and [datetime]$_.At -lt $at
        } | Sort-Object At -Descending | Select-Object -First 1)
        $after = @($usage | Where-Object {
            [string]$_.Session -eq $session -and [datetime]$_.At -gt $at
        } | Sort-Object At | Select-Object -First 1)
        if ($before.Count -ne 1 -or $after.Count -ne 1) { continue }
        $beforeInput = Get-EfficiencyNumber (Get-EfficiencyProperty $before[0] 'Input')
        $afterInput = Get-EfficiencyNumber (Get-EfficiencyProperty $after[0] 'Input')
        if ($beforeInput -gt 0) {
            $reductionTotal += [Math]::Max(0, (($beforeInput - $afterInput) / [double]$beforeInput) * 100)
        }
        $afterFresh = Get-EfficiencyNumber (Get-EfficiencyProperty $after[0] 'NewInput')
        if ($afterFresh -gt [Math]::Max(1000, ($medianFresh * 2))) { $rereadSpikes++ }
        $paired++
    }

    $rate = if ($usage.Count -gt 0) {
        [Math]::Round(($compactions.Count / [double]$usage.Count) * 100, 1)
    }
    else { [double]0 }
    $averageReduction = if ($paired -gt 0) {
        [Math]::Round($reductionTotal / $paired, 1)
    }
    else { [double]0 }

    if ($usage.Count -eq 0) {
        $statusCode = 'NoData'
        $label = 'Waiting for local usage'
        $detail = 'No completed token events are available.'
    }
    elseif ($compactions.Count -eq 0) {
        $statusCode = 'Stable'
        $label = 'No compaction churn'
        $detail = 'No compaction event was detected in the loaded local range.'
    }
    elseif ($rate -gt 10 -or $rereadSpikes -gt 0) {
        $statusCode = 'Churning'
        $label = 'Compaction churn detected'
        $detail = ('{0} compaction(s), {1} post-compaction reread spike(s), {2:N1}% average context reduction.' -f `
            $compactions.Count, $rereadSpikes, $averageReduction)
    }
    else {
        $statusCode = 'Healthy'
        $label = 'Compaction looks healthy'
        $detail = ('{0} compaction(s) across {1} completed turn(s); {2:N1}% average context reduction.' -f `
            $compactions.Count, $usage.Count, $averageReduction)
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-compaction-health-no-content-no-identifiers'
        StatusCode = $statusCode
        Label = $label
        Detail = $detail
        Compactions = $compactions.Count
        CompactionsPerHundredTurns = $rate
        PairedCompactions = $paired
        AverageContextReductionPercent = $averageReduction
        PostCompactionRereadSpikes = $rereadSpikes
    }
}

function ConvertTo-EfficiencyResetDateTime {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToLocalTime() }
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).LocalDateTime }
    $text = ([string]$Value).Trim()
    [int64]$epoch = 0
    if ([int64]::TryParse($text, [ref]$epoch)) {
        try {
            if ([Math]::Abs($epoch) -ge 100000000000) {
                return [datetimeoffset]::FromUnixTimeMilliseconds($epoch).LocalDateTime
            }
            return [datetimeoffset]::FromUnixTimeSeconds($epoch).LocalDateTime
        }
        catch { return $null }
    }
    try { return [datetimeoffset]::Parse($text).LocalDateTime } catch { return $null }
}

function Get-QuotaWindowMetrics {
    [CmdletBinding()]
    param(
        [object]$RateLimits,
        [datetime]$AsOf = (Get-Date)
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @('primary', 'secondary')) {
        $label = if ($name -eq 'primary') { 'Short window' } else { 'Long window' }
        $window = Get-EfficiencyNestedValue -Object $RateLimits -Name $name
        $usedValue = Get-EfficiencyNestedValue -Object $window -Name 'used_percent'
        if ($null -eq $usedValue) {
            $usedValue = Get-EfficiencyNestedValue -Object $window -Name 'usage_percent'
        }
        $available = ($null -ne $window -and $null -ne $usedValue)
        [double]$used = 0
        if ($available) {
            try { $used = [Math]::Max(0, [Math]::Min(100, [double]$usedValue)) }
            catch { $available = $false }
        }
        $resetAt = ConvertTo-EfficiencyResetDateTime -Value (
            Get-EfficiencyNestedValue -Object $window -Name 'reset_at'
        )
        $windowMinutes = Get-EfficiencyNestedValue -Object $window -Name 'window_minutes'
        if ($null -eq $windowMinutes) {
            $windowMinutes = Get-EfficiencyNestedValue -Object $window -Name 'limit_window_minutes'
        }
        $paceLabel = ''
        $paceDifference = $null
        if ($available -and $null -ne $resetAt -and $null -ne $windowMinutes) {
            try { $duration = [double]$windowMinutes } catch { $duration = 0 }
            if ($duration -gt 0) {
                $startAt = $resetAt.AddMinutes(-$duration)
                $elapsed = ($AsOf - $startAt).TotalMinutes
                if ($elapsed -ge 0 -and $elapsed -le $duration) {
                    $expected = [Math]::Max(0, [Math]::Min(100, ($elapsed / $duration) * 100))
                    $paceDifference = [Math]::Round($used - $expected)
                    if ([Math]::Abs([double]$paceDifference) -lt 5) {
                        $paceLabel = 'Near even pace'
                    }
                    elseif ($paceDifference -gt 0) {
                        $paceLabel = "$paceDifference pts above even pace"
                    }
                    else {
                        $paceLabel = ('{0} pts below even pace' -f [Math]::Abs([double]$paceDifference))
                    }
                }
            }
        }
        $resetLabel = if ($null -eq $resetAt) {
            'Reset time unavailable'
        }
        else {
            $remaining = $resetAt - $AsOf
            if ($remaining.TotalMinutes -le 0) {
                'Reset metadata expired'
            }
            elseif ($remaining.TotalDays -ge 1) {
                'Resets in {0}d {1}h' -f [Math]::Floor($remaining.TotalDays), $remaining.Hours
            }
            elseif ($remaining.TotalHours -ge 1) {
                'Resets in {0}h {1}m' -f [Math]::Floor($remaining.TotalHours), $remaining.Minutes
            }
            else {
                'Resets in {0}m' -f [Math]::Max(1, [Math]::Ceiling($remaining.TotalMinutes))
            }
        }
        $rows.Add([pscustomobject][ordered]@{
            Name = $name
            Label = $label
            Available = $available
            UsedPercent = [Math]::Round($used, 1)
            RemainingPercent = [Math]::Round((100 - $used), 1)
            ResetAt = $resetAt
            ResetLabel = $resetLabel
            PaceDifference = $paceDifference
            PaceLabel = $paceLabel
        })
    }
    return @($rows)
}

function Get-CodexEfficiencyProfileCatalog {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject][ordered]@{
            Name = 'Saver'
            ReasoningEffort = 'low'
            Verbosity = 'low'
            Description = 'Lowest routine reasoning and concise answers; best for straightforward work.'
        },
        [pscustomobject][ordered]@{
            Name = 'Balanced'
            ReasoningEffort = 'medium'
            Verbosity = 'low'
            Description = 'Moderate reasoning with concise answers; recommended general default.'
        },
        [pscustomobject][ordered]@{
            Name = 'Quality'
            ReasoningEffort = 'high'
            Verbosity = 'medium'
            Description = 'More reasoning and detail for difficult work; typically uses more resources.'
        }
    )
}

function Get-DefaultCodexConfigPath {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        throw 'USERPROFILE is unavailable; supply an explicit Codex config path.'
    }
    return Join-Path (Join-Path $env:USERPROFILE '.codex') 'config.toml'
}

function ConvertFrom-EfficiencyTomlValue {
    param([string]$Text)

    $trimmed = $Text.Trim()
    if ($trimmed -match '^"([^"]*)"\s*(?:#.*)?$') {
        return [pscustomobject]@{ Parsed = $true; Value = [string]$Matches[1] }
    }
    if ($trimmed -match '^([0-9]+)\s*(?:#.*)?$') {
        return [pscustomobject]@{ Parsed = $true; Value = [int64]$Matches[1] }
    }
    return [pscustomobject]@{ Parsed = $false; Value = $null }
}

function Get-CodexEfficiencyConfigState {
    [CmdletBinding()]
    param([string]$Path = '')

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultCodexConfigPath }
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $values = @{}
    $present = @{}
    $valid = @{}
    $hasValid = @{}
    foreach ($key in @('model') + $script:managedConfigKeys) {
        $values[$key] = $null
        $present[$key] = $false
        $valid[$key] = $true
        $hasValid[$key] = $false
    }
    [int]$duplicates = 0
    [int]$invalid = 0
    [int]$managedLines = 0

    if ($exists) {
        $insideTable = $false
        foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
            if ($line -match '^\s*\[') { $insideTable = $true }
            if ($insideTable) { continue }
            if ($line -notmatch '^\s*(model|model_reasoning_effort|model_verbosity|model_auto_compact_token_limit)\s*=\s*(.+?)\s*$') {
                continue
            }
            $key = [string]$Matches[1]
            $rawValue = [string]$Matches[2]
            $managedLines++
            if ([bool]$present[$key] -and $key -in $script:managedConfigKeys) { $duplicates++ }
            $present[$key] = $true
            $parsed = ConvertFrom-EfficiencyTomlValue -Text $rawValue
            $isValid = [bool]$parsed.Parsed
            if ($isValid) {
                switch ($key) {
                    'model' {
                        $isValid = (
                            [string]$parsed.Value -match '^[A-Za-z0-9._-]{1,80}$'
                        )
                    }
                    'model_reasoning_effort' {
                        $isValid = (
                            [string]$parsed.Value -in @('none','minimal','low','medium','high','xhigh','max','ultra')
                        )
                    }
                    'model_verbosity' {
                        $isValid = ([string]$parsed.Value -in @('low','medium','high'))
                    }
                    'model_auto_compact_token_limit' {
                        $isValid = (
                            $parsed.Value -is [int64] -and
                            [int64]$parsed.Value -ge 1000 -and
                            [int64]$parsed.Value -le 1000000
                        )
                    }
                }
            }
            if ($isValid) {
                $values[$key] = $parsed.Value
                $hasValid[$key] = $true
                $valid[$key] = $true
            }
            else {
                $valid[$key] = [bool]$hasValid[$key]
                if ($key -in $script:managedConfigKeys) { $invalid++ }
            }
        }
    }

    $issueCount = $duplicates + $invalid
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'allowlisted-codex-settings-no-secrets-no-paths'
        Exists = $exists
        Model = if ([bool]$valid['model']) { [string]$values['model'] } else { '' }
        ModelPresent = [bool]$present['model']
        ReasoningEffort = if ([bool]$valid['model_reasoning_effort']) {
            [string]$values['model_reasoning_effort']
        }
        else { '' }
        ReasoningEffortPresent = [bool]$present['model_reasoning_effort']
        Verbosity = if ([bool]$valid['model_verbosity']) {
            [string]$values['model_verbosity']
        }
        else { '' }
        VerbosityPresent = [bool]$present['model_verbosity']
        AutoCompactTokenLimit = if ([bool]$valid['model_auto_compact_token_limit']) {
            $values['model_auto_compact_token_limit']
        }
        else { $null }
        AutoCompactTokenLimitPresent = [bool]$present['model_auto_compact_token_limit']
        ManagedLines = $managedLines
        DuplicateCount = $duplicates
        InvalidCount = $invalid
        IssueCount = $issueCount
        StatusCode = if (-not $exists) { 'Defaults' } elseif ($issueCount -eq 0) { 'Healthy' } else { 'NeedsRepair' }
        StatusLabel = if (-not $exists) {
            'Codex defaults active'
        }
        elseif ($issueCount -eq 0) {
            'Allowlisted settings valid'
        }
        else {
            "$issueCount allowlisted configuration issue(s)"
        }
        RepairAvailable = ($issueCount -gt 0)
    }
}

function Get-CodexEfficiencyConfigPreview {
    [CmdletBinding()]
    param(
        [ValidateSet('Saver','Balanced','Quality')][string]$ProfileName,
        [string]$Path = ''
    )

    $efficiencyProfile = @(Get-CodexEfficiencyProfileCatalog | Where-Object Name -eq $ProfileName)[0]
    $state = Get-CodexEfficiencyConfigState -Path $Path
    $changes = [System.Collections.Generic.List[object]]::new()
    if ([string]$state.ReasoningEffort -ne [string]$efficiencyProfile.ReasoningEffort) {
        $changes.Add([pscustomobject][ordered]@{
            Setting = 'Reasoning effort'
            CurrentValue = $(if ($state.ReasoningEffort) { $state.ReasoningEffort } else { 'Codex default' })
            ProposedValue = [string]$efficiencyProfile.ReasoningEffort
            Impact = 'Changes future Codex reasoning effort; no request is made by this monitor.'
        })
    }
    if ([string]$state.Verbosity -ne [string]$efficiencyProfile.Verbosity) {
        $changes.Add([pscustomobject][ordered]@{
            Setting = 'Answer verbosity'
            CurrentValue = $(if ($state.Verbosity) { $state.Verbosity } else { 'Codex default' })
            ProposedValue = [string]$efficiencyProfile.Verbosity
            Impact = 'Changes future answer detail; no request is made by this monitor.'
        })
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'allowlisted-config-preview-no-secrets-no-paths'
        ProfileName = $efficiencyProfile.Name
        Description = $efficiencyProfile.Description
        ChangeCount = $changes.Count
        Changes = @($changes)
        RequiresConfirmation = ($changes.Count -gt 0)
        CurrentStatus = $state.StatusLabel
    }
}

function Export-CodexEfficiencyRollback {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rollback = [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'allowlisted-codex-settings-no-secrets-no-paths'
        CreatedAt = (Get-Date).ToString('o')
        ConfigExisted = [bool]$State.Exists
        ReasoningEffortPresent = [bool]$State.ReasoningEffortPresent
        ReasoningEffort = [string]$State.ReasoningEffort
        VerbosityPresent = [bool]$State.VerbosityPresent
        Verbosity = [string]$State.Verbosity
        AutoCompactTokenLimitPresent = [bool]$State.AutoCompactTokenLimitPresent
        AutoCompactTokenLimit = $State.AutoCompactTokenLimit
    }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $rollback | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Write-CodexManagedConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Desired,
        [string[]]$KeysToNormalize
    )

    $lines = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        @(Get-Content -LiteralPath $Path -Encoding UTF8)
    }
    else { @() }
    $beforeTable = [System.Collections.Generic.List[string]]::new()
    $tables = [System.Collections.Generic.List[string]]::new()
    $insideTable = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[') { $insideTable = $true }
        if (-not $insideTable -and
            $line -match '^\s*(model_reasoning_effort|model_verbosity|model_auto_compact_token_limit)\s*=') {
            $key = [string]$Matches[1]
            if ($key -in $KeysToNormalize) { continue }
        }
        if ($insideTable) { $tables.Add($line) } else { $beforeTable.Add($line) }
    }
    while ($beforeTable.Count -gt 0 -and
        [string]::IsNullOrWhiteSpace($beforeTable[$beforeTable.Count - 1])) {
        $beforeTable.RemoveAt($beforeTable.Count - 1)
    }
    foreach ($key in $KeysToNormalize) {
        if (-not $Desired.Contains($key) -or $null -eq $Desired[$key] -or
            [string]::IsNullOrWhiteSpace([string]$Desired[$key])) {
            continue
        }
        if ($key -eq 'model_auto_compact_token_limit') {
            $beforeTable.Add(('{0} = {1}' -f $key, [int64]$Desired[$key]))
        }
        else {
            $beforeTable.Add(('{0} = "{1}"' -f $key, [string]$Desired[$key]))
        }
    }
    if ($tables.Count -gt 0 -and $beforeTable.Count -gt 0) { $beforeTable.Add('') }
    $output = @($beforeTable) + @($tables)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Set-Content -LiteralPath $temporary -Value $output -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Set-CodexEfficiencyConfigProfile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet('Saver','Balanced','Quality')][string]$ProfileName,
        [string]$Path = '',
        [Parameter(Mandatory = $true)][string]$RollbackPath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultCodexConfigPath }
    $preview = Get-CodexEfficiencyConfigPreview -ProfileName $ProfileName -Path $Path
    if ($preview.ChangeCount -eq 0) {
        return [pscustomobject]@{
            Applied = $false
            ProfileName = $ProfileName
            ChangeCount = 0
            State = Get-CodexEfficiencyConfigState -Path $Path
        }
    }
    if (-not $PSCmdlet.ShouldProcess('the allowlisted Codex configuration keys', "Apply $ProfileName efficiency profile")) {
        return [pscustomobject]@{ Applied = $false; ProfileName = $ProfileName; ChangeCount = 0; State = $null }
    }
    $state = Get-CodexEfficiencyConfigState -Path $Path
    Export-CodexEfficiencyRollback -State $state -Path $RollbackPath
    $efficiencyProfile = @(Get-CodexEfficiencyProfileCatalog | Where-Object Name -eq $ProfileName)[0]
    $desired = [ordered]@{
        model_reasoning_effort = [string]$efficiencyProfile.ReasoningEffort
        model_verbosity = [string]$efficiencyProfile.Verbosity
    }
    Write-CodexManagedConfig -Path $Path -Desired $desired `
        -KeysToNormalize @('model_reasoning_effort','model_verbosity')
    return [pscustomobject][ordered]@{
        Applied = $true
        ProfileName = $ProfileName
        ChangeCount = $preview.ChangeCount
        State = Get-CodexEfficiencyConfigState -Path $Path
        RestartCodexRecommended = $true
        OutboundRequestMade = $false
    }
}

function Repair-CodexEfficiencyConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Path = '',
        [Parameter(Mandatory = $true)][string]$RollbackPath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultCodexConfigPath }
    $state = Get-CodexEfficiencyConfigState -Path $Path
    if (-not $state.RepairAvailable) {
        return [pscustomobject]@{ Repaired = $false; IssueCount = 0; State = $state }
    }
    if (-not $PSCmdlet.ShouldProcess('the allowlisted Codex configuration keys', 'Normalize duplicate or invalid values')) {
        return [pscustomobject]@{ Repaired = $false; IssueCount = $state.IssueCount; State = $state }
    }
    Export-CodexEfficiencyRollback -State $state -Path $RollbackPath
    $desired = [ordered]@{}
    if ($state.ReasoningEffort) { $desired['model_reasoning_effort'] = $state.ReasoningEffort }
    if ($state.Verbosity) { $desired['model_verbosity'] = $state.Verbosity }
    if ($null -ne $state.AutoCompactTokenLimit) {
        $desired['model_auto_compact_token_limit'] = [int64]$state.AutoCompactTokenLimit
    }
    Write-CodexManagedConfig -Path $Path -Desired $desired -KeysToNormalize $script:managedConfigKeys
    return [pscustomobject][ordered]@{
        Repaired = $true
        IssueCount = $state.IssueCount
        State = Get-CodexEfficiencyConfigState -Path $Path
        OutboundRequestMade = $false
    }
}

function Restore-CodexEfficiencyConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Path = '',
        [Parameter(Mandatory = $true)][string]$RollbackPath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-DefaultCodexConfigPath }
    if (-not (Test-Path -LiteralPath $RollbackPath -PathType Leaf)) {
        throw 'No local allowlisted configuration rollback is available.'
    }
    $rollback = Get-Content -LiteralPath $RollbackPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$rollback.SchemaVersion -ne 1 -or
        [string]$rollback.PrivacyClass -ne 'allowlisted-codex-settings-no-secrets-no-paths') {
        throw 'The local configuration rollback schema is unsupported.'
    }
    if (-not $PSCmdlet.ShouldProcess('the allowlisted Codex configuration keys', 'Restore prior values')) {
        return [pscustomobject]@{ Restored = $false; State = $null }
    }
    $desired = [ordered]@{}
    if ([bool]$rollback.ReasoningEffortPresent) {
        $desired['model_reasoning_effort'] = [string]$rollback.ReasoningEffort
    }
    if ([bool]$rollback.VerbosityPresent) {
        $desired['model_verbosity'] = [string]$rollback.Verbosity
    }
    if ([bool]$rollback.AutoCompactTokenLimitPresent) {
        $desired['model_auto_compact_token_limit'] = [int64]$rollback.AutoCompactTokenLimit
    }
    Write-CodexManagedConfig -Path $Path -Desired $desired -KeysToNormalize $script:managedConfigKeys
    return [pscustomobject][ordered]@{
        Restored = $true
        State = Get-CodexEfficiencyConfigState -Path $Path
        OutboundRequestMade = $false
    }
}

function Get-CodexToolSurfaceAudit {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = '',
        [object[]]$IntegrationEvents
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Get-DefaultCodexConfigPath }
    [int]$configuredMcp = 0
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $ConfigPath -Encoding UTF8) {
            if ($line -match '^\s*\[(?:mcp_servers|mcp)\.[^\]]+\]\s*$') { $configuredMcp++ }
        }
    }
    $observed = @($IntegrationEvents | Where-Object { $null -ne $_ })
    $categories = @($observed | ForEach-Object {
        '{0}|{1}' -f [string](Get-EfficiencyProperty $_ 'Kind'), [string](Get-EfficiencyProperty $_ 'Name')
    } | Sort-Object -Unique)
    $opportunity = ($configuredMcp -gt 0 -and $observed.Count -gt 0 -and $configuredMcp -gt $categories.Count)
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'aggregate-tool-surface-no-names-no-paths'
        ConfiguredMcpServers = $configuredMcp
        ObservedToolCategories = $categories.Count
        ObservedCalls = $observed.Count
        ReviewOpportunity = $opportunity
        Recommendation = if ($opportunity) {
            'Review unused tool surfaces before a fresh task; this monitor never disables them automatically.'
        }
        elseif ($configuredMcp -eq 0) {
            'No configured MCP server sections were counted.'
        }
        else {
            'No obvious surface-count mismatch was detected in the loaded range.'
        }
        OutboundRequestMade = $false
    }
}

function Get-CodexEfficiencyPolicyText {
    [CmdletBinding()]
    param()

    return @(
        $script:policyStartMarker
        '## Local usage-efficiency policy'
        ''
        '- Use RTK for supported verbose external CLI commands; keep RTK telemetry disabled.'
        '- Prefer targeted `rg` searches, result counts, and narrow line ranges before broad file reads.'
        '- Cap exploratory result sets and summarize large local outputs before returning them to the model.'
        '- Use quiet test/build modes when full logs are unnecessary; expand output only after a failure.'
        '- Reuse unchanged context and avoid repeating instructions or data already available in the task.'
        '- Keep monitoring local: never send monitor data, local logs, prompts, or tool output to a service.'
        $script:policyEndMarker
    ) -join [Environment]::NewLine
}

function Get-CodexEfficiencyPolicyState {
    [CmdletBinding()]
    param([string]$Path = '')

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            throw 'USERPROFILE is unavailable; supply an explicit AGENTS.md path.'
        }
        $Path = Join-Path (Join-Path $env:USERPROFILE '.codex') 'AGENTS.md'
    }
    $content = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    else { '' }
    $startCount = ([regex]::Matches($content, [regex]::Escape($script:policyStartMarker))).Count
    $endCount = ([regex]::Matches($content, [regex]::Escape($script:policyEndMarker))).Count
    $startIndex = $content.IndexOf($script:policyStartMarker, [System.StringComparison]::Ordinal)
    $endIndex = $content.IndexOf($script:policyEndMarker, [System.StringComparison]::Ordinal)
    $installed = ($startCount -eq 1 -and $endCount -eq 1 -and $startIndex -lt $endIndex)
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'managed-policy-status-no-content-no-paths'
        Installed = $installed
        StatusCode = if ($startCount -eq 0 -and $endCount -eq 0) {
            'Off'
        }
        elseif ($installed) {
            'Installed'
        }
        else {
            'NeedsRepair'
        }
        StatusLabel = if ($startCount -eq 0 -and $endCount -eq 0) {
            'Efficiency policy not installed'
        }
        elseif ($installed) {
            'Managed efficiency policy installed'
        }
        else {
            'Managed policy markers need repair'
        }
        OutboundRequestMade = $false
    }
}

function Set-CodexEfficiencyPolicy {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][bool]$Enabled,
        [string]$Path = ''
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            throw 'USERPROFILE is unavailable; supply an explicit AGENTS.md path.'
        }
        $Path = Join-Path (Join-Path $env:USERPROFILE '.codex') 'AGENTS.md'
    }
    $state = Get-CodexEfficiencyPolicyState -Path $Path
    if ($state.StatusCode -eq 'NeedsRepair') {
        throw 'Managed efficiency-policy markers are unbalanced; repair the marker block manually before changing it.'
    }
    if ([bool]$state.Installed -eq $Enabled) { return $state }
    $action = if ($Enabled) { 'Install managed local efficiency policy' } else { 'Remove managed local efficiency policy' }
    if (-not $PSCmdlet.ShouldProcess('the managed Codex efficiency-policy block', $action)) { return $state }
    $content = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }
    else { '' }
    if ($Enabled) {
        $separator = if ([string]::IsNullOrWhiteSpace($content)) { '' } else { [Environment]::NewLine + [Environment]::NewLine }
        $content = $content.TrimEnd() + $separator + (Get-CodexEfficiencyPolicyText) + [Environment]::NewLine
    }
    else {
        $pattern = '(?s)\s*' + [regex]::Escape($script:policyStartMarker) + '.*?' +
            [regex]::Escape($script:policyEndMarker) + '\s*'
        $content = ([regex]::Replace($content, $pattern, [Environment]::NewLine + [Environment]::NewLine)).Trim()
        if ($content) { $content += [Environment]::NewLine }
    }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        Set-Content -LiteralPath $temporary -Value $content -Encoding UTF8 -NoNewline
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
    return Get-CodexEfficiencyPolicyState -Path $Path
}

Export-ModuleMember -Function @(
    'New-CodexSchemaTracker',
    'Add-CodexSchemaObservation',
    'Get-CodexSchemaHealth',
    'Get-PromptCacheSavings',
    'Get-SessionEfficiencyAdvice',
    'Get-CompactionChurn',
    'Get-QuotaWindowMetrics',
    'Get-CodexEfficiencyProfileCatalog',
    'Get-CodexEfficiencyConfigState',
    'Get-CodexEfficiencyConfigPreview',
    'Set-CodexEfficiencyConfigProfile',
    'Repair-CodexEfficiencyConfig',
    'Restore-CodexEfficiencyConfig',
    'Get-CodexToolSurfaceAudit',
    'Get-CodexEfficiencyPolicyText',
    'Get-CodexEfficiencyPolicyState',
    'Set-CodexEfficiencyPolicy'
)
