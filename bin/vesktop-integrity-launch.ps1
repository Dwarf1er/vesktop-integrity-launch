#requires -Version 5.0
<#
.SYNOPSIS
    Wraps Vesktop.exe: verifies Vencord files against a locally recorded
    "known good" baseline before every launch, and self-heals via
    `vesktop --repair` if they don't match.

.DESCRIPTION
    Compares against a baseline captured locally right after a
    verified-good repair, rather than against GitHub's current build, so
    normal upstream churn doesn't get flagged as corruption. See README.md
    for the full rationale.

    install.ps1 points a rewritten shortcut's Target at:
        powershell.exe -WindowStyle Hidden -NoLogo -NoProfile
            -ExecutionPolicy Bypass -File vesktop-integrity-launch.ps1
            -VesktopExe "<original target>"
    with -IconLocation left pointing at the original .exe so the shortcut
    still looks like Vesktop.
#>

param(
    [string]$VesktopExe,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

function Get-VesktopExe {
    if ($VesktopExe -and (Test-Path $VesktopExe)) { return $VesktopExe }
    if ($env:VESKTOP_EXE -and (Test-Path $env:VESKTOP_EXE)) { return $env:VESKTOP_EXE }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\vesktop\Vesktop.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Vesktop\Vesktop.exe"),
        (Join-Path $env:ProgramFiles "Vesktop\Vesktop.exe")
    )
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ($programFilesX86) {
        $candidates += (Join-Path $programFilesX86 "Vesktop\Vesktop.exe")
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }

    $cmd = Get-Command vesktop.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

$resolvedExe = Get-VesktopExe
if (-not $resolvedExe) {
    # Fail loudly: with no binary resolved there's no fallback launch target.
    Write-Error "vesktop-integrity-launch: could not find Vesktop.exe. Pass -VesktopExe or set VESKTOP_EXE."
    exit 1
}

$dataDir = if ($env:VENCORD_USER_DATA_DIR) { $env:VENCORD_USER_DATA_DIR } else { Join-Path $env:APPDATA "vesktop" }
$vencordFilesDir = Join-Path $dataDir "sessionData\vencordFiles"

$filesToCheck = @(
    "vencordDesktopMain.js",
    "vencordDesktopPreload.js",
    "vencordDesktopRenderer.js",
    "vencordDesktopRenderer.css"
)

$stateDir = Join-Path $env:LOCALAPPDATA "vesktop-integrity"
$baselineFile = Join-Path $stateDir "baseline.json"
$logFile = Join-Path $stateDir "launch.log"
$lockDir = Join-Path $stateDir "lock"
$lockStaleSecs = 300

New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz"
    Add-Content -Path $logFile -Value "$ts $Message"
}

function Send-Notification {
    param([string]$Message)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.Visible = $true
        $icon.BalloonTipTitle = "Vesktop"
        $icon.BalloonTipText = $Message
        $icon.ShowBalloonTip(4000)
        $script:notifyIcons += $icon
    } catch {}
}
$script:notifyIcons = @()

# A notification failure must never be able to abort the caller's control
# flow and skip the repair logic that follows it.
function Send-NotificationSafe {
    param([string]$Message)
    try {
        Send-Notification $Message
    } catch {
        Write-Log "notification failed (non-fatal): $_"
    }
}

# mkdir is atomic on NTFS too, so it doubles as a portable lock.
function Enter-Lock {
    $waited = 0
    while (-not (New-Item -ItemType Directory -Path $lockDir -ErrorAction SilentlyContinue)) {
        if (Test-Path $lockDir) {
            $age = ((Get-Date) - (Get-Item $lockDir).LastWriteTime).TotalSeconds
            if ($age -gt $lockStaleSecs) {
                Write-Log "removing stale lock (age $([int]$age)s)"
                Remove-Item $lockDir -Recurse -Force -ErrorAction SilentlyContinue
                continue
            }
        }
        Start-Sleep -Seconds 1
        $waited++
        if ($waited -ge 30) { return $false }
    }
    return $true
}

function Exit-Lock {
    Remove-Item $lockDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Write-Baseline {
    foreach ($f in $filesToCheck) {
        if (-not (Test-Path (Join-Path $vencordFilesDir $f))) { return $false }
    }
    $hashes = [ordered]@{}
    foreach ($f in $filesToCheck) {
        $hashes[$f] = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $vencordFilesDir $f)).Hash
    }
    $tmp = "$baselineFile.tmp"
    $hashes | ConvertTo-Json | Set-Content -Path $tmp
    Move-Item -Path $tmp -Destination $baselineFile -Force
    return $true
}

function Test-Baseline {
    if (-not (Test-Path $baselineFile)) { return $false }
    if (-not (Test-Path $vencordFilesDir)) { return $false }
    try {
        $baseline = Get-Content $baselineFile -Raw | ConvertFrom-Json
    } catch {
        return $false
    }
    foreach ($f in $filesToCheck) {
        $path = Join-Path $vencordFilesDir $f
        if (-not (Test-Path $path)) { return $false }
        $current = (Get-FileHash -Algorithm SHA256 -Path $path).Hash
        $expected = $baseline.$f
        if (-not $expected -or $current -ne $expected) { return $false }
    }
    return $true
}

function Invoke-Repair {
    Write-Log "running: $resolvedExe --repair"
    $proc = Start-Process -FilePath $resolvedExe -ArgumentList "--repair" -Wait -PassThru -WindowStyle Hidden
    Write-Log "repair exited with status $($proc.ExitCode)"
    if (Write-Baseline) {
        Write-Log "baseline updated after repair"
        return $true
    } else {
        Write-Log "repair did not produce a complete, valid install; baseline left untouched"
        return $false
    }
}

# Wrapped in try/catch so this script can never be the reason Vesktop
# fails to start.
try {
    $version = & $resolvedExe --version 2>$null
    Write-Log "launch: $version ($resolvedExe)"

    if (Enter-Lock) {
        try {
            if (-not (Test-Path $baselineFile)) {
                Write-Log "no baseline found, establishing one via repair"
                Send-NotificationSafe "Setting up Vesktop integrity monitoring..."
                if (-not (Invoke-Repair)) {
                    Send-NotificationSafe "Vesktop repair failed to produce a complete install - launching anyway."
                }
            } elseif (-not (Test-Baseline)) {
                Write-Log "integrity check failed against baseline"
                Send-NotificationSafe "Vesktop files look corrupted - repairing before launch..."
                if (Invoke-Repair) {
                    Send-NotificationSafe "Vesktop repaired successfully."
                } else {
                    Send-NotificationSafe "Vesktop repair failed - launching existing (possibly broken) install."
                }
            } else {
                Write-Log "integrity check passed"
            }
        } finally {
            Exit-Lock
        }
    } else {
        Write-Log "lock timeout, launching without integrity check"
    }
} catch {
    try { Write-Log "unexpected error: $_" } catch {}
}

$launchParams = @{ FilePath = $resolvedExe }
if ($RemainingArgs -and $RemainingArgs.Count -gt 0) {
    $launchParams["ArgumentList"] = $RemainingArgs
}
Start-Process @launchParams
