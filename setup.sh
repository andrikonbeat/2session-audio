#!/usr/bin/env bash
#
# setup.sh — dual-session-setup orchestrator (main entry point).
# Runs the shared-audio install for the current user and, when enabled, the
# optional caelestia-shell integration. Position-independent: it sources its
# lib/ from its own directory.
#
# Usage:
#   setup.sh             full run for the current user (config auto-created)
#   setup.sh --check     print detected environment; exit 0; write nothing
#   setup.sh --dry-run   simulate the full run; write nothing, no restarts
#   setup.sh --ui-only   only the caelestia-shell integration
#   setup.sh --uninstall delegate to uninstall.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$DIR/lib/audio.sh"
# shellcheck disable=SC1091
. "$DIR/lib/ui.sh"

usage() {
  cat <<'EOF'
Uso: setup.sh [opción]

  (sin opción)   instalación completa para el usuario actual
  --check        informa el entorno detectado y el estado de archivos (sin escrituras)
  --dry-run      simula la instalación completa (sin escrituras ni reinicios)
  --ui-only      solo la integración de shell.json (para la sesión caelestia)
  --uninstall    desinstala: restaura respaldos y elimina archivos creados
EOF
}

MODE="run"
case "${1:-}" in
  --check)
    MODE="check"
    CHECK=1
    ;;
  --dry-run)
    MODE="dry-run"
    DRY_RUN=1
    ;;
  --ui-only)
    MODE="ui-only"
    ;;
  --uninstall)
    if [ -x "$DIR/uninstall.sh" ]; then
      exec "$DIR/uninstall.sh"
    fi
    die "No se encontró $DIR/uninstall.sh"
    ;;
  "")
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "Opción desconocida: $1"
    ;;
esac

log_info "=== Dual-Session Setup — usuario: $USER ==="
load_config

print_report() {
  echo
  echo "Entorno detectado:"
  echo "  Tarjeta:        card${CARD_INDEX} (${CARD_ALSA_NAME})"
  echo "  Ranura PCI:     ${CARD_SLOT}"
  echo "  Nombre ALSA:    ${CARD_ALSA_NAME}"
  echo "  Dispositivo:    ${ALSA_DEVICE}"
  echo "  Claves IPC:     dmix=${IPC_KEY_BASE}   dsnoop=${IPC_KEY2}"
  echo "  Calidad:        rate=${RATE} format=${FORMAT} channels=${CHANNELS}"
  echo "  Tamaños:        period=${PERIOD_SIZE} buffer=${BUFFER_SIZE}"
  if [ "$ENABLE_UI" -eq 1 ]; then
    echo "  UI (shell.json): habilitado"
  else
    echo "  UI (shell.json): deshabilitado (falta $SHELL_JSON o ENABLE_UI=0)"
  fi
  echo
  echo "Estado de archivos:"
  echo "  $ASOUNDRC — $(path_state "$ASOUNDRC") (respaldo: $(has_backup "$ASOUNDRC"))"
  echo "  $WP_CONF — $(path_state "$WP_CONF")"
  echo "  $PW_CONF — $(path_state "$PW_CONF")"
  echo "  $SHELL_JSON — $(path_state "$SHELL_JSON") (respaldo: $(has_backup "$SHELL_JSON"))"
  echo "  Config: $CONF — $(path_state "$CONF")"
}

print_summary() {
  echo
  echo "=== RESUMEN — usuario: $USER ==="
  echo "  .asoundrc:      $(path_state "$ASOUNDRC")"
  echo "  WirePlumber:    $(path_state "$WP_CONF")"
  echo "  PipeWire sink:  $(path_state "$PW_CONF")"
  if [ "$ENABLE_UI" -eq 1 ]; then
    echo "  shell.json:     fusionado (botón 'Switch session' + launcher)"
  fi
  echo
  echo "Verificación:"
  echo "  wpctl status"
  echo "  aplay -D plug:dmix_pch -t raw -r ${RATE} -c ${CHANNELS} -f ${FORMAT} /dev/zero   (Ctrl-C para detener)"
  echo
  echo "IMPORTANTE: REPITA ESTE SCRIPT EN LA CUENTA DE CADA USUARIO DE SESIÓN."
}

case "$MODE" in
  check)
    print_report
    exit 0
    ;;
  dry-run)
    log_info "Modo simulación: no se escribe ningún archivo ni se reinician servicios."
    audio_install
    if [ "$ENABLE_UI" -eq 1 ]; then
      ui_install
    else
      log_info "UI: omitida (ENABLE_UI=0 o sin shell.json)"
    fi
    print_summary
    ;;
  ui-only)
    ui_install
    echo
    echo "=== UI lista — botón 'Switch session' disponible (Ctrl+Alt+Supr o launcher: > switch) ==="
    ;;
  run)
    ensure_config
    audio_install
    if [ "$ENABLE_UI" -eq 1 ]; then
      ui_install
    else
      log_info "UI: omitida (ENABLE_UI=0 o sin shell.json)"
    fi
    print_summary
    ;;
esac

exit 0