# vesktop-integrity-launch

Vesktop checks that its Vencord files (`vencordDesktopMain.js`,
`vencordDesktopPreload.js`, `vencordDesktopRenderer.js`,
`vencordDesktopRenderer.css`) are *present* on every launch, but not that
they're *intact*. If one of them gets corrupted (a bad disk write, an
interrupted update), Vesktop can keep running in a broken state
indefinitely, even across updates. Vesktop ships a `--repair`
flag that fixes this, but nothing tells you to run it.

This wraps your normal Vesktop launch: before starting Vesktop, it checks
the Vencord files against a locally recorded "known good" baseline, and
runs `vesktop --repair` automatically if they don't match.

## Why not just compare against GitHub on every launch?

Vencord's releases that `--repair` downloads from are a
continuously-updated rolling `devbuild` tag on GitHub, not something tied
to your installed Vesktop version. It changes independently, often
multiple times a week. Comparing local files to GitHub's current
"latest" on every launch would flag them as "corrupted" any time upstream
published a newer build since you last repaired, which is most of the
time. That would make this a "force-update on every launch" tool rather
than a corruption detector.

Instead, this records a SHA-256 baseline of the four files locally right
after a verified-good repair, and compares against that baseline on
every subsequent launch. That answers "did something break since this
was last known to work," which is the real question, and needs no
network access during normal launches.

The first time you run this, no baseline exists yet, so it forces one
repair before recording the baseline. Trusting whatever's currently on
disk as "good" on the first run would enshrine any existing, unnoticed
corruption as the new normal.

## Install

### Linux

```sh
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
  baseline. Match → launches normally, no network involved. Mismatch (or
  a file went missing) → notifies you, runs `--repair`, re-hashes, updates
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

## Other known limitations

- **Flatpak** installs are detected and the correct sandboxed data path is
  used, but this is not tested.
- This only checks the four Vencord files `--repair` manages; it doesn't
  check Vesktop's own application files.

## License

This software is licensed under the [MIT LICENSE](LICENSE).
