#!/usr/bin/env bash
#
# tests/smoke.sh — end-to-end smoke test for the dual-session product.
#
# Runs setup.sh / uninstall.sh against a throwaway HOME with `systemctl` and
# `amixer` stubbed out, so it never touches the real system or the real audio
# stack. It asserts the product writes what it should, that --check/--dry-run
# write nothing, and that uninstall removes the hardware-mixer pin.
#
# Usage: bash tests/smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
BIN="$TMP/bin"
export SYSTEMCTL_LOG="$TMP/systemctl.log"
export AMIXER_LOG="$TMP/amixer.log"
mkdir -p "$HOME" "$BIN"
: > "$SYSTEMCTL_LOG"
: > "$AMIXER_LOG"

# --- stubs -----------------------------------------------------------------
cat > "$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
exit 0
EOF
cat > "$BIN/amixer" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$AMIXER_LOG"
exit 0
EOF
chmod +x "$BIN/systemctl" "$BIN/amixer"
export PATH="$BIN:$PATH"

PIN_SCRIPT="$HOME/.local/share/dual-session-setup/pin-mixer.sh"
MIXER_UNIT="$HOME/.config/systemd/user/dual-session-audio-mixer.service"

FAILS=0
ok()   { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1" >&2; FAILS=$((FAILS + 1)); }
assert_file()      { [ -f "$1" ] && ok "$2" || fail "$2 (falta $1)"; }
assert_no_file()   { [ ! -e "$1" ] && ok "$2" || fail "$2 (existe $1)"; }
assert_exec()      { [ -x "$1" ] && ok "$2" || fail "$2 (no ejecutable: $1)"; }
assert_log()       { grep -qF -- "$2" "$1" && ok "$3" || fail "$3 (no está '$2' en $1)"; }

# --- --check and --dry-run must not write --------------------------------
HOME="$HOME" bash "$ROOT/setup.sh" --check >/dev/null
assert_no_file "$PIN_SCRIPT" "--check no escribe el script del mixer"

HOME="$HOME" bash "$ROOT/setup.sh" --dry-run >/dev/null
assert_no_file "$PIN_SCRIPT" "--dry-run no escribe el script del mixer"
assert_no_file "$MIXER_UNIT" "--dry-run no escribe la unidad systemd"

# --- real run (against the fake HOME) ------------------------------------
HOME="$HOME" bash "$ROOT/setup.sh" >/dev/null

assert_file "$PIN_SCRIPT" "setup crea el script del mixer"
assert_exec "$PIN_SCRIPT" "el script del mixer es ejecutable"
assert_file "$MIXER_UNIT" "setup crea la unidad systemd --user"
assert_log "$SYSTEMCTL_LOG" "daemon-reload" "systemctl --user daemon-reload se llama"
assert_log "$SYSTEMCTL_LOG" "enable --now dual-session-audio-mixer.service" \
  "la unidad del mixer se habilita"
assert_log "$AMIXER_LOG" "100%" "el mixer de hardware se fija a 100%"

# --- uninstall removes the pin -------------------------------------------
HOME="$HOME" bash "$ROOT/uninstall.sh" >/dev/null

assert_no_file "$PIN_SCRIPT" "uninstall elimina el script del mixer"
assert_no_file "$MIXER_UNIT" "uninstall elimina la unidad systemd"
assert_log "$SYSTEMCTL_LOG" "disable --now dual-session-audio-mixer.service" \
  "la unidad del mixer se deshabilita"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "smoke: OK"
  exit 0
fi
echo "smoke: $FAILS fallo(s)" >&2
exit 1
