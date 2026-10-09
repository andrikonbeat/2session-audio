#!/usr/bin/env bash
#
# lib/audio.sh — shared ALSA/PipeWire audio setup for the dual-session product.
# Sourced by setup.sh / uninstall.sh; depends on lib/common.sh.
#
# Installs per user (no root, no sudo):
#   * ~/.asoundrc                              — shared dmix/dsnoop PCMs with
#                                                deterministic IPC keys
#   * WirePlumber rules                        — force the detected card onto
#                                                the shared dmix
#   * static PipeWire adapter sink             — fallback for sessions where
#                                                WirePlumber skips the card
# and restarts that user's audio stack. Restart never happens under
# --check/--dry-run; removal only deletes files whose content signature still
# matches the manifest (user-modified files are kept).
set -euo pipefail

audio_install() {
  local pwfmt=""

  log_info "--- Audio compartido (usuario: $USER) ---"
  log_info "Tarjeta: card${CARD_INDEX} (${CARD_ALSA_NAME}) — ranura ${CARD_SLOT}"

  # 1) shared ~/.asoundrc with deterministic dmix/dsnoop keys
  backup_file "$ASOUNDRC"
  write_tracked "$ASOUNDRC" <<EOF
# Shared dmix for the on-board HDA card detected at setup time.
# Allows multiple sessions (different users) to play simultaneously.
# Same keys on every user account => same shared-memory mixer.
pcm.dmix_pch {
    type dmix
    ipc_key ${IPC_KEY_BASE}
    ipc_key_add_uid false
    ipc_perm 0666
    slave {
        pcm "plughw:CARD=${CARD_ALSA_NAME},DEV=${ALSA_DEVICE}"
        period_time 0
        period_size ${PERIOD_SIZE}
        buffer_size ${BUFFER_SIZE}
        rate ${RATE}
        format ${FORMAT}
        channels ${CHANNELS}
    }
}
pcm.plug_dmix_pch {
    type plug
    slave.pcm "dmix_pch"
}
pcm.dsnoop_pch {
    type dsnoop
    ipc_key ${IPC_KEY2}
    ipc_key_add_uid false
    ipc_perm 0666
    slave {
        pcm "plughw:CARD=${CARD_ALSA_NAME},DEV=${ALSA_DEVICE}"
        period_time 0
        period_size ${PERIOD_SIZE}
        buffer_size ${BUFFER_SIZE}
        rate ${RATE}
        format ${FORMAT}
        channels ${CHANNELS}
    }
}
pcm.plug_dsnoop_pch {
    type plug
    slave.pcm "dsnoop_pch"
}
EOF

  # 2) WirePlumber rules: disable ACP for this card, force the shared dmix path
  apply_or_report "Crear directorio $(dirname "$WP_CONF")" mkdir -p "$(dirname "$WP_CONF")"
  write_tracked "$WP_CONF" <<EOF
# Force the on-board HDA card onto a shared ALSA dmix PCM so multiple desktop
# sessions (different users) can play simultaneously. Other cards keep their
# default ACP behavior.
monitor.alsa.rules = [
  {
    matches = [
      { device.name = "~alsa_card.${CARD_SLOT}" }
    ]
    actions = {
      update-props = {
        api.alsa.use-acp = false
      }
    }
  }
  {
    matches = [
      { node.name = "~alsa_output.${CARD_SLOT}.*" }
    ]
    actions = {
      update-props = {
        api.alsa.path = "plug:dmix_pch"
      }
    }
  }
]
EOF

  # 3) static PipeWire adapter sink — covers sessions where WirePlumber does
  #    not enumerate the card; harmless when it does
  apply_or_report "Crear directorio $(dirname "$PW_CONF")" mkdir -p "$(dirname "$PW_CONF")"
  pwfmt="${FORMAT//_/}"
  write_tracked "$PW_CONF" <<EOF
context.objects = [
  {
    factory = adapter
    args = {
      factory.name      = api.alsa.pcm.sink
      node.name         = "alsa_output.pch-dmix"
      node.description  = "PCH dmix compartido (dual-session)"
      media.class       = "Audio/Sink"
      api.alsa.path     = "plug:dmix_pch"
      api.alsa.period-size = ${PERIOD_SIZE}
      api.alsa.headroom = 0
      audio.format      = "${pwfmt}"
      audio.rate        = ${RATE}
      audio.channels    = ${CHANNELS}
      audio.position    = [ FL FR ]
    }
  }
]
EOF

  # 4) product files are world-readable configs
  apply_or_report "chmod 644 de los 3 archivos de audio" chmod 644 "$ASOUNDRC" "$WP_CONF" "$PW_CONF"

  # 5) manifest: record exact content signatures for safe removal
  apply_or_report "Actualizar manifiesto $MANIFEST" update_manifest

  # 6) restart this user's audio stack (never under --check/--dry-run)
  if [ "$CHECK" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    log_info "[simulación] Reiniciar pipewire pipewire-pulse wireplumber (systemctl --user)"
  else
    log_info "Reiniciando PipeWire / pipewire-pulse / WirePlumber..."
    if ! systemctl --user restart pipewire pipewire-pulse wireplumber; then
      log_warn "No se pudo reiniciar la pila de audio; reinicie la sesión"
    fi
    sleep 2
  fi

  # 7) pin the card's hardware playback mixer to unity (see lib/mixer.sh)
  mixer_install
}

# Remove the shared-audio files the product created, restore the pre-install
# ~/.asoundrc backup, and drop the manifest. Files whose content no longer
# matches the manifest (user-modified) are NEVER deleted; their backup is kept.
audio_remove() {
  local path="" sig="" actual=""

  log_info "--- Quitar audio compartido ---"
  for path in "$ASOUNDRC" "$WP_CONF" "$PW_CONF"; do
    sig="$(manifest_sig "$path")"
    [ -n "$sig" ] || continue    # product never tracked it: leave alone
    [ -f "$path" ] || continue   # already gone
    actual="$(md5sum < "$path" | awk '{print $1}')"
    if [ "$sig" = "$actual" ]; then
      apply_or_report "Eliminar $path" rm -f "$path"
    else
      log_warn "Se conserva $path (modificado tras la instalación)"
    fi
  done

  # restore the pre-install .asoundrc backup only when the product-owned file
  # was actually removed; modified/untracked copies stay untouched
  if [ -n "$(manifest_sig "$ASOUNDRC")" ] && [ ! -f "$ASOUNDRC" ]; then
    restore_backup "$ASOUNDRC"
  fi

  # remove the hardware-mixer pin first (it needs the manifest to verify files)
  mixer_remove

  apply_or_report "Eliminar manifiesto $MANIFEST" rm -f "$MANIFEST"
  # leave no empty product directories behind (may pre-exist: ignore failures)
  rmdir "$(dirname "$WP_CONF")" 2>/dev/null || true
  rmdir "$(dirname "$PW_CONF")" 2>/dev/null || true
}