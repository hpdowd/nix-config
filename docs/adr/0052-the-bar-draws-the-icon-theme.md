# 0052 — the bar draws the icon theme, and a minimized window can be picked

**Status:** Accepted (2026-08-28).

Supersedes the "not adopted" note in [0051](0051-waybar-is-the-tiling-bar-again.md),
narrows [0033](0033-the-control-centre-is-a-reader.md), and puts the themed app
icons `wlr/taskbar` used to draw back on the bar without re-listing every window.

## Context

0051 removed `wlr/taskbar` and with it the last module that asked the icon theme
for art, then proved — and did not adopt — that `-gtk-icontheme()` in the
stylesheet reaches Papirus from any module. Two things had been recorded as
impossible and only one of them was:

- **A module's label is text**, so an icon *name* cannot go in it. True, and it
  is why the bar's glyphs are nf-md.
- **`restore_minimized` cannot target a window.** True of that verb, and it is
  why 0033 refused a picker: a menu that accepts a choice it cannot honour is
  worse than no menu. But it is not true of mango's IPC. **`mmsg dispatch
  focusid client,<id>` restores a specific minimized window**, onto the tag you
  are viewing, focused — verified on throwaway windows, targeting the right one
  while a more recently minimized window stayed hidden.

`focusid` is in mango's dispatch table but the bare form `focusid <id>` answers
`{"error":"unknown function"}`. The argument syntax is the whole difference.

## Decision

**Icon names are declared in Nix and drawn by the stylesheet.**
`modules/home/waybar.nix` holds `appIcons` (appid → icon name), `moduleIcons`
and `batteryRungs`, and generates `mango/waybar/icons.css` beside `colors.css`.
Three modules changed:

| Module | Was | Is |
|---|---|---|
| `custom/window` | nf-md glyph prepended by the script | `#custom-window.<appid>` background, the script emits the class |
| `custom/minimized` | one glyph per hidden window | a count behind one icon; click opens a rofi picker with per-window art |
| `battery` | nf-md `format-icons` ladder | Papirus's `battery-level-*-symbolic` ladder, one CSS class per rung |

**The picker is rofi's**, as the weather panel is ([0050](0050-the-weather-panel-is-rofis.md)).
A rofi row carries its own icon, which is the surface a waybar module cannot be:
GTK gives a module one background image, not one per item.

**It is on `SUPER+CTRL+I` as well as the bar**, beside `SUPER+I` and
`SUPER+SHIFT+I`. The appid table is therefore a generated file
(`mango/waybar/app-icons.json`) rather than an argument on the bar's click: a
table reaching only one of the two callers would give the key an iconless menu.
With nothing minimised the picker notifies rather than exiting quietly — from
the bar that state is unreachable, and from a key it would be [0033](0033-the-control-centre-is-a-reader.md)'s
action that appears to do nothing.

**Every rule the generator emits carries a class.** Not style — necessity; see
Consequences.

## Consequences

- **The bar's icons are now two vocabularies on purpose**: Papirus for the three
  modules above, nf-md for the rest. 0051 unified the packs and this splits them
  again, but along a line that reads — an *app* wears its own icon, a *reading*
  wears a glyph.
- **App icons come through in full colour**; symbolic ones follow the module's
  `color`. The charging battery is green because the module is. 0051's log said
  CSS backgrounds could not be recoloured at all, which is wrong for
  `-symbolic` names and right for app icons.
- **`format-charging` and `format-plugged` are gone**, so `format-alt` works on
  AC for the first time — `update()` overrode it whenever a per-status format
  existed (`battery.cpp:730`).
- **`warning` and `critical` are gone as state names.** A battery module gets
  one state class and the ladder needs all of them, so the colour rides the
  rungs: `l0` is capacity ≤ 5 and `l20` is ≤ 20, still upower's
  `PercentageCritical` and `PercentageLow`. One class carries the icon and the
  colour, which is one fewer pair to keep in step.
- **Three checks, for three things that fail without a word.**
  `checks/static.sh` resolves every icon name against the built theme and its
  inheritance chain; asserts icons.css and style-solid.css never set
  `background-image` for the same selector; and asserts no generated rule is a
  bare id.
- **`equibop` and `imv` are stand-ins** in [0041](0041-artefacts-are-generated-not-named.md)'s
  sense — neither name exists in Papirus, and equibop ships no icon anywhere.

### The three failures this cost

- **`Equibop` was never an appid.** The table had been keyed on it since the
  glyphs were written; mango reports `equibop`. The window title had silently
  worn the default glyph for every Equibop window.
- **A bare `#custom-minimized` rule draws no icon at all.** style-solid.css
  gives every module `background: transparent` — the *shorthand*, which resets
  `background-image` — at one-id specificity, after the `@import`. Both sheets
  are valid and GTK reports neither.
- **rofi's dmenu icon syntax cannot go through a shell variable.** It puts a NUL
  between the row and its metadata, and no bash string carries NUL. `rofi_menu`
  in `lib.sh` reads entries with `entries=$(cat)`, so the picker cannot use it;
  the bytes go straight down the pipe instead.
