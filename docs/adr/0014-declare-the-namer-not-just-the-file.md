# 0014 — Declaring a file is not declaring the config; declare what names it

**Status:** Accepted (2026-08-09)

Extends [0009](0009-generated-config-over-linked-files.md) (generate config
where a module exists) and [0011](0011-shell-is-gated-too.md) (static
assertions run inside the build).

## Context

Phase 4's sweep looked for files that nothing selects. It found the opposite
problem, three times: files that *are* selected, correctly, by something that
was itself in no repo.

| Declared | Reached only via | On a fresh clone |
|---|---|---|
| `mango/elephant/menus/connectivity/connectivity.lua` | `~/.config/elephant/menus.toml`, hand-written | elephant loads no menu — the Connectivity entry does not exist |
| `mango/fsel/config.toml` | `~/.config/fsel`, a hand-made symlink into the mango tree | fsel runs with stock colours |
| elephant's bitwarden provider | `~/.config/elephant/bitwarden.toml`, hand-written | provider loads with upstream defaults |

Each looked converted. The file was tracked, it was in the store, it was linked
into `~/.config` — and it still did nothing on any machine but this one,
because the program reads a *different* directory and only a local, undeclared
file bridged the two.

This is the migration's failure shape one level up. `@home` carried the bridges
across, so everything worked here and the gap was invisible from inside the
repo. `elephant listproviders` naming `menus:connectivity` was the only way to
tell the difference between "declared and working" and "declared and inert".

## Decision

**A config is declared only when the thing that *names* it is declared too.**
Tracking the file it points at is half the job.

- `elephant/menus.toml` is **generated** rather than linked, because it carries
  an absolute path that must come from `config.xdg.configHome` — a `.source`
  entry would freeze `/home/henry` into the repo.
- `elephant/bitwarden.toml` is vendored as a file entry, leaving
  `~/.config/elephant/` writable for elephant's own caches.
- `fsel` **moved out of the mango tree** to `dotfiles/fsel/` and is declared at
  `~/.config/fsel`, the path fsel actually reads. The hand-made symlink is
  retired; `unlinkStaleConfigDirs` removes it on the next activation, which is
  what that activation script has always been for.

### Reachability is checked both ways, per selector

`checks/static.sh` enumerates each selector's values **from its writers** and
asserts the correspondence in both directions:

- every mode in `desktop-mode.sh`'s `MODES` has a `<mode>.conf`, a
  `modes/<mode>.sh` and a `walker/configs/<mode>.toml` — and no walker config
  names a mode that does not exist;
- every `theme =` named in a walker config has a `walker/themes/<name>/` — and
  no theme directory exists that no config names;
- elephant's menu path is declared, and there is at least one `.lua` behind it.

**One direction alone misses half the class.** A missing file is a runtime
fallback that mostly looks fine; a surplus file is dead weight that still looks
maintained. `walker/themes/mango/` was the second kind — 765 lines, documented
in two places as the default, reachable from nothing.

A first attempt matched filenames against a concatenation of every other
tracked file. It flagged both live walker themes, because the strings that name
them live in the very directory the scan excluded to avoid self-matches — and
loosening it would have made `tiling` match `current_mode()`'s fallback and
pass on nothing. Generic string matching cannot express this; enumerating the
selector can.

## Consequences

- **A new mode is now three assertions, not a hope.** Adding one without its
  walker config fails the build instead of falling back at runtime.
- **`dotfiles/mango/` no longer holds config for non-mango programs.** `fsel`
  moved out; `elephant/menus/` stays, because elephant is pointed at it
  deliberately and the menus call mango's own scripts.
- **The check is only as good as its enumeration.** It reads `MODES` out of
  `desktop-mode.sh` with `sed`; if that line's shape changes the scan finds
  nothing and **fails**, by the floor rule from
  [0011](0011-shell-is-gated-too.md) — it does not pass quietly.
- **Verify by output stays the real test.** `elephant listproviders` naming
  `menus:connectivity` is the evidence that the wiring works; the build check
  only proves it is declared.
