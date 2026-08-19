Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-PersonalMonitorSettings {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        StartAtSignIn = $false
        StartMinimizedToTray = $false
        RefreshSeconds = 5
        NotificationsEnabled = $true
        ShowChatTitles = $true
        ReportingTimeZone = 'Local'
        LastBackupAt = $null
        LastDiagnosticsAt = $null
    }
}

function Import-PersonalMonitorSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-PersonalMonitorSettings
    }
    $settings = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$settings.SchemaVersion -ne 1) { throw 'Unsupported personal settings schema.' }
    foreach ($property in @('StartAtSignIn','StartMinimizedToTray','LastBackupAt','LastDiagnosticsAt')) {
        if ($null -eq $settings.PSObject.Properties[$property]) {
            throw "Personal settings are missing $property."
        }
    }
    # RefreshSeconds was added to schema 1 after the first public settings
    # files existed. Preserve backward compatibility instead of resetting the
    # user's other personal preferences.
    if ($null -eq $settings.PSObject.Properties['RefreshSeconds']) {
        $settings | Add-Member -NotePropertyName RefreshSeconds -NotePropertyValue 5
    }
    foreach ($default in @(
        @{ Name='NotificationsEnabled'; Value=$true },
        @{ Name='ShowChatTitles'; Value=$true },
        @{ Name='ReportingTimeZone'; Value='Local' }
    )) {
        if ($null -eq $settings.PSObject.Properties[$default.Name]) {
            $settings | Add-Member -NotePropertyName $default.Name -NotePropertyValue $default.Value
        }
    }
    $refreshSeconds = [int]$settings.RefreshSeconds
    if ($refreshSeconds -lt 1 -or $refreshSeconds -gt 60) {
        throw 'Personal settings RefreshSeconds must be between 1 and 60.'
    }
    $settings.RefreshSeconds = $refreshSeconds
    $settings.NotificationsEnabled = [bool]$settings.NotificationsEnabled
    $settings.ShowChatTitles = [bool]$settings.ShowChatTitles
    if ([string]::IsNullOrWhiteSpace([string]$settings.ReportingTimeZone)) { $settings.ReportingTimeZone = 'Local' }
    return $settings
}

function Export-PersonalMonitorSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Settings,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([int]$Settings.SchemaVersion -ne 1) { throw 'Refusing to write unsupported personal settings.' }
    if ($null -eq $Settings.PSObject.Properties['RefreshSeconds'] -or
        [int]$Settings.RefreshSeconds -lt 1 -or [int]$Settings.RefreshSeconds -gt 60) {
        throw 'Refusing to write personal settings with an invalid RefreshSeconds value.'
    }
    foreach ($property in @('NotificationsEnabled','ShowChatTitles','ReportingTimeZone')) {
        if ($null -eq $Settings.PSObject.Properties[$property]) { throw "Refusing to write personal settings missing $property." }
    }
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and
        -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Get-PersonalStartupRegistrationPath {
    [CmdletBinding()]
    param([string]$StartupFolder = '')

    if ([string]::IsNullOrWhiteSpace($StartupFolder)) {
        $StartupFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    }
    if ([string]::IsNullOrWhiteSpace($StartupFolder)) {
        throw 'The current Windows account startup folder is unavailable.'
    }
    return Join-Path ([System.IO.Path]::GetFullPath($StartupFolder)) 'Live Codex Usage Monitor.cmd'
}

function Test-PersonalStartupRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [string]$StartupFolder = ''
    )

    $registrationPath = Get-PersonalStartupRegistrationPath -StartupFolder $StartupFolder
    if (-not (Test-Path -LiteralPath $registrationPath -PathType Leaf)) {
        return [pscustomobject]@{
            Registered = $false
            MatchesLauncher = $false
            RegistrationPath = $registrationPath
            Status = 'Off'
        }
    }
    $content = Get-Content -LiteralPath $registrationPath -Raw -Encoding UTF8
    $expected = [System.IO.Path]::GetFullPath($LauncherPath)
    return [pscustomobject]@{
        Registered = $true
        MatchesLauncher = ($content -like "*$expected*" -and $content -match 'StartMinimizedToTray')
        RegistrationPath = $registrationPath
        Status = $(if ($content -like "*$expected*" -and $content -match 'StartMinimizedToTray') { 'Enabled' } else { 'Needs repair' })
    }
}

function Set-PersonalStartupRegistration {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][bool]$Enabled,
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [string]$StartupFolder = ''
    )

    $resolvedLauncher = [System.IO.Path]::GetFullPath($LauncherPath)
    if (-not (Test-Path -LiteralPath $resolvedLauncher -PathType Leaf)) {
        throw "Monitor launcher not found: $resolvedLauncher"
    }
    if ($resolvedLauncher.Contains('"')) { throw 'The launcher path cannot contain a quotation mark.' }
    $registrationPath = Get-PersonalStartupRegistrationPath -StartupFolder $StartupFolder
    if ($Enabled) {
        $parent = Split-Path -Parent $registrationPath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $parent)
        }
        if ($PSCmdlet.ShouldProcess($registrationPath, 'Enable start at sign-in')) {
            $lines = @(
                '@echo off'
                'rem Live Codex Usage Monitor - current Windows account only'
                ('start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -StartMinimizedToTray' -f $resolvedLauncher)
            )
            Set-Content -LiteralPath $registrationPath -Value $lines -Encoding Ascii
        }
    }
    elseif ((Test-Path -LiteralPath $registrationPath -PathType Leaf) -and
        $PSCmdlet.ShouldProcess($registrationPath, 'Disable start at sign-in')) {
        $content = Get-Content -LiteralPath $registrationPath -Raw -Encoding UTF8
        if ($content -notmatch 'Live Codex Usage Monitor') {
            throw 'Refusing to remove an unrecognized startup file.'
        }
        Remove-Item -LiteralPath $registrationPath -Force
    }
    return Test-PersonalStartupRegistration -LauncherPath $resolvedLauncher -StartupFolder $StartupFolder
}

function Get-PersonalBackupAllowList {
    return @(
        'aggregate-v1.json',
        'official-dashboard-history-v1.json',
        'guard-policy-v1.json',
        'cost-profile-v1.json',
        'personal-settings-v1.json'
    )
}

function Export-PersonalMonitorBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory,
        [string]$AppVersion = ''
    )

    $resolvedStateRoot = [System.IO.Path]::GetFullPath($StateRoot)
    $resolvedDestination = [System.IO.Path]::GetFullPath($DestinationDirectory)
    if (-not (Test-Path -LiteralPath $resolvedDestination -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $resolvedDestination)
    }
    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('live-codex-backup-{0}' -f [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    try {
        $manifestFiles = [System.Collections.Generic.List[object]]::new()
        foreach ($name in Get-PersonalBackupAllowList) {
            $source = Join-Path $resolvedStateRoot $name
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            $destination = Join-Path $temporaryRoot $name
            Copy-Item -LiteralPath $source -Destination $destination
            $manifestFiles.Add([pscustomobject][ordered]@{
                Name = $name
                Sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
        $manifest = [pscustomobject][ordered]@{
            SchemaVersion = 1
            PrivacyClass = 'personal-aggregate-settings-no-raw-logs'
            CreatedAt = (Get-Date).ToString('o')
            AppVersion = $AppVersion
            Files = @($manifestFiles)
        }
        $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $temporaryRoot 'manifest.json') -Encoding UTF8
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $fileName = 'live-codex-personal-backup-{0}.zip' -f (Get-Date).ToString('yyyyMMdd-HHmmss')
        $backupPath = Join-Path $resolvedDestination $fileName
        if (Test-Path -LiteralPath $backupPath) {
            $backupPath = Join-Path $resolvedDestination ('live-codex-personal-backup-{0}-{1}.zip' -f (Get-Date).ToString('yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0,6))
        }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($temporaryRoot, $backupPath)
        return [pscustomobject][ordered]@{
            Path = $backupPath
            CreatedAt = Get-Date
            Files = $manifestFiles.Count
            PrivacyClass = $manifest.PrivacyClass
        }
    }
    finally {
        $resolvedTemporary = [System.IO.Path]::GetFullPath($temporaryRoot)
        $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($resolvedTemporary.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolvedTemporary -PathType Container)) {
            Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
        }
    }
}

function Get-PersonalMonitorBackupPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Backup not found: $Path" }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead([System.IO.Path]::GetFullPath($Path))
    try {
        $allowed = @(Get-PersonalBackupAllowList)
        $entries = @($archive.Entries)
        foreach ($entry in $entries) {
            if ([string]::IsNullOrWhiteSpace($entry.Name) -or $entry.FullName -ne $entry.Name) {
                throw 'Backup contains an unsafe nested or relative path.'
            }
            if ($entry.Name -ne 'manifest.json' -and $entry.Name -notin $allowed) {
                throw "Backup contains an unsupported file: $($entry.Name)"
            }
        }
        $manifestEntry = @($entries | Where-Object Name -eq 'manifest.json' | Select-Object -First 1)
        if ($manifestEntry.Count -ne 1) { throw 'Backup manifest is missing.' }
        $reader = New-Object System.IO.StreamReader($manifestEntry[0].Open())
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        if ([int]$manifest.SchemaVersion -ne 1 -or
            [string]$manifest.PrivacyClass -ne 'personal-aggregate-settings-no-raw-logs') {
            throw 'Backup schema or privacy class is unsupported.'
        }
        foreach ($file in @($manifest.Files)) {
            if ([string]$file.Name -notin $allowed) { throw "Manifest contains an unsupported file: $($file.Name)" }
            $entry = @($entries | Where-Object Name -eq ([string]$file.Name) | Select-Object -First 1)
            if ($entry.Count -ne 1) { throw "Manifest file is missing: $($file.Name)" }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $stream = $entry[0].Open()
                try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant() }
                finally { $stream.Dispose() }
            }
            finally { $sha.Dispose() }
            if ($hash -ne [string]$file.Sha256) { throw "Backup integrity check failed for $($file.Name)." }
        }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            CreatedAt = [datetime]$manifest.CreatedAt
            AppVersion = [string]$manifest.AppVersion
            Files = @($manifest.Files | Select-Object -ExpandProperty Name)
            PrivacyClass = [string]$manifest.PrivacyClass
        }
    }
    finally { $archive.Dispose() }
}

function Import-PersonalMonitorBackup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [string]$PreRestoreBackupDirectory = '',
        [string]$AppVersion = ''
    )

    $preview = Get-PersonalMonitorBackupPreview -Path $Path
    $resolvedStateRoot = [System.IO.Path]::GetFullPath($StateRoot)
    if (-not (Test-Path -LiteralPath $resolvedStateRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $resolvedStateRoot)
    }
    $preRestore = $null
    if (-not [string]::IsNullOrWhiteSpace($PreRestoreBackupDirectory)) {
        $preRestore = Export-PersonalMonitorBackup -StateRoot $resolvedStateRoot `
            -DestinationDirectory $PreRestoreBackupDirectory -AppVersion $AppVersion
    }
    if (-not $PSCmdlet.ShouldProcess($resolvedStateRoot, 'Restore personal monitor settings and aggregate history')) {
        return [pscustomobject]@{ Restored = $false; Files = 0; PreRestoreBackup = $preRestore }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead([System.IO.Path]::GetFullPath($Path))
    $restored = 0
    try {
        foreach ($name in @($preview.Files)) {
            $entry = @($archive.Entries | Where-Object Name -eq $name | Select-Object -First 1)
            if ($entry.Count -ne 1) { throw "Validated backup entry disappeared: $name" }
            $destination = Join-Path $resolvedStateRoot $name
            $temporary = "$destination.$([guid]::NewGuid().ToString('N')).tmp"
            $entryStream = $entry[0].Open()
            try {
                $fileStream = [System.IO.File]::Create($temporary)
                try { $entryStream.CopyTo($fileStream) }
                finally { $fileStream.Dispose() }
            }
            finally { $entryStream.Dispose() }
            Move-Item -LiteralPath $temporary -Destination $destination -Force
            $restored++
        }
    }
    finally { $archive.Dispose() }
    return [pscustomobject][ordered]@{
        Restored = $true
        Files = $restored
        CreatedAt = $preview.CreatedAt
        AppVersion = $preview.AppVersion
        PreRestoreBackup = $preRestore
        RestartRequired = $true
    }
}

function Get-PersonalMonitorDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CodexHome,
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][object]$RtkSnapshot,
        [Parameter(Mandatory = $true)][object]$GuardReadiness,
        [Parameter(Mandatory = $true)][object]$StartupRegistration,
        [object]$EfficiencyConfigState = $null,
        [object]$EfficiencyPolicyState = $null,
        [object]$SchemaHealth = $null,
        [bool]$PersistenceEnabled = $true,
        [string]$AppVersion = ''
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $sessionCount = 0
    foreach ($name in @('sessions','archived_sessions')) {
        $folder = Join-Path $CodexHome $name
        if (Test-Path -LiteralPath $folder -PathType Container) {
            $sessionCount += @(Get-ChildItem -LiteralPath $folder -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue).Count
        }
    }
    $rows.Add([pscustomobject]@{
        Check = 'Local Codex logs'
        Status = $(if ($sessionCount -gt 0) { 'OK' } else { 'Warning' })
        Detail = $(if ($sessionCount -gt 0) { "$sessionCount local log file(s) available." } else { 'No local Codex JSONL files were found.' })
    })
    $rows.Add([pscustomobject]@{
        Check = 'Aggregate history'
        Status = $(if ($PersistenceEnabled) { 'OK' } else { 'Off' })
        Detail = $(if ($PersistenceEnabled) { 'Local aggregate-only persistence is enabled.' } else { 'Persistence was disabled for this launch.' })
    })
    $rows.Add([pscustomobject]@{
        Check = 'State folder'
        Status = $(if (Test-Path -LiteralPath $StateRoot -PathType Container) { 'OK' } else { 'Ready' })
        Detail = 'Private per-user application state; no raw session logs are copied here.'
    })
    $rows.Add([pscustomobject]@{
        Check = 'RTK'
        Status = $(if ([bool]$RtkSnapshot.Working) { 'OK' } elseif ([string]$RtkSnapshot.HealthCode -in @('Ineffective','ReadyNoData')) { 'Partial' } else { 'Warning' })
        Detail = ('{0}; {1:N0} command(s), ~{2:N0} estimated tokens saved, {3:N0} failure(s).' -f `
            $RtkSnapshot.HealthLabel, [int64]$RtkSnapshot.TotalCommands, [int64]$RtkSnapshot.SavedTokensEstimate, [int]$RtkSnapshot.FailureCount)
    })
    $rows.Add([pscustomobject]@{
        Check = 'RTK privacy'
        Status = $(if ([bool]$RtkSnapshot.TelemetryBlocked -and -not [bool]$RtkSnapshot.OutboundRequestMade) { 'OK' } else { 'Failure' })
        Detail = 'RTK telemetry is blocked for monitor queries; no monitor network request was made.'
    })
    $guardStatus = if ([string]$GuardReadiness.StatusCode -eq 'Armed' -and -not [bool]$StartupRegistration.MatchesLauncher) { 'Warning' } else { 'OK' }
    $guardDetail = [string]$GuardReadiness.StatusLabel
    if ([string]$GuardReadiness.StatusCode -eq 'Armed' -and -not [bool]$StartupRegistration.MatchesLauncher) {
        $guardDetail += '; start-at-sign-in is off, so enforcement is not always available.'
    }
    $rows.Add([pscustomobject]@{ Check = 'Usage guard'; Status = $guardStatus; Detail = $guardDetail })
    $rows.Add([pscustomobject]@{
        Check = 'Start with Windows'
        Status = $(if ([bool]$StartupRegistration.MatchesLauncher) { 'OK' } elseif ([bool]$StartupRegistration.Registered) { 'Warning' } else { 'Off' })
        Detail = $(if ([bool]$StartupRegistration.MatchesLauncher) { 'Enabled for this Windows account.' } elseif ([bool]$StartupRegistration.Registered) { 'Startup entry exists but needs repair.' } else { 'Not enabled; this is optional unless enforced guard continuity is wanted.' })
    })
    if ($null -ne $EfficiencyConfigState) {
        $rows.Add([pscustomobject]@{
            Check = 'Efficiency configuration'
            Status = $(if ([string]$EfficiencyConfigState.StatusCode -eq 'NeedsRepair') { 'Warning' } else { 'OK' })
            Detail = [string]$EfficiencyConfigState.StatusLabel
        })
    }
    if ($null -ne $EfficiencyPolicyState) {
        $rows.Add([pscustomobject]@{
            Check = 'Output-budget policy'
            Status = $(if ([string]$EfficiencyPolicyState.StatusCode -eq 'NeedsRepair') { 'Warning' } elseif ([bool]$EfficiencyPolicyState.Installed) { 'OK' } else { 'Off' })
            Detail = [string]$EfficiencyPolicyState.StatusLabel
        })
    }
    if ($null -ne $SchemaHealth) {
        $rows.Add([pscustomobject]@{
            Check = 'Codex log schema'
            Status = $(if ([string]$SchemaHealth.StatusCode -eq 'Healthy') { 'OK' } elseif ([string]$SchemaHealth.StatusCode -eq 'NoData') { 'Ready' } else { 'Warning' })
            Detail = [string]$SchemaHealth.Detail
        })
    }
    $rows.Add([pscustomobject]@{
        Check = 'Privacy and cost'
        Status = 'OK'
        Detail = 'Local-only diagnostics; no ChatGPT turn, API request, credit, or paid service.'
    })
    $rows.Add([pscustomobject]@{
        Check = 'Application version'
        Status = 'Info'
        Detail = $(if ($AppVersion) { $AppVersion } else { 'Unknown' })
    })
    return @($rows)
}

function Export-PersonalDiagnosticReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$AppVersion = ''
    )

    $report = [pscustomobject][ordered]@{
        SchemaVersion = 1
        PrivacyClass = 'sanitized-no-usernames-no-paths-no-content'
        GeneratedAt = (Get-Date).ToString('o')
        AppVersion = $AppVersion
        Checks = @($Rows | ForEach-Object {
            [pscustomobject][ordered]@{
                Check = [string]$_.Check
                Status = [string]$_.Status
                Detail = [string]$_.Detail
            }
        })
    }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent)
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
    return $report
}

Export-ModuleMember -Function @(
    'New-PersonalMonitorSettings',
    'Import-PersonalMonitorSettings',
    'Export-PersonalMonitorSettings',
    'Get-PersonalStartupRegistrationPath',
    'Test-PersonalStartupRegistration',
    'Set-PersonalStartupRegistration',
    'Export-PersonalMonitorBackup',
    'Get-PersonalMonitorBackupPreview',
    'Import-PersonalMonitorBackup',
    'Get-PersonalMonitorDiagnostics',
    'Export-PersonalDiagnosticReport'
)
