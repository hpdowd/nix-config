#!/usr/bin/env bash
# Waybar module: the active TLP power profile. Prints one JSON object.
#
# Reads TLP's own state file rather than /sys/firmware/acpi/platform_profile,
# which this used to poll. That attribute is a thinkpad_acpi dytc hint and is
# identical across all three profiles for every value the scheduler sees —
# governor, epp, min, max and boost do not move with it. It reported a mode
# that did not exist. docs/adr/0017.

PWRFILE=/run/tlp/last_pwr

if [ ! -r "$PWRFILE" ]; then
	printf '{"text":"?","tooltip":"TLP is not running — no active power profile","class":"unavailable"}\n'
	exit 0
fi

# "<profile> <power-source>", from tlp-func-base: PP_PRF=0 PP_BAL=1 PP_SAV=2,
# PS_AC=0 PS_BAT=1. Verified live against `tlp-stat -s` on both mains and
# battery. Anything else must render visibly rather than blank — an empty
# custom module is indistinguishable from an absent one.
read -r pp ps <"$PWRFILE"

# Escapes, not literal glyphs. Written literally on 2026-07-31 the characters
# were lost in transit and every branch assigned the empty string, so the module
# emitted {"text":""} and waybar drew nothing -- which is how it was reported:
# "I still don't see a power mode module". $'\UXXXXXXXX' keeps the source ASCII
# and puts the codepoint where checks/static.sh can read it.
#
# NOT A BOLT. `performance` was nf-fa-bolt until 2026-08-28, sitting one module
# to the left of a battery whose charging art is a bolt inside a battery \u2014 two
# bolts 30px apart, and the red one meant the CPU governor. A gauge cannot be
# misread as charge state. docs/adr/0057.
#
# `class` must stay a single word: waybar splits it on whitespace, so
# "unknown (9)" becomes the two classes `unknown` and `(9)` and matches no rule
# in style-solid.css. The code goes in the tooltip instead.
case "$pp" in
0) name=performance class=performance icon=$'\U000F0874' ;;                      # nf-md-gauge_full
1) name=balanced class=balanced icon=$'\U000F029A' ;;                            # nf-md-gauge
2) name=fanless class=fanless icon=$'\U000F032A' ;;                              # nf-md-leaf
*) name="unknown (profile code ${pp:-none})" class=unknown icon=$'\U000F02D7' ;; # nf-md-help_circle
esac

case "$ps" in
0) src="mains" ;;
1) src="battery" ;;
*) src="unknown supply" ;;
esac

# The fanless profile is the one that overrides the charger, so say what it is
# holding — "power-saver on mains" otherwise reads like a bug.
if [ "$pp" = 2 ]; then
	tip="Power profile: fanless — 1.1 GHz cap, no boost, iGPU pinned low (on $src)"
else
	tip="Power profile: $name (on $src)"
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$icon" "$tip" "$class"
