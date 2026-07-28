Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RtkExecutable {
    [CmdletBinding()]
    param([string]$ConfiguredPath = '')

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $candidates.Add($ConfiguredPath)
    }
    try {
        $command = Get-Command rtk.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
            $candidates.Add([string]$command.Source)
        }
    }
    catch { Write-Verbose 'rtk.exe was not found on PATH.' }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates.Add((Join-Path $env:USERPROFILE '.local\bin\rtk.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\rtk\rtk.exe'))
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        try {
            $fullPath = [System.IO.Path]::GetFullPath([string]$candidate)
            if (Test-Path -LiteralPath $fullPath -PathType Leaf) { return $fullPath }
        }
        catch { Write-Verbose "Ignored invalid RTK candidate path: $candidate" }
    }
    return ''
}

function Get-RtkDefaultDatabasePath {
    [CmdletBinding()]
    param()

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'rtk\history.db'))
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'rtk\tracking.db'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $candidates.Add((Join-Path $env:APPDATA 'rtk\history.db'))
        $candidates.Add((Join-Path $env:APPDATA 'rtk\tracking.db'))
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    if ($candidates.Count -gt 0) {
        return [System.IO.Path]::GetFullPath($candidates[0])
    }
    return ''
}

function ConvertTo-RtkProcessArgument {
    param([string]$Value)

    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-LocalRtk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [string[]]$Arguments = @(),
        [ValidateRange(250, 30000)][int]$TimeoutMilliseconds = 5000
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ExecutablePath
    $startInfo.Arguments = (@($Arguments | ForEach-Object { ConvertTo-RtkProcessArgument -Value ([string]$_) }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    # Defense in depth: monitor-triggered RTK diagnostics can never emit RTK telemetry.
    $startInfo.EnvironmentVariables['RTK_TELEMETRY_DISABLED'] = '1'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            return [pscustomobject]@{ ExitCode = -1; Stdout = ''; Stderr = 'RTK did not start.'; TimedOut = $false }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            try { $process.Kill() } catch { Write-Verbose 'RTK timed out and had already exited before termination.' }
            return [pscustomobject]@{ ExitCode = -1; Stdout = ''; Stderr = 'RTK timed out.'; TimedOut = $true }
        }
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Stdout = [string]$stdout
            Stderr = [string]$stderr
            TimedOut = $false
        }
    }
    catch {
        return [pscustomobject]@{ ExitCode = -1; Stdout = ''; Stderr = $_.Exception.Message; TimedOut = $false }
    }
    finally {
        $process.Dispose()
    }
}

function ConvertFrom-RtkGainJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Json)

    $value = $Json | ConvertFrom-Json
    if ($null -eq $value -or $null -eq $value.PSObject.Properties['summary']) {
        throw 'RTK gain output did not contain a summary.'
    }
    $summary = $value.summary
    $daily = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @($value.daily)) {
        if ($null -eq $row) { continue }
        $daily.Add([pscustomobject][ordered]@{
            Date = [string]$row.date
            Commands = [int64]$row.commands
            InputTokensEstimate = [int64]$row.input_tokens
            OutputTokensEstimate = [int64]$row.output_tokens
            SavedTokensEstimate = [int64]$row.saved_tokens
            SavingsPercent = [Math]::Round([double]$row.savings_pct, 1)
            TotalTimeMilliseconds = [int64]$row.total_time_ms
        })
    }
    return [pscustomobject][ordered]@{
        TotalCommands = [int64]$summary.total_commands
        InputTokensEstimate = [int64]$summary.total_input
        OutputTokensEstimate = [int64]$summary.total_output
        SavedTokensEstimate = [int64]$summary.total_saved
        SavingsPercent = [Math]::Round([double]$summary.avg_savings_pct, 1)
        TotalTimeMilliseconds = [int64]$summary.total_time_ms
        Daily = @($daily)
    }
}

function Get-RtkFailureSummary {
    [CmdletBinding()]
    param([string]$Text = '')

    $failureCount = 0
    $recoveryRate = $null
    if ($Text -match '(?im)No parse failures recorded') {
        return [pscustomobject]@{ FailureCount = 0; RecoveryRate = $null; Detail = 'No parse failures recorded.' }
    }
    if ($Text -match '(?im)Total failures\s*:?\s*(\d+)') {
        $failureCount = [int]$Matches[1]
    }
    elseif ($Text -match '(?im)(\d+)\s+(?:parse\s+)?failures?') {
        $failureCount = [int]$Matches[1]
    }
    if ($Text -match '(?im)Recovery rate\s*:?\s*([0-9.]+)%') {
        $recoveryRate = [double]$Matches[1]
    }
    return [pscustomobject]@{
        FailureCount = $failureCount
        RecoveryRate = $recoveryRate
        Detail = $(if ([string]::IsNullOrWhiteSpace($Text)) { 'RTK did not return failure diagnostics.' } else { $Text.Trim() })
    }
}

function ConvertTo-RtkStatusSnapshot {
    param(
        [string]$HealthCode,
        [string]$HealthLabel,
        [string]$Message,
        [bool]$Installed = $false,
        [bool]$Working = $false,
        [string]$Version = '',
        [string]$ExecutablePath = '',
        [string]$DatabasePath = '',
        [datetime]$LastTrackedAt = [datetime]::MinValue,
        [double]$DataAgeMinutes = -1,
        [int64]$TotalCommands = 0,
        [int64]$InputTokensEstimate = 0,
        [int64]$OutputTokensEstimate = 0,
        [int64]$SavedTokensEstimate = 0,
        [double]$SavingsPercent = 0,
        [int]$FailureCount = 0,
        [Nullable[double]]$RecoveryRate = $null,
        [object[]]$Daily = @(),
        [string]$FailureDetail = ''
    )

    $todayKey = (Get-Date).ToString('yyyy-MM-dd')
    $today = @($Daily | Where-Object { [string]$_.Date -eq $todayKey } | Select-Object -First 1)
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        HealthCode = $HealthCode
        HealthLabel = $HealthLabel
        Message = $Message
        Installed = $Installed
        Working = $Working
        Version = $Version
        ExecutablePath = $ExecutablePath
        DatabasePath = $DatabasePath
        LastTrackedAt = $(if ($LastTrackedAt -eq [datetime]::MinValue) { $null } else { $LastTrackedAt })
        DataAgeMinutes = $DataAgeMinutes
        TotalCommands = $TotalCommands
        InputTokensEstimate = $InputTokensEstimate
        OutputTokensEstimate = $OutputTokensEstimate
        SavedTokensEstimate = $SavedTokensEstimate
        SavingsPercent = $SavingsPercent
        TodayCommands = $(if ($today.Count -gt 0) { [int64]$today[0].Commands } else { 0 })
        TodaySavedTokensEstimate = $(if ($today.Count -gt 0) { [int64]$today[0].SavedTokensEstimate } else { 0 })
        TodaySavingsPercent = $(if ($today.Count -gt 0) { [double]$today[0].SavingsPercent } else { 0 })
        FailureCount = $FailureCount
        RecoveryRate = $RecoveryRate
        FailureDetail = $FailureDetail
        Daily = @($Daily)
        TelemetryBlocked = $true
        TelemetryDetail = 'RTK_TELEMETRY_DISABLED=1 is forced for every monitor query.'
        EstimateDetail = 'RTK estimates shell-output tokens from bytes; these are not billed ChatGPT tokens or cash savings.'
        ObservedAt = Get-Date
        OutboundRequestMade = $false
    }
}

function Get-RtkSavingsSnapshot {
    [CmdletBinding()]
    param(
        [string]$RtkPath = '',
        [string]$DatabasePath = '',
        [datetime]$RecentShellActivityAt = [datetime]::MinValue,
        [datetime]$Now = (Get-Date),
        [scriptblock]$CommandRunner,
        [switch]$Disabled
    )

    if ($Disabled) {
        return ConvertTo-RtkStatusSnapshot -HealthCode 'Disabled' -HealthLabel 'Disabled for this session' `
            -Message 'RTK diagnostics were disabled by the monitor launch parameters.'
    }
    $executable = Resolve-RtkExecutable -ConfiguredPath $RtkPath
    if ([string]::IsNullOrWhiteSpace($executable)) {
        return ConvertTo-RtkStatusSnapshot -HealthCode 'NotInstalled' -HealthLabel 'Not installed' `
            -Message 'RTK was not found. Savings cannot be measured until RTK is installed and used to run supported commands.'
    }
    if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
        $DatabasePath = Get-RtkDefaultDatabasePath
    }
    $selectedRunner = $CommandRunner
    $invoke = {
        param([string[]]$Arguments)
        if ($null -ne $selectedRunner) {
            return & $selectedRunner $executable $Arguments
        }
        return Invoke-LocalRtk -ExecutablePath $executable -Arguments $Arguments
    }

    $versionResult = & $invoke @('--version')
    $versionText = (([string]$versionResult.Stdout + ' ' + [string]$versionResult.Stderr).Trim())
    $version = if ($versionText -match '(\d+\.\d+\.\d+(?:[-+][^\s]+)?)') { $Matches[1] } else { $versionText }
    $gainResult = & $invoke @('gain','--all','--format','json')
    if ([int]$gainResult.ExitCode -ne 0 -or [bool]$gainResult.TimedOut) {
        $detail = ([string]$gainResult.Stderr).Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'RTK gain returned a non-zero exit code.' }
        return ConvertTo-RtkStatusSnapshot -HealthCode 'Unavailable' -HealthLabel 'Not working' `
            -Message $detail -Installed $true -Version $version -ExecutablePath $executable -DatabasePath $DatabasePath
    }
    try {
        $gain = ConvertFrom-RtkGainJson -Json ([string]$gainResult.Stdout)
    }
    catch {
        return ConvertTo-RtkStatusSnapshot -HealthCode 'Unavailable' -HealthLabel 'Invalid local data' `
            -Message $_.Exception.Message -Installed $true -Version $version -ExecutablePath $executable -DatabasePath $DatabasePath
    }

    $failureResult = & $invoke @('gain','--failures')
    $failureText = (([string]$failureResult.Stdout + [Environment]::NewLine + [string]$failureResult.Stderr).Trim())
    $failures = if ([int]$failureResult.ExitCode -eq 0) {
        Get-RtkFailureSummary -Text $failureText
    }
    else {
        [pscustomobject]@{ FailureCount = 0; RecoveryRate = $null; Detail = 'RTK failure diagnostics were unavailable.' }
    }

    $lastTrackedAt = [datetime]::MinValue
    $dataAgeMinutes = -1
    if (-not [string]::IsNullOrWhiteSpace($DatabasePath) -and
        (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        $lastTrackedAt = (Get-Item -LiteralPath $DatabasePath).LastWriteTime
        $dataAgeMinutes = [Math]::Max(0, [Math]::Round(($Now - $lastTrackedAt).TotalMinutes, 1))
    }

    $healthCode = 'Idle'
    $healthLabel = 'Working - idle'
    $message = 'RTK is installed and its local savings history can be read.'
    $working = $true
    if ([int64]$gain.TotalCommands -eq 0) {
        $healthCode = 'ReadyNoData'
        $healthLabel = 'Ready - no tracked commands'
        $message = 'RTK is available, but no supported command has been tracked yet.'
    }
    elseif ([int]$failures.FailureCount -gt 0) {
        $healthCode = 'Degraded'
        $healthLabel = 'Degraded'
        $message = '{0} RTK parse failure(s) were recorded; raw-output fallback may have reduced or eliminated savings.' -f $failures.FailureCount
        $working = $false
    }
    elseif ($RecentShellActivityAt -ne [datetime]::MinValue -and
        $RecentShellActivityAt -ge $Now.AddMinutes(-15) -and
        ($lastTrackedAt -eq [datetime]::MinValue -or $lastTrackedAt -lt $RecentShellActivityAt.AddMinutes(-2))) {
        $healthCode = 'PossibleBypass'
        $healthLabel = 'Possible bypass'
        $message = 'Recent local tool activity is newer than RTK history. A command may have run without the RTK prefix.'
        $working = $false
    }
    elseif ([int64]$gain.TotalCommands -ge 3 -and [int64]$gain.SavedTokensEstimate -eq 0) {
        $healthCode = 'Ineffective'
        $healthLabel = 'Working - no savings'
        $message = 'RTK is tracking commands, but it has not reduced shell output yet.'
    }
    elseif ($lastTrackedAt -ne [datetime]::MinValue -and $dataAgeMinutes -le 15) {
        $healthCode = 'Active'
        $healthLabel = 'Working - active'
        $message = 'RTK tracking is active and its local history is current.'
    }
    elseif ([int64]$gain.SavedTokensEstimate -eq 0) {
        $healthCode = 'Idle'
        $healthLabel = 'Working - no savings yet'
        $message = 'RTK is tracking commands; no output reduction has been measured yet.'
    }
    else {
        $message = 'RTK is installed, tracking locally, and has recorded output reduction.'
    }

    return ConvertTo-RtkStatusSnapshot -HealthCode $healthCode -HealthLabel $healthLabel -Message $message `
        -Installed $true -Working $working -Version $version -ExecutablePath $executable -DatabasePath $DatabasePath `
        -LastTrackedAt $lastTrackedAt -DataAgeMinutes $dataAgeMinutes `
        -TotalCommands $gain.TotalCommands -InputTokensEstimate $gain.InputTokensEstimate `
        -OutputTokensEstimate $gain.OutputTokensEstimate -SavedTokensEstimate $gain.SavedTokensEstimate `
        -SavingsPercent $gain.SavingsPercent -FailureCount $failures.FailureCount `
        -RecoveryRate $failures.RecoveryRate -Daily $gain.Daily -FailureDetail $failures.Detail
}

Export-ModuleMember -Function @(
    'Resolve-RtkExecutable',
    'Get-RtkDefaultDatabasePath',
    'Invoke-LocalRtk',
    'ConvertFrom-RtkGainJson',
    'Get-RtkFailureSummary',
    'Get-RtkSavingsSnapshot'
)
