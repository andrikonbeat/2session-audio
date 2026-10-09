# Feature: user-friendly-ux

## Objective
Turn the product into a one-command, no-jargon experience for non-technical
users: a single command installs **and** configures the current account; the
only remaining step is to run the same command in the other session's account.

## Problem
Today the user must (a) run `install.sh` and then (b) separately run
`setup.sh` per account, and the output talks about *dmix*, *IPC key*, *PCI
slot* and *ACP*. A non-technical user does not know what to run next, whether
they need sudo, or how to check it worked.

## Scope (authorized)
- `install.sh` installs and then configures the current account automatically.
- Friendly, non-technical Spanish messages on the golden path.
- A single, clear "what to do next" instruction (run the same command in the
  other session account).
- `README.md` rewritten for non-technical users; technical detail kept lower.
- Extend the smoke test to cover the `install.sh` auto-setup.
- Keep every existing flag and the advanced `--check` / `--dry-run` paths.

## Out of scope
- Auto-configuring other OS users (needs sudo; left as clear instructions).
- Changing the dmix / ACP architecture, config keys, or the mixer pin.

## Constraints
- **No interactive prompts**: the installer may run piped (`curl | bash`), so
  stdin is the script itself; never `read` from it.
- Idempotent, safe, reversible; the golden path never uses sudo.
- User-facing text in Spanish; code comments in English.
- Conventional Commits; one work-unit commit per task.

## Tasks
- [ ] U1 feature doc + Engram mirror (mirror blocked: MCP project ambiguity).
- [ ] U2 `install.sh`: auto-setup, friendly flow, flags, desktop entry.
- [ ] U3 `setup.sh` + `lib/common.sh`: friendly header / next-steps hint.
- [ ] U4 `README.md`: non-technical rewrite.
- [ ] U5 `tests/smoke.sh`: cover `install.sh` auto-setup.
- [ ] U6 verify + commit + push.

## Acceptance criteria
- Running `install.sh` ends with the current account fully configured (no
  second command required).
- The golden-path output contains no unexplained jargon and always states the
  next step and how to uninstall.
- `--help`, `--check`, `--dry-run`, `--no-setup`, `--uninstall` still work.
- `bash -n` clean on every script; the smoke test passes.

## Applicable checks
- `bash -n` on every script.
- `./install.sh --help` / `./install.sh --check` / `./install.sh --dry-run`.
- `bash tests/smoke.sh` (fake HOME, stubbed `systemctl` / `amixer`).

## Delivery
- Work-unit commits on `fix/hardware-mixer-volume` (continues this branch).
- Push to `origin/main` at the end (user-authorized).

## Verification & progress
- U1 done — feature doc written.
- U2 done — `install.sh`: one command = copy + configure; flags
  `--check/--dry-run/--no-setup/--uninstall/--help`; friendly banner; updated
  desktop entry.
- U3 done — `setup.sh` friendly header + next-steps summary;
  `lib/common.sh` `RAW_*` constants + `other_session_users()` helper.
- U4 done — `README.md` restructured: non-technical quickstart / FAQ /
  uninstall on top; technical detail kept below.
- U5 done — `tests/smoke.sh`: 5 new assertions for `install.sh` (17 total).
- U6 done — evidence:
  - `bash -n` clean on all 8 scripts.
  - `install.sh --help` and `--check` behave and mutate nothing.
  - fake-HOME `install.sh` -> copies the program, configures the account
    (pin script + unit), and adds the menu entry.
  - `bash tests/smoke.sh` -> `smoke: OK` (17 ok, 0 fallos).
  - Pushed to `origin/main` (fast-forward `f495b5f..08902c4`); the remote
    one-liner now serves this version.
