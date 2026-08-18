# The one palette — whichever scheme `./scheme.nix` names.
#
# This file used to BE the palette. It is now the dispatcher, and its interface
# is deliberately unchanged: it still evaluates to a flat `rec` attrset of bare
# hex, so all thirteen consumers and `pkgs/default.nix` read it exactly as
# before. That is the whole trick — adding scheme selection touched no consumer.
#
# THE KEY NAMES ARE GRUVBOX'S, and every theme file must supply all of them.
# They outlived the scheme that named them because thirteen consumers and
# `checks/static.sh` address colours by them; renaming is a separate change from
# recolouring. Where a name no longer describes its value — `magenta` is
# Catppuccin's *pink*, `cyan` its *teal* — the theme file says so in a comment.
#
# `rec` in each theme file matters: the semantic roles are defined in terms of
# the canonical ones, so a **missing key is an eval error** rather than a
# silently-default colour.
#
# To add a scheme: copy a file in `./themes/`, replace the values, point
# `scheme.nix` at it, and run `nix flake check` — which asserts every text role
# clears its contrast floor, so an unreadable scheme cannot land quietly. What
# this does NOT switch is the six theme *packages* (GTK, icons, cursor, Kvantum,
# noctalia, yazi); both current schemes are Catppuccin-hued and share them. A
# scheme from another family needs those moved per-theme too —
# `docs/THEME-MIGRATION.md` §2 is the list and `docs/adr/0030` the reasoning.
import ./themes/${import ./scheme.nix}.nix
