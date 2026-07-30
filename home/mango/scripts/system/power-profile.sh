#!/usr/bin/env bash
# Waybar module: current ACPI platform profile. Prints one JSON object.
#
# Replaces waybar's built-in `power-profiles-daemon` module, which was dead on
# this system: that module binds the net.hadess.PowerProfiles D-Bus API, and
# power-profiles-daemon is deliberately disabled in modules/system/power.nix
# because it conflicts with TLP. `busctl --system list` shows nothing
# implementing that API, so the module had nothing to talk to and rendered
# empty — which reads as "the module is missing from the bar".
#
# The ThinkPad exposes the same three states through the kernel directly:
#   /sys/firmware/acpi/platform_profile_choices -> low-power balanced performance
# so this reads that instead and needs no daemon at all. Note the ACPI name is
# `low-power`, not power-profiles-daemon's `power-saver`.

PROFILE_FILE=/sys/firmware/acpi/platform_profile

if [ ! -r "$PROFILE_FILE" ]; then
    printf '{"text":"","tooltip":"No ACPI platform profile on this machine","class":"unavailable"}\n'
    exit 0
fi

profile=$(cat "$PROFILE_FILE")

case "$profile" in
    performance) icon="" ;;   # nf-fa-bolt
    balanced)    icon="" ;;   # nf-fa-adjust
    low-power)   icon="" ;;   # nf-fa-battery_empty
    *)           icon="" ;;   # nf-fa-question
esac

printf '{"text":"%s","tooltip":"Power profile: %s","class":"%s"}\n' \
    "$icon" "$profile" "$profile"
