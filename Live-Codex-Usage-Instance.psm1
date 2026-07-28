Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MonitorInstanceObjectNames {
    [CmdletBinding()]
    param(
        [string]$ScopeSeed = ''
    )

    if ([string]::IsNullOrWhiteSpace($ScopeSeed)) {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $ScopeSeed = $identity.User.Value
        }
        finally {
            $identity.Dispose()
        }
    }
    if ([string]::IsNullOrWhiteSpace($ScopeSeed)) {
        throw 'A per-user instance scope could not be determined.'
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $seedBytes = [System.Text.Encoding]::UTF8.GetBytes($ScopeSeed)
        $digest = $sha256.ComputeHash($seedBytes)
        $fingerprint = ([System.BitConverter]::ToString($digest) -replace '-', '').Substring(0, 24)
    }
    finally {
        $sha256.Dispose()
    }

    [pscustomobject]@{
        MutexName = "Local\LiveCodexUsageMonitor.$fingerprint.Mutex"
        EventName = "Local\LiveCodexUsageMonitor.$fingerprint.Activate"
    }
}

function New-CurrentUserMutexSecurity {
    [CmdletBinding()]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $security = New-Object System.Security.AccessControl.MutexSecurity
        $rule = New-Object System.Security.AccessControl.MutexAccessRule(
            $identity.User,
            [System.Security.AccessControl.MutexRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        [void]$security.SetAccessRule($rule)
        $security
    }
    finally {
        $identity.Dispose()
    }
}

function New-CurrentUserEventSecurity {
    [CmdletBinding()]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $security = New-Object System.Security.AccessControl.EventWaitHandleSecurity
        $rule = New-Object System.Security.AccessControl.EventWaitHandleAccessRule(
            $identity.User,
            [System.Security.AccessControl.EventWaitHandleRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        [void]$security.SetAccessRule($rule)
        $security
    }
    finally {
        $identity.Dispose()
    }
}

function New-MonitorInstanceCoordinator {
    [CmdletBinding()]
    param(
        [string]$ScopeSeed = ''
    )

    $names = Get-MonitorInstanceObjectNames -ScopeSeed $ScopeSeed
    $eventCreated = $false
    $activationEvent = $null
    $mutex = $null
    try {
        $eventSecurity = New-CurrentUserEventSecurity
        $activationEvent = [System.Threading.EventWaitHandle]::new(
            $false,
            [System.Threading.EventResetMode]::AutoReset,
            $names.EventName,
            [ref]$eventCreated,
            $eventSecurity
        )

        $mutexCreated = $false
        $mutexSecurity = New-CurrentUserMutexSecurity
        $mutex = [System.Threading.Mutex]::new(
            $true,
            $names.MutexName,
            [ref]$mutexCreated,
            $mutexSecurity
        )

        if (-not $mutexCreated) {
            $requested = $activationEvent.Set()
            $mutex.Dispose()
            $activationEvent.Dispose()
            return [pscustomobject]@{
                IsPrimary = $false
                ActivationRequested = [bool]$requested
                Mutex = $null
                ActivationEvent = $null
                OwnsMutex = $false
                StatusCode = $(if ($requested) { 'ExistingActivated' } else { 'ExistingDetected' })
            }
        }

        [pscustomobject]@{
            IsPrimary = $true
            ActivationRequested = $false
            Mutex = $mutex
            ActivationEvent = $activationEvent
            OwnsMutex = $true
            StatusCode = 'Primary'
        }
    }
    catch {
        if ($null -ne $mutex) { $mutex.Dispose() }
        if ($null -ne $activationEvent) { $activationEvent.Dispose() }
        throw
    }
}

function Test-MonitorInstanceActivation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Coordinator
    )

    if (-not $Coordinator.IsPrimary -or $null -eq $Coordinator.ActivationEvent) {
        return $false
    }
    [bool]$Coordinator.ActivationEvent.WaitOne(0)
}

function Close-MonitorInstanceCoordinator {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [psobject]$Coordinator
    )

    if ($null -eq $Coordinator) { return }
    if ($Coordinator.OwnsMutex -and $null -ne $Coordinator.Mutex) {
        try { $Coordinator.Mutex.ReleaseMutex() }
        catch [System.ApplicationException] {
            # The process is already releasing an abandoned or non-owned handle.
        }
    }
    if ($null -ne $Coordinator.Mutex) { $Coordinator.Mutex.Dispose() }
    if ($null -ne $Coordinator.ActivationEvent) { $Coordinator.ActivationEvent.Dispose() }
}

Export-ModuleMember -Function @(
    'Get-MonitorInstanceObjectNames',
    'New-MonitorInstanceCoordinator',
    'Test-MonitorInstanceActivation',
    'Close-MonitorInstanceCoordinator'
)
