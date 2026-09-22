#!/usr/bin/env bash
#
# dual-session-setup-all.sh
# ==========================
# One-click (double-click) installer for the dual-session setup:
#   1) Shared audio dmix for this user (dual-session-audio-setup.sh)
#   2) Caelestia shell.json UI integration, only when running as caelestia
# No sudo needed. Run once per user that needs audio (caelestia and andrik).
#
set -euo pipefail

# Location-independent: works from any home / copy location.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Dual-session setup for user: $USER ==="
echo

# --- 1) Audio (per-user) ---------------------------------------------------
if [ -x "$DIR/dual-session-audio-setup.sh" ]; then
  bash "$DIR/dual-session-audio-setup.sh"
else
  echo "WARNING: $DIR/dual-session-audio-setup.sh not found; audio step skipped."
fi

# --- 2) caelestia UI (session-switch button + launcher action) -------------
if [ "$USER" = "caelestia" ] && [ -x "$DIR/dual-session-ui-setup.sh" ]; then
  echo
  echo "=== UI setup (caelestia shell.json) ==="
  bash "$DIR/dual-session-ui-setup.sh"
fi

echo
echo "=== RESUMEN ==="
echo "  Audio compartido:  instalado para $USER ($([ -f "$HOME/.asoundrc" ] && echo OK || echo FALTA))"
echo "  Sink PCH dmix:     $([ -f "$HOME/.config/pipewire/pipewire.conf.d/10-pch-dmix-sink.conf" ] && echo OK || echo FALTA)"
if [ "$USER" = "caelestia" ]; then
  echo "  Boton 'Switch session': CTRL+ALT+Delete (4to boton) o launcher > switch"
  echo "  Volver a Hyprland: Ctrl+Alt+F3"
fi
echo
echo "Importante: correr ESTE MISMO acceso una vez en CADA usuario con audio."
echo "La terminal se puede cerrar."