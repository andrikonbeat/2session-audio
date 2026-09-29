#!/usr/bin/env bash
#
# install.sh — installs the dual-session-setup product into the user's home:
#   ~/.local/share/dual-session-setup/          (scripts + lib/)
#   ~/.local/share/applications/dual-session-setup.desktop
# Idempotent: re-running just re-copies the files and refreshes the
# desktop entry.
set -euo pipefail

# Canonical GitHub source used when the script is piped via curl and lib/ is
# not available next to the running script.
GITHUB_OWNER="andrikonbeat"
GITHUB_REPO="2session-audio"
GITHUB_BRANCH="main"
GITHUB_TARBALL_URL="https://codeload.github.com/$GITHUB_OWNER/$GITHUB_REPO/tar.gz/refs/heads/$GITHUB_BRANCH"

# BASH_SOURCE[0] is unset under `set -u` when the script is piped via
# curl/stdin; default to empty and let the bootstrap guard below handle it.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"

# Bootstrap mode: when the script is piped via curl it runs from a temp/pipe
# location and lib/ is not next to it. Download the source tarball instead.
if [ ! -f "$DIR/lib/common.sh" ]; then
  echo "Descargando Dual-Session Setup desde GitHub..."
  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "Error: se necesitan curl y tar para instalar desde GitHub." >&2
    echo "Instálalos o clona el repositorio y ejecuta ./install.sh." >&2
    exit 1
  fi
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$GITHUB_TARBALL_URL" | tar -xz -C "$TMP"
  # The archive extracts under a folder named <repo>-<branch>; locate lib/
  # anywhere in the temp dir as a guard against upstream renames.
  TARBALL_COMMON="$(find "$TMP" -maxdepth 3 -name common.sh -path '*/lib/*' -printf '%p\n' | head -1)"
  if [ -z "$TARBALL_COMMON" ]; then
    echo "Error: la descarga de GitHub no contiene lib/common.sh." >&2
    exit 1
  fi
  DIR="$(cd "$(dirname "$(dirname "$TARBALL_COMMON")")" && pwd)"
fi

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