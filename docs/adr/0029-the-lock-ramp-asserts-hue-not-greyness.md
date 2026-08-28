# 0029 — The lock ramp asserts the palette's hue, not greyness

**Status:** Accepted (2026-08-18)

Amends [0018](0018-lock-background-is-a-pool.md) (the lock background is a
generated pool) and was forced by the Catppuccin migration that
[0028](0028-one-palette-reaches-every-config-it-can.md) made cheap enough to
attempt.

## Context

`pkgs/default.nix` builds the swaylock background pool as a ramp of nine tones
centred on `palette.bg0`, and asserts two properties of every generated PNG:
that its mean is `bg0` ±1, and that **every tone is neutral — R = G = B**.

The second assertion was correct by accident. Gruvbox's base is `#282828`, which
is grey, so "a ramp through the base colour" and "a grayscale ramp" described the
same thing and the check could be written either way. It was written the narrow
way, in both places that needed it: `blocks.py` rejected non-neutral *stops*, and
the derivation's `checkPhase` rejected non-neutral *tones*.

Catppuccin Mocha's base is `#1e1e2e` — blue by 16 in the third channel. Every
generated tone fails a neutrality test, so the palette change failed the build,
which is what it was designed to do. `docs/THEME-MIGRATION.md` §1 anticipated
this and said the check must be changed in the same commit, with a reason.

The reason matters more than the mechanism, because the obvious response is to
delete the check. What it catches is genuinely hard to see: the lock screen is
the one surface a user meets with nothing else on screen to compare against, so
a background carrying a hue the palette never named looks deliberate. It is
the same class as the drifted palette 0028 exists to prevent, on the one surface
where drift is least visible.

## Decision

**Generalise both assertions from "grey" to "one hue", and derive the ramp per
channel.**

The ramp offsets all three channels of `bg0` by the same ±6, so every tone keeps
`bg0`'s exact channel offsets and differs only in lightness. The checks assert
that property:

| | Before | After |
|---|---|---|
| `blocks.py`, on its stops | `R == G == B` | all stops share one `(R-G, G-B)` |
| `checkPhase`, on every tone | `R == G == B` | offsets equal `bg0`'s |
| `checkPhase`, on the mean | mean of all channels, `bg0[0]` ±1 | **per channel**, `bg0[c]` ±1 |

A neutral base still satisfies all three, with offsets `(0, 0)` — the old
gruvbox ramp passes the new check unchanged, which is how the generalisation was
verified.

The per-channel mean is a strengthening that came along for free: the old
combined mean would let a ramp that drifted `+9` in red and `−9` in blue average
back into range.

Exactness is affordable here and is not a tolerance. `ramp()` interpolates each
channel from an integer base by an identical delta, so the fractional parts agree
and all three channels round the same way; the upscale is `-filter Point`, which
introduces no new colours. The mean stays a ±1 tolerance for the reason it always
was — 96 blocks sampled from 9 tones vary by ±1 through sampling alone.

## Consequences

- Changing the scheme no longer requires touching this check. `bg0` can be any
  colour; the ramp follows it. That removes the one hard blocker the migration
  runbook had.
- The guarantee is unchanged in the case that matters: the lock screen cannot
  wear a colour the palette did not name.
- **The narrow version was not wrong, and this is not a lesson about writing
  checks loosely.** `R = G = B` was the true statement about the system at the
  time, it failed exactly when the underlying assumption expired, and it failed
  at build time with a message that named the problem. A looser check written in
  2026-08 would have bought nothing and asserted less for two years. The habit
  worth keeping is the one that worked: assert the strongest true property, and
  let the build report it when it stops being true.
- Cost: the derivation is harder to read. `mid` is a three-element list and the
  `checkPhase` is generated with `zipListsWith` over the channel names, where it
  used to be one `magick` call and a string comparison.
