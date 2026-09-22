# Dual-Session Setup

Run one ALSA sound card from two graphical sessions at the same time, on the
same machine, without editing config files or using sudo. Run once per user
that needs audio, and both sessions share the same card through an ALSA dmix.

## Quick install

Install with one line (requires `curl`, present on most Linux desktops):

```sh
curl -fsSL https://raw.githubusercontent.com/andrikonbeat/Dual-Session-Setup/main/install.sh | bash
```

Uninstall with one line:

```sh
curl -fsSL https://raw.githubusercontent.com/andrikonbeat/Dual-Session-Setup/main/uninstall.sh | bash
```

The classic clone-based install still works: `git clone` the repository and
run `./install.sh` from the checkout.

## What and why

A typical on-board HDA card exposes a single substream. The first session's
PipeWire takes it exclusively and the second session ends up with a silent
"Dummy Output" sink (`EBUSY`). This product makes every session open the card
through a shared ALSA dmix, forces WirePlumber onto that path, and adds a
static PipeWire adapter sink for sessions that skip the card. Everything is
auto-detected, deterministic across users, and reversible.

## Quick path

1. Run `./install.sh` once (or `~/.local/share/dual-session-setup/setup.sh`
   directly, no install needed).
2. Run the setup once **in every session user's account**:
   `~/.local/share/dual-session-setup/setup.sh`
3. Verify with `wpctl status` (look for "PCH dmix compartido (dual-session)")
   or play a test tone (Ctrl-C to stop):
   `aplay -D plug:dmix_pch -t raw -r 48000 -c 2 -f S16_LE /dev/zero`

## Usage

| Command | Effect |
|---|---|
| `setup.sh` | Full run for the current user (audio + UI integration if enabled). Creates the config file on first run. |
| `setup.sh --check` | Print the detected environment and file state. Writes nothing. |
| `setup.sh --dry-run` | Simulate the full run. Writes nothing, never restarts services. |
| `setup.sh --ui-only` | Only the caelestia-shell integration (requires `shell.json`). |
| `setup.sh --uninstall` | Restore backups and remove every file the product created. |
| `install.sh` | Copy the product to `~/.local/share/dual-session-setup/` and add a desktop entry. |
| `uninstall.sh` | Same as `setup.sh --uninstall`, plus removal of the installed copy and the desktop entry. |

`--uninstall` never deletes a file you modified: files whose content no longer
matches the product's recorded signature are kept, together with their backup.

## Configuration

On the first real run, `~/.config/dual-session-setup.conf` is created with the
detected values (600 permissions). It is never overwritten; edit it to
override detection, then re-run `setup.sh`.

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
| `ENABLE_UI` | `1` if `shell.json` exists | Enable the caelestia-shell integration (`0`/`1`). |
| `IPC_KEY_BASE` | derived | First shared dmix key; the dsnoop key is `IPC_KEY_BASE + 1`. |

### Detection order

1. Scan `/proc/asound/card*/codec#0` for on-board codec signatures (Realtek
   `ALC*`, `VT*`, `CX*`, `STAC*`, Sigmatel, Analog Devices).
2. Fallback: first card whose sysfs device class is `0403` (Audio) and whose
   short name is not HDMI / Display Audio.
3. Last resort: `card0`.

Override anything with the config file when detection picks the wrong card.

## How the shared keys work across users

Both users must open the same dmix to mix into the same PCM. The IPC key is
derived from the card's PCI slot with `cksum`, so **any account on the same
machine computes the same two keys** (`key1 = 10000000 + (cksum % 80000000)`,
`key2 = key1 + 1`). `ipc_key_add_uid false` and `ipc_perm 0666` make the
shared-memory mixer accessible to both users. Running the setup script once
per account is all that is needed; the results are identical.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "Dummy Output" sink after setup | The card is not being forced onto the dmix. Check `wpctl status` and that `~/.config/wireplumber/wireplumber.conf.d/51-pch-shared-dmix.conf` exists; restart the session. |
| `aplay: ... Device or resource busy` | Another process grabs the substream directly. Both sessions must use `dmix_pch`; never address the card with `hw:...` in custom configs. |
| Sound does not mix across users | Shared-memory key mismatch. The keys are derived from the PCI slot; if a config override sets `IPC_KEY_BASE`, it must be identical in every account. |
| Card moved to a different PCI slot | Detection is slot-based. Check `setup.sh --check`, fix `CARD_SLOT` (and `CARD_ALSA_NAME`) in the config, re-run the setup on every account. |
| `setup.sh --check` shows the wrong card | Override `CARD_SLOT` / `CARD_ALSA_NAME` / `ALSA_DEVICE` in the config file. |

## Uninstall

Run `setup.sh --uninstall` (or the desktop menu entry) in every account that
ran the setup. It restores the pre-install `~/.asoundrc` and `shell.json`
backups, removes the shared-audio files whose signatures match, and deletes
the config and manifest. `uninstall.sh` additionally removes the installed
copy and the desktop entry. Re-running is safe: a second run finds nothing.