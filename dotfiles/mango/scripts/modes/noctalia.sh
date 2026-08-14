#!/usr/bin/env bash
# Noctalia mode — noctalia-shell replaces waybar and swaync. docs/adr/0020.
# The body is apply_mode() in ../lib.sh, as for tiling and hud.
. "$HOME/.config/mango/scripts/lib.sh"

# Seed, never own. noctalia rewrites settings.json itself (Commons/Settings.qml
# writes through a JsonAdapter), so no xdg.configFile may claim the path — two
# owners is an activation failure. `install -Dm644`, not `cp`: the source is a
# 0444 store file and cp would carry that mode across, the same trap apply_mode
# documents. Only the keys that would otherwise fight this machine are set; the
# rest come from the package's own Assets/settings-default.json, and noctalia's
# migrations all guard on the old key being present, so a partial file is safe —
# verified by running the shell against a scratch config, all 11 keys intact
# after the v0 -> v59 chain. `showChangelogOnStartup` and `notifyUpdates` stop
# the popup and the nag, NOT the GitHub fetch: nothing gates that. SYSTEM.md §13.
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/settings.json"
[ -f "$DEST" ] || install -Dm644 "$MANGO_DIR/noctalia/settings.json" "$DEST"

apply_mode noctalia
