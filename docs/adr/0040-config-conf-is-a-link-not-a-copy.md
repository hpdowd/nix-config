# 0040 — `config.conf` is a link, not a copy

**Status:** Accepted (2026-08-20)

Completes the governing principle of Phase 3 in `docs/PLAN-idiomatic-nix.md` —
*push variation to build time; let runtime only select*. Extends the link
ownership rule of [0034](0034-colour-follows-the-mode-artefacts-do-not.md) to
the one path it did not cover.

## Context

`apply_mode` in `dotfiles/mango/scripts/lib.sh` was the only runtime **write**
into `~/.config/mango`:

```sh
install -m 644 "$MANGO_DIR/$mode/$mode.conf" "$MANGO_DIR/config.conf"
```

so `config.conf` was a verbatim *duplicate* of whichever mode was active. That
made it the one file in the tree git must not track and no `xdg.configFile` may
claim, and it carried a scar: `install -m 644` rather than `cp`, because
`~/.config/mango` is a store path, so `<mode>.conf` is 0444 and `cp` gave the
new destination the source's mode — the first switch wrote a 0444 `config.conf`
and every switch after it died with `Permission denied`.

A copy is also **stale by construction**. Rebuild while a mode is active and
`<mode>.conf` re-points at a new store path; `config.conf` still holds the old
bytes until the next mode switch. Nothing says so.

Meanwhile [0034](0034-colour-follows-the-mode-artefacts-do-not.md) had already
established the right shape for exactly this problem — four link paths owned by
`apply_theme` and by nothing else, seeded at activation, asserted absent from
the generation. `config.conf` was the same problem solved a different way.

## Decision

**`apply_mode` re-points a symlink instead of copying:**

```sh
ln -sfn "$MANGO_DIR/$mode/$mode.conf" "$MANGO_DIR/config.conf"
```

mango is still launched with **no `-c`**, so `cli_config_path` stays empty and
every `./` in the tree still resolves against `$HOME/.config/mango/`
(`parse_config.h:3276`). That is what makes this cheap: all **20** `source=`
lines across `tiling.conf`, `noctalia.conf` and `universal/settings.conf` keep
working untouched, and nothing about session startup changes — so unlike the
alternative below, the change is validatable in-session rather than logout-only.

Three things come with it:

- **The target is checked before anything is written.** `ln -sfn` to a missing
  target *succeeds*, where the copy it replaced failed loudly. A dangling
  `config.conf` drops mango to built-in defaults with no keybinds. The guard
  runs before `state_write`, because recording a mode that was not applied is
  the one-way switch `lib.sh`'s header exists to foreclose.
- **Seeded at activation** (`seedModeConfig` in `modules/home/dotfiles.nix`),
  mirroring `seedModeTheme`, hard-coded to `tiling` to match
  `current_mode()`'s fallback. This *closes* the fresh-machine hole rather than
  preserving it: verified by probe, mango with no `config.conf` falls back to
  `/etc/mango/config.conf`, which does not exist on NixOS — the package ships
  its default under `$out/etc/`, which never lands at `/etc`.
- **`config.conf` joins the runtime-link list in `checks/static.sh`**, asserted
  absent from the generation alongside `apply_theme`'s four.

**`recursive = true` stays.** It was previously described as the last
writability exemption to remove. It is not only that: it is the mechanism that
lets twelve *generated* files live inside the hand-written mango tree. Removing
the writer is the win; removing the flag costs a twelve-file rehoming and buys
bookkeeping.

## Alternatives

**`load_config_file` over IPC, plus `mango -c` at login**, removing
`config.conf` entirely. This is the purest form of the principle and was
rejected on cost: relative sources resolve against `dirname(cli_config_path)`,
so all 20 `source=` lines would need rewriting; the state path would need a
fourth spelling inside a system module, crossing the boundary `lib.sh` exists to
guard; and it stays logout-only. The dispatch was traced through the source
(`bind_define.h:2284`, `ipc.h:410`) and **never fired** — sending it into a
running session re-points `cli_config_path` for the rest of that session.
Revisit only if `config.conf` must leave `~/.config/mango` for another reason.

## Consequences

- `readlink ~/.config/mango/config.conf` now *names the active mode*, which is
  a better answer than the old `diff`-against-two-files.
- A rebuild while a mode is active is picked up by the next reload, not the
  next mode switch — the link resolves through `<mode>.conf`, which
  home-manager re-points.
- `config.conf` is still gitignored and still must not be an `xdg.configFile`.
  Both directions are asserted: tracked-vs-gitignored, and absent from the
  generation.
- A revert to `install`/`cp` would *work*, and would silently reintroduce the
  staleness. So the link itself is asserted, not just its absence from the
  generation.
- The `install -m 644` scar is gone from the repo entirely. It briefly
  reappeared in `checks/static.sh`, which stages each mode's conf into a fake
  `HOME` and hit the identical 0444 inheritance — then went away again when
  that staging became a symlink to match this decision. What remains there is
  `cp -r --no-preserve=mode`, which is a different trap: the copied *directory*
  is 0555, so nothing can be created inside it at all.
