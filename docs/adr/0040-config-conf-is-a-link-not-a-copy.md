# 0040 — `config.conf` is a link, not a copy

**Status:** Accepted (2026-08-20)

Completes Phase 3 of `docs/PLAN-idiomatic-nix.md` — *push variation to build
time; let runtime only select*. Extends the link ownership rule of
[0034](0034-colour-follows-the-mode-artefacts-do-not.md) to the one path it did
not cover.

## Context

`apply_mode` in `dotfiles/mango/scripts/lib.sh` held the only runtime **write**
into `~/.config/mango`:

```sh
install -m 644 "$MANGO_DIR/$mode/$mode.conf" "$MANGO_DIR/config.conf"
```

so `config.conf` was a duplicate of whichever mode was active. That made it the
one file in the tree git must not track and no `xdg.configFile` may claim, and
it carried a scar: `install -m 644` rather than `cp`, because `~/.config/mango`
is a store path, so `<mode>.conf` is 0444 and `cp` gave the destination the
source's mode. The first switch wrote a 0444 `config.conf` and every switch
after it died with `Permission denied`.

A copy also goes stale. Rebuild while a mode is active and `<mode>.conf`
re-points at a new store path, while `config.conf` keeps the old bytes until the
next mode switch. Nothing reports this.

[0034](0034-colour-follows-the-mode-artefacts-do-not.md) had already solved the
same problem a better way: four link paths owned by `apply_theme` and nothing
else, seeded at activation, asserted absent from the generation.

## Decision

**`apply_mode` re-points a symlink instead of copying:**

```sh
ln -sfn "$MANGO_DIR/$mode/$mode.conf" "$MANGO_DIR/config.conf"
```

mango is still launched with **no `-c`**, so `cli_config_path` stays empty and
every `./` in the tree still resolves against `$HOME/.config/mango/`
(`parse_config.h:3276`). That keeps the change cheap: all **20** `source=` lines
across `tiling.conf`, `noctalia.conf` and `universal/settings.conf` work
untouched, and session startup does not change, so the result could be checked
in-session instead of after a logout.

Three things come with it:

- **The target is checked before anything is written.** `ln -sfn` to a missing
  target succeeds, where the copy it replaced failed loudly, and a dangling
  `config.conf` drops mango to built-in defaults with no keybinds. The check
  runs before `state_write`, so a mode that was not applied does not get
  recorded as active.
- **Seeded at activation** by `seedModeConfig` in `modules/home/dotfiles.nix`,
  mirroring `seedModeTheme`, hard-coded to `tiling` to match `current_mode()`'s
  fallback. This closes the fresh-machine hole rather than keeping it: verified
  by probe, mango with no `config.conf` falls back to `/etc/mango/config.conf`,
  which does not exist on NixOS — the package ships its default under
  `$out/etc/`, which never lands at `/etc`.
- **`config.conf` joins the runtime-link list in `checks/static.sh`**, asserted
  absent from the generation alongside `apply_theme`'s four.

**`recursive = true` stays.** It had been described as the last writability
exemption to remove. It is also what lets twelve *generated* files live inside
the hand-written mango tree. Removing the writer was the win; removing the flag
would cost a twelve-file rehoming and buy bookkeeping.

## Alternatives

**`load_config_file` over IPC plus `mango -c` at login**, removing `config.conf`
altogether. Rejected on cost: relative sources resolve against
`dirname(cli_config_path)`, so all 20 `source=` lines would need rewriting; the
state path would need a fourth spelling inside a system module, crossing the
boundary `lib.sh` exists to guard; and it stays logout-only. The dispatch was
traced through the source (`bind_define.h:2284`, `ipc.h:410`) and **never
fired** — sending it into a running session re-points `cli_config_path` for the
rest of that session. Revisit only if `config.conf` has to leave
`~/.config/mango` for some other reason.

## Consequences

- `readlink ~/.config/mango/config.conf` names the active mode, which is easier
  than diffing it against two files.
- A rebuild during an active mode is picked up by the next reload rather than
  the next mode switch, because the link resolves through `<mode>.conf`, which
  home-manager re-points.
- `config.conf` is still gitignored and still must not be an `xdg.configFile`.
  Both are asserted: tracked-vs-gitignored, and absent from the generation.
- Reverting to `install`/`cp` would work, and would bring the staleness back
  without any sign of it. So the `ln -sfn` itself is asserted, not just the
  absence from the generation.
- Migration is lazy. `[ -e ]` follows symlinks and finds an existing regular
  file, so an already-configured machine keeps its copy until the next mode
  switch. Harmless, but `readlink` returns nothing until then.
- The `install -m 644` scar briefly reappeared in `checks/static.sh`, which
  stages each mode's conf into a fake `HOME` and hit the same 0444 inheritance.
  It went away again when that staging became a symlink to match this decision.
  What remains there is `cp -r --no-preserve=mode`, for a different problem: the
  copied *directory* is 0555, so nothing can be created inside it.
