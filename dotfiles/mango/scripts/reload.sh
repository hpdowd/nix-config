#!/usr/bin/env bash

# Refuse to run as root. Under sudo, `~` becomes /root, so this fails with
# "/root/.config/mango/scripts/mode.sh: No such file or directory" and then
# "MANGO_INSTANCE_SIGNATURE is not set" — errors that read like a broken
# install rather than "you used sudo". Worse, if root did have a config tree,
# the mode script would write root-owned files into it and break the next
# ordinary run. mmsg also has to talk to the compositor as the user owning the
# session, so root cannot do anything useful here anyway.
if [ "$(id -u)" -eq 0 ]; then
	echo "reload.sh: run as your normal user, not root — mango runs in your session." >&2
	exit 1
fi

~/.config/mango/scripts/mode.sh

# `mmsg dispatch reload_config`, not `mmsg -s -d reload_config`.
#
# The old form printed `{"error":"unknown command"}` and exited 0, so this
# script reported success while never reloading anything — every "reload" was
# really just the mode script rewriting config.conf, with the compositor still
# running the old configuration until the next logout. The `-s -d` flags are
# from an older, dwl-style mmsg; the current CLI (`mmsg --help`) has exactly
# three verbs: get, dispatch, watch. Compositor functions go through dispatch.
#
# Fixed 2026-07-31. Verify with the return value, which is the only signal:
# `{"success":true}` versus `{"error":"unknown command"}`.
mmsg dispatch reload_config

# Nothing to restart after this. Until 2026-08-14 the reload also had to bounce
# the elephant daemon, because walker could not draw a window without it — see
# docs/adr/0021. rofi has no daemon: every menu is a fresh process that reads
# ~/.config/rofi/config.rasi on the way up, so a rebuild is the whole reload.
