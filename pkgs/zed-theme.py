#!/usr/bin/env python3
"""Write a Zed theme from this repo's palette. docs/adr/0041.

    zed-theme.py <palette.json> <scheme-name> <out.json>

Zed loads user themes from `~/.config/zed/themes/*.json`, which
`programs.zed-editor.themes` writes. That matters beyond convenience: the theme
used to come from Zed's own extension registry, and `modules/home/programs.nix`
recorded it as "THE ONE PAIR NO CHECK HERE CAN GATE" — the repo could assert
that a theme file NAMED an extension and a theme, and nothing more, because
both halves lived on Zed's servers. A theme written into the generation is
gateable like everything else.

AUTHORED FROM ROLES, NOT TRANSFORMED FROM ZED'S OWN THEME. Substituting into
Zed's Gruvbox was the obvious route and it is wrong: that file holds 63 distinct
colours for a palette with about twenty, because its values have drifted
(`#fb4a35` where gruvbox is `#fb4934`, three different `#fabd2e`/`#fabd2f`/
`#f9bd2f`). Mapping them back would copy somebody else's rounding into every
scheme this repo ever wears.

The key list is Zed's, read off `assets/themes/gruvbox/gruvbox.json` at v0.199.5
— 135 style keys, 43 syntax keys, 8 players. The counts are asserted, which
catches a key dropped HERE. It cannot catch Zed adding one: a key this file
omits falls back to Zed's default and looks merely unstyled, so a Zed upgrade
is a reason to re-read the schema.
"""

import json
import sys

STYLE_KEYS = 135
SYNTAX_KEYS = 43
PLAYERS = 8


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    p = json.load(open(sys.argv[1], encoding="utf-8"))
    scheme = sys.argv[2]

    def c(role, alpha=1.0):
        """A role as Zed's #rrggbbaa."""
        return f"#{p[role]}{round(max(0.0, min(1.0, alpha)) * 255):02x}"

    def mix(role_a, role_b, t, alpha=1.0):
        a = [int(p[role_a][i : i + 2], 16) for i in (0, 2, 4)]
        b = [int(p[role_b][i : i + 2], 16) for i in (0, 2, 4)]
        rgb = "".join(f"{round(x + t * (y - x)):02x}" for x, y in zip(a, b))
        return f"#{rgb}{round(alpha * 255):02x}"

    clear = "#00000000"

    style = {
        # Surfaces.
        "background": c("bg0"),
        "elevated_surface.background": c("bg1"),
        "surface.background": c("bg1"),
        "panel.background": c("bg1"),
        "status_bar.background": c("bg0"),
        "title_bar.background": c("bg1"),
        "title_bar.inactive_background": c("bg0"),
        "toolbar.background": c("bg0"),
        "tab_bar.background": c("bg1"),
        "tab.active_background": c("bg0"),
        "tab.inactive_background": c("bg1"),
        "editor.background": c("bg0"),
        "editor.gutter.background": c("bg0"),
        "editor.subheader.background": c("bg1"),
        "editor.active_line.background": c("bg1", 0.6),
        "editor.highlighted_line.background": c("bg1"),
        "drop_target.background": c("accent", 0.25),
        "search.match_background": c("accent", 0.3),
        "editor.document_highlight.read_background": c("bg2", 0.6),
        "editor.document_highlight.write_background": c("bg3", 0.6),
        # Elements.
        "element.background": c("bg1"),
        "element.hover": c("bg2"),
        "element.active": c("bg2"),
        "element.selected": c("bg2"),
        "element.disabled": c("bg1"),
        "ghost_element.background": clear,
        "ghost_element.hover": c("bg1"),
        "ghost_element.active": c("bg2"),
        "ghost_element.selected": c("bg2"),
        "ghost_element.disabled": clear,
        # Borders.
        "border": c("bg2"),
        "border.variant": c("bg1"),
        "border.focused": c("accent"),
        "border.selected": c("accent"),
        "border.disabled": c("bg1"),
        "border.transparent": clear,
        "pane.focused_border": c("accent"),
        "panel.focused_border": c("accent"),
        # Text.
        "text": c("fg1"),
        "text.muted": c("fg4"),
        "text.placeholder": c("comment"),
        "text.disabled": c("comment"),
        "text.accent": c("accent"),
        "editor.foreground": c("fg1"),
        "editor.line_number": c("comment"),
        "editor.active_line_number": c("fg1"),
        "editor.hover_line_number": c("fg4"),
        "editor.invisible": c("bg3"),
        "editor.wrap_guide": c("bg2", 0.5),
        "editor.active_wrap_guide": c("bg3"),
        "link_text.hover": c("accent"),
        # Icons.
        "icon": c("fg1"),
        "icon.muted": c("fg4"),
        "icon.disabled": c("comment"),
        "icon.placeholder": c("comment"),
        "icon.accent": c("accent"),
        # Scrollbar.
        "scrollbar.thumb.background": c("fg4", 0.25),
        "scrollbar.thumb.hover_background": c("fg4", 0.4),
        "scrollbar.thumb.border": clear,
        "scrollbar.track.background": clear,
        "scrollbar.track.border": c("bg1"),
        # Terminal. The sixteen slots go straight across; `dim_*` is this
        # repo's derivation, blended toward the background, because Zed asks
        # for a third axis the palette does not have.
        "terminal.background": c("bg0"),
        "terminal.foreground": c("fg1"),
        "terminal.bright_foreground": c("fg0"),
        "terminal.dim_foreground": c("fg4"),
    }

    ansi = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    for name in ansi:
        style[f"terminal.ansi.{name}"] = c(name)
        style[f"terminal.ansi.bright_{name}"] = c("br" + name.capitalize())
        style[f"terminal.ansi.dim_{name}"] = mix(name, "bg0", 0.4)

    # Every status role is a triad: the colour, a wash of it, and a border.
    for key, role in [
        ("error", "errColor"),
        ("warning", "warnColor"),
        ("success", "okColor"),
        ("info", "infoColor"),
        ("conflict", "warnColor"),
        ("created", "okColor"),
        ("deleted", "errColor"),
        ("modified", "warnColor"),
        ("renamed", "infoColor"),
        ("hidden", "comment"),
        ("hint", "infoColor"),
        ("ignored", "comment"),
        ("predictive", "comment"),
        ("unreachable", "comment"),
    ]:
        style[key] = c(role)
        style[f"{key}.background"] = c(role, 0.15)
        style[f"{key}.border"] = c(role, 0.4)

    style["version_control.added"] = c("okColor")
    style["version_control.deleted"] = c("errColor")
    style["version_control.modified"] = c("warnColor")

    # Collaborator colours. Eight, rotating through the palette's own accents
    # so two people are never the same colour.
    player_roles = [
        "accent",
        "brBlue",
        "brGreen",
        "brYellow",
        "brMagenta",
        "brCyan",
        "brRed",
        "fg4",
    ]
    style["players"] = [
        {"cursor": c(r), "background": c(r), "selection": c(r, 0.24)} for r in player_roles
    ]

    def syn(role, style_=None, weight=None):
        return {"color": c(role), "font_style": style_, "font_weight": weight}

    syntax = {
        "comment": syn("comment", "italic"),
        "comment.doc": syn("comment", "italic"),
        "keyword": syn("red"),
        "operator": syn("fg4"),
        "punctuation": syn("fg4"),
        "punctuation.bracket": syn("fg4"),
        "punctuation.delimiter": syn("fg4"),
        "punctuation.list_marker": syn("brCyan"),
        "punctuation.special": syn("brRed"),
        "string": syn("green"),
        "string.escape": syn("brGreen"),
        "string.regex": syn("brGreen"),
        "string.special": syn("brCyan"),
        "string.special.symbol": syn("brCyan"),
        "number": syn("magenta"),
        "boolean": syn("magenta"),
        "constant": syn("magenta"),
        "function": syn("brGreen"),
        "function.builtin": syn("brGreen"),
        "type": syn("brYellow"),
        "enum": syn("brYellow"),
        "variant": syn("brYellow"),
        "constructor": syn("brYellow"),
        "namespace": syn("brYellow"),
        "variable": syn("fg1"),
        "variable.special": syn("brBlue"),
        "property": syn("blue"),
        "attribute": syn("brBlue"),
        "label": syn("brBlue"),
        "selector": syn("brBlue"),
        "selector.pseudo": syn("brBlue"),
        "tag": syn("red"),
        "preproc": syn("fg1"),
        "primary": syn("fg1"),
        "embedded": syn("fg1"),
        "hint": syn("comment", "italic"),
        "predictive": syn("comment", "italic"),
        "link_text": syn("magenta", "italic"),
        "link_uri": syn("brCyan", "italic"),
        "title": syn("brGreen", None, 700),
        "emphasis": syn("brBlue", "italic"),
        "emphasis.strong": syn("brBlue", None, 700),
        "text.literal": syn("brCyan"),
    }

    if len(style) != STYLE_KEYS:
        sys.exit(
            f"zed-theme: wrote {len(style)} style keys, Zed's own theme has {STYLE_KEYS}. "
            f"A key this file omits falls back to Zed's default and looks merely unstyled."
        )
    if len(syntax) != SYNTAX_KEYS:
        sys.exit(
            f"zed-theme: wrote {len(syntax)} syntax keys, Zed's own theme has {SYNTAX_KEYS}."
        )
    if len(style["players"]) != PLAYERS:
        sys.exit(f"zed-theme: wrote {len(style['players'])} players, Zed's own theme has {PLAYERS}.")

    style["syntax"] = syntax
    theme = {
        "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
        "name": scheme,
        "author": "generated from modules/home/palette.nix",
        "themes": [
            {
                "name": scheme,
                "appearance": "dark",
                "accents": [c(r) for r in player_roles],
                "style": style,
            }
        ],
    }
    with open(sys.argv[3], "w", encoding="utf-8") as fh:
        json.dump(theme, fh, indent=2)
        fh.write("\n")
    print(f"zed-theme: {len(style) - 1} style keys, {len(syntax)} syntax keys")


if __name__ == "__main__":
    main()
