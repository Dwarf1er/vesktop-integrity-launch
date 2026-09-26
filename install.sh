#!/usr/bin/env bash
#
# Installs vesktop-integrity-launch and wires it into how you launch
# Vesktop, without touching Vesktop's own signed/packaged files. See
# README.md for what each OS does. Re-run any time to update after a
# `git pull`.

set -euo pipefail

RAW_BASE="https://raw.githubusercontent.com/Dwarf1er/vesktop-integrity-launch/main"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SCRIPT="$REPO_DIR/bin/vesktop-integrity-launch"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/vesktop-integrity-launch"

OS_NAME="$(uname -s)"

TMP_SCRIPT=""
cleanup() { [[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT"; }
trap cleanup EXIT

# Not run from inside a clone (piped straight from curl, or this file
# downloaded on its own): $BASH_SOURCE[0] then resolves to somewhere
# with no bin/ next to it, so fetch the launcher script itself instead.
if [[ ! -f "$SRC_SCRIPT" ]]; then
    echo "No local checkout found, fetching launcher script from GitHub..."
    TMP_SCRIPT="$(mktemp)"
    curl -fsSL "$RAW_BASE/bin/vesktop-integrity-launch" -o "$TMP_SCRIPT"
    SRC_SCRIPT="$TMP_SCRIPT"
fi

echo "Installing vesktop-integrity-launch to $INSTALL_PATH"
mkdir -p "$INSTALL_DIR"
cp "$SRC_SCRIPT" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

case "$OS_NAME" in
Linux)
    # Find the existing Vesktop .desktop file so we inherit its Name/Icon/
    # Categories/MimeType instead of hardcoding a copy that can drift.
    CANDIDATES=(
        "/usr/share/applications/vesktop.desktop"
        "/usr/share/applications/dev.vencord.Vesktop.desktop"
        "/var/lib/flatpak/exports/share/applications/dev.vencord.Vesktop.desktop"
        "$HOME/.local/share/flatpak/exports/share/applications/dev.vencord.Vesktop.desktop"
    )
    SRC_DESKTOP=""
    for c in "${CANDIDATES[@]}"; do
        if [[ -f "$c" ]]; then
            SRC_DESKTOP="$c"
            break
        fi
    done

    if [[ -z "$SRC_DESKTOP" ]]; then
        echo "Could not find an existing Vesktop .desktop file in the usual locations." >&2
        echo "The launcher script is installed at $INSTALL_PATH, point your launcher's" >&2
        echo "Exec= at it manually, or set the VESKTOP_BIN env var and add \"$INSTALL_PATH\"" >&2
        echo "wherever you currently invoke vesktop." >&2
        exit 0
    fi

    DEST_DIR="$HOME/.local/share/applications"
    DEST_DESKTOP="$DEST_DIR/$(basename "$SRC_DESKTOP")"
    mkdir -p "$DEST_DIR"

    echo "Found Vesktop launcher entry: $SRC_DESKTOP"
    echo "Creating user override: $DEST_DESKTOP"

    # Rewrite only the Exec= line(s) to route through our wrapper: drop the
    # original binary token but keep its trailing args/placeholders (%U),
    # since our script resolves the real vesktop binary itself. Keep
    # everything else (Name, Icon, MimeType, StartupWMClass, ...) as-is.
    sed -E "s|^Exec=[^ ]+(.*)|Exec=$INSTALL_PATH\\1|" "$SRC_DESKTOP" >"$DEST_DESKTOP"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DEST_DIR" >/dev/null 2>&1 || true
    fi

    echo
    echo "Done. Launching Vesktop from your app menu will now run the integrity"
    echo "check first. If your desktop environment caches menu entries, you may"
    echo "need to log out/in once for it to notice."
    ;;
Darwin)
    echo
    echo "Done installing the script. Vesktop.app is notarized, so this installer"
    echo "will not modify it directly (that would break its code signature)."
    echo
    echo "To make a double-clickable wrapper that runs the integrity check and"
    echo "then opens Vesktop:"
    echo "  1. Open Automator, choose 'New Document' -> 'Application'."
    echo "  2. Add a 'Run Shell Script' action with:"
    echo "       $INSTALL_PATH"
    echo "  3. Save it as, e.g., 'Vesktop (checked).app' in /Applications."
    echo "  4. Use that instead of Vesktop.app in your Dock / Spotlight / Login Items."
    echo
    echo "See README.md for the full walkthrough."
    ;;
*)
    echo "Unsupported OS: $OS_NAME" >&2
    exit 1
    ;;
esac
