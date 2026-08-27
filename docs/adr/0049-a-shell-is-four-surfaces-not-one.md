# 0049 — A shell is four surfaces, and the bar was the only declared one

**Status:** Accepted (2026-08-26).

Extends [0045](0045-wayle-is-the-tiling-shell.md), which specified the bar and
left the rest of wayle on its defaults.

## Context

0045 replaced waybar with a shell and then configured it like a bar. The bar got
six generated layouts, seventeen stylesheet rules and a session button measured
off screenshots. The three surfaces beside it got nothing:

| Surface | What it was wearing |
|---|---|
| eight dropdowns | `styling.rounding = "sm"`, `styling.scale = 1.01` |
| notification popups | a drop shadow, and an urgency bar at *every* urgency |
| the OSD | no `[osd]` block existed at all |

Two things make that worse than an oversight. **swayosd was removed on
2026-08-26** ([0047](0047-a-retired-daemon-is-a-call-that-exits-0.md)) for
drawing a second caps-lock overlay over wayle's, so wayle's OSD is now the only
one this machine has — volume, brightness and the lock keys all land on a
surface nothing here describes. And the house language is already written down:
`rofi/config.rasi` states it as *square, 1px, flat, one accent, no zebra
striping*, read off `tiling.conf` and the bar's own sheet. The bar obeys it. The
panels the bar opens did not.

`popup-urgency-bar` is the sharpest case. Its default is `low` — the
**minimum**, so the coloured bar is drawn at every urgency and therefore marks
nothing. That is [0048](0048-state-colour-rides-the-class-the-script-prints.md)'s
argument one surface over: *the resting state carries no rule, because a
permanently-lit thing has no signal in it.*

## Decision

**Every wayle surface is declared, not just the bar.** `styling.rounding` and
`styling.scale` take the bar's own values; `[osd]` is written out even where the
values match wayle's, so the next change to it is a diff rather than a
discovery; the popup loses its shadow and marks only `critical`.

Three assertions in `checks/static.sh`, one per surface. The rounding one reads
**inside `[styling]`** rather than grepping the file: `[bar]` carries its own
`rounding = "none"`, so a bare grep would pass on the bar's line after the
styling key was deleted — a check that goes on passing once its subject is gone.

**What this does not do.** `general.font-sans` is also shell-wide, and it is set
to the bar's stack — so dropdown and notification body text renders in 3270
while rofi, the other menu surface, is Hack. Left alone: splitting it means
holding the bar's stack on `.module` in `index.scss`, which is a change to the
sheet rather than to the config, and it wants its own pass.

## Consequences

- **Six generated files gain an `[osd]` table** that mostly restates wayle's
  defaults. That is deliberate and is the point: only `border` and `margin`
  differ, and they are visible as decisions because the other five are written
  beside them. `margin` was recovered from `runtime.toml`, below.
- **A rounded dropdown is now a gate failure**, not a thing to notice.
- **`styling.scale` is pinned at 1.0.** Its default is 1.01, which is not a
  choice anyone made about this machine.
- **Critical notifications now look different from ordinary ones**, which they
  did not before. Nothing on this machine sends critical often, so the first one
  after this change is the test of it.
- **A declared surface can still be overridden at runtime.** `wayle config set`
  writes `~/.config/wayle/runtime.toml` and that file beats the generated one,
  reporting only `config.toml change ignored … runtime override active` in the
  journal. It was holding `osd.margin` when this landed, so the new block
  appeared to do nothing. Declaring a surface does not make it the only owner —
  `docs/gotchas.md` → Wayle has the reset.
