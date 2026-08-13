# 0018 — The lock background is a pre-generated pool, picked per lock

**Status:** Accepted (2026-08-13)

## Context

The lock screen was a flat `#282828` — which is exactly what
`docs/gotchas.md` warns a blank lock looks like: a machine that is off or hung.
The clock and ring were already there as proof of life; the background was
carrying nothing.

The obvious first move was `--effect-pixelate` against the existing solid
colour. **It does nothing, for two independent reasons**, and would have exited
0 while doing it:

- `apply_effects` is called once, on a *loaded image*. With no `-i` and no `-S`
  there is no image, so the effects list is never reached at all.
- `effect_pixelate` averages each block. The average of a uniform field is that
  same value, so `#282828` in gives `#282828` out.

Both are recorded in `docs/gotchas.md` → swaylock. A background image is
therefore a precondition, not a preference.

Three further findings shaped what the image had to be:

- **Scaling softens it.** `render_background_image` sets
  `CAIRO_FILTER_BILINEAR`, so any image that is not already 1:1 with the output
  arrives with its block edges blurred. The pool is generated at the panel's
  native 1920×1200.
- **A weighted ramp clumps.** Sampling five tones with one at 68% left
  **236 of 360 blocks as a single connected region** — two thirds of the screen
  reading as one flat mass, which is the thing the texture existed to avoid.
  Fixed by a fine ramp plus a hard no-matching-neighbour constraint.
- **A tinted ramp is not a shade.** `#282828` is neutral (R=G=B=40), so stops
  like `#322e2b` (R50/G46/B43) read as a *different colour*, not as a lighter
  or darker version of the background. This one survived four rounds of
  adjusting brightness because brightness was never what was wrong.

The remaining requirement was that the pattern vary per lock. `programs.swaylock.settings`
generates one static config file, so `image=` cannot vary from inside it: the
choice has to be made by whatever invokes swaylock.

## Decision

**The background is a pool built at build time, and a wrapper picks a member per
lock.**

`pkgs/lock-backgrounds` generates 24 PNGs from fixed seeds — reproducible as a
derivation, even though which member gets used is not. `pkgs/lockscreen` picks
one with `$RANDOM` and execs swaylock with `-i`.

**Every lock path goes through `lockscreen`**: swayidle's `before-sleep` and
`lock`, the idle timeout, wlogout, the power menu, and the mango binds.

Three constraints on the shape of it:

- **Not named `swaylock`.** A wrapper of that name lands earlier in PATH and
  shadows swaylock-effects — the same trap that makes
  `programs.swaylock.package = null` load-bearing.
- **Generation is build-time, never lock-time.** swayidle's `before-sleep` hook
  blocks suspend until it exits; a PNG encode on that path buys nothing and
  risks a lock that is late or absent.
- **An empty pool falls back to the solid colour.** A lock that will not start
  is worse than a plain one.

The image properties are asserted in the derivation's `checkPhase`, not left to
the ramp arithmetic: every tone neutral (exact), and the mean within ±1 of 40.
The tolerance is deliberate — 96 blocks drawn from 9 tones vary by ±1 through
sampling alone, so an equality test fails on roughly one seed in four while
catching nothing a ±1 test misses.

## Consequences

**This costs the "one config, bare `swaylock -f`" property**, which
`modules/home/programs.nix` had called out as deliberate. Six call sites now
name `lockscreen` instead. The config file is still single and still read by all
of them — the wrapper execs swaylock, it does not replace it — but the
indirection is real and has to be greppable.

`checks/static.sh` asserts both halves: that swayidle reaches `lockscreen`, and
that the pool the wrapper actually points at is non-empty. The old assertion
matched the literal string `swaylock` in the swayidle unit and would have passed
by finding nothing.

`lockscreen` is in `home.packages` **only** because the mango binds are plain
text in a store path and cannot interpolate a Nix path. Everything Nix can
reach uses `${pkgs.lockscreen}` directly.

24 variants, 192 KB, rather than true per-lock uniqueness. For an abstract
neutral texture nobody will memorise, the difference is not observable; the
runtime failure path avoided is.

An external output at a different resolution gets a bilinear-softened copy.
Cosmetic, confined to that output, and fixable with per-resolution pools if it
ever matters.
