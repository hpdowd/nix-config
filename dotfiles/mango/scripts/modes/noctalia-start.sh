#!/usr/bin/env bash
# The noctalia handover, called from noctalia/autostart.conf. Not `noctalia.sh`
# — that name is the mode entry point, which mode.sh resolves from the mode
# name; this runs later, from the autostart that entry point installs.
#
# Three `exec=` lines did this before 2026-08-15 and could not do it correctly,
# because the handover has an order and a failure path and separate exec= lines
# have neither:
#
#   Order. swaync must be dead before noctalia claims
#   org.freedesktop.Notifications. The second claimant of a DBus name does not
#   error, it just never receives a notification (docs/adr/0005).
#
#   Failure. The unit wedges easily: five crashes inside StartLimitIntervalSec
#   leaves it `failed` permanently, and every later start then refuses with
#   "attempted too often". `systemctl` does say so and exits 1 — but an `exec=`
#   line has no reader for either, so it lands nowhere and the mode switch
#   reports success. Observed on 2026-08-15: noctalia crash-looped against a
#   stale WAYLAND_DISPLAY, and every switch afterwards produced no bar and no
#   word. A mode that silently has neither a bar nor a notification daemon is
#   the worst outcome available here, so this keeps swaync when noctalia does
#   not come up, and says why.
set -u

# WAYBAR IS THE TILING BAR AGAIN (docs/adr/0051), so this is the live handover
# rather than the residue sweep it was between 2026-08-24 and 2026-08-26. See
# the note in tiling/autostart.conf for why it is not `-f`: waybar's cmdline
# carries no path, so an anchored pattern misses while an unanchored comm match
# finds the wrapper `.waybar-wrapped`.
pkill waybar 2>/dev/null

# awww is a BARE PROCESS again, not a unit. wayle spawned awww-daemon as its own
# child and `stop wayle` took it down with it; wallpaper-restore.sh starts it
# directly now, so it needs killing directly. Match comm with the wrapper's
# leading dot — `-x` misses `.awww-daemon-wr`, and `-f` would match this line.
pkill '^\.?awww-daemon' 2>/dev/null

# Still stopped, and still by unit: wayle is installed but no longer started by
# tiling/autostart.conf, so this only matters for a session that predates the
# switch or a wayle-restart.sh run by hand. `stop` is idempotent.
systemctl --user stop wayle 2>/dev/null

pkill -x dsearch 2>/dev/null
pkill -f '^swaync( |$)' 2>/dev/null

# Night light goes with the bar: this mode has no control that reaches wlsunset,
# so it ends it. docs/adr/0037. Every entry, not just a switch — the unit is
# WantedBy=graphical-session.target, so logging straight in here starts it.
#
# `stop`, not pkill: Restart=always would undo a kill in three seconds
# (docs/gotchas.md -> night light).
night_light_was_on=0
if systemctl --user is-active --quiet wlsunset; then
	night_light_was_on=1
	systemctl --user stop wlsunset
fi

# quickshell never removes an instance directory when the shell exits — it just
# reports them ("Dead instances:" is part of every failed `ipc call`). Each
# holds a socket, a lock and a log that reaches 1.5 MB, in $XDG_RUNTIME_DIR,
# which is a tmpfs: 18 of them were holding 11 MB of RAM on 2026-08-16.
#
# Liveness comes from by-pid/, which is quickshell's own index, so this makes no
# guess about the lock format. A recycled PID reads as alive and is simply not
# pruned — the safe direction, and the next start collects it.
QS_RUN="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell"
if [ -d "$QS_RUN/by-pid" ]; then
	for link in "$QS_RUN"/by-pid/*; do
		[ -e "$link" ] || continue
		pid=${link##*/}
		kill -0 "$pid" 2>/dev/null && continue
		target=$(readlink -f "$link") || continue
		# Only inside the tree, so a broken link can never widen this.
		case "$target" in
		"$QS_RUN"/*) rm -rf -- "$target" ;;
		esac
		rm -f -- "$link"
	done
	# by-shell/ and by-path/ are symlink indexes into by-id; the entries whose
	# targets just went are now dangling.
	find "$QS_RUN/by-shell" "$QS_RUN/by-path" -xtype l -delete 2>/dev/null
fi

# Clears a `start-limit-hit` left by an earlier attempt. Without it the mode is
# stuck until someone runs this by hand, which is not discoverable from a
# missing bar. Harmless on a unit that is running, absent or already clean.
systemctl --user reset-failed noctalia 2>/dev/null
systemctl --user start noctalia 2>/dev/null

# `start` returns as soon as the process is forked, so it says nothing about
# whether the shell survived contact with the compositor — quickshell aborts
# ~700 ms in when it cannot open the display. Wait for `active`, then confirm it
# is still active a moment later: a crash-looping unit is briefly active on
# every restart, and a single check catches it in exactly that window.
up=0
for _ in $(seq 1 20); do
	if systemctl --user is-active --quiet noctalia; then
		sleep 1.5
		systemctl --user is-active --quiet noctalia && up=1
		break
	fi
	sleep 0.5
done

if [ "$up" -eq 0 ]; then
	# Put the notification daemon back before trying to notify with it.
	swaync &
	sleep 0.5
	notify-send -u critical "Noctalia" \
		"Shell failed to start — swaync restored. See: systemctl --user status noctalia"
fi

# After the daemon question above, so there is something to notify with either
# way. Only when something was actually turned off.
if [ "$night_light_was_on" -eq 1 ]; then
	notify-send "Night light" "Off — it does not run in noctalia mode, and stays off when you switch back"
fi
