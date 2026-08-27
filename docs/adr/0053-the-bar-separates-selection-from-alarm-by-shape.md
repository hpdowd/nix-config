# 0053 — the bar separates selection from alarm by shape, not by hue

**Status:** Accepted (2026-08-27).

Amends the colour half of [0042](0042-separators-belong-to-the-layout.md) and
[0051](0051-waybar-is-the-tiling-bar-again.md).

## Context

`style-solid.css` used `@accent` for selection and for benign status, and the
alarm roles for trouble. Whether those are distinguishable is a property of the
scheme, not of the stylesheet, and no check covered it: both colours resolve,
both are used, and `palette_pair` passes either way.

Heartbox sets `accent = red`, one step from its `errColor`:

| scheme | accent | err | ΔE2000 | hue gap |
|---|---|---|---|---|
| nord | `#8fbcbb` | `#bf616a` | 44.7 | 178° |
| gruvbox | `#d79921` | `#fb4934` | 31.8 | 40° |
| mocha | `#cba6f7` | `#f38ba8` | 21.1 | 54° |
| heartbox | `#e02030` | `#ff4a58` | 10.9 | 5° |

So the active workspace tag (filled `@accent`) and an urgent one (filled `@red`)
were two near-identical blocks in the same row meaning opposite things.

Two other measurements:

- `@base` on `@accent` is 3.87:1 under heartbox, against 5.94–9.23 under the
  other four. That was the lowest-contrast text on the bar. `@text` on `@accent`
  is 4.03:1, so flipping does not help.
- `@overlay` on `@base` is 1.28:1 under heartbox against 2.06 under
  mocha-high-contrast. `@overlay` is a background role, so its strength as a
  hairline is whatever gap a scheme left between `bg0` and `bg2`, and 0042 made
  that hairline the only expression of the bar's grouping.

## Decision

**The active tag is a 2px `@accent` underline with a `@text` label; urgent stays
a filled `@red` block.** Shape distinguishes them under every scheme, and it
removes the 3.87:1 label. The border is reserved as `transparent` on every
button, or the active one is 2px taller and its label shifts on each tag switch.
It moves to the top edge on a bottom bar, as `window#waybar`'s border does.

**Hairlines are `mix(@base, @subtext, 0.3)`** — `.sep`, the bar's border and the
tooltip outline. That is 1.68–2.20:1 across the five schemes against 1.28–2.06
for `@overlay`, which keeps the two hover backgrounds.

**The left half takes identity tints.** Time, weather, media and minimized
windows are four unrelated kinds of information, where the right half is machine
state that the alarm colours already sort. Each takes a hue mixed toward the
neutral it would otherwise be: weather `mix(@text, @blue, 0.6)`, media
`mix(@text, @accent, 0.5)`, minimized `mix(@subtext, @yellow, 0.4)`. They land
7.25–11.5:1 on `@base` and 22–48 ΔE2000 apart. The clock takes no hue; at 18px
it is already distinct. The media tint also carries playback state, because
waybar adds `#mpris.${status}` and `paused` drops to `@subtext`.

**The right half has a stated vocabulary and `@accent` is not in it.**

| colour | means |
|---|---|
| `@green` | connected, charging, saving power |
| `@yellow` | warning threshold |
| `@red` | critical, error, drawing hard |
| `@blue` | a hold you have set |
| `@subtext` | resting |
| `@accent` | not used here |

`custom/power-profile.balanced` and `bluetooth.connected` drew `@accent`. Both
are benign, and `balanced` is what the machine reports almost always, so the
loudest element on the bar marked the ordinary state. `balanced` is `@subtext`
now; `bluetooth.connected` is `@green`, matching `custom/vpn.connected`.
Night-mode keeps `@yellow` rather than the `@blue` row, because there the colour
shows the effect.

Buttons are `@subtext` at rest. `custom/power` was `@blue` on the grounds that
the glyph was the NixOS logo; it has been nf-md-power (U+F0425) since 0051.

**`@text` where a module's value is the information, `@subtext` where its glyph
is.** `cpu` and `memory` move up. `custom/minimized` stays `@subtext` because
those windows are off screen.

**Three font sizes: 13.5 base, 16 on the power button, 18 on the clock.** There
were five. `13px` on five glyph-only modules and `14px` on weather are both half
a pixel from the base — no visible size difference, but a different rasterisation
on a bitmap-derived face.

**Spacing is CSS, not glyph strings.** `custom/power`, `custom/vpn` and the eight
`custom/notification` icons carried trailing spaces. The right screen-edge inset
is `#custom-power { padding-right: 12px }`, mirroring the clock.

## Consequences

- The tag strip is flush to the line on both sides. `#workspaces { padding: 0 }`
  is `(1,0,0)` and beats `.sep`'s `padding-left` at `(0,1,0)`, and
  `#mpris.sep { margin-left: 0 }` closes the other side. The buttons keep their
  own 8px, so a glyph never touches a line but the box does, which lets a hover
  or an urgent fill run to the group edge. It looks like a mistake next to the
  11px after every other separator, so it is asserted rather than left to be
  corrected. An 11px version shipped for one commit.
- Four assertions: `@accent` appears only on the active tag (`mix()` exempt);
  `balanced` is read as a value and must be `@subtext`; the buttons reserve the
  transparent border; `mpris` still follows `ext/workspaces`, so `#mpris.sep`
  closes the boundary it was written for.
- A plain icon name ignores `color`; `-symbolic` follows it. `view-restore` drew
  a white icon beside a tinted count. `view-restore-symbolic` resolves through
  `Papirus-Dark`'s inheritance and takes the module's colour.
- An undefined colour inside `mix()` is silent. waybar logged an invalid property
  on the same line and nothing about `mix(@base, @nosuchcolour, 0.3)`.
  `palette_pair`'s both-directions check is what covers this.
- `custom/vpn` emitted `"class":""`, which is an absence rather than a state and
  cannot be checked. It emits `off` now, and still renders when off because it is
  a click target.
- The icon gap moved from `padding-left: 22px` to `26px` on `custom/window`,
  `custom/minimized` and `battery`, which are one setting. At 22 the gap after a
  16px icon inset by 4px is 2px.
- Verified by rendering both bar positions from the built generation and sampling
  pixels. The hairline reads `#49464a`, which is `mix(#1a1214, #b8c0c8, 0.3)`;
  GTK's `mix()` interpolates in sRGB.
