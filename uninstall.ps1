#requires -Version 5.0
<#
.SYNOPSIS
    Reverts what install.ps1 did: restores original shortcuts from their
    ".original.lnk" backups and removes the installed launcher script and
    cached baseline/log.
#>

$ErrorActionPreference = "Stop"

$installDir = Join-Path $env:LOCALAPPDATA "VesktopIntegrityLauncher"
$stateDir = Join-Path $env:LOCALAPPDATA "vesktop-integrity"

$shortcutPaths = @(
    (Join-Path ([Environment]::GetFolderPath("Desktop")) "Vesktop.lnk"),
    (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Vesktop.lnk"),
    (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Vesktop.lnk")
)

foreach ($lnkPath in $shortcutPaths) {
    $backupPath = "$lnkPath.original.lnk"
    if (Test-Path $backupPath) {
        Write-Host "Restoring $lnkPath from backup"
        Copy-Item -Path $backupPath -Destination $lnkPath -Force
        Remove-Item -Path $backupPath -Force
    }
}

if (Test-Path $installDir) {
    Write-Host "Removing $installDir"
    Remove-Item -Path $installDir -Recurse -Force
}

if (Test-Path $stateDir) {
    Write-Host "Removing cached baseline/log at $stateDir"
    Remove-Item -Path $stateDir -Recurse -Force
}

Write-Host "Done."
