#!/usr/bin/env python3
"""Write Colloid's `_color-palette-*.scss` from this repo's palette. docs/adr/0041.

    colloid-palette.py <palette.json> <out.scss>

Colloid compiles from SCSS and keeps every colour it uses in one file per
scheme — `_color-palette-gruvbox.scss`, `_color-palette-nord.scss` and three
more, all with identical variable names. So this phase adds a file rather than
patching upstream's internals, and the only coupling is to those names.

THE GREY RAMP IS ANCHORED, NOT INTERPOLATED END TO END. Upstream's own gruvbox
file was read off against `modules/home/themes/gruvbox.nix` and the stops land
exactly on that palette's ramp:

    $grey-150 = fg1    $grey-550 = bg3    $grey-650 = bg1
    $grey-350 = fg4    $grey-600 = bg2    $grey-700 = bg0
    $grey-400 = comment                   $black    = mantle

That is reproduced here: the roles this repo actually has are pinned to the
stops upstream pins them to, and only the gaps between them are interpolated.
A single lerp from `fg0` to `mantle` would be simpler and would put every
Colloid surface a shade away from the palette the rest of the machine wears.

Two of Colloid's eight hues have no role here — `purple` and `orange` — and are
blended from the ones that do. That is invention, and it is confined to these
two lines so it can be found again.
"""

import json
import sys

VARS = 43  # what upstream's own files declare; asserted before writing


def chan(h):
    h = h.lstrip("#")
    return [int(h[i : i + 2], 16) for i in (0, 2, 4)]


def hex6(rgb):
    return "#" + "".join(f"{max(0, min(255, round(c))):02x}" for c in rgb)


def mix(a, b, t):
    """t=0 gives a, t=1 gives b."""
    return [x + t * (y - x) for x, y in zip(chan(a), chan(b))]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    p = json.load(open(sys.argv[1], encoding="utf-8"))

    def c(role):
        return "#" + p[role]

    white = "#ffffff"
    black = "#000000"

    # The grey ramp. Anchors are this palette's own roles at the stops upstream
    # uses them at; everything else is a mix of its two neighbours.
    anchor = {
        "050": hex6(mix(c("fg0"), white, 0.35)),
        "100": c("fg0"),
        "150": c("fg1"),
        "350": c("fg4"),
        "400": c("comment"),
        "550": c("bg3"),
        "600": c("bg2"),
        "650": c("bg1"),
        "700": c("bg0"),
        "800": c("mantle"),
        "950": hex6(mix(c("mantle"), black, 0.6)),
    }
    between = {
        "200": ("150", "350", 1 / 3),
        "250": ("150", "350", 1 / 2),
        "300": ("150", "350", 2 / 3),
        "450": ("400", "550", 1 / 3),
        "500": ("400", "550", 2 / 3),
        "750": ("700", "800", 1 / 2),
        "850": ("800", "950", 1 / 3),
        "900": ("800", "950", 2 / 3),
    }
    grey = dict(anchor)
    for stop, (lo, hi, t) in between.items():
        grey[stop] = hex6(mix(anchor[lo], anchor[hi], t))

    # The eight hues. Colloid wants a light/dark pair each; this palette's
    # bright/normal axis is exactly that pair.
    hues = {
        "red": (c("brRed"), c("red")),
        "blue": (c("brBlue"), c("blue")),
        "teal": (c("brCyan"), c("cyan")),
        "green": (c("brGreen"), c("green")),
        "yellow": (c("brYellow"), c("yellow")),
        # No role for these two. Pink leans the magenta toward red, purple
        # leans it toward blue — the two directions a magenta can go.
        "pink": (hex6(mix(c("brMagenta"), c("red"), 0.35)), hex6(mix(c("magenta"), c("red"), 0.35))),
        "purple": (c("brMagenta"), c("magenta")),
        "orange": (hex6(mix(c("brYellow"), c("brRed"), 0.5)), hex6(mix(c("yellow"), c("red"), 0.5))),
    }

    out = ["// GENERATED from modules/home/palette.nix by pkgs/colloid-palette.py.",
           "// docs/adr/0041. Edit the theme file, then rebuild.", ""]
    for name, (light, dark) in hues.items():
        out += [f"// {name.capitalize()}", f"${name}-light: {light};", f"${name}-dark: {dark};", ""]
    out.append("// Grey")
    for stop in sorted(grey, key=int):
        out.append(f"$grey-{stop}: {grey[stop]};")
    out += [
        "",
        "// White",
        f"$white: {c('fg0')};",
        "",
        "// Black",
        f"$black: {c('mantle')};",
        "",
        "// Button",
        f"$button-close: {c('errColor')};",
        f"$button-max: {c('okColor')};",
        f"$button-min: {c('warnColor')};",
        "",
        "// Link",
        f"$links: {c('infoColor')};",
        "",
        "// Theme",
        # Colloid's accent, and the one place this file names THIS repo's
        # `accent` rather than an ANSI slot.
        f"$default-light: {c('accent')};",
        f"$default-dark: {hex6(mix(c('accent'), c('mantle'), 0.3))};",
        "",
    ]

    text = "\n".join(out)
    declared = sum(1 for line in out if line.startswith("$"))
    if declared != VARS:
        sys.exit(
            f"colloid-palette: wrote {declared} variables, upstream's files declare "
            f"{VARS}. A variable Colloid reads and this file does not set falls back "
            f"to its own default, silently."
        )
    open(sys.argv[2], "w", encoding="utf-8").write(text)
    print(f"colloid-palette: {declared} variables written")


if __name__ == "__main__":
    main()
