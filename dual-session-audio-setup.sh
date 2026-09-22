#!/usr/bin/env bash
#
# dual-session-audio-setup.sh
# ===========================
# Shared audio for two logged-in desktop sessions on the same machine
# (e.g. andrik/KDE on tty2 + caelestia/Hyprland on tty3).
#
# Problem it solves:
#   The onboard HDA Intel PCH (ALC887-VD) has ONE substream. The first
#   session's PipeWire takes it EXCLUSIVELY (EBUSY) and the other session
#   ends up with only a "Dummy Output" sink (silent).
#
# Fix:
#   Both sessions open the card through a SHARED ALSA dmix (same ipc_key,
#   ipc_key_add_uid=false, ipc_perm=0666) so they mix into the same PCM.
#   WirePlumber is told to stop using ACP for this card and force the dmix
#   path; a static PipeWire adapter sink covers sessions where WirePlumber
#   refuses to enumerate the card (observed on caelestia's side).
#
# RUN IT AS EVERY USER THAT NEEDS AUDIO (no sudo needed):
#     bash dual-session-audio-setup.sh
#   It installs the files into $HOME and restarts that user's audio stack.
#
# NOTES FOR A FRESH INSTALL:
#   * Same hardware => defaults below are correct. If the card moves to a
#     different PCI slot / ALSA index, adjust SLOT and the "hw:0,0" lines.
#   * To write files into the OTHER user's home from this session, the
#     directory needs an ACL:
#         sudo setfacl -R -m u:<youruser>:rwx -m d:u:<youruser>:rwx /home/<other>
#   * The dmix/dsnoop ipc keys only need to MATCH across users; change them
#     if you ever have a conflict with something else on the system.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Detect (or default) the onboard HDA PCH PCI slot
# ---------------------------------------------------------------------------
SLOT="pci-0000_00_1f.3"   # <- this machine (ASUS/typical Intel PCH)
for codec in /proc/asound/card*/codec#0; do
  [ -r "$codec" ] || continue
  if grep -qiE "ALC887|ALC892|ALC1150|ALC1220" "$codec" 2>/dev/null; then
    carddir="$(basename "$(dirname "$codec")")"   # e.g. card0
    found="$(readlink -f "/sys/class/sound/$carddir/device" 2>/dev/null | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]' | tail -1 || true)"
    if [ -n "$found" ]; then
      SLOT="pci-$(echo "$found" | tr ':' '_')"
      echo "Detected onboard HDA at $found"
    fi
    break
  fi
done
echo "Using PCI slot: $SLOT  (card is opened as hw:0,0; fix here if ALSA indexes differ)"

# ---------------------------------------------------------------------------
# 1) ~/.asoundrc — shared dmix + dsnoop PCM definitions
# ---------------------------------------------------------------------------
cat > "$HOME/.asoundrc" <<EOF
# Shared dmix for the onboard HDA Intel PCH (ALC887-VD, card 0)
# Allows multiple sessions (different users) to play simultaneously.
# Same key on every user account => same shared-memory mixer.
pcm.dmix_pch {
    type dmix
    ipc_key 13579246
    ipc_key_add_uid false
    ipc_perm 0666
    slave {
        pcm "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 8192
        rate 48000
        format S16_LE
        channels 2
    }
}
pcm.plug_dmix_pch {
    type plug
    slave.pcm "dmix_pch"
}
pcm.dsnoop_pch {
    type dsnoop
    ipc_key 13579247
    ipc_key_add_uid false
    ipc_perm 0666
    slave {
        pcm "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 8192
        rate 48000
        format S16_LE
        channels 2
    }
}
pcm.plug_dsnoop_pch {
    type plug
    slave.pcm "dsnoop_pch"
}
EOF

# ---------------------------------------------------------------------------
# 2) WirePlumber rules — disable ACP for the card and force the dmix path
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/wireplumber/wireplumber.conf.d"
cat > "$HOME/.config/wireplumber/wireplumber.conf.d/51-pch-shared-dmix.conf" <<EOF
# Force the onboard HDA PCH onto a shared ALSA dmix PCM so multiple desktop
# sessions (different users) can play simultaneously. The NVidia HDMI card
# keeps its default ACP behavior.
monitor.alsa.rules = [
  {
    matches = [
      { device.name = "~alsa_card.${SLOT}" }
    ]
    actions = {
      update-props = {
        api.alsa.use-acp = false
      }
    }
  }
  {
    matches = [
      { node.name = "~alsa_output.${SLOT}.*" }
    ]
    actions = {
      update-props = {
        api.alsa.path = "plug:dmix_pch"
      }
    }
  }
]
EOF

# ---------------------------------------------------------------------------
# 3) Static PipeWire adapter sink — opens the shared dmix directly.
#    Covers sessions where WirePlumber does not enumerate the card at all
#    (observed on caelestia's side); harmless anyway if it does.
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.config/pipewire/pipewire.conf.d"
cat > "$HOME/.config/pipewire/pipewire.conf.d/10-pch-dmix-sink.conf" <<'EOF'
context.objects = [
  {
    factory = adapter
    args = {
      factory.name   = api.alsa.pcm.sink
      node.name      = "alsa_output.pch-dmix"
      node.description = "PCH dmix compartido (dual-session)"
      media.class    = "Audio/Sink"
      api.alsa.path  = "plug:dmix_pch"
      api.alsa.period-size = 1024
      api.alsa.headroom     = 0
      audio.format   = "S16LE"
      audio.rate     = 48000
      audio.channels = 2
      audio.position = [ FL FR ]
    }
  }
]
EOF

chmod 644 "$HOME/.asoundrc" \
          "$HOME/.config/wireplumber/wireplumber.conf.d/51-pch-shared-dmix.conf" \
          "$HOME/.config/pipewire/pipewire.conf.d/10-pch-dmix-sink.conf"

echo "Files installed for user: $USER"
echo "  - $HOME/.asoundrc"
echo "  - $HOME/.config/wireplumber/wireplumber.conf.d/51-pch-shared-dmix.conf"
echo "  - $HOME/.config/pipewire/pipewire.conf.d/10-pch-dmix-sink.conf"

# ---------------------------------------------------------------------------
# 4) Restart this user's audio stack
# ---------------------------------------------------------------------------
echo "Restarting pipewire / pipewire-pulse / wireplumber..."
systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 2

echo
echo "Done for $USER. Verify with:  wpctl status"
echo "  * The shared sink appears as 'PCH dmix compartido (dual-session)'."
echo "  * echo test:  aplay -D plug:dmix_pch -t raw -r 48000 -c 2 -f S16_LE /dev/zero (Ctrl-C to stop)"
echo
echo "REPEAT THIS SCRIPT IN EVERY SESSION USER'S ACCOUNT (same hardware defaults)."