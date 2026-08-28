# 0028 — One palette reaches every config it can; six theme packages it cannot

**Status:** Accepted (2026-08-17)

Extends [0009](0009-generated-config-over-linked-files.md) (generate config
where a module exists) and follows [0027](0027-one-editor-nvim.md), which
removed the first of the two files 0009 had exempted.

## Context

`modules/home/palette.nix` was created on 2026-08-14 to stop the Gruvbox
palette existing in three places at once. It succeeded for the six consumers it
reached — kitty, foot, imv, swaylock, waybar, rofi — and an audit on 2026-08-17
found **twelve more copies it did not**, holding the same scheme in five
different spellings:

| Spelling | Where |
|---|---|
| `0xrrggbbaa` | mango's four mode configs and `universal/settings.conf` |
| `rgb(215, 153, 33)` | fsel's `config.toml`, swaync's `style.css` |
| `#rrggbb` | ncspot's theme in `programs.nix`, the lock-background ramp |
| a plugin name | nvim's `gruvbox.nvim` |
| a package name | the GTK theme, the icon theme, Kvantum, the cursor, noctalia's `predefinedScheme` |

The decimal spelling is the part worth recording. A repo-wide grep for `d79921`
— the accent, and the value most likely to be edited — found **neither** fsel
nor swaync, because both write it as `rgb(215, 153, 33)`. Two copies of the one
colour this palette exists to keep single were invisible to the obvious search.

## Decision

**Generate every colour that can be generated; name the rest as packages.**

Converted, all from `palette.nix`:

| Consumer | Mechanism |
|---|---|
| mango | generated `universal/colors-<mode>.conf`, pulled in by mango's own `source=` include. Three files because `bordercolor` differs by mode (0022) |
| nvim | generated `lua/config/palette.lua`, fed to `gruvbox.nvim`'s `palette_overrides` hook |
| swaync | the `:root` block generated and concatenated onto a hand-written body fragment |
| fsel | whole file generated; `dotfiles/fsel/` is gone |
| ncspot | its muted variants moved *into* `palette.nix` as a named `muted` set |
| lock-backgrounds | the ramp centred on `bg0`, with the build check's bounds computed from the same value |

**Three mechanisms, chosen per consumer rather than uniformly**, because the
failure modes differ:

- **A generated sibling inside a recursive tree** (mango, as waybar already
  did). Available only where `recursive = true`, and safe only because the
  generated paths do not exist under `dotfiles/` — a generated file at a linked
  path is an activation failure, not a merge.
- **A store-side merge** (nvim). It is linked as one directory symlink, so
  there is no sibling to add; a `runCommand` copies the tree and drops the
  generated file in. Chosen over flipping it to `recursive = true`, whose
  failure mode here is destroying the checkout ([0002](0002-out-of-store-dotfiles.md)).
- **Build-time concatenation** (swaync). Not the `@import` split that waybar and
  rofi use: swaync's CSS engine is not GTK's and `@import` is unverified in it,
  and a stylesheet whose colours fail to resolve renders as "swaync ignored the
  theme" — indistinguishable from a theme someone chose. Concatenating removes
  the runtime resolution entirely.

**Not converted, and the reason is structural rather than a judgment call.**
These are not hex this repo owns:

| | What it actually is |
|---|---|
| GTK theme | `pkgs.gruvbox-gtk-theme` runs upstream's `install.sh -n Gruvbox -c dark -t yellow`; the palette is in their SCSS |
| GTK4 | `gtk4.theme = config.gtk.theme` — follows the above |
| icon theme | Papirus, with the folder colour set by an overlay `override { color = "yellow"; }` chosen to match the accent |
| cursor | rendered bitmaps |
| Kvantum | largely a rendered SVG of widget art; the 9 hex in `.kvconfig` are a fraction of it |
| noctalia | `predefinedScheme = "Gruvbox"`, a name its shell resolves internally |
| yazi flavor | 783 hex of third-party syntax theme — 0009's "a colour scheme is data" argument, at scale |

The icon override is the one of these that looks like palette data and is not:
`color = "yellow"` selects a pre-rendered folder set, not a hex value.

For these, "change the scheme" means picking a different upstream artefact.
That is mostly a `theme.nix` edit, and `palette.nix` cannot reach it.
`docs/THEME-MIGRATION.md` is the runbook.

## Consequences

- **The conversion is a provable no-op.** Every generated file was diffed
  against the file it replaced: the mango configs, fsel's TOML, ncspot's theme,
  swaync's stylesheet and the lock ramp's `--stops` are byte-identical, and the
  20 nvim overrides equal `gruvbox.nvim`'s upstream defaults exactly. Nothing
  about the machine's appearance changed, which is the point — this is a change
  to where the values live, and any visible difference would have been a bug.
- **The hand-written configs now hold no hex, and a check keeps it that way.**
  `checks/static.sh` gained 11 assertions: each generated file exists, is
  non-empty and contains the accent *in that consumer's own spelling*; each
  mango mode config actually `source=`s its colours; and a **ceiling** — no
  palette hex anywhere in `dotfiles/` outside the exempt theme data. The
  existing checks were floors (a name defined must be used). This is the first
  one that fails on something *appearing*, because that is the direction drift
  travels.
- **The check reads the accent from a generated file, not from itself.** A
  check carrying its own copy of the value under test passes forever and proves
  nothing — the same class of mistake as the palette it guards.
- **mango's colours now need a rebuild, not a reload.** They are a store path,
  like everything else under `dotfiles/mango/`. `mango-reload` alone re-reads
  the last rebuild's copy, which looks exactly like the change having had no
  effect — the trap `CLAUDE.md` already names for this tree, now with one more
  way in.
- **`dotfiles/swaync/style.css` is now `style-body.css`, a fragment.** It is not
  a usable stylesheet alone. Renamed so that is obvious from the file listing
  rather than only from a comment.
- **nvim's coverage is partial by construction.** 20 of `gruvbox.nvim`'s 54
  palette keys are overridden; the `*_hard`/`*_soft` variants, `faded_*`, the
  orange pair and the diff colours keep upstream's values, because
  `palette.nix` does not name them. Fine on gruvbox, a visible hybrid on any
  other scheme — the point at which the plugin should be swapped rather than
  overridden.
- **A muted variant now lives in `palette.nix` rather than at its consumer.**
  ncspot's desaturated set is not derivable from the main palette by any
  formula (`ebdbb2` → `c9b890` is not a uniform scale), so it is named there as
  its own values. Keeping it next to its one consumer is how the palette came
  to exist in three places in the first place: it looks local right up until the
  scheme changes and that set is still gruvbox.
