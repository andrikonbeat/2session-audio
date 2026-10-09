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

# BASH_SOURCE[0] is unset under `set -u` when the script is piped via
# curl/stdin; default to empty and let the piped-mode guard below handle it.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"

# Piped mode: when the script is run via curl, lib/ is not next to it. Source
# the libs from the installed copy instead; exit 0 (idempotent) when neither
# location has an installation.
if [ ! -f "$DIR/lib/common.sh" ]; then
  DIR="$HOME/.local/share/dual-session-setup"
  if [ ! -f "$DIR/lib/common.sh" ]; then
    echo "No se encontró una instalación de Dual-Session Setup; no hay nada que desinstalar."
    exit 0
  fi
fi
# shellcheck disable=SC1091
. "$DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$DIR/lib/audio.sh"
# shellcheck disable=SC1091
. "$DIR/lib/mixer.sh"
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
echo "  - servicio de usuario $MIXER_SERVICE (deshabilitado; $MIXER_UNIT)"
echo "Restaurado:"
echo "  - $ASOUNDRC (desde respaldo, si existía)"
echo "  - $SHELL_JSON (desde respaldo, si existía)"
echo "Hecho."