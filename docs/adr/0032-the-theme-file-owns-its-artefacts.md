# 0032 — The theme file owns its artefacts, and contrast is measured where it is drawn

**Status:** Accepted (2026-08-18)

Completes [0030](0030-the-scheme-is-a-file-not-an-option.md), whose last
consequence said moving the theme packages per-theme was *"the next commit, not
this one"*. This is that commit.

## Context

0030 made the palette switchable — one string in `modules/home/scheme.nix`,
thirteen colour consumers follow — and stopped there, because both schemes that
existed were Catppuccin Mocha and shared every non-colour artefact.

Adding Gruvbox and Nord removed that excuse. Those artefacts are not hex and the
palette cannot reach them: rendered SVG widget art, cursor bitmaps, compiled
SCSS, an icon set, a yazi flavor, and names other programs resolve internally
(noctalia, nvim's plugin, Zed's theme). They were spelled across `theme.nix`,
`pkgs/default.nix`, `dotfiles/Kvantum/kvantum.kvconfig`,
`dotfiles/mango/noctalia/settings-pinned.json`,
`dotfiles/nvim/lua/plugins/colorscheme.lua` and `gtk-apply.sh` — a six-file
migration with **no gate**, where every one fails by falling back to a default
that looks like a theme someone chose.

The contrast check 0030 introduced also turned out to be measuring two things
wrongly, both invisible because every value involved was individually plausible.

## Decision

**A theme file declares its artefacts, not just its colours.**

- `packages` — GTK, Kvantum, icon, cursor, yazi: a nixpkgs attribute plus the
  **theme directory name** the program resolves. Never construct that name:
  `catppuccin-mocha-mauve-standard`, `catppuccin-mocha-mauve-cursors` and
  `catppuccin-mocha-mauve` are spelled three ways from each other and from the
  attribute (`mochaMauve`); `nordic` ships `Nordic-darker` and `Nordic-Darker`
  in one package; `capitaine-cursors-themed` installs
  `Capitaine Cursors (Gruvbox)`, parentheses included.
- `apps` — noctalia, nvim and Zed, which hold a scheme's *name*.

`pkgs/default.nix` resolves the package names, reading the palette by `import`
for the same reason the lock ramp does: an overlay cannot see `config.*` (0030).

**Every shipped scheme is fully native.** `native = false` marks a stand-in and
nothing uses one. noctalia constrains the candidates to the ten it ships; nixpkgs
fully serves three — Catppuccin, Gruvbox, Nord. Ayu and Dracula were built,
gated, and dropped for three stand-ins each.

**nvim swaps the plugin** rather than overriding a foreign one
(`THEME-MIGRATION.md` §3). `lua/plugins/colorscheme.lua` and a names-only
`lua/config/scheme.lua` are generated; `lazy.lua` and `ui.lua` read the latter.
`lua/config/palette.lua` is generated only for a theme that deviates from its own
plugin.

**Two contrast floors, no minimum under them.** `contrastFloor` for what this
machine draws text with, `ansiFloor` for the terminal slots. `HARD_MIN = 3.0` is
removed as an invention: it arrived with `mocha-high-contrast` out of a request
for readable text and then read like an external requirement. It would have
forbidden Nord, at 1.69:1 as published. The rule instead: **upstream values ship
as published; values this repo derives are chosen to be legible.**

## Consequences

- Switching to a scheme from another family is one line and a rebuild, gated.
  All four schemes pass `nix flake check`.
- **Four roles were never audited.** The check read hex with `sed`, so
  `okColor = green;` read as "role absent" — all four status roles, in every
  theme. It now receives the palette **resolved by Nix**. That also retired
  `mauve`, a key only the check ever read.
- **The live theme had an ncspot error row at 1.28:1.** `muted.err` is a
  *background* — ncspot draws `error_fg` (= `muted.fg`) on it — but the check
  measured it against `muted.surface`, a pair ncspot never draws, and reported
  7.05:1. **A check measuring the wrong two colours is worse than no check,
  because it reports a number.**
- **One combined floor forced a lie.** Gruvbox's normal red is 2.69:1 by
  upstream's design; a single floor would have been 2.6 for that scheme, letting
  `comment` rot to meet it.
- **The lock ramp had a rounding bug two schemes hid.** `blocks.py` interpolated
  three channels independently, trusting them to round alike; Python's `round()`
  is round-half-to-**even**, so `(5, 8, 14)` becomes `(6, 10, 16)` at `t=.25`. It
  diverges only when the half-case lands *and* parities differ — and no shipped
  scheme can expose it (Gruvbox three equal channels, Mocha and Nord three even
  ones), which is the argument for fixing it structurally rather than adding a
  case. One channel is interpolated now, the rest derived from fixed offsets.
- **And its checkPhase failed on a neutral palette.** ImageMagick picks a
  colorspace from content, so gruvbox's grey ramp wrote a Gray PNG whose green
  channel read 0. The earlier generalisation from `R = G = B` to per-channel
  offsets fixed the tinted case and opened the neutral one — both schemes it was
  tested against were tinted. `-type TrueColor` on write, `-colorspace sRGB` on
  measurement.
- **`Adwaita-dark` is unusable as a fallback because no check can see it.** GTK3
  renders it from compiled-in resources and no directory for it exists. Found
  because the package check verifies toolkit built-ins rather than waving them
  through; the finding outlived the schemes that needed a fallback.
- `gtk-apply.sh` reads the theme name out of the generated `settings.ini` rather
  than carrying a literal. It exports `GTK_THEME`, so a stale copy would have
  overridden the correct setting for every later user service.
- Two generated files got scheme-neutral names, since a name embedding the scheme
  is wrong for all but one: `scheme.theme.css` (Equibop — moved in `lib.sh` in
  the same change, because Equibop ignores a missing theme **without logging**)
  and `scheme` (yazi).
- **Zed is the one pair no check can gate** — extension id and theme name both
  live in Zed's registry. Verify by opening it.
- Cost: a theme file is roughly twice the size. And requiring native artefacts is
  what cut ten candidates to three — adding a fourth means packaging something,
  not writing a theme file. Rose Pine needs one GTK theme.
