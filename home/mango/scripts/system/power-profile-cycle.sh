#!/usr/bin/env bash
# Cycle the ACPI platform profile: low-power -> balanced -> performance -> …
#
# Rewritten 2026-07-30. This used `powerprofilesctl`, which does not exist on
# this system — power-profiles-daemon is disabled in modules/system/power.nix
# because it conflicts with TLP, so every click ran a missing binary and did
# nothing at all.
#
# The write needs group permission: a systemd.tmpfiles rule in power.nix
# chgrp's the attribute to `wheel` and makes it group-writable — the same
# pattern the micmute LED uses in modules/system/audio.nix.
#
# Pass a profile name to set it directly: power-profile-cycle.sh low-power

PROFILE_FILE=/sys/firmware/acpi/platform_profile

[ -w "$PROFILE_FILE" ] || {
    notify-send -u critical "Power profile" "$PROFILE_FILE is not writable" 2>/dev/null
    exit 1
}

if [ -n "$1" ]; then
    next="$1"
else
    case "$(cat "$PROFILE_FILE")" in
        low-power)   next=balanced ;;
        balanced)    next=performance ;;
        performance) next=low-power ;;
        *)           next=balanced ;;
    esac
fi

echo "$next" > "$PROFILE_FILE" || exit 1

# Repaint the waybar module immediately rather than waiting for its interval.
pkill -RTMIN+11 waybar
