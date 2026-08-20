#!/usr/bin/env python3
"""Tint an achromatic Kvantum SVG onto this repo's palette. docs/adr/0041.

    kvantum-recolour.py <svg> <dark-hex> <light-hex>

The source (KvantumAlt) is greyscale, so it carries a lightness ramp and no
hue at all. Every colour in it is mapped by luminance onto the <dark>..<light>
axis, which reproduces the artwork's own shading against a palette it was not
drawn for without inventing a single relationship.

Two assertions, because a substitution that stops matching leaves a complete,
valid, UNRECOLOURED theme that Kvantum renders without complaint:

  a floor      on how many distinct colours were found, so a regex that stops
               matching cannot pass by finding nothing
  no leftovers no colour in any OTHER notation may remain. This one is not
               theoretical: KvantumAlt holds eight THREE-digit colours
               (`fill:#fff`, `#555`, `stop-color:#fff`) which a six-digit
               regex skips in silence, leaving pure white highlights in a
               theme that has no white. Found 2026-08-20 by asking what the
               first version of this assertion could actually catch — it could
               catch nothing, being a subset test on a set built from the same
               regex.
"""

import re
import sys

# KvantumAlt held 21 on 2026-08-20. A floor rather than that number: the source
# is nixpkgs' Kvantum, which moves on `nix flake update`, and a bump that
# retouches the art must not break the build.
MIN_COLOURS = 15

# Three- AND six-digit. The short form is rarer but it is in there, and a
# recolour that skips it leaves the source's own white behind.
HEX = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")

# Everything else that is a colour in SVG. None of these appear in KvantumAlt
# today; the assertion is for the bump that introduces one.
OTHER = re.compile(r"#[0-9a-fA-F]{8}\b|\brgba?\(")


def channels(h):
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def luminance(rgb):
    r, g, b = rgb
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    path, dark_hex, light_hex = sys.argv[1], sys.argv[2], sys.argv[3]
    dark, light = channels(dark_hex), channels(light_hex)

    svg = open(path, encoding="utf-8").read()
    found = {m.group(1).lower() for m in HEX.finditer(svg)}
    if len(found) < MIN_COLOURS:
        sys.exit(
            f"kvantum-recolour: only {len(found)} distinct colours in {path}, "
            f"expected at least {MIN_COLOURS} — the scan is broken, not the source."
        )

    mapping = {}
    for src in found:
        t = luminance(channels(src))
        mapping[src] = "".join(
            f"{round(d + t * (l - d)):02x}" for d, l in zip(dark, light)
        )

    out = HEX.sub(lambda m: "#" + mapping[m.group(1).lower()], svg)

    # A colour this pass cannot express is a colour left wearing the source's
    # scheme. Fail rather than ship it: the whole point of choosing a greyscale
    # base is that NOTHING in the art keeps its own colour.
    other = sorted({m.group(0) for m in OTHER.finditer(out)})
    if other:
        sys.exit(
            f"kvantum-recolour: {len(other)} colour notation(s) this script does "
            f"not handle remain in {path}: {', '.join(other)}"
        )

    open(path, "w", encoding="utf-8").write(out)
    print(f"kvantum-recolour: {len(found)} colours tinted onto #{dark_hex}..#{light_hex}")


if __name__ == "__main__":
    main()
