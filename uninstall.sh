#!/usr/bin/env bash
#
# Removes what install.sh set up: the wrapper script, the .desktop
# override (Linux), and the cached integrity baseline/log.

set -euo pipefail

INSTALL_PATH="$HOME/.local/bin/vesktop-integrity-launch"
STATE_DIR_LINUX="${XDG_CACHE_HOME:-$HOME/.cache}/vesktop-integrity"
STATE_DIR_MAC="$HOME/Library/Caches/vesktop-integrity"

OS_NAME="$(uname -s)"

if [[ -f "$INSTALL_PATH" ]]; then
    echo "Removing $INSTALL_PATH"
    rm -f "$INSTALL_PATH"
fi

case "$OS_NAME" in
Linux)
    for f in "$HOME/.local/share/applications/vesktop.desktop" \
        "$HOME/.local/share/applications/dev.vencord.Vesktop.desktop"; do
        if [[ -f "$f" ]] && grep -q "vesktop-integrity-launch" "$f" 2>/dev/null; then
            echo "Removing $f (restores the system-wide Vesktop launcher entry)"
            rm -f "$f"
        fi
    done
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi
    if [[ -d "$STATE_DIR_LINUX" ]]; then
        echo "Removing cached baseline/log at $STATE_DIR_LINUX"
        rm -rf "$STATE_DIR_LINUX"
    fi
    ;;
Darwin)
    if [[ -d "$STATE_DIR_MAC" ]]; then
        echo "Removing cached baseline/log at $STATE_DIR_MAC"
        rm -rf "$STATE_DIR_MAC"
    fi
    echo
    echo "If you created an Automator wrapper app, delete it manually and go"
    echo "back to launching Vesktop.app directly."
    ;;
esac

echo "Done."
