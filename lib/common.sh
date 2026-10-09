#!/usr/bin/env bash
#
# lib/common.sh — shared helpers for the dual-session-setup product.
# Sourced by setup.sh / uninstall.sh; not executable on its own.
#
# Responsibilities:
#   * config load (defaults + ~/.config/dual-session-setup.conf overrides)
#   * hardware detection (codec scan, first non-HDMI 0403 card fallback, card0)
#   * deterministic IPC-key derivation (identical on every user account)
#   * backup / restore / idempotent-write helpers
#   * logging + --check / --dry-run mutation gating
#
# Every function is safe under CHECK=1 / DRY_RUN=1: they never write files and
# never restart services. In --dry-run they report what WOULD happen instead.
set -euo pipefail

# ---------------------------------------------------------------------------
# Modes / paths
# ---------------------------------------------------------------------------
MODE="${MODE:-run}"        # run | check | dry-run
CHECK="${CHECK:-0}"        # 1 = report only, no mutation
DRY_RUN="${DRY_RUN:-0}"    # 1 = print steps, no mutation

CONF="$HOME/.config/dual-session-setup.conf"
MANIFEST="$HOME/.config/dual-session-setup.manifest"

ASOUNDRC="$HOME/.asoundrc"
SHELL_JSON="$HOME/.config/caelestia/shell.json"
WP_CONF="$HOME/.config/wireplumber/wireplumber.conf.d/51-pch-shared-dmix.conf"
PW_CONF="$HOME/.config/pipewire/pipewire.conf.d/10-pch-dmix-sink.conf"

# Hardware-mixer pin: a standalone script + a systemd --user oneshot that keep
# the shared card's hardware playback mixer at unity. See lib/mixer.sh for why.
DEST="$HOME/.local/share/dual-session-setup"
PIN_SCRIPT="$DEST/pin-mixer.sh"
MIXER_UNIT="$HOME/.config/systemd/user/dual-session-audio-mixer.service"
MIXER_SERVICE="dual-session-audio-mixer.service"

# Public one-liners shown to the user (kept in one place).
GITHUB_OWNER="andrikonbeat"
GITHUB_REPO="2session-audio"
GITHUB_BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_OWNER/$GITHUB_REPO/$GITHUB_BRANCH"
RAW_INSTALL="$RAW_BASE/install.sh"
RAW_UNINSTALL="$RAW_BASE/uninstall.sh"

# Files the product owns; content signatures go into $MANIFEST so uninstall
# never deletes a user-modified file.
TRACKED_FILES=(
  "$ASOUNDRC"
  "$WP_CONF"
  "$PW_CONF"
  "$SHELL_JSON"
  "$PIN_SCRIPT"
  "$MIXER_UNIT"
)

# ---------------------------------------------------------------------------
# Logging (Spanish, matches the project's user-facing language)
# ---------------------------------------------------------------------------
log_info()  { printf '==> %s\n' "$*"; }
log_warn()  { printf 'AVISO: %s\n' "$*" >&2; }
log_error() { printf 'ERROR: %s\n' "$*" >&2; }
die()       { log_error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Mode gating — the single place that decides whether a step really runs.
# ---------------------------------------------------------------------------
apply_or_report() {
  local label="$1"; shift
  if [ "$CHECK" -eq 1 ]; then
    return 0                                  # --check never mutates
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "[simulación] $label"
    return 0
  fi
  "$@"
}

# ---------------------------------------------------------------------------
# Hardware detection (generalized; no hardcoded codec / PCI slot)
# ---------------------------------------------------------------------------
# ALSA short name (e.g. PCH) of a card index, from /proc/asound/cards.
alsa_card_name() {
  local idx="$1" name
  name="$(awk -v i="$idx" '
    $1 == i && match($0, /\[[^]]+\]/) { print substr($0, RSTART + 1, RLENGTH - 2); exit }
  ' /proc/asound/cards 2>/dev/null || true)"
  # /proc/asound/cards pads the short name to a fixed column width
  printf '%s\n' "${name%"${name##*[![:space:]]}"}"
}

# PCI-slot string (pci-XXXX_XX_X.X) of a card index, resolved via sysfs.
slot_for_index() {
  local idx="$1" dev addr
  dev="$(readlink -f "/sys/class/sound/card${idx}/device" 2>/dev/null || true)"
  [ -n "$dev" ] || return 1
  addr="$(printf '%s\n' "$dev" | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' | tail -1 || true)"
  [ -n "$addr" ] || return 1
  printf 'pci-%s\n' "${addr//:/_}"
}

# Card index whose sysfs device resolves to a given PCI slot.
card_index_for_slot() {
  local slot="$1" n s
  for c in /sys/class/sound/card*; do
    n="${c##*/card}"
    s="$(slot_for_index "$n" 2>/dev/null)" || continue
    if [ "$s" = "$slot" ]; then
      printf '%s\n' "$n"
      return 0
    fi
  done
  return 1
}

# Detect the on-board HDA card for this machine. Sets CARD_INDEX and CARD_SLOT.
# Strategy: 1) known on-board codec signatures, 2) first non-HDMI card whose
# device class is 0403 (Audio), 3) card0 as last resort.
detect_onboard_slot() {
  local idx="" n class name codec

  # 1) on-board codec scan (Realtek / VIA / Conexant / IDT / Analog Devices)
  for codec in /proc/asound/card*/codec#0; do
    [ -r "$codec" ] || continue
    if grep -qiE 'ALC[0-9]+|Realtek|VT[0-9]+|CX[0-9]+|STAC[0-9]+|Sigmatel|Analog Devices' "$codec" 2>/dev/null; then
      n="$(basename "$(dirname "$codec")")"
      idx="${n#card}"
      log_info "Codec on-board detectado en card${idx}"
      break
    fi
  done

  # 2) fallback: first card with audio device class 0403, not HDMI
  if [ -z "$idx" ]; then
    for c in /sys/class/sound/card*; do
      n="${c##*/card}"
      [ -r "$c/device/class" ] || continue
      IFS= read -r class < "$c/device/class"
      class="${class#0x}"
      class="${class:0:4}"
      [ "$class" = "0403" ] || continue
      name="$(alsa_card_name "$n")"
      case "$name" in
        *HDMI*|*'Display Audio'*) continue ;;
      esac
      idx="$n"
      log_info "Primera tarjeta 0403 no-HDMI: card${idx} (${name})"
      break
    done
  fi

  # 3) last resort
  if [ -z "$idx" ]; then
    idx=0
    log_warn "No se detectó HDA on-board; se usa card0 como último recurso"
  fi

  CARD_INDEX="$idx"
  if ! CARD_SLOT="$(slot_for_index "$CARD_INDEX")"; then
    CARD_SLOT="card${CARD_INDEX}"
    log_warn "Sin ranura PCI para card${CARD_INDEX}; se usa '${CARD_SLOT}'"
  fi
}

# Deterministic IPC keys for a slot: identical value on every user account.
# Prints "<key1> <key2>" (key2 = key1 + 1).
derive_ipc_keys() {
  local slot="$1" sum key1 key2
  sum="$(printf '%s' "$slot" | cksum)"
  sum="${sum%% *}"
  key1=$(( 10000000 + (sum % 80000000) ))
  key2=$(( key1 + 1 ))
  printf '%s %s\n' "$key1" "$key2"
}

# ---------------------------------------------------------------------------
# Configuration: defaults + ~/.config/dual-session-setup.conf overrides.
# load_config detects and loads WITHOUT writing; ensure_config persists the
# detected values on the first REAL run and never overwrites an existing file.
# ---------------------------------------------------------------------------
load_config() {
  local k

  ALSA_DEVICE="${ALSA_DEVICE:-0}"
  RATE="${RATE:-48000}"
  FORMAT="${FORMAT:-S16_LE}"
  CHANNELS="${CHANNELS:-2}"
  PERIOD_SIZE="${PERIOD_SIZE:-1024}"
  BUFFER_SIZE="${BUFFER_SIZE:-8192}"
  # Hardware playback controls pinned to unity (space-separated); see lib/mixer.sh.
  MIXER_CONTROLS="${MIXER_CONTROLS:-Master PCM Front}"

  # config-file overrides (documented keys win over detection)
  if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF" || die "Config no válido: $CONF"
  fi

  # ENABLE_UI: explicit value (env/config) wins; default is 1 only when the
  # caelestia shell.json exists (the integration layer is optional).
  if [ -z "${ENABLE_UI+x}" ]; then
    if [ -f "$SHELL_JSON" ]; then
      ENABLE_UI=1
    else
      ENABLE_UI=0
    fi
  fi

  # hardware detection unless overridden by the config file
  if [ -z "${CARD_SLOT:-}" ] && [ -z "${CARD_INDEX:-}" ]; then
    detect_onboard_slot
  elif [ -n "${CARD_SLOT:-}" ] && [ -z "${CARD_INDEX:-}" ]; then
    CARD_INDEX="$(card_index_for_slot "$CARD_SLOT")" || CARD_INDEX=0
  fi
  if [ -z "${CARD_SLOT:-}" ]; then
    CARD_SLOT="$(slot_for_index "$CARD_INDEX")" || CARD_SLOT="card${CARD_INDEX}"
  fi
  CARD_ALSA_NAME="${CARD_ALSA_NAME:-$(alsa_card_name "$CARD_INDEX")}"
  [ -n "$CARD_ALSA_NAME" ] || CARD_ALSA_NAME="card${CARD_INDEX}"

  # deterministic shared keys (config may pin IPC_KEY_BASE)
  if [ -z "${IPC_KEY_BASE:-}" ]; then
    IPC_KEY_BASE="$(derive_ipc_keys "$CARD_SLOT" | awk '{print $1}')"
  fi
  IPC_KEY2=$(( IPC_KEY_BASE + 1 ))
}

# Persist the detected values (first real run only; never overwrites).
ensure_config() {
  [ -f "$CONF" ] && return 0
  [ "$CHECK" -eq 1 ] && return 0
  [ "$DRY_RUN" -eq 1 ] && return 0
  apply_or_report "Crear config $CONF" bash -c '
    mkdir -p "${1%/*}"
    umask 077
    cat > "$1"
  ' _ "$CONF" <<EOF
# dual-session-setup configuration (auto-generated on first run)
# Edit any value to override detection, then re-run setup.sh to apply it.
CARD_SLOT=$CARD_SLOT
CARD_ALSA_NAME=$CARD_ALSA_NAME
ALSA_DEVICE=$ALSA_DEVICE
RATE=$RATE
FORMAT=$FORMAT
CHANNELS=$CHANNELS
PERIOD_SIZE=$PERIOD_SIZE
BUFFER_SIZE=$BUFFER_SIZE
ENABLE_UI=$ENABLE_UI
IPC_KEY_BASE=$IPC_KEY_BASE
MIXER_CONTROLS=$MIXER_CONTROLS
EOF
}

# ---------------------------------------------------------------------------
# Backup / restore / idempotent writes
# ---------------------------------------------------------------------------
newest_backup() {
  local path="$1" bak=""
  bak="$(ls -1t "${path}".dss-bak-* 2>/dev/null | head -n1 || true)"
  printf '%s\n' "$bak"
}

# Copy <path> to <path>.dss-bak-<timestamp> only if NO dss-bak-* exists yet
# (never stacks backups).
backup_file() {
  local path="$1" bak
  if compgen -G "${path}.dss-bak-*" >/dev/null 2>&1; then
    log_info "Ya existe respaldo para $path"
    return 0
  fi
  [ -f "$path" ] || return 0
  bak="$path.dss-bak-$(date +%Y%m%d-%H%M%S)"
  apply_or_report "Respaldar $path -> $bak" cp -a "$path" "$bak"
}

# Restore the newest .dss-bak-* over <path> and remove that backup.
restore_backup() {
  local path="$1" bak
  bak="$(newest_backup "$path")"
  if [ -z "$bak" ] || [ ! -f "$bak" ]; then
    log_info "Sin respaldo para $path"
    return 0
  fi
  apply_or_report "Restaurar $path desde $bak" cp -a "$bak" "$path"
  apply_or_report "Eliminar respaldo $bak" rm -f "$bak"
}

# Write content (from stdin) to <path> only when it differs (idempotent).
# Under --check/--dry-run it compares in memory and only reports.
write_tracked() {
  local dest="$1" tmp=""

  if [ "$CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    # compare only; the process substitution avoids creating any file
    if [ -f "$dest" ] && cmp -s - "$dest" < <(cat); then
      log_info "Sin cambios: $dest"
    else
      log_info "[simulación] Escribir $dest"
    fi
    return 0
  fi

  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    log_info "Sin cambios: $dest"
    rm -f "$tmp"
    return 0
  fi
  if [ -f "$dest" ]; then
    chmod --reference="$dest" "$tmp" 2>/dev/null || true
  else
    chmod 644 "$tmp"
  fi
  mv -f "$tmp" "$dest"
  log_info "Escrito: $dest"
}

# ---------------------------------------------------------------------------
# Manifest: exact content signatures of the files the product wrote, so
# uninstall only deletes what the product itself created.
# ---------------------------------------------------------------------------
update_manifest() {
  local f
  : > "$MANIFEST"
  for f in "${TRACKED_FILES[@]}"; do
    [ -f "$f" ] || continue
    printf '%s  %s\n' "$(md5sum < "$f" | awk '{print $1}')" "$f" >> "$MANIFEST"
  done
  log_info "Manifiesto actualizado: $MANIFEST"
}

# Content signature recorded in the manifest for a path ('' when absent).
manifest_sig() {
  local path="$1"
  [ -f "$MANIFEST" ] || return 0
  awk -v p="$path" '$2 == p {print $1; exit}' "$MANIFEST"
}

# ---------------------------------------------------------------------------
# Report helpers (used by setup.sh --check)
# ---------------------------------------------------------------------------
path_state() {
  local path="$1"
  if [ -e "$path" ]; then printf 'presente'; else printf 'ausente'; fi
}

has_backup() {
  local path="$1"
  if compgen -G "${path}.dss-bak-*" >/dev/null 2>&1; then printf 'sí'; else printf 'no'; fi
}

# Names of OTHER logged-in users (best-effort; empty when unknown). Used to
# nudge the user to run the setup in the other session's account.
other_session_users() {
  command -v loginctl >/dev/null 2>&1 || return 0
  loginctl list-sessions --no-legend 2>/dev/null \
    | awk -v me="$USER" '$3 != "" && $3 != me {print $3}' \
    | sort -u
}