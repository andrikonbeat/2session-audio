#!/usr/bin/env bash
#
# lib/ui.sh — optional caelestia-shell integration (merge-only).
# Sourced by setup.sh / uninstall.sh; depends on lib/common.sh.
#
# Active only when $HOME/.config/caelestia/shell.json exists; otherwise it
# logs "skipped" and returns 0. The integration is OPTIONAL for the caelestia
# shell, never a hard requirement.
#
# ui_install backs the file up, MERGES three keys with python3 and never
# touches any other key:
#   * session.icons.hibernate        -> "switch_account"
#   * session.commands.hibernate     -> generalized session-switch command
#   * launcher action "Switch session" (appended only if absent)
# validates the result with python3 -m json.tool, then writes via
# write_tracked (only when the content changed). ui_remove restores the
# pre-install backup.
set -euo pipefail

# Command stored in shell.json; $(...) and $USER expand when the shell action
# runs (click time), targeting the first OTHER seat0 graphical session of a
# different user. The awk matches the tty field in both the classic 5-column
# and the modern 9-column loginctl layouts (TTY in $5 / $7 respectively).
SWITCH_CMD="$(cat <<'EOF'
loginctl activate $(loginctl list-sessions --no-legend | awk '$4 == "seat0" && $3 != "'"$USER"'" && ($5 ~ /^tty/ || $7 ~ /^tty/) {print $1; exit}')
EOF
)"

ui_install() {
  local tmp=""

  if [ ! -f "$SHELL_JSON" ]; then
    log_info "UI: sin $SHELL_JSON; integración de shell omitida (opcional)"
    return 0
  fi

  if [ "$CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    log_info "[simulación] Respaldar $SHELL_JSON"
    log_info "[simulación] Fusionar session.icons.hibernate / session.commands.hibernate y acción 'Switch session'"
    log_info "[simulación] Validar JSON y escribir solo si cambia"
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 no encontrado; integración de shell omitida (no crítica)"
    return 0
  fi

  backup_file "$SHELL_JSON"
  log_info "Fusionando shell.json (solo claves de sesión / acción de lanzador)..."
  tmp="$(SHELL_JSON="$SHELL_JSON" SWITCH_CMD="$SWITCH_CMD" python3 - <<'PY'
import json
import os
import tempfile

path = os.environ["SHELL_JSON"]
cmd = os.environ["SWITCH_CMD"]

with open(path, encoding="utf-8") as fh:
    data = json.load(fh)

session = data.setdefault("session", {})
session.setdefault("icons", {})["hibernate"] = "switch_account"
session.setdefault("commands", {})["hibernate"] = ["bash", "-c", cmd]

actions = data.setdefault("launcher", {}).setdefault("actions", [])
if not any(isinstance(a, dict) and a.get("name") == "Switch session" for a in actions):
    actions.append({
        "name": "Switch session",
        "icon": "switch_account",
        "description": "Switch to the other graphical session, leaving this one active",
        "command": ["bash", "-c", cmd],
    })

fd, tmp = tempfile.mkstemp(prefix=".shell.json.", dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=4, ensure_ascii=False)
    fh.write("\n")
print(tmp)
PY
)"

  if ! python3 -m json.tool "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    die "shell.json fusionado no válido"
  fi
  write_tracked "$SHELL_JSON" < "$tmp"
  rm -f "$tmp"
  apply_or_report "Actualizar manifiesto $MANIFEST" update_manifest
}

# Restore the pre-install shell.json backup. If the current file still matches
# the manifest (product merge untouched) the backup is consumed; otherwise the
# user's copy and the backup are both kept.
ui_remove() {
  local sig="" actual=""

  [ -f "$SHELL_JSON" ] || return 0
  sig="$(manifest_sig "$SHELL_JSON")"
  [ -n "$sig" ] || return 0    # product never merged it: leave alone
  actual="$(md5sum < "$SHELL_JSON" | awk '{print $1}')"
  if [ "$sig" = "$actual" ]; then
    restore_backup "$SHELL_JSON"
  else
    log_warn "Se conserva $SHELL_JSON (modificado) junto con su respaldo"
  fi
}