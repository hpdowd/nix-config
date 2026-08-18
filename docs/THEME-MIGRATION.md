# Migrating the theme

How to change what this machine looks like, given the arrangement `docs/adr/0028`
put in place. Written as a runbook because the work splits into two halves that
fail in completely different ways, and the second half is the one people forget.

Companion reading: `docs/SYSTEM.md` §6 (where config lives),
`docs/gotchas.md` → Theming (what has already bitten us), `docs/adr/0028` (why
it is arranged this way).

---

## 0. Decide which kind of change this is

The two cases need different amounts of work, and conflating them is how a
migration ends up half-done and looking deliberate.

| | **Recolour** | **New scheme** |
|---|---|---|
| Example | gruvbox medium → gruvbox hard; a different accent | gruvbox → nord, catppuccin, everforest |
| `palette.nix` | edit values | edit values |
| The six theme packages | usually unchanged | **all six must be replaced** |
| nvim | keep the plugin, overrides carry the change | **swap the plugin** — see §3 |
| ncspot's `muted` set | re-derive by eye | re-derive by eye |
| Realistic effort | one file, one rebuild | a day, spread across six upstreams |

If you are doing a **recolour**, §1 and §4–6 are the whole job. Everything in §2
and §3 is for a **new scheme**.

---

## 1. The palette — one file, twelve consumers

`modules/home/palette.nix`. Editing it recolours **kitty, foot, imv, swaylock,
waybar, rofi, mango, nvim, swaync, fsel, ncspot and the lock-screen background
ramp** — no other file needs touching for any of them.

### Anatomy

It is a `rec` attrset in four blocks. `rec` matters: the semantic roles are
defined in terms of the canonical names, so a **missing key is an eval error**,
not a silently-default colour.

| Block | Keys | Who reads it |
|---|---|---|
| Canonical | `bg0`–`bg3`, `fg0`/`fg1`/`fg4`, the 16 ANSI names (`red`…`brWhite`) | the terminals want the full 16; everything else builds from these |
| Semantic roles | `base`, `surface`, `overlay`, `text`, `subtext`, `accent`, `okColor`, `warnColor`, `errColor`, `infoColor` | the bar, the menus, the compositor borders, swaync |
| Terminal aliases | `bg`, `fg`, `selBg` | kitty and foot, which named these first |
| `muted` | `bg`, `fg`, `dim`, `accent`, `ok`, `err`, `surface`, `overlay` | ncspot only |

**Values are bare hex, no leading `#`.** Every consumer spells it differently —
kitty `#rrggbb`, foot bare, GTK CSS `#`, mango `0xrrggbbaa`, fsel and swaync
decimal `rgb(r, g, b)` — so the shared form is the one they all build from.

### Two constraints that are not obvious

**`bg0` must stay neutral (R = G = B), or the build fails.** The lock-screen
background pool is a grayscale ramp centred on `bg0`, and `pkgs/default.nix`
asserts every generated PNG is untinted. A tinted `bg0` fails
`nix flake check` with `non-neutral tones — the ramp is tinted`. This is
deliberate: a tinted lock background is a legitimate thing to want, but it is a
decision, and this is the one surface that would otherwise absorb it silently.
To take it: change the `tinted` check in `pkgs/default.nix` in the same commit,
and say why.

**The `muted` set has no formula.** It is ncspot's deliberately desaturated
variant — `ebdbb2` → `c9b890` is not a uniform scale, and no darkening function
reproduces it. Re-pick these eight by eye against the new scheme. They live in
`palette.nix` rather than next to ncspot precisely so that this step is visible
rather than discovered later.

---

## 2. The six theme packages — one at a time

These are **not hex this repo owns**. Each is an upstream artefact — compiled
SCSS, rendered SVG widget art, cursor bitmaps, or a name another program
resolves internally. `palette.nix` cannot reach any of them, and there is no
version of this repo in which it could.

| # | What | Where | How to change |
|---|---|---|---|
| 1 | **GTK theme** | `modules/home/theme.nix` `gtk.theme` → `pkgs.gruvbox-gtk-theme`, vendored in `pkgs/default.nix` | Point at a different theme package. Ours builds upstream's `install.sh -n Gruvbox -c dark -t yellow`; a different family means a different derivation, not different flags |
| 2 | **GTK4** | `theme.nix` `gtk4.theme = config.gtk.theme` | Follows #1 automatically. Do not set it to `null` unless you intend GTK4/libadwaita apps to drop to Adwaita |
| 3 | **Icon theme** | `theme.nix` `gtk.iconTheme` (`Papirus-Dark`), recoloured by the `papirus-icon-theme.override { color = "yellow"; }` in `pkgs/default.nix` | The folder colour is chosen to match the accent. Change the override's `color` when the accent moves |
| 4 | **Cursor** | `theme.nix` `home.pointerCursor` → `Capitaine Cursors (Gruvbox)` | Rendered bitmaps. Pick a different cursor package |
| 5 | **Kvantum (Qt)** | `dotfiles/Kvantum/kvantum.kvconfig` (`theme=Gruvbox#`) and the `dotfiles/Kvantum/Gruvbox#/` directory beside it | Drop in the new theme's directory and change the `theme=` line. Largely a rendered SVG of widget art — the hex in `.kvconfig` is a fraction of it |
| 6 | **noctalia** | `dotfiles/mango/noctalia/settings-pinned.json` → `colorSchemes.predefinedScheme` | A **name** noctalia's shell resolves internally. Use one of its own scheme names; there is no hex to supply |

Plus one file that is colour *data* rather than a package:

| | **yazi flavor** | `dotfiles/yazi/flavors/noctalia.yazi/`, declared at `programs.yazi.flavors` | 783 hex of third-party syntax theme. Replace the flavor directory wholesale; do not hand-edit it |

> **`checks/static.sh` exempts exactly these** from its no-stray-hex rule (the
> yazi flavor, Kvantum, and the GTK `colors.css` files, which are Breeze's
> palette and not ours). If you add a seventh such artefact, add it to the
> exemption list in the same change — otherwise the ceiling check fails on
> third-party data and someone will "fix" it by deleting the check.

---

## 3. nvim — the one partial case

nvim's colours come from the `gruvbox.nvim` plugin, driven through its
`palette_overrides` hook by a generated `lua/config/palette.lua`. **20 of the
plugin's 54 palette keys are overridden.** The rest — the `*_hard`/`*_soft`
variants, `faded_*`, the orange pair, and the diff backgrounds — keep upstream's
values, because `palette.nix` does not name them.

The decision rule:

- **Recolour within gruvbox** → nothing to do. The 20 overridden keys carry the
  change; the 34 unnamed ones stay in family and nobody notices.
- **New scheme** → **swap the plugin.** Overriding 20 keys of a gruvbox theme
  with nord values leaves 34 gruvbox values in place, and the result is a
  visible hybrid, not a nord colourscheme. Replace `ellisonleao/gruvbox.nvim` in
  `dotfiles/nvim/lua/plugins/colorscheme.lua`, and either drop
  `palette_overrides` or re-map `lua/config/palette.lua` in
  `modules/home/dotfiles.nix` to whatever the new plugin's override hook expects
  — most have one, and the key names will differ.

Do not try to close the 34-key gap by adding those names to `palette.nix`. They
are one plugin's internal vocabulary, not this machine's colours.

---

## 4. Gate it

```sh
nix flake check
```

**What it catches:** eval errors from a missing palette key; a generated file
that is missing or empty; a generated file that no longer contains the accent in
its consumer's own spelling; a mango mode config that stopped `source=`ing its
colours; any palette hex reappearing in a hand-written file under `dotfiles/`;
and a tinted lock ramp.

**What it does not catch:** whether the new colours are *legible*. Contrast is
not asserted anywhere. Nor is anything about the six packages in §2 — a
half-migrated Kvantum theme passes every check and looks wrong only on screen.

---

## 5. Apply

```sh
rebuild        # sudo nixos-rebuild switch --flake "$HOME/src/nix-config#thinkpad"
```

Quote the flake ref — `EXTENDED_GLOB` makes `#` a pattern operator in zsh.

Then reload, per `CLAUDE.md`'s table. **Rebuild first, always**: everything
under `dotfiles/mango/` is a store path, so reloading alone re-reads the *last*
rebuild's copy, which is indistinguishable from the change having had no effect.

| Surface | Reload |
|---|---|
| mango, waybar | `~/.config/mango/scripts/reload.sh`, `mango-reload`, `waybar-reload` |
| GTK apps | `~/.config/mango/scripts/system/gtk-apply.sh` |
| kitty | `kill -SIGUSR1 $KITTY_PID` |
| foot, ncspot, imv, yazi, zed, htop | restart the app |
| nvim | restart |
| swaync | mode switch (`autostart.conf` owns its lifecycle — `docs/adr/0005`) |

---

## 6. Verify by output

Exit status proves nothing here — a missing theme and a broken theme look
identical, and both look like a theme someone chose. Every command below was run
against this repo and produces output you can read.

```sh
# The generated files, as the rebuild will install them.
G=$(nix eval --raw '.#nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage')
grep -r 'color=' "$G/home-files/.config/mango/universal/colors-tiling.conf"
cat "$G/home-files/.config/nvim/lua/config/palette.lua"
cat "$G/home-files/.config/fsel/config.toml"
sed -n '1,16p' "$G/home-files/.config/swaync/style.css"
```

```sh
# GTK / icons / cursor — what the session actually resolved.
for k in gtk-theme icon-theme cursor-theme; do
  printf '%-14s ' "$k"; dconf read /org/gnome/desktop/interface/$k
done
grep -E 'theme-name|cursor' ~/.config/gtk-3.0/settings.ini
```

> **Use `dconf read`, not `gsettings get`.** From a task shell or this repo's
> devShell, `gsettings` reports `No schemas installed` — which reads exactly
> like "the theme is unset" and is not.

```sh
# Qt / Kvantum
head -3 ~/.config/Kvantum/kvantum.kvconfig      # expect theme=<your theme>

# nvim actually loading the generated palette
nvim --headless '+lua local p=require("config.palette") print("keys="..vim.tbl_count(p).." dark0="..p.dark0)' +qa
```

```sh
# The whole assertion suite, with the palette section visible
SYS=$(nix eval --raw '.#nixosConfigurations.thinkpad.config.system.build.toplevel')
bash checks/static.sh "$PWD" "$G" "$SYS" | sed -n '/Generated palette/,/^$/p'
```

Expect 13 ticks in that last block. A count that has *dropped* is the failure
mode this repo is built around: a scan that stops matching passes by finding
nothing.

---

## 7. Traps specific to this operation

- **nvim is broken between the edit and the rebuild.** `colorscheme.lua` does
  `require("config.palette")`, and that file only exists in the generated tree.
  Open nvim after editing but before rebuilding and lazy.nvim reports a failed
  plugin config and you get no colourscheme. Not damage — rebuild and it is
  gone — but it looks alarming and it is expected.
- **mango's `config.conf` keeps a stale copy until the next mode switch.** It is
  written at runtime by `scripts/lib.sh` from the mode config, is deliberately
  untracked (`docs/adr/0002`), and is skipped by the stray-hex check for that
  reason. Switch modes once after a palette change.
- **Store files are read-only, so you cannot hand-patch one to preview a
  colour.** Edit `palette.nix` and rebuild; there is no faster loop, and trying
  to make one is how `~/.config` acquires a second owner.
- **A GTK `url()` that fails to resolve draws the missing-image box and logs
  nothing.** If a new GTK theme references assets by relative path, they must
  end up beside the stylesheet in the store — see `docs/adr/0009` for the
  wlogout instance of this.
- **Do not run `dbus-update-activation-environment` or `systemctl --user
  import-environment` to make a theme change take effect.** From this repo's
  devShell it writes a scratchpad `XDG_CONFIG_HOME` into every user unit started
  afterwards. `docs/gotchas.md` → Session environment.

---

## 8. Rollback

Colours are cosmetic, so the boot-level safety nets are not needed here — this
is a `git` problem, not a generation problem.

```sh
git diff --stat                      # confirm the blast radius first
git restore modules/home/palette.nix # or the whole change
rebuild
```

If a rebuild has already landed and you want the previous generation back,
`nixos-rebuild switch --rollback` works, but reverting the commit and rebuilding
is cleaner and leaves the repo and the running system agreeing about why.

---

## 9. The short version

1. Edit `modules/home/palette.nix` — twelve consumers follow.
2. If the family changed, replace the six theme packages in §2 and swap nvim's
   plugin (§3). If it did not, skip both.
3. `nix flake check`.
4. `rebuild`, then reload — rebuild first, always.
5. Read the output of §6. Thirteen ticks in the palette block.
