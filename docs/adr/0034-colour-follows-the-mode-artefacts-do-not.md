# 0034 — Colour follows the mode; artefacts do not

**Status:** Accepted (2026-08-19)

Completes [0032](0032-the-theme-file-owns-its-artefacts.md) (the theme file owns
its artefacts) by drawing the line that record implied but did not need: the two
halves it separated turn out to have *different lifetimes*, not just different
mechanisms. Extends [0030](0030-the-scheme-is-a-file-not-an-option.md) (the
scheme is a file, not an option) — `modes.nix` is a second file for the same
reason. Applies to [0022](0022-noctalia-mode-looks-like-noctalia.md)'s pinned
settings, which now take their scheme from the mode rather than the machine.

## Context

The question asked was whether desktop-mode switching should become
**build-time** — a rebuild per mode — so that `tiling` and `noctalia` could
theme entirely independently.

It should not, and the reason is worth writing down because the proposal is
reasonable and the counter-argument is not obvious: **a rebuild buys only the
half that was already free.**

[0032](0032-the-theme-file-owns-its-artefacts.md) split a scheme in two. The
palette reaches colour; a theme file separately *names* the artefacts the
palette cannot reach — GTK and Kvantum widget art, the icon set, cursor bitmaps,
the yazi flavor, the nvim plugin, the Zed theme, noctalia's own scheme. Those
are rendered SVG, compiled SCSS and plugin code. They are **built**.

Which means the artefact half already changes with one line in `scheme.nix` plus
a rebuild, and build-time modes would add nothing to it. What they would cost is
everything else: the runtime switch (`SUPER+CTRL+/` becomes a rebuild), `hud`
forced to pick a side, and `dotfiles.nix`, `programs.nix`, `theme.nix` and
`waybar.nix` all made mode-conditional. Four files gain a branch each, in a repo
whose signature bug is a branch nobody notices is dead.

Stated plainly, and this is the part that has to be said out loud rather than
discovered later: **"entirely differently per mode" is not reachable at all.**
Recolouring GTK at runtime while gruvbox's widget art stays put is the hybrid
[0032](0032-the-theme-file-owns-its-artefacts.md) rejected for nvim, one toolkit
over. What *is* reachable is everything the shell draws itself, and that is most
of what is on screen.

## Decision

**A second file, `modules/home/modes.nix`, naming the colour-only scheme each
desktop mode wears.** `scheme.nix` keeps its single string and now means the
*artefact* scheme.

```nix
{ tiling = "gruvbox"; hud = "gruvbox"; noctalia = "nord"; }
```

A file rather than an option, for [0030](0030-the-scheme-is-a-file-not-an-option.md)'s
reason applied one layer along: each value is interpolated into
`import ./themes/<name>.nix`, so a typo is a **file-not-found at eval**. An
option typed `str` would accept `"gruvbxo"` and leave the failure to whichever
consumer read it first — and that consumer would fall back to its own default
and look merely unstyled.

**The scope line: a consumer may follow the mode only if colour is the WHOLE of
its theme.** Terminals, menus, bar CSS, window-manager chrome — yes. Widget art,
icons, cursors, plugins, the built lock-background ramp — no, permanently.

**Two consumers follow it today, and both are build-time.**

- **mango's chrome.** `universal/colors-<mode>.conf` was already generated per
  mode, differing only in the border role
  ([0022](0022-noctalia-mode-looks-like-noctalia.md)). It now differs in scheme
  too, which is a one-line change to a file that already existed — the whole
  reason this is the first phase.
- **noctalia's own palette.** `colorSchemes.predefinedScheme` in
  `settings-pinned.json` moves from `scheme.nix` to `modes.nix`. noctalia runs
  in exactly **one** mode, so it needs no runtime swap — only the right name at
  build time. Left on `scheme.nix` it would contradict the mango chrome now
  drawn around it, and a shell in one scheme inside borders in another is the
  one result worse than either scheme alone: it looks deliberate.

**kitty, foot, rofi and ncspot follow it through a runtime symlink** — phase 2
for the first three, landed the same day; ncspot in phase 3a. All four run in
*every* mode and read one fixed path, so each reads through an indirection
`apply_theme()` re-points:

| Link (runtime, owned by `apply_theme`) | Target (generated, per mode) |
|---|---|
| `kitty/current-theme.conf` | `kitty/colors-<mode>.conf` |
| `foot/themes/noctalia` | `foot/colors-<mode>` |
| `rofi/colors.rasi` | `rofi/colors-<mode>.rasi` |
| `ncspot/config.toml` | `ncspot/colors-<mode>.toml` |

**Equibop follows it with no link at all** (phase 3a): it enables a theme by
*filename* out of its own `settings.json`, which the mode switch already
rewrote. `apply_theme` names `equibop/themes/<mode>.theme.css`.

**The generated halves are keyed by MODE, not by scheme.** The obvious spelling
is one sidecar per distinct scheme and `apply_theme <scheme>`, and it is wrong:
it makes a scheme *name* cross the Nix→shell boundary, which is a value both
sides must spell identically — the drift `lib.sh` was extracted to stop, and
what broke the mode switch one-way on 2026-07-31. Keyed by mode, the shell
already holds the only argument there is. `tiling` and `hud` sharing a scheme
costs one duplicate generated file that nothing reads by hand.

**The two odd link names are what make noctalia's own templates a later toggle
rather than a redesign.** `current-theme.conf` is exactly what noctalia's kitty
post-hook `ln -sf`s, and that hook refuses to touch an unwritable `kitty.conf`.
`themes/noctalia` is what its foot hook greps for before it `sed -i`s
`foot.ini` — and `foot.ini` is a read-only store symlink, so that `sed` is the
difference between a no-op and this repo silently ceasing to own the file. The
name holds gruvbox in tiling mode and that is correct.

**waybar and swaync stay on `scheme.nix`, so the divergence still has a ceiling
and the ceiling is asserted.** They do not run in noctalia mode and are
generated once, so `tiling` and `hud` must name the same scheme *and* it must be
`scheme.nix`'s. Only `noctalia` may differ. What it cannot reach remains the
artefact half — GTK and Qt widget art, icons, cursor, yazi, nvim, Zed — and that
is permanent, not pending.

**Every scheme in service is audited, not just the selected one.** `flake.nix`
passed `checks/static.sh` a single resolved palette; it now passes the artefact
scheme *and* every scheme a mode names, deduplicated. A legibility floor that
only ever measured `scheme.nix`'s would have reported a clean bill of health for
a mode nobody can read — the check passing by never looking, which is the exact
failure the floors exist to prevent. Each is still measured against **its own**
declared floors: the assertion is "this theme is as legible as it claims", and
Nord's comment colour is 1.69:1 and that is Nord
([0032](0032-the-theme-file-owns-its-artefacts.md)).

**A mode scheme does not need artefact packages.** The artefact check still runs
against `scheme.nix`'s theme only, deliberately — demanding a GTK theme and a
cursor set for a scheme that supplies neither would make a colour-only scheme
impossible to add.

## Consequences

- **`modes.nix` and `MODES` are cross-checked both ways.** A missing key is
  already an eval error, since `dotfiles.nix` interpolates it into an `import`.
  The direction eval **cannot** see is the other one: a key naming no mode is a
  colour scheme nothing can ever select, and it reads like a mode that exists.
  `checks/static.sh` asserts both, with a floor on each side.
- **The per-mode colour check reads `focuscolor`, not `bordercolor`.** The
  border role differs by mode *by design* — `surface` in tiling and hud,
  `overlay` in noctalia ([0022](0022-noctalia-mode-looks-like-noctalia.md)) — so
  it is the one line in the file that proves nothing about which scheme produced
  it. The accent is the same role in all three.
- **The generated header names its scheme.** `colors-<mode>.conf` opens with the
  theme file it came from and the mode that selected it. A generated file whose
  provenance is a sentence rather than a name is the one that gets edited by
  hand.
- **A colour was found spelled outside the theme files, and nothing could have
  caught it.** `inactive_tab_foreground = "#d5c4a1"` — gruvbox's `fg2`, which
  this palette has no role for — sat in `programs.nix` through
  gruvbox → Catppuccin → gruvbox. The drift ceiling greps for the hexes the
  *current* themes declare, so an orphan from a retired scheme matches nothing
  and reads as a pass. It is `subtext` now, and a new check asserts no
  six-digit hex literal appears in any `.nix` outside `modules/home/themes/`,
  floored on the number of files scanned since the pass state is zero matches.
- **`checks/static.sh`'s fourth argument changed shape**, from one palette to
  `{ artefact, modes, schemes }`. `pal` reads `$PAL_SCHEME`, which the floor
  audit re-points per scheme and restores afterwards. The scheme name is still
  read out of `scheme.nix` by hand and cross-checked against what Nix resolved —
  not to catch a typo, which eval already catches, but to catch the two drifting
  apart and every message below naming a scheme the machine is not wearing.
- **Three negative tests were run before this landed**, because a check that has
  never failed proves nothing: `tiling` diverging from `hud`, both diverging from
  the artefact scheme, and a key naming no mode. All three failed with the right
  message and the right reason.
- **noctalia mode is now visibly a different scheme from the rest of the
  machine**, which is the point and also the first time this repo has shipped an
  intentional inconsistency. It is bounded: the shell and the chrome agree with
  each other, the terminals agree with the artefact scheme, and nothing is left
  guessing which it should have been.

## The three consumers fail in three different ways, and one was a surprise

Measured on 2026-08-19 against the built config, not read off documentation.
This is the finding that decided how `apply_theme` and the bootstrap are shaped:

| | Missing colour file | So |
|---|---|---|
| **rofi** | `@import` skipped, nothing logged | falls back to its built-in Solarized; looks like a theme |
| **kitty** | `include` skipped, nothing logged | **every colour falls to a built-in default — `color0` and `background` both `#000000`** |
| **foot** | `failed to open` on stderr, **exit 230** | foot does not start at all |

foot being loud is the reverse of what the design note assumed, and it changes
what the bootstrap is for. It is not a cosmetic safety net: without the link,
**there is no terminal.** Two things follow, and both are in place:

- **`apply_theme` verifies every target before linking any of them**, and
  refuses as a set. A half-applied theme is not reachable, and a mode switch
  cannot leave foot unable to start.
- **`mode-theme.nix` seeds the links at activation** if they are missing
  *or dangling* (`[ -e ]` follows symlinks, so dropping a mode from `modes.nix`
  is repaired too). Without it, a fresh machine has no link until the first mode
  switch — and no foot. It seeds to `tiling`, which is also `current_mode()`'s
  fallback in `lib.sh`; one default, two readers, agreed by construction. It
  deliberately does **not** read `current-mode`: a second reader of the state
  directory in a language that cannot share `lib.sh` is exactly the drift
  `lib.sh` exists to prevent, and being one mode switch stale is the cheaper
  cost.

**foot cannot be told to reload, either.** 1.27's `SIGUSR1`/`SIGUSR2` switch
between the sections *already loaded*; there is no config re-read, so a swap
reaches **new windows only**. Undocumented, that reads as the swap being broken,
so `apply_theme` says it in the notification every time rather than relying on
this paragraph. kitty's `SIGUSR1` does work and is sent. rofi re-reads on every
launch and needs nothing.

## Phasing

1. **Done.** `modes.nix`; mango chrome and noctalia's scheme follow it; the
   checks and the multi-scheme audit.
2. **Done.** The runtime swap for kitty, foot and rofi: `mode-theme.nix`
   generates the per-mode halves, `apply_theme()` in `lib.sh` re-points the
   links, `checks/static.sh` asserts each sidecar carries its mode's accent in
   that consumer's own spelling, that each config still contains its include,
   and that none of the three link paths is also an `xdg.configFile`.
3a. **Done.** Equibop and ncspot on the same mechanism, which turned out to be
   two different mechanisms:

   - **Equibop needed no link.** It enables a theme by *filename* out of its own
     `settings.json`, which the mode switch already rewrote — the indirection
     the other four had to be given, it already had. So the generated file is
     `equibop/themes/<mode>.theme.css` and `apply_theme` writes the name. It is
     generated in `dotfiles.nix` rather than `mode-theme.nix`, with the `scale`
     and `channels` helpers that have other callers there; the rule is that a
     generated file lives with its consumer's other generated config, which is
     where mango's `colors-<mode>.conf` already was.
   - **ncspot's whole config IS its theme**, so the link is `config.toml`
     itself. That is affordable only because the home-manager module wraps its
     `xdg.configFile` in `mkIf (cfg.settings != { })` — `settings = { }`
     installs the package and claims no path, so tier 1 keeps the half that
     matters and gives up only the typing on twenty strings. One value there
     re-claims the path and breaks activation; the check asserts it stays out of
     the generation, and `gotchas.md` records why the empty set is load-bearing.
   - **The accent needle could not see the failure that actually matters here.**
     ncspot is drawn entirely from the `muted` set, and `p.accent` written where
     `m.accent` was meant is a colour from the *right scheme and the wrong half*
     — the file still contains the muted accent somewhere, so every existing
     assertion passed. Measured, not theorised. The check now asserts every hex
     in ncspot's config is a value from that scheme's `muted` set, which is only
     stateable because ncspot is the one consumer drawn from a single half.
   - **ncspot cannot reload either**, and worse than foot: it reads
     `config.toml` once at startup, so a running one keeps its colours until
     restarted. The notification names whichever of foot and ncspot is actually
     running, so the message stays true rather than listing caveats nobody has
     open.

   Three negative tests before it landed — a renamed Equibop suffix, a
   `programs.ncspot.settings` value re-claiming `config.toml`, and ncspot
   generated from the canonical ramp instead of `muted`. All three failed
   correctly.

3b. **Not done, and gated on a decision.** noctalia's auto-theming templates,
   restricted to the hookless or guard-satisfied set — never `mango` or `yazi`,
   whose hooks `cp --remove-destination` and `sed -i` over store symlinks and
   quietly un-manage the path. Two things to settle first: noctalia's foot
   template writes the same `themes/noctalia` path this design links (the mode
   switch is the last writer, so it wins, but that is one path with two writers
   and should be a decision rather than a race), and wallpaper-derived colour is
   **ungated by construction** — the contrast floors, the per-consumer accent
   spellings and the drift ceiling all go blind for anything a template
   writes.
