# Feature: github-publish (one-line install + GitHub release)

## Objective
Publish the dual-session-setup product to GitHub (public, account `andrikonbeat`)
so anyone can install and uninstall it with a one-line command, no clone needed.

## Problem
The product is local-only today. `install.sh`/`uninstall.sh` copy from the local
clone directory (`DIR`), so piping them via `curl | bash` breaks: the lib/ files
are not next to the running script, and the scripts do not know where to get them.

## Why
User request: make it available on GitHub for everyone, with the simplest
possible install/uninstall experience. This overrides the earlier
"no remote" out-of-scope note in `odd/tasks/dual-session-product.md`,
which the user explicitly revoked in this feature.

## Scope (authorized)
- Public repo `Dual-Session-Setup` on `andrikonbeat` (their authenticated gh
  session, keyring credential).
- Main branch carries the product; push `main` as the publish target.
- `install.sh`: detect piped/bootstrap mode; when the source copy is not next
  to the script, download the tarball (codeload, branch `main`) to a temp dir
  and install from there. Clone mode keeps current behavior.
- `uninstall.sh`: detect piped mode; source libs from the installed copy at
  `~/.local/share/dual-session-setup`; report "nothing to do" when not installed.
- README: quick-install + quick-uninstall one-liners at the top.
- Keep idempotency and safety guarantees (backups, never delete user-modified
  files, `--check`/`--dry-run` untouched).

## Out of scope
- Releases/tags/assets (plain branch tarball is enough for v1).
- Windows/macOS.
- Changing setup.sh behavior or the audio/ui logic.

## Constraints
- bash 4+; curl required at install time (documented in README).
- Spanish user-facing output; English code comments/docs.
- Conventional Commits, work-unit commits.

## Tasks
- [ ] T1 `install.sh` bootstrap mode: tarball download fallback when lib/ is absent.
- [ ] T2 `uninstall.sh` piped mode: libs from installed copy; not-installed no-op.
- [ ] T3 README: one-line install/uninstall at the top + curl prerequisite note.
- [ ] T4 Publish: merge to main, create GitHub repo, push, verify one-liner
      syntax with a temp-dir fake-HOME run.

## Approval & verification
- `bash -n` on install.sh/uninstall.sh.
- Fake-HOME piped-mode smoke test: run scripts with lib/ absent to prove the
  bootstrap path (network stub or real fetch) — T1/T2 must still produce a
  working installed copy and a clean uninstall.
- Clone-mode regression: existing install/remove cycle still passes.
- `git diff --stat` focused; README one-liner URLs tested once published.