# Feature: hardware-mixer-volume

## Objective
Stop the shared-dmix setup from leaving the card's hardware playback mixer
muted or attenuated, which makes every session quiet no matter what the
desktop volume slider says.

## Problem
Forcing the card onto `plug:dmix_pch` requires `api.alsa.use-acp = false`.
ACP is also the layer that maps the desktop volume onto the card's hardware
mixer. With ACP off, PipeWire applies only *software* volume and leaves the
card's hardware playback controls (e.g. `Master`) at whatever ALSA restored.
On the test machine `/var/lib/alsa/asound.state` holds `Master=41` (-23 dB),
so audio is quiet after every boot, the desktop slider reports 100%, and
manual `alsamixer` fixes do not persist.

Evidence (verified): with the product config active, `Master` is **not**
touched by a full `pipewire`/`pipeplumber` restart (stayed at 41/64). Setting
`api.alsa.soft-mixer = false` on the node rule does **not** restore the
mapping either (tested). `/etc/alsa/state-daemon.conf` absent -> the
`alsa-restore.service` scheme re-applies the saved low value on every boot.

## Why
User reports chronic low volume that returns after every reboot on a machine
running this product (two sessions: KDE/`andrik` + Hyprland/`caelestia`).

## Scope (authorized)
- Pin the detected card's hardware playback mixer to unity at install and on
  every login via a `systemd --user` oneshot service (no root).
- Config key `MIXER_CONTROLS` (default `Master PCM Front`) to override the
  pinned controls.
- Track and remove the new artifacts with the existing manifest machinery.
- Document the behaviour in README + troubleshooting.
- Add a regression smoke test (`tests/smoke.sh`).

## Out of scope
- Changing the dmix / ACP architecture.
- Editing the global `/var/lib/alsa/asound.state` (needs root).
- Any push / PR / remote action.

## Constraints
- bash 4+ only; no new runtime deps.
- User-facing echo output in Spanish; code comments and README in English.
- `--check` / `--dry-run` must not mutate anything nor call `systemctl`.
- Conventional Commits, one work-unit commit per task.

## Tasks
- [ ] T1 feature doc + Engram mirror + branch `fix/hardware-mixer-volume`.
- [ ] T2 `lib/mixer.sh`: standalone pin script + systemd unit + install/remove.
- [ ] T3 `lib/common.sh`: paths, `MIXER_CONTROLS`, tracked files, config key.
- [ ] T4 `lib/audio.sh` + `setup.sh` + `uninstall.sh`: wiring.
- [ ] T5 `tests/smoke.sh`: fake-HOME regression harness.
- [ ] T6 `README.md`: behaviour, config key, troubleshooting row.
- [ ] T7 verification: `bash -n`, `--check`, `--dry-run`, smoke test.

## Acceptance criteria
- After a real run, the card's hardware playback controls are at unity.
- The pin is re-applied at every login (unit enabled) and removed on uninstall.
- `--check` / `--dry-run` mutate nothing and never call `systemctl`.
- On uninstall, a file is deleted only while its content matches the manifest.
- Every script passes `bash -n`; the smoke test passes.

## Applicable checks
- `bash -n` on every script.
- `./setup.sh --check` and `./setup.sh --dry-run` (no mutation, no restart).
- `tests/smoke.sh` (fake HOME, stubbed `systemctl` / `amixer`).

## Delivery
- Forecast: ~350 authored changed lines -> under the 400-line advisory, so no
  chain/PR split is triggered. Work-unit commits on `fix/hardware-mixer-volume`.

## Verification & progress
- T1 done — branch `fix/hardware-mixer-volume`; feature doc written.
- T2 done — `lib/mixer.sh`: generates the standalone pin script + systemd
  `--user` oneshot, installs/enables/applies it, and removes it safely.
- T3 done — `lib/common.sh`: `DEST`/`PIN_SCRIPT`/`MIXER_UNIT`/`MIXER_SERVICE`,
  `MIXER_CONTROLS` default + config key, both new files added to `TRACKED_FILES`.
- T4 done — `lib/audio.sh` calls `mixer_install`/`mixer_remove`; `setup.sh` and
  `uninstall.sh` source `lib/mixer.sh`; summary + uninstall output updated.
- T5 done — `tests/smoke.sh` (fake HOME, stubbed `systemctl`/`amixer`).
- T6 done — `README.md`: why-section, config key, troubleshooting rows, tree.
- T7 done — evidence:
  - `bash -n` clean on all 8 scripts.
  - `./setup.sh --check` -> exit 0, writes nothing.
  - `./setup.sh --dry-run` -> reports `[simulación] Escribir .../pin-mixer.sh`,
    `Mixer HW: script=ausente servicio=ausente` (no mutation, no systemctl).
  - fake-HOME real run -> `pin-mixer.sh` valid (`bash -n` ok, mode 700), unit
    correct; `amixer ... sset ... 100%` observed; enable/disable observed.
  - `bash tests/smoke.sh` -> `smoke: OK` (12 ok, 0 fallos).

### Route
- Inline, single writer thread. The change is one cohesive, fully-designed unit
  (a new lib module plus mechanical wiring); no research or design remained.

### Open
- Commit identity: git has no `user.name`/`user.email` configured here; the repo
  history is authored by `caelestia <caelestia@Andrik>`. Pending the user's call.
- Persisting `Master=100%` across reboots on the real machine still needs either
  `sudo alsactl store` or running this product's pin service in each account.
- CAUTION: do not run full `setup.sh` in only one account — it regenerates
  `~/.asoundrc` with a new derived `ipc_key` and breaks cross-user dmix sharing
  until every session user re-runs the setup.
