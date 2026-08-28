# 0003 — Runtime state and user data live outside the config tree

**Status:** Accepted (2026-07-30)

## Context

`~/.config/mango/state/` held `current-mode`, `waybar-layout`, `night-temp`,
`last-vpn` and `pia-auth` (PIA credentials, mode 600). `~/.config/mango/wallpaper/`
held a 4.6 MB PNG.

This looks like untidiness. It is not: the state is what keeps the directory writable.
**State written into a config directory is precisely what forces that directory
to stay writable**, and therefore out of the Nix store. Two files nobody thinks
about were the reason an entire directory could not be made reproducible.

It also put credentials inside a git repo, relying on a `.gitignore` line to
keep them out of history.

## Decision

- Runtime state → `${XDG_STATE_HOME:-$HOME/.local/state}/mango/`
- User data (the wallpaper) → `${XDG_DATA_HOME:-$HOME/.local/share}/mango/`

Every script resolves the directory through those variables, so there is one
place to change it. The old `mango/state/` path stays in `.gitignore` so a stray
script cannot quietly recreate it.

## Consequences

- Credentials are no longer inside the repo at all.
- Config directories become candidates for the store. `mango` remains
  out-of-store for a different reason — the generated `config.conf`, see
  [0002](0002-out-of-store-dotfiles.md) — but state is no longer that reason.
- A fresh clone has no wallpaper and no saved mode. `wallpaper-restore.sh`
  exits 0 when the file is absent, so this is not an error.
- Anything new that persists across runs goes in `~/.local/state`, not next to
  the config that reads it. A gitignore rule for a file the repo's own scripts
  write is this decision being violated.
