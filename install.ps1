#requires -Version 5.0
<#
.SYNOPSIS
    Installs vesktop-integrity-launch and retargets your Vesktop shortcuts
    to run it first.

.DESCRIPTION
    Copies the launcher script to a stable per-user location, then finds
    your Vesktop shortcuts (Desktop and Start Menu) and rewrites their
    Target to invoke the launcher via powershell.exe, passing the
    shortcut's original target as -VesktopExe. The shortcut's icon is left
    pointing at the real Vesktop.exe so it still looks like Vesktop.

    The original shortcut is backed up next to itself as
    "<name>.original.lnk", and re-running this script is idempotent.

    Known limitation: this does not update the "discord://" protocol
    handler, so links opened that way bypass the integrity check. See
    README.md.
#>

$ErrorActionPreference = "Stop"

$repoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcScript = Join-Path $repoDir "bin\vesktop-integrity-launch.ps1"

$installDir = Join-Path $env:LOCALAPPDATA "VesktopIntegrityLauncher"
$installPath = Join-Path $installDir "vesktop-integrity-launch.ps1"

Write-Host "Installing vesktop-integrity-launch to $installPath"
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -Path $srcScript -Destination $installPath -Force

function Find-VesktopExe {
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
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Get-ShortcutPaths {
    $paths = @(
        (Join-Path ([Environment]::GetFolderPath("Desktop")) "Vesktop.lnk"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Vesktop.lnk"),
        (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Vesktop.lnk")
    )
    return $paths | Where-Object { Test-Path $_ }
}

$shortcuts = Get-ShortcutPaths
if (-not $shortcuts -or $shortcuts.Count -eq 0) {
    Write-Warning "No Vesktop shortcuts found in the usual Desktop/Start Menu locations."
    $fallbackExe = Find-VesktopExe
    if ($fallbackExe) {
        Write-Host "Found Vesktop.exe at $fallbackExe, but no shortcut to retarget."
    }
    Write-Host "Point a shortcut's Target at powershell.exe with arguments:"
    Write-Host "  -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installPath`" -VesktopExe `"<path to Vesktop.exe>`""
    exit 0
}

$shell = New-Object -ComObject WScript.Shell

foreach ($lnkPath in $shortcuts) {
    Write-Host "Processing shortcut: $lnkPath"
    $lnk = $shell.CreateShortcut($lnkPath)

    if ($lnk.TargetPath -match "powershell\.exe$" -and $lnk.Arguments -match [Regex]::Escape($installPath)) {
        Write-Host "  Already points at vesktop-integrity-launch, skipping."
        continue
    }

    $backupPath = "$lnkPath.original.lnk"
    if (-not (Test-Path $backupPath)) {
        Copy-Item -Path $lnkPath -Destination $backupPath
        Write-Host "  Backed up original shortcut to $backupPath"
    }

    $originalTarget = $lnk.TargetPath
    $originalWorkDir = $lnk.WorkingDirectory
    if (-not $originalTarget -or -not (Test-Path $originalTarget)) {
        Write-Warning "  Could not resolve a valid existing target for $lnkPath, skipping."
        continue
    }

    $powershellExe = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path $powershellExe)) {
        $powershellExe = "powershell.exe"
    }

    $lnk.TargetPath = $powershellExe
    $lnk.Arguments = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installPath`" -VesktopExe `"$originalTarget`""
    $lnk.IconLocation = "$originalTarget,0"
    if ($originalWorkDir) {
        $lnk.WorkingDirectory = $originalWorkDir
    } else {
        $lnk.WorkingDirectory = Split-Path -Parent $originalTarget
    }
    $lnk.Save()
    Write-Host "  Retargeted -> $powershellExe (launches $originalTarget via integrity check)"
}

Write-Host
Write-Host "Done. Note: the 'discord://' protocol handler is not updated by this"
Write-Host "installer, so links opened that way will bypass the integrity check."
