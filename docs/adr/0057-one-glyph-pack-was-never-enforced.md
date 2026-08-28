# 0057 — One glyph pack was never enforced

**Status:** Accepted (2026-08-28). Supersedes part of
[0051](0051-waybar-is-the-tiling-bar-again.md) — the one-pack pass — and part of
[0053](0053-the-bar-separates-selection-from-alarm-by-shape.md), the neutral
tiers.

## Context

`docs/adr/0051` unified the bar on nf-md and `checks/static.sh` grew a scan to
hold it. `docs/adr/0054` extended that scan to the glyphs scripts print, after
night-mode.sh was found still writing Font Awesome's moon.

Both passed. Both were wrong.

The script half read `grep -oE '\\U[0-9A-Fa-f]{8}'` — capital `U`, eight
digits. Every Font Awesome and nf-weather glyph in the tree was written the
other legal bash form, `$'\uXXXX'`, four digits, and matched nothing:

| file | pack | count |
|---|---|---|
| `system/weather.sh` | nf-weather | 13 |
| `menus/control-center.sh` | nf-fa | 12 |
| `system/power-profile.sh` | nf-fa | 4 |
| `volume-menu.sh`, `bluetooth-menu.sh`, `vpn-menu.sh` | nf-fa | 9 |

Including `control-center.sh`'s `$''` — nf-fa-moon_o, the exact glyph
0054 was written to catch, rewritten as an escape and left in the other pack.
The floor assertion (`glyphseen -eq 0`) could not save it: idle-inhibit.sh
supplied two real matches, so the count was 12 and 12 is not zero.

The raw-literal half had the matching hole. Its comment says "plane 15 leads
with 0xF3" and its bracket is `[\xee\xef]`, so raw nf-md literals in `vpn.sh`
and `phone-status.sh` sat outside the convention the comment states.

Three consequences were visible on the bar and went unreported:

- **Two lightning bolts, 30px apart.** `custom/power-profile` drew nf-fa-bolt
  in red for `performance`, immediately left of a battery whose Papirus art is
  a bolt inside a battery. A red bolt beside a battery looks like charge state.
- **The panel disagreed with the bar it opens from.** control-center.sh gave
  bluetooth, volume, night mode and the power profile different glyphs from the
  modules they mirror, and mixed four nf-md with twelve nf-fa in one list.
- **The weather module was a third vocabulary** — thin nf-weather outlines
  beside solid nf-md shapes, next to the clock.

Separately, 0053 wrote down two neutral tiers and the bar had three. `opacity:
0.5` was on `bluetooth.off`, `night-mode.off` and `weather.stale`; `vpn.off`,
`idle-inhibitor.deactivated` and every `dnd-`/`inhibited-` notification state
meant the same thing at full `@subtext` — 3.37:1 against 10.01:1 for one
semantic, with no rule saying which. Six of `custom/notification`'s eight
classes had no rule at all, so do-not-disturb was indistinguishable from a
quiet inbox.

And four `format-alt` declarations had never toggled. `ALabel::handleToggle` is
gated on `config_["format-alt-click"].isUInt()` (ALabel.cpp:181) and waybar
sets no default, so clock, memory, network and battery each carried a second
reading nothing could reach. `memory` also had `on-click = "alt"`, which is not
a waybar action name — `AModule::handleUserEvent` falls through to `forkExec`,
so every left-click ran `alt` as a shell command and failed.

## Decision

- **The scan reads both escape widths, either case, and skips what is not a
  glyph.** U+E000 is the line: below it an escape is a field separator, above it
  a 4-digit escape can never reach U+F0000 and is therefore always another
  pack. The raw-byte test covers 0xEE, 0xEF and 0xF3.
- **The floor is 40, not 0.** A zero floor is what let a scan matching 12 of 51
  report a clean bill. The floor has to sit above the largest count a broken
  pattern can still return.
- **All 39 glyphs move to nf-md**, written as `$'\UXXXXXXXX'`, rendered to
  check rather than trusted by name.
- **`performance` is a gauge, not a bolt** — nf-md-gauge_full, with nf-md-gauge
  for balanced and the existing leaf for fanless. The module stays in the
  battery group; the shape is what stops it being read as charge state.
- **VPN-off draws nf-md-shield_off**, not the check-shield both states shared.
- **Three neutral tiers, written down and applied to every state**: `@text` for
  a value, `@subtext` at rest, `@subtext` at 0.5 for off or suppressed.
  `#pulseaudio.muted` is the one stated exception — it also carries the
  microphone indicator.
- **`bluetooth` at rest is `@subtext`.** It was `@text`, the brightest icon in
  its group, for a module reporting nothing.
- **`format-alt-click = 1` is emitted by `mkBar` for any module declaring a
  `format-alt`**, so the pair cannot come apart again. `memory`'s
  `on-click = "alt"` is gone.

## Consequences

The scan reads 65 escapes across 52 scripts where it read 12, and the count is
the assertion as much as the pattern is.

Two glyph vocabularies remain, deliberately: the bar is 3270 Nerd Font and
every rofi surface is Hack Nerd Font, so the type still changes when the panel
opens even though the icons no longer do. That is a font decision, not a pack
one, and it is not made here.

Weather's clear-night and night-mode's toggle are both nf-md-weather_night.
They sit in different groups and coincide only on a clear night with night mode
on; the collision was accepted rather than resolved with a second moon.

`#tray > .passive` is deleted. `show-passive-items` defaults false, so the rule
could never match — a styled state for a widget waybar does not render.
