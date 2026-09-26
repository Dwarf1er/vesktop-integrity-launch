<div align="center">

# Vesktop Integrity Launch
##### Self-Healing Launches for Vesktop

<img alt="vesktop-integrity-launch logo" height="280" src="/assets/vesktop-integrity-launch-logo.webp" />

![License](https://img.shields.io/github/license/Dwarf1er/vesktop-integrity-launch?style=for-the-badge)
![Version](https://img.shields.io/github/v/release/Dwarf1er/vesktop-integrity-launch?style=for-the-badge)
![Issues](https://img.shields.io/github/issues/Dwarf1er/vesktop-integrity-launch?style=for-the-badge)
![PRs](https://img.shields.io/github/issues-pr/Dwarf1er/vesktop-integrity-launch?style=for-the-badge)
![Contributors](https://img.shields.io/github/contributors/Dwarf1er/vesktop-integrity-launch?style=for-the-badge)
![Stars](https://img.shields.io/github/stars/Dwarf1er/vesktop-integrity-launch?style=for-the-badge)

</div>

# Project Description

Vesktop checks that its Vencord files (`vencordDesktopMain.js`,
`vencordDesktopPreload.js`, `vencordDesktopRenderer.js`,
`vencordDesktopRenderer.css`) are *present* on every launch, but not that
they're *intact*. If one of them gets corrupted (a bad disk write, an
interrupted update), Vesktop can keep running in a broken state
indefinitely, even across updates. Vesktop ships a `--repair` flag that
fixes this, but nothing tells you to run it.

**vesktop-integrity-launch** wraps your normal Vesktop launch: before
starting Vesktop, it checks the Vencord files against a locally recorded
"known good" baseline, and runs `vesktop --repair` automatically if they
don't match. No prompts, no manual repairs, no network access needed for
a normal launch that passes the check.

If you find this useful, consider starring the repo to show your support! 🌟

# Why vesktop-integrity-launch?

Comparing against GitHub's current "latest" build on every launch was
considered and rejected: Vencord's releases that `--repair` downloads
from are a continuously-updated rolling `devbuild` tag, not something
tied to your installed Vesktop version, so that would flag files as
"corrupted" any time upstream published a newer build since you last
repaired; most of the time. Instead, this tool:

- Records a **local SHA-256 baseline** of the four Vencord files right
  after a verified-good repair, and compares against *that*, not
  upstream, on every launch.
- Answers "did something break since this was last known to work,"
  the actual question that matters, without needing network access.
- **Self-heals silently**: a mismatch triggers `vesktop --repair`
  automatically and updates the baseline, instead of leaving you to run
  into broken behavior with no idea why.
- **Never blocks your launch**: the check is isolated from the real
  launch, so a bug in this tool, or a failed repair, can never be the
  reason Vesktop fails to start.

# Table of Contents

<!-- mtoc-start -->

  * [Features](#features)
  * [Installation](#installation)
    * [Linux](#linux)
    * [Windows](#windows)
    * [macOS](#macos)
  * [Uninstall](#uninstall)
  * [How it decides what's "correct"](#how-it-decides-whats-correct)
  * [Known Limitations](#known-limitations)
* [License](#license)
* [Acknowledgements](#acknowledgements)

<!-- mtoc-end -->

## Features

- **Local baseline integrity check**: Hashes the four Vencord files and
  compares against a locally recorded known-good baseline, not upstream.
- **Automatic self-repair**: Runs `vesktop --repair` and refreshes the
  baseline whenever a mismatch or missing file is detected.
- **Transparent wrapping**: Installs alongside your existing Vesktop
  launcher (menu entry or shortcut) without modifying Vesktop's own
  signed/packaged files.
- **Fail-safe by design**: The integrity check can never prevent
  Vesktop from launching, even if it errors out internally.
- **Cross-platform**: Linux (native packages and Flatpak), Windows, and
  macOS are all supported, each with an install path suited to how that
  OS packages Vesktop.

## Installation

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/Dwarf1er/vesktop-integrity-launch/main/install.sh | bash
```

Or, if you'd rather review the code first:

```sh
git clone https://github.com/Dwarf1er/vesktop-integrity-launch.git
cd vesktop-integrity-launch
./install.sh
```

Installs the launcher to `~/.local/bin/vesktop-integrity-launch`, then
finds your existing Vesktop `.desktop` entry (checked in the common
locations for native packages and Flatpak) and creates a user-level
override in `~/.local/share/applications/` that points at the launcher
instead, keeping every other field (Name, Icon, MimeType,
`StartupWMClass`, ...) exactly as it was. The system-wide `.desktop` file
is never touched, so a package update won't undo this.

You may need to log out and back in once for your desktop environment to
notice the new menu entry.

### Windows

Run from PowerShell:

```powershell
irm https://raw.githubusercontent.com/Dwarf1er/vesktop-integrity-launch/main/install.ps1 | iex
```

Or, if you'd rather review the code first:

```powershell
git clone https://github.com/Dwarf1er/vesktop-integrity-launch.git
cd vesktop-integrity-launch
.\install.ps1
```

Installs the launcher to
`%LOCALAPPDATA%\VesktopIntegrityLauncher\vesktop-integrity-launch.ps1`,
then finds your Vesktop shortcuts (Desktop and Start Menu) and retargets
them to run the launcher via `powershell.exe`, passing the original
`Vesktop.exe` path through. The shortcut's icon is left pointing at the
real executable so it still looks like a normal Vesktop shortcut. The
original shortcut is backed up next to itself as `<name>.original.lnk`
before being changed.

**Known limitation:** this does not update the `discord://` protocol
handler registration, so links opened that way currently bypass the
integrity check and launch `Vesktop.exe` directly.

### macOS

```sh
curl -fsSL https://raw.githubusercontent.com/Dwarf1er/vesktop-integrity-launch/main/install.sh | bash
```

Or, if you'd rather review the code first:

```sh
git clone https://github.com/Dwarf1er/vesktop-integrity-launch.git
cd vesktop-integrity-launch
./install.sh
```

Installs the launcher script, but does **not** touch `Vesktop.app`
itself. Vesktop's macOS build is notarized; patching files inside a
notarized `.app` bundle invalidates its code signature, and macOS will
then refuse to launch it (or show a "damaged app" warning). Modifying the
signed bundle in place isn't a safe option here.

Instead, `install.sh` prints instructions for making a small, separate
wrapper app with Automator ("Run Shell Script" pointed at the installed
launcher script), which you then use in place of `Vesktop.app` in your
Dock, Spotlight, or Login Items. This is a manual one-time step.

## Uninstall

```sh
./uninstall.sh      # Linux / macOS
.\uninstall.ps1      # Windows
```

Restores your original shortcuts/launcher entry and removes the cached
baseline and log.

## How it decides what's "correct"

- **First run ever:** no baseline exists, so it runs `vesktop --repair`
  once, then hashes the resulting files and stores that as the baseline.
- **Every launch after that:** hashes the four files and compares to the
  baseline. Match -> launches normally, no network involved. Mismatch (or
  a file went missing) -> notifies you, runs `--repair`, re-hashes, updates
  the baseline, then launches.
- **If a repair doesn't produce a complete, valid set of files** (e.g. no
  network): the baseline is left untouched, and Vesktop still launches
  best-effort with whatever is currently on disk, rather than blocking
  you from opening the app. The next launch will try repairing again.

Logs of what happened on each launch are kept at:
- Linux: `~/.cache/vesktop-integrity/launch.log`
- macOS: `~/Library/Caches/vesktop-integrity/launch.log`
- Windows: `%LOCALAPPDATA%\vesktop-integrity\launch.log`

The integrity check itself is isolated from the final launch (on
Linux/macOS it runs in a subshell, on Windows inside a try/catch), so a
bug or unexpected error in the checking logic can't be the reason
Vesktop fails to start.

## Known Limitations

- **Flatpak** installs are detected and the correct sandboxed data path is
  used, but this is not tested.
- This only checks the four Vencord files `--repair` manages; it doesn't
  check Vesktop's own application files.
- **Windows:** the `discord://` protocol handler is not retargeted, so
  links opened that way bypass the integrity check (see above).

# License

This software is licensed under the [MIT LICENSE](LICENSE).

# Acknowledgements

This tool wraps, and depends entirely on, the great work of the
[Vencord](https://github.com/Vencord/Vencord) and
[Vesktop](https://github.com/Vencord/Vesktop) projects; including the
`--repair` flag this launcher builds on.
