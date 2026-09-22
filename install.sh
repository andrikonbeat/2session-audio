#!/usr/bin/env bash
#
# install.sh — installs the dual-session-setup product into the user's home:
#   ~/.local/share/dual-session-setup/          (scripts + lib/)
#   ~/.local/share/applications/dual-session-setup.desktop
# Idempotent: re-running just re-copies the files and refreshes the
# desktop entry.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/share/dual-session-setup"
APPS="$HOME/.local/share/applications"

echo "=== Instalación Dual-Session Setup (usuario: $USER) ==="
mkdir -p "$DEST" "$APPS"

if [ "$DIR" != "$DEST" ]; then
  rm -rf "$DEST/lib"
  cp -f "$DIR/setup.sh" "$DIR/uninstall.sh" "$DEST/"
  cp -r "$DIR/lib" "$DEST/lib"
fi
chmod +x "$DEST/setup.sh" "$DEST/uninstall.sh"

cat > "$APPS/dual-session-setup.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=Dual-Session Setup
Comment=Configura el audio compartido (dmix) y el cambio de sesión. Correr una vez por usuario con audio.
Exec=$DEST/setup.sh
Icon=audio-speakers
Terminal=true
Categories=System;Settings;
EOF
chmod 644 "$APPS/dual-session-setup.desktop"

echo
echo "Instalado en: $DEST"
echo "Entrada de menú: $APPS/dual-session-setup.desktop"
echo
echo "Siguiente paso:"
echo "  $DEST/setup.sh            # en CADA usuario con audio"
echo "  $DEST/setup.sh --check    # ver entorno detectado"