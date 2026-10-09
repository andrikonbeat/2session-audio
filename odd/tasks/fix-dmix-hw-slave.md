# Feature: fix-dmix-hw-slave

## Objective
Restore audio on the affected machine and stop the product from shipping a
`~/.asoundrc` that kills PipeWire at startup.

## Problem
`lib/audio.sh` generated the shared dmix/dsnoop slaves as
`pcm "plughw:CARD=<name>,DEV=0"`. ALSA's dmix can only attach to an `hw` PCM, so
opening `plug:dmix_pch` failed with:

```
dmix plugin can be only connected to hw plugin
spa.alsa: 'plug:dmix_pch': playback open failed: Argumento inválido
```

PipeWire's static adapter could not be created (`can't create object from
factory adapter`), `pipewire.service` exited (status 234) and hit
`start-limit-hit`; `pipewire-pulse` and `wireplumber` failed by dependency.
Result: **no audio at all** for the account that ran the installer.

## Why
Regression reported by the user right after running the one-command install. The
bug had been in the product since T3; the old hand-written `~/.asoundrc` on this
machine used `hw:0,0` and masked it.

## Scope (authorized)
- Correct the dmix/dsnoop slave to `hw:CARD=<name>,DEV=<n>`.
- Add a regression assertion to `tests/smoke.sh`.
- Correct the stale scope guidance in `dual-session-product.md`.
- Restore audio on the affected machine.
- Ship the fix to `origin/main`.

## Out of scope
- Changing the overall dmix/adapter design.
- System-wide (sudo) install mode.

## Constraints
- No new runtime deps; same no-root model.
- User-facing output in Spanish, code/comments in English.

## Tasks
- [x] F1 Fix `lib/audio.sh` slave PCMs (`plughw:` -> `hw:`).
- [x] F2 Regression assertions in `tests/smoke.sh`.
- [x] F3 Correct the stale guidance in `dual-session-product.md`.
- [x] F4 Restore audio on this machine and sync the installed copy.
- [x] F5 Commit + push to `origin/main` (fast-forward `ce87f03..be361e5`; the
      remote one-liner now serves the fix).

## Acceptance criteria
- The generated `~/.asoundrc` uses `pcm "hw:CARD=…,DEV=…"` for both slaves.
- `pipewire`/`pipewire-pulse`/`wireplumber` start and stay active after install.
- The smoke suite fails if `plughw` ever returns.

## Verification
- F4: `/home/andrik/.asoundrc` corrected in place; `systemctl --user
  reset-failed pipewire pipewire-pulse wireplumber` then `restart`; all three
  `active`; `wpctl status` shows the dmix sink and the journal is error-free.
- F1-F3: `bash tests/smoke.sh` (see F5).
