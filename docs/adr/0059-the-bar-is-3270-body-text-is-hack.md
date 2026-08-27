# 0059 — The bar is 3270; body text is Hack

**Date** 2026-08-28
**Status** Accepted
**Reverses the font clause of**
[0058](0058-one-text-face-and-the-window-that-is-playing.md)

## Context

0058 moved the bar off 3270 and onto Hack. The argument was that the bar was
the only surface not reading in the machine's own face, so the type changed
shape when the control centre opened over the bar that opened it.

The argument was sound and the conclusion was wrong. 3270 is what the bar is
wanted to look like — a narrow, bitmap-derived display face, which is a
deliberate look and not an accident of history. 0058 traded that for a
consistency nobody had asked for, and the seam it closed was one nobody had
noticed.

Hack and 0xProto were both put in the bar and looked at, as whole bars, in
place. Both are wider and rounder than 3270, and neither is the wanted look.

## Decision

**The bar is `Symbols Nerd Font Mono, 3270 Nerd Font` at 13.5px, bold.** wayle
mirrors the same stack, because it is the same bar in a mode that no longer
starts it.

**Body text is Hack**: the rofi menus, wlogout, the terminal, the editor,
swaylock and GTK. 3270 is a display face that needs bold to hold together at
all; it is the wrong choice for a dense list, and the menus are lists.

**Two faces by role is the rule.** "One font everywhere" is not a rule, it is
the mistake 0058 made. What matters is that each role has one face and the
roles are written down.

`nerd-fonts._3270` returns to `fonts.nix`.

## Consequences

- `checks/static.sh` asserts three things now: the bar's stack, that its size
  and weight moved together, and that the menus and wlogout are on Hack. The
  last one exists so a well-meant "unify the fonts" does not land a third time.
- 13.5px and `bold` are one decision. GTK takes a fractional size here; 14 read
  large and 13 read small. 3270's regular goes thin and uneven under 14px, so
  dropping the weight while keeping the size makes the bar look blurry rather
  than small — and that is the kind of edit that looks like tidying.
- Symbols stays first in the stack for the reason it always has: 3270 patches
  the Nerd Font icons in at their natural width but keeps its own 0.54em
  advance, so their ink overflows the cell to the right.
- The change 0058 made that survives is the *unification of the glyph
  vocabulary* — the bar and its control centre draw the same nf-md icons. That
  was the seam worth closing. The typeface was not.
