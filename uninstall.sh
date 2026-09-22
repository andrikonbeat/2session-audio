#!/usr/bin/env bash
#
# uninstall.sh — removes the dual-session-setup product:
#   * shared-audio files and the pre-install ~/.asoundrc backup restore
#   * the caelestia shell.json backup restore
#   * ~/.config/dual-session-setup.conf / .manifest
#   * ~/.local/share/dual-session-setup/ and the .desktop entry
# Idempotent: a second run finds nothing left to do.
# User-modified files are NEVER deleted; their backups are kept and reported.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$DIR/lib/audio.sh"
# shellcheck disable=SC1091
. "$DIR/lib/ui.sh"

# Leave the current directory before removing files that might contain it
# (when running from the installed copy).
cd /

DEST="$HOME/.local/share/dual-session-setup"
APPS="$HOME/.local/share/applications"

echo "=== Desinstalación Dual-Session Setup (usuario: $USER) ==="

audio_remove
ui_remove

apply_or_report "Eliminar config $CONF" rm -f "$CONF"
apply_or_report "Eliminar entrada de menú $APPS/dual-session-setup.desktop" rm -f "$APPS/dual-session-setup.desktop"
apply_or_report "Eliminar directorio instalado $DEST" rm -rf "$DEST"

echo
echo "Eliminado:"
echo "  - $DEST"
echo "  - $APPS/dual-session-setup.desktop"
echo "  - $CONF"
echo "Restaurado:"
echo "  - $ASOUNDRC (desde respaldo, si existía)"
echo "  - $SHELL_JSON (desde respaldo, si existía)"
echo "Hecho."