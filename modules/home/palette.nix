# The one palette — whichever scheme `./scheme.nix` names.
#
# This file used to BE the palette. It is now the dispatcher, and its interface
# is deliberately unchanged where it can be: it still evaluates to a flat `rec`
# attrset of bare hex, so all thirteen colour consumers and `pkgs/default.nix`
# read it exactly as before.
#
# THE COLOUR KEY NAMES ARE GRUVBOX'S, and every theme file must supply all of
# them. They outlived the scheme that named them because thirteen consumers and
# `checks/static.sh` address colours by them; renaming is a separate change from
# recolouring. Where a name no longer describes its value — Catppuccin's
# `magenta` is its *pink*, `cyan` its *teal*; Nord's `magenta` slot holds its
# Purple — the theme file says so in a comment.
#
# `rec` in each theme file matters: the semantic roles are defined in terms of
# the canonical ones, so a **missing key is an eval error** rather than a
# silently-default colour.
#
# ── What a theme file declares ───────────────────────────────────────────────
#
#   contrastFloor   the ratio every role THIS MACHINE draws text with clears
#   ansiFloor       the ratio the sixteen terminal slots clear — a separate
#                   number because on gruvbox they are 2.69:1 by upstream's
#                   design, and one combined floor would drag the first down to
#                   meet it (docs/adr/0032)
#   the colours     canonical ramp, semantic roles, terminal aliases, `muted`
#   packages        GTK, Kvantum, icon, cursor and yazi artefacts, BY NAME
#   apps            noctalia, nvim and Zed, which hold a scheme's NAME rather
#                   than its colours
#
# `packages` and `apps` are the half the palette cannot reach: rendered SVG
# widget art, cursor bitmaps, compiled SCSS, and names other programs resolve
# internally. Before 2026-08-18 they were spelled out across theme.nix,
# pkgs/default.nix, two dotfiles and a shell script, which made a scheme change
# a six-file migration with no gate on getting it wrong. `pkgs/default.nix`
# resolves the package names; `checks/static.sh` asserts each one exists.
#
# `native = false` on a `packages` entry marks a STAND-IN: an artefact that does
# not follow this scheme at all, only a neutral that does not fight it. **No
# shipped scheme uses one.** That is the selection criterion rather than a happy
# accident — noctalia ships ten colour schemes and nixpkgs fully serves three of
# them (Catppuccin, Gruvbox, Nord), so those are the three here. The marker and
# the check that counts them stay, for whatever is added next.
#
# ── Adding a scheme ─────────────────────────────────────────────────────────
#
# Copy a file in `./themes/`, replace the values, point `scheme.nix` at it, and
# run `nix flake check` — which asserts every text role clears its declared
# floor and every artefact it names resolves, so an unreadable or half-packaged
# scheme cannot land quietly. `docs/THEME-MIGRATION.md` is the runbook.
import ./themes/${import ./scheme.nix}.nix
