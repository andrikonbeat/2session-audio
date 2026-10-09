# 2session-audio

Share one ALSA sound card between two graphical sessions on the same Linux
machine — no config file editing, no sudo. Install once per user that needs
audio; every session opens the card through a shared ALSA dmix and the same
sound works everywhere.

## Quick start

### 1. Install (one line)

Requires `curl` (present on most Linux desktops):

```sh
curl -fsSL https://raw.githubusercontent.com/andrikonbeat/2session-audio/main/install.sh | bash
```

Alternative: `git clone https://github.com/andrikonbeat/2session-audio` and run
`./install.sh` from the checkout. Either way the product lands in
`~/.local/share/dual-session-setup/` and a desktop menu entry is added.

### 2. Run the setup in EVERY user account that needs audio

```sh
~/.local/share/dual-session-setup/setup.sh
```

Run it once per user (or once per graphical session), not just once per
machine. The second user does **not** need a separate configuration — the
shared keys are derived deterministically from the card's PCI slot, so every
account computes the same values.

### 3. Verify

```sh
wpctl status      # look for "PCH dmix compartido (dual-session)"
```

or play a test tone (Ctrl-C to stop):

```sh
aplay -D plug:dmix_pch -t raw -r 48000 -c 2 -f S16_LE /dev/zero
```

### Uninstall (one line)

```sh
curl -fsSL https://raw.githubusercontent.com/andrikonbeat/2session-audio/main/uninstall.sh | bash
```

Run the uninstall in every account that ran the setup. Re-running is safe: a
second run finds nothing left to do.

## Requirements

| Requirement | Notes |
|---|---|
| Linux with PipeWire + WirePlumber | The whole point is sharing via an ALSA dmix under PipeWire. |
| systemd + logind | Used to detect and switch to the other graphical session. |
| bash ≥ 4 | Default on virtually every modern distro. |
| `curl` + `tar` | Only needed for the one-line install path. |
| `python3` | Only for the optional launcher-shell (`shell.json`) integration. |

Not supported: PulseAudio-only setups, non-systemd environments, non-Linux
platforms. Everything is detected automatically; when detection picks the
wrong card, override it in the config file (see Configuration).

## Why this exists

A typical on-board HDA card exposes a single substream. The first session's
PipeWire grabs it exclusively and the second session ends up with a silent
"Dummy Output" sink (`EBUSY`).

This product:

1. Opens the card through a **shared ALSA dmix** (`~/.asoundrc`), so multiple
   sessions can mix into the same PCM.
2. Forces **WirePlumber** onto that shared path.
3. Adds a **static PipeWire adapter sink** for sessions that skip the card.
4. Pins the card's **hardware playback mixer to unity** on every login, so
   disabling ACP does not leave the card quiet (see below).

Everything is auto-detected, deterministic across users, and fully reversible.

## How the shared keys work across users

Both users must open the same dmix to mix into the same PCM. The IPC key is
derived from the card's PCI slot with `cksum`, so **any account on the same
machine computes the same two keys** (`key1 = 10000000 + (cksum % 80000000)`,
`key2 = key1 + 1`). `ipc_key_add_uid false` and `ipc_perm 0666` make the
shared-memory mixer accessible to both users. Running the setup once per
account is all that is needed; the results are identical.

## Why the hardware mixer is pinned

Forcing the card onto the shared dmix requires `api.alsa.use-acp = false` (ACP
would otherwise take the card over). But ACP is also what maps the desktop
volume onto the card's **hardware** mixer. With ACP off, PipeWire applies only
*software* volume and leaves the hardware playback controls (e.g. `Master`) at
whatever ALSA restored at boot.

If that saved value is below unity the card stays quiet no matter what the
desktop slider shows — the slider reads 100% while the hardware sits at, say,
−23 dB — and fixing it by hand does not survive a reboot, because
`alsa-restore` re-applies the saved low value.

To keep the shared setup loud, the setup writes a small script and a
`systemd --user` oneshot unit that pin the detected card's hardware playback
mixer to unity on every login:

```
~/.local/share/dual-session-setup/pin-mixer.sh
~/.config/systemd/user/dual-session-audio-mixer.service
```

The unit is enabled at install and removed on uninstall. Override the pinned
controls with `MIXER_CONTROLS` (see Configuration).

## Usage reference

| Command | Effect |
|---|---|
| `setup.sh` | Full run for the current user (audio + UI integration if enabled). Creates the config file on first run. |
| `setup.sh --check` | Print the detected environment and file state. Writes nothing. |
| `setup.sh --dry-run` | Simulate the full run. Writes nothing, never restarts services. |
| `setup.sh --ui-only` | Only the launcher-shell integration (requires `shell.json`). |
| `setup.sh --uninstall` | Restore backups and remove every file the product created. |
| `install.sh` | Copy the product to `~/.local/share/dual-session-setup/` and add a desktop entry. |
| `uninstall.sh` | Same as `setup.sh --uninstall`, plus removal of the installed copy and the desktop entry. |

## Safety guarantees

- **`--check` and `--dry-run` never write or mutate anything.**
- **Config files are never overwritten** — locals are backed up first.
- **Your modified files are never deleted** — an uninstall keeps any file whose
  content no longer matches the recorded signature, together with its backup.
- **Idempotent** — re-running any command is safe.

## Configuration

On the first real run, `~/.config/dual-session-setup.conf` is created with the
detected values (mode `600`). It is never overwritten; edit it to override
detection, then re-run `setup.sh`.

| Key | Default | Meaning |
|---|---|---|
| `CARD_SLOT` | detected | PCI slot of the audio card, e.g. `pci-0000_00_1f.3`. |
| `CARD_ALSA_NAME` | detected | ALSA short name from `/proc/asound/cards`, e.g. `PCH`. |
| `ALSA_DEVICE` | `0` | ALSA device number. |
| `RATE` | `48000` | Sample rate for the shared PCMs. |
| `FORMAT` | `S16_LE` | Sample format for the shared PCMs. |
| `CHANNELS` | `2` | Channel count for the shared PCMs. |
| `PERIOD_SIZE` | `1024` | dmix period size. |
| `BUFFER_SIZE` | `8192` | dmix buffer size. |
| `ENABLE_UI` | `1` if `shell.json` exists | Enable the launcher-shell integration (`0`/`1`). |
| `IPC_KEY_BASE` | derived | First shared dmix key; the dsnoop key is `IPC_KEY_BASE + 1`. |
| `MIXER_CONTROLS` | `Master PCM Front` | Hardware playback controls pinned to 100% on login (space-separated). Set the controls your card actually exposes. |

### Detection order

1. Scan `/proc/asound/card*/codec#0` for on-board codec signatures (Realtek
   `ALC*`, `VT*`, `CX*`, `STAC*`, Sigmatel, Analog Devices).
2. Fallback: first card whose sysfs device class is `0403` (Audio) and whose
   short name is not HDMI / Display Audio.
3. Last resort: `card0`.

Override anything with the config file when detection picks the wrong card.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "Dummy Output" sink after setup | The card is not forced onto the dmix. Check `wpctl status` and that `~/.config/wireplumber/wireplumber.conf.d/51-pch-shared-dmix.conf` exists; restart the session. |
| `aplay: ... Device or resource busy` | Another process grabs the substream directly. Both sessions must use `dmix_pch`; never address the card with `hw:...` in custom configs. |
| Sound does not mix across users | Shared-memory key mismatch. Keys derive from the PCI slot; if a config override sets `IPC_KEY_BASE`, it must be identical in every account. |
| Card moved to a different PCI slot | Detection is slot-based. Check `setup.sh --check`, fix `CARD_SLOT` (and `CARD_ALSA_NAME`) in the config, re-run the setup on every account. |
| `setup.sh --check` shows the wrong card | Override `CARD_SLOT` / `CARD_ALSA_NAME` / `ALSA_DEVICE` in the config file. |
| Sound is very quiet at 100% (the slider lies) | With ACP off, PipeWire cannot raise the card's hardware mixer. Check `amixer -c PCH sget Master`; the product pins `MIXER_CONTROLS` on login. If your card has no `Master`, set `MIXER_CONTROLS` to the controls it does expose, then `systemctl --user restart dual-session-audio-mixer.service`. |
| `dual-session-audio-mixer.service` not found | Run `setup.sh` in this account (the unit is per user). Confirm the script exists at `~/.local/share/dual-session-setup/pin-mixer.sh` and re-run `systemctl --user daemon-reload`. |

## What gets installed

```
~/.local/share/dual-session-setup/
├── setup.sh        # main orchestrator
├── install.sh
├── uninstall.sh
└── lib/
    ├── common.sh   # detection, config, backup/restore
    ├── audio.sh    # asoundrc + WirePlumber/PipeWire confs
    ├── mixer.sh    # pin the hardware playback mixer to unity on login
    └── ui.sh       # launcher-shell (shell.json) merge integration
```

Plus, on first run: `~/.config/dual-session-setup.conf` and
`~/.config/dual-session-setup.manifest` (the signature list used by the
uninstaller), and a `systemd --user` unit
`~/.config/systemd/user/dual-session-audio-mixer.service` with its helper
`~/.local/share/dual-session-setup/pin-mixer.sh`.

## Support

Found a bug or want a feature? Open an issue at
https://github.com/andrikonbeat/2session-audio/issues