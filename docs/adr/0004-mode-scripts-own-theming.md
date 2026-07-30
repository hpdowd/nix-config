# 0004 — Mode scripts own theming; no `active-theme` indirection

**Status:** Accepted (2026-07-30)

## Context

Theming is driven by the Mangowm mode scripts in
`home/mango/scripts/modes/`. Terminals used to reach their palette through an
indirection: `kitty/active-theme.conf` and `foot/active-theme.ini` were symlinks
that each mode script rewrote on every switch.

The indirection **selected nothing**. Both `tiling.sh` and `hud.sh` pointed the
symlinks at the *same* gruvbox files, and `kitty.conf` was including its theme
twice as a result. It had been meaningful only while the removed `dms` mode
carried its own palette.

It also cost something concrete: a config directory containing a symlink that
gets rewritten at runtime must stay writable, and therefore out of the store.

Separately, home-manager's `gtk` block and `mango/scripts/system/gtk-apply.sh`
both write the same dconf keys, and home-manager reasserts its values on every
`nixos-rebuild switch` and at login — so declaring `gtk` in Nix silently reverts
whatever a mode switch just set.

## Decision

- Terminals name their theme directly. `kitty.conf` includes
  `gruvbox-orange.conf`; `foot.ini` includes `gruvbox-colors.ini`.
- Mode switching is the point of the setup, so **the scripts win**: the `gtk`
  block stays out of `modules/home/theme.nix`. Nix owns only what the scripts
  never touch — theme *packages*, the Qt platform theme, cursors.

## Consequences

- `kitty/` and `foot/` became store-based ([0002](0002-out-of-store-dotfiles.md)).
- Do not reintroduce `active-theme.*`. Naming the theme directly is what keeps
  those directories in the store.
- Do not add a `gtk` block to `theme.nix` without simultaneously stripping the
  `gsettings` lines from `gtk-apply.sh`. Doing one without the other produces a
  theme that reverts on rebuild, with nothing in any log.
