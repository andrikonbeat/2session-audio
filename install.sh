#!/usr/bin/env bash
#
# install.sh — one-command installer for dual-session-setup.
#
# Golden path: fetch the source (when piped via curl), copy the product into
# the user's home, and immediately configure the CURRENT account. No sudo, no
# prompts (it may run piped, so stdin is the script itself), idempotent:
# re-running just re-copies and re-applies.
#
# Usage:
#   install.sh              install + configure the current account
#   install.sh --check      report the detected environment (no changes)
#   install.sh --dry-run    simulate the whole thing (no changes)
#   install.sh --no-setup   only copy the product, do not configure
#   install.sh --uninstall  remove the product
#   install.sh --help
set -euo pipefail

GITHUB_OWNER="andrikonbeat"
GITHUB_REPO="2session-audio"
GITHUB_BRANCH="main"
GITHUB_TARBALL_URL="https://codeload.github.com/$GITHUB_OWNER/$GITHUB_REPO/tar.gz/refs/heads/$GITHUB_BRANCH"
RAW_INSTALL="https://raw.githubusercontent.com/$GITHUB_OWNER/$GITHUB_REPO/$GITHUB_BRANCH/install.sh"

# BASH_SOURCE[0] is unset under `set -u` when the script is piped via
# curl/stdin; default to empty and let the bootstrap guard below handle it.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"

usage() {
  cat <<EOF
Uso: install.sh [opción]

  (sin opción)   instala y configura el audio para la cuenta actual
  --check        muestra el entorno detectado, sin cambiar nada
  --dry-run      simula la instalación, sin cambiar nada
  --no-setup     solo copia el programa (no configura el audio)
  --uninstall    desinstala y restaura lo que había antes
  --help         muestra esta ayuda

Instalación de una línea:
  curl -fsSL $RAW_INSTALL | bash

Después, corré el mismo comando en la otra cuenta de sesión para que las
dos suenen al mismo tiempo.
EOF
}

MODE="install"
case "${1:-}" in
  ""|--install) MODE="install" ;;
  --check)      MODE="check" ;;
  --dry-run)    MODE="dry-run" ;;
  --no-setup)   MODE="no-setup" ;;
  --uninstall)  MODE="uninstall" ;;
  -h|--help)    MODE="help" ;;
  *)
    echo "Opción desconocida: $1" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac

if [ "$MODE" = "help" ]; then
  usage
  exit 0
fi

# Bootstrap mode: when piped via curl, the script runs from a temp/pipe
# location and lib/ is not next to it. Download the source tarball instead.
if [ ! -f "$DIR/lib/common.sh" ]; then
  echo "==> Descargando Dual-Session Setup..."
  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "Error: se necesitan 'curl' y 'tar' para instalar desde GitHub." >&2
    echo "Instalalos, o cloná el repositorio y ejecutá ./install.sh." >&2
    exit 1
  fi
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$GITHUB_TARBALL_URL" | tar -xz -C "$TMP"
  TARBALL_COMMON="$(find "$TMP" -maxdepth 3 -name common.sh -path '*/lib/*' -printf '%p\n' | head -1)"
  if [ -z "$TARBALL_COMMON" ]; then
    echo "Error: la descarga de GitHub no contiene lib/common.sh." >&2
    exit 1
  fi
  DIR="$(cd "$(dirname "$(dirname "$TARBALL_COMMON")")" && pwd)"
fi

# --check / --dry-run / --uninstall just delegate to the real scripts.
case "$MODE" in
  check)     exec "$DIR/setup.sh" --check ;;
  dry-run)   exec "$DIR/setup.sh" --dry-run ;;
  uninstall) exec "$DIR/uninstall.sh" ;;
esac

DEST="$HOME/.local/share/dual-session-setup"
APPS="$HOME/.local/share/applications"

cat <<EOF
==========================================================
 Dual-Session Setup — audio compartido
==========================================================
 Esto configura TU cuenta ($USER). No usa sudo y no toca
 tus archivos personales. Se puede deshacer.
==========================================================

EOF

echo "==> [1/2] Instalando el programa..."
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
Comment=Configura el audio compartido para que todas tus sesiones suenen. Corré también en la otra cuenta.
Exec=$DEST/setup.sh
Icon=audio-speakers
Terminal=true
Categories=System;Settings;
EOF
chmod 644 "$APPS/dual-session-setup.desktop"

echo "    Programa instalado en: $DEST"
echo "    Entrada de menú:       $APPS/dual-session-setup.desktop"

if [ "$MODE" = "no-setup" ]; then
  echo
  echo "Listo (solo el programa). Para configurar el audio ahora:"
  echo "  $DEST/setup.sh"
  exit 0
fi

echo
echo "==> [2/2] Configurando el audio de tu cuenta..."
echo
"$DEST/setup.sh"
