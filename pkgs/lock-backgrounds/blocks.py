#!/usr/bin/env python3
"""Emit one swaylock background as a binary PPM, at grid resolution.

Upscaling to the panel's native size is ImageMagick's job, not this script's:
swaylock draws backgrounds with CAIRO_FILTER_BILINEAR, so an image that is not
already 1:1 with the output arrives with its block edges blurred.

Two invariants, both asserted rather than assumed — each is a mistake that was
made and shipped-looking during this file's development:

  - every stop sits on ONE hue: the channel offsets (R-G, G-B) are identical
    across the ramp, so the stops differ only in lightness. A ramp whose hue
    drifts reads as a *different colour*, not as a lighter or darker shade of
    the background.

    This was `R=G=B` while the palette was gruvbox, whose base #282828 is
    neutral. Catppuccin Mocha's #1e1e2e is not, so the invariant is stated as
    what it always meant — one hue, varying only in lightness — rather than as
    the grayscale special case of it. A neutral base still satisfies it, with
    offsets (0, 0).
  - no block equals any of its eight neighbours. Sampling a weighted ramp
    without this left two thirds of the screen as one connected region.
"""

import argparse
import random
import sys


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def ramp(stops, steps):
    """Piecewise-linear interpolation across `stops`, to `steps` colours.

    An odd `steps` over a symmetric ramp puts one entry exactly on the middle
    stop; an even count straddles it, which drags the mean off the base colour.
    """
    cols = []
    for i in range(steps):
        t = i / max(steps - 1, 1) * (len(stops) - 1)
        lo = min(int(t), len(stops) - 2)
        f = t - lo
        a, b = hex_to_rgb(stops[lo]), hex_to_rgb(stops[lo + 1])
        cols.append(tuple(round(a[c] + (b[c] - a[c]) * f) for c in range(3)))
    return cols


def build(gw, gh, n, rng):
    """Uniform choice per cell, excluding whatever the eight neighbours used."""
    grid = [[None] * gw for _ in range(gh)]
    for y in range(gh):
        for x in range(gw):
            banned = set()
            for dy, dx in ((0, -1), (-1, -1), (-1, 0), (-1, 1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < gh and 0 <= nx < gw and grid[ny][nx] is not None:
                    banned.add(grid[ny][nx])
            choices = [i for i in range(n) if i not in banned]
            if not choices:
                sys.exit("ramp has too few tones to avoid every neighbour")
            grid[y][x] = rng.choice(choices)
    return grid


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--grid", required=True, help="WxH in blocks")
    p.add_argument("--steps", type=int, required=True)
    p.add_argument("--stops", required=True, help="comma-separated hex")
    p.add_argument("--seed", type=int, required=True)
    p.add_argument("--out", required=True)
    a = p.parse_args()

    stops = a.stops.split(",")
    offsets = {tuple(c - hex_to_rgb(s)[0] for c in hex_to_rgb(s)) for s in stops}
    if len(offsets) != 1:
        sys.exit(
            "stops do not share one hue: channel offsets "
            f"{sorted(offsets)} differ, so the ramp shifts colour as well as "
            "lightness"
        )

    gw, gh = (int(v) for v in a.grid.split("x"))
    pal = ramp(stops, a.steps)
    grid = build(gw, gh, len(pal), random.Random(a.seed))

    with open(a.out, "wb") as f:
        f.write(f"P6\n{gw} {gh}\n255\n".encode())
        for row in grid:
            for c in row:
                f.write(bytes(pal[c]))


if __name__ == "__main__":
    main()
