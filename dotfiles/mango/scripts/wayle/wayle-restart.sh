#!/usr/bin/env bash
# Restarts wayle from the current desktop mode, layout and position state.
#
# Called by wayle-layout.sh and wayle-position.sh directly, and by the `exec=`
# line in tiling/autostart.conf — which fires at login and on every
# `mmsg dispatch reload_config`, so a reload re-reads all three state files.
# This is the single place that knows how they combine.
#
# THAT `exec=` IS ALSO HOW `mango-reload` AND A MODE SWITCH REACH THE BAR: both
# end in `reload_config` and neither calls this script. (The list above said
# `desktop-mode.sh` for a while — inherited from waybar-restart.sh, and never
# true of either.) `exec-once=` there would break all three paths at once, so
# checks/static.sh asserts the spelling.
#
# It only selects a file and re-points a link. Every (layout, position) pair is
# generated as its own TOML by modules/home/wayle.nix, because `bar.location`
# lives in the file and wayle takes no flag for it — the same reason waybar
# needed six configs. docs/adr/0045.
#
# ~/.config/wayle/config.toml is this script's, and no xdg.configFile may claim
# it: two owners for one path is an activation failure, not a merge. That is why
# `services.wayle.settings` is `{ }`, exactly as `programs.ncspot.settings` is.
# checks/static.sh asserts the path is absent from the generation.
set -u

. "$HOME/.config/mango/scripts/lib.sh"

# noctalia mode has its own shell. Every caller below would otherwise start
# wayle on top of it — including the two pickers, whose own guards fire before
# this one. Stop rather than merely return: this is also the path a switch into
# noctalia takes, so leaving a stale bar up would be the visible failure.
#
# `systemctl --user stop`, not pkill: the unit is the owner (docs/adr/0005), and
# stop is idempotent and harmless when the unit is already down.
if ! mode_has_bar; then
	systemctl --user stop wayle 2>/dev/null
	systemctl --user stop awww 2>/dev/null
	exit 0
fi

POSITION=$(bar_position)
LAYOUT=$(bar_layout)

SRC="$WAYLE_DIR/layouts/$LAYOUT-$POSITION.toml"

# A state file holding a typo would otherwise leave config.toml pointing at
# nothing, and wayle starts with its built-in defaults rather than erroring —
# a bar that renders, plausibly, and is not the one that was asked for.
if [ ! -f "$SRC" ]; then
	echo "wayle-restart: no layout for layout=$LAYOUT position=$POSITION," \
		"falling back to full/top" >&2
	notify-send -u critical "Wayle" "No layout '$LAYOUT-$POSITION' — using full/top"
	SRC="$WAYLE_DIR/layouts/full-top.toml"
fi

# Still missing means the generation itself is wrong, which a rebuild fixes and
# this script cannot. Refuse rather than start a default bar that looks like a
# theme regression.
if [ ! -f "$SRC" ]; then
	notify-send -u critical "Wayle" "No generated layouts at all — rebuild needed"
	exit 1
fi

# `ln -sfn`, and the link points at the ~/.config path rather than into the
# store, so it survives a rebuild: the target is itself a home-manager symlink
# and gets re-pointed there. Same shape as apply_theme's four links.
ln -sfn "$SRC" "$WAYLE_DIR/config.toml"

# Clears a `start-limit-hit` left by an earlier attempt. Without it the mode is
# stuck until someone runs this by hand, which is not discoverable from a
# missing bar — the failure noctalia-start.sh was written around.
systemctl --user reset-failed wayle 2>/dev/null

# The wallpaper engine is wayle's in this mode, so awww comes up with it.
# docs/adr/0045 — noctalia manages its own.
systemctl --user reset-failed awww 2>/dev/null
systemctl --user start awww 2>/dev/null

# `restart`, not `start`: this is also the reload path, and wayle reads
# config.toml once at startup. Restart starts a stopped unit too.
systemctl --user restart wayle 2>/dev/null

# The saved wallpaper, once wayle is answering. Backgrounded so a wallpaper
# that cannot be restored never holds up the bar — the script polls and reports
# for itself. docs/adr/0045.
"$MANGO_DIR/scripts/system/wallpaper-restore.sh" &
