#!/usr/bin/env bash
# Volume menu — set volume, toggle mute, switch sinks, enable amplification

. "$HOME/.config/mango/scripts/lib.sh"

VOL=$'\U000F057E '   # nf-md-volume_high
MUTE=$'\U000F0581 '  # nf-md-volume_off
CHECK=$'\U000F012C ' # nf-md-check
GEAR=$'\U000F0493 '  # nf-md-cog
SEP=$'────────────────────────'

# ── Current state ──────────────────────────────────────────────────────
sink_info=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
# e.g. "Volume: 0.87" or "Volume: 1.20 [muted]"
vol_raw=$(awk '{print $2}' <<<"$sink_info")
muted=false
[[ "$sink_info" == *"[MUTED]"* ]] && muted=true

# Convert to integer percentage
vol_pct=$(awk "BEGIN{printf \"%d\", $vol_raw * 100}")

if $muted; then
	mute_entry="${MUTE}  Unmute  ·  (${vol_pct}%)"
else
	mute_entry="${MUTE}  Mute"
fi

# ── Sink list ──────────────────────────────────────────────────────────
declare -A sink_id_map sink_name_map
sink_list=""

while IFS= read -r line; do
	id=$(echo "$line" | grep -oP '^\s*\*?\s*\K[0-9]+')
	name=$(echo "$line" | sed 's/^\s*\*\?\s*[0-9]*\.\s*//' | sed 's/\s*\[.*\]$//' | xargs)
	[ -z "$id" ] || [ -z "$name" ] && continue
	is_default=false
	[[ "$line" == *"*"* ]] && is_default=true
	if $is_default; then
		entry="${CHECK}  ${name}"
	else
		entry="${VOL}  ${name}"
	fi
	sink_id_map["$entry"]="$id"
	sink_name_map["$entry"]="$name"
	sink_list+="${entry}"$'\n'
done < <(wpctl status 2>/dev/null | awk '/Sinks:/{found=1; next} found && /^\s*(Sources:|Sink endpoints:)/{exit} found && /^\s*[\*]?\s*[0-9]+\./{print}')

# ── Volume presets ─────────────────────────────────────────────────────
presets=""
for pct in 25 50 75 100 125 150; do
	if [ "$vol_pct" -eq "$pct" ] && ! $muted; then
		presets+="${CHECK}  ${pct}%"$'\n'
	else
		presets+="${VOL}  ${pct}%"$'\n'
	fi
done

# ── Build menu ─────────────────────────────────────────────────────────
menu="${mute_entry}"$'\n'
menu+="${SEP}"$'\n'
menu+="${presets}"
menu+="${SEP}"$'\n'
[ -n "$sink_list" ] && menu+="${sink_list}"
menu+="${SEP}"$'\n'
menu+="${GEAR}  Audio settings (pavucontrol)"

# ── Show ───────────────────────────────────────────────────────────────
choice=$(printf '%s' "$menu" | rofi_menu 20 -no-custom -p "${VOL} ${vol_pct}%")
[ -z "$choice" ] && exit 0

# ── Handle ─────────────────────────────────────────────────────────────
case "$choice" in
"$mute_entry")
	wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
	;;
"${VOL}  25%" | "${CHECK}  25%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.25 ;;
"${VOL}  50%" | "${CHECK}  50%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.50 ;;
"${VOL}  75%" | "${CHECK}  75%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.75 ;;
"${VOL}  100%" | "${CHECK}  100%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.00 ;;
"${VOL}  125%" | "${CHECK}  125%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.25 ;;
"${VOL}  150%" | "${CHECK}  150%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.50 ;;
"${GEAR}  Audio settings (pavucontrol)")
	pavucontrol &
	;;
"$SEP")
	exit 0
	;;
*)
	# Sink switch
	if [ -n "${sink_id_map[$choice]+x}" ]; then
		wpctl set-default "${sink_id_map[$choice]}" &&
			notify-send -t 2000 "Audio" "Output: ${sink_name_map[$choice]}"
	fi
	;;
esac
