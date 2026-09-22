# Feature: dual-session-product (portable installer)

## Objective
Convert the personal dual-session setup scripts into a portable, installable
product that works on any Linux machine with two graphical sessions: auto-detect
audio hardware (HDA card, PCI slot) and the other active session/user, derive
shared dmix keys deterministically (same value on every account), install and
uninstall cleanly with backups, and document usage.

## Problem
The current scripts only work on this machine:
- Hardware hardcoded: Realtek ALC887/892/1150/1220 codecs, PCI slot `pci-0000_00_1f.3`.
- Users hardcoded: audio setup must be run per-user but keys only match because
  they are constants; UI integration hardcodes target user `andrik` and
  rewrites the entire caelestia `shell.json` (destructive on shell changes).
- `Dual-Session-Setup.desktop` points to an absolute path; `andrik/` is a
  full duplicate copy (maintenance hazard).
- No git, no uninstaller, no README, no error handling, no dry-run.

## Why
User explicitly selected the "Portable, any machine" scope.

## Scope (authorized)
- Generalize hardware detection beyond the hardcoded codec list; fallback to
  the first non-HDMI HDA card; config file overrides.
- Deterministic per-card dmix/dsnoop IPC keys (identical on every user account).
- Use `plughw:CARD=<name>,DEV=0` instead of `hw:0,0` where supported.
- Generalized session-switch integration: target any other active graphical
  session on seat0; MERGE (never overwrite) `shell.json`; backup + restore.
- Installer to `~/.local/share/dual-session-setup/` + `~/.local/share/applications/`.
- Uninstaller restoring all backups and removing created files.
- README with usage, config reference, troubleshooting.
- `git init` local repository (no push/PR/remote by anyone in this feature).
- Remove `andrik/` duplicate and the old absolute-path `.desktop` from the
  repo (superseded by the product; user intent is productization).
- Config file `~/.config/dual-session-setup.conf` auto-created with detected
  values, documented overrides.

## Out of scope
- Non-PipeWire backends (PulseAudio etc.).
- Non-logind/non-systemd environments.
- Push, PR, release, or remote of any kind.
- Non-Linux platforms.

## Constraints
- bash 4+ only; no new runtime deps (python3 for JSON merge; jq optional).
- User-facing echo output in Spanish (existing project language); code comments
  and README in English.
- Safety: never overwrite a user config without a backup; `--check` and
  `--dry-run` modes must not mutate anything.
- Conventional Commits, work-unit commits per task.

## Tasks
- [ ] T1 Repo bootstrap: `git init`, baseline commit of existing files, feature
      document + Engram mirror.
- [x] T2 `lib/common.sh`: config loader (defaults + overrides), hardware
      detection (codec scan + non-HDMI fallback + slot), logging, backup/restore helpers.
- [x] T3 `lib/audio.sh`: generalized audio setup (deterministic dmix keys,
      `plughw:CARD=...`, WirePlumber + PipeWire confs from config, audio restart).
- [x] T4 `lib/ui.sh`: generalized session-switch merge for caelestia
      `shell.json` (backup, merge-only, restore hook); any other seat0 session as target.
- [x] T5 `setup.sh`: orchestrator — audio for current user, conditional UI,
      `--check`/`--dry-run`/`--uninstall`, summary with verification commands.
- [x] T6 `install.sh` + `uninstall.sh` + generated `.desktop` (location-independent).
- [x] T7 Remove `andrik/` duplicate and old `.desktop` from repo.
- [x] T8 `README.md` + final verification: `bash -n` on every script, dry-run smoke test.

## Acceptance criteria
- Runs on a machine with different codec/PCI slot without editing scripts
  (config override available and documented).
- Two users on the same machine generate identical shared config (keys match).
- Existing `shell.json` is backed up and merged, never rewritten; uninstall restores it.
- Install/remove cycle is idempotent; no files left behind.
- Every script passes `bash -n`; `--dry-run` and `--check` run clean and mutate nothing.
- All tasks close with a work-unit Conventional Commit.

## Applicable checks
- `bash -n` on every script (shellcheck unavailable: `command -v shellcheck` -> none).
- Smoke test: `./setup.sh --check` and `./setup.sh --dry-run` as this user
  (dry-run must not restart audio nor write files).
- Functional change is the refactor itself; no test framework (TDD off — no
  framework configured; ordinary functional checks apply).

## Verification & progress
- T1: done — repo created (`git init -b main`), baseline commit `01d7c58`,
  feature doc commit `dd5266f`. Engram mirror: PENDING (MCP server rejected
  save twice, no registered session) — resync when available.
- T2: done (`9542c3f`) — `lib/common.sh` added (+ `.gitignore` for `.atl/`
  runtime artifacts). Verified on this machine: ALC887-VD → card0 →
  `pci-0000_00_1f.3`, `CARD_ALSA_NAME=PCH` (padded column trimmed),
  `IPC_KEY_BASE=70279166` / `+1=70279167`, ENABLE_UI default 1 (shell.json
  present). `bash -n` passes.
- T3: done (`e5b4314`) — `lib/audio.sh`. Fake-HOME cycle test (stubbed
  restart): install → `.asoundrc` with `plughw:CARD=PCH,DEV=0` + derived keys,
  WP/PW confs, manifest with 4 signatures; re-run idempotent ("Sin cambios");
  remove restores pre-install `.asoundrc`, second remove silent; user-modified
  `.asoundrc` never deleted, backup kept.
- T4: done (`4f32145`) — `lib/ui.sh`. Fake-HOME merge test on a copy of the
  real `shell.json`: `session.icons.hibernate=switch_account`,
  `session.commands.hibernate` = generalized command (literal `$USER` at
  click time), launcher action appended only when absent (no duplicate),
  all other keys preserved (14 acciones / 7 quickToggles), JSON válido,
  re-run "Sin cambios", `ui_remove` restores backup.
- T5: done (`390d6d8`) — `setup.sh` (executable). Live verification on this
  machine: `./setup.sh --check` exit 0, `.asoundrc`/`shell.json` mtime+sha256
  unchanged, config not created; `./setup.sh --dry-run` exit 0, every step
  `[simulación]` incl. restart, no files/backups written, pch count stable.
- T6: done (`7acaa77`) — `install.sh` + `uninstall.sh` (both executable).
  Fake-HOME cycle: install → installed copy location-independent (own lib/,
  `--check` exit 0, UI correctly off without shell.json) → uninstall from the
  installed copy removes EVERYTHING (find: nothing left), second uninstall
  idempotent; `setup.sh --uninstall` delegation verified.
- T7: done (`d78a48b`) — legacy scripts + `andrik/` + old `.desktop` removed
  (904 deletions, matches forecast). Repo root now: setup.sh, install.sh,
  uninstall.sh, lib/, README (T8), odd/.
- T8: done (`b781449`) — `README.md`. Final suite PASS: (1) `bash -n` on all
  6 scripts; (2) `./setup.sh --check` exit 0, `.asoundrc`+`shell.json`
  sha256/mtime unchanged, no config created, pch count stable at 1 (pre-existing
  file), no backups; (3) `./setup.sh --dry-run` exit 0, same no-mutation
  checks, zero real systemctl restarts, 12 steps all `[simulación]`.
- DONE — all tasks closed with work-unit Conventional Commits.
- Remaining: none after T8.

## Native review (gentle-ai, RDD) — closed by operator disposition
- START: lineage `review-084d5f8adf897df2`, target `sha256:ce836496…a9ed`,
  base-diff vs `main` (17 paths, 1906 changed lines, tier high, budget 200);
  user consented (granted).
- Failure: the 4 reviewer Tasks (`review-risk`, `review-resilience`,
  `review-readability`, `review-reliability`) all failed with
  `OpenCode's free tier can only be used from within OpenCode`. Root cause:
  sub-agent model provider (inherited Zen gateway; no credentials configured
  via `opencode auth`). Environment/provider limitation, NOT a Gentle AI
  defect, NOT a candidate defect — no defect handoff.
- STATUS re-offered the same bound collect slot; per contract no blind retry
  into the same provider failure; one actionable decision surfaced to the user.
- Decision: user chose **Abandon review and deliver**.
- Abandon committed (`gentle-ai.review-reclaim-record/v1`,
  reason `operator_disposition`, actor `user-caelestia`, discarded_lens_results
  empty, findings_present false); authority quarantined under
  `.git/gentle-ai/review-transactions/quarantine/`.
- Post-abandon `gentle-ai review status --cwd .` → `entries: []`, lock
  released. Delivery is unmanaged under ordinary repository policy: the review
  neither approves nor blocks; the functional verification suite above stands
  (bash -n, --check, --dry-run, fake-HOME cycles).

## Delivery
- Forecast ~1900 authored lines (baseline ~904 to be deleted + ~1000 new,
  generated files excluded) → exceeds 400. Strategy: `ask-on-risk`.
- No remote configured → chain/PR strategy deferred; work-unit commits stay
  local. Running count recorded here as commits land.
- Running authored count vs baseline `01d7c58`: T2 `9542c3f` → +429;
  T5 `390d6d8` → +719; T6 `7acaa77` → +868; before T8 (T7 applied): +959/−904
  (16 files changed, 959 insertions, 904 deletions); final (all commits):
  see `git diff --stat 01d7c58` → 9 files/957 (new product, README, docs),
  no legacy files remain.
- Record per task: route (inline/delegated) + trigger evidence.