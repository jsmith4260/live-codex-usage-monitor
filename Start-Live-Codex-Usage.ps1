$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$monitor = Join-Path $scriptDir 'Live-Codex-Usage-GUI.ps1'

if (-not (Test-Path -LiteralPath $monitor -PathType Leaf)) {
    throw "Monitor entry point is missing: $monitor"
}

$previousPreference = $ErrorActionPreference
try {
    # Capture startup failures so a hidden-console launch can still present a
    # visible, actionable error instead of disappearing without explanation.
    $ErrorActionPreference = 'Continue'
    $output = @(& powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File $monitor @args 2>&1)
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}

if ($exitCode -ne 0) {
    $detailLines = @($output | Select-Object -Last 12 | ForEach-Object { [string]$_ })
    $detail = ($detailLines -join [Environment]::NewLine).Trim()
    if ([string]::IsNullOrWhiteSpace($detail)) {
        $detail = "PowerShell exited with code $exitCode."
    }
    $message = @"
Live Codex Usage Monitor could not start.

$detail

Run START-HERE.cmd --check-only from Command Prompt for policy diagnostics.
"@
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show(
            $message,
            'Unable to start Live Codex Usage Monitor',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
    catch {
        [Console]::Error.WriteLine($message)
    }
    exit $exitCode
}

if ($output.Count -gt 0) {
    Write-Output $output
}
exit 0
