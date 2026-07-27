#!/bin/bash
# Bluetooth manager menu

WALKER=(~/.config/mango/scripts/walker/walker.sh -d)

BT=$'\uf294 '    # fa-bluetooth
SCAN=$'\uf021 '  # fa-refresh
CHECK=$'\uf00c ' # fa-check
GEAR=$'\uf013 '  # fa-cog

SEP_CONNECTED=$'── Connected ──────────────'
SEP_PAIRED=$'── Paired ─────────────────'
SEP_AVAILABLE=$'── Available ──────────────'

# ── Cache ──────────────────────────────────────────────────────────────
BT_PAIRED_CACHE="/tmp/bt-paired.cache"
BT_ALL_CACHE="/tmp/bt-all.cache"

# Kick off background refresh so next open gets current data
bluetoothctl devices Paired > "$BT_PAIRED_CACHE" 2>/dev/null &
bluetoothctl devices        > "$BT_ALL_CACHE"    2>/dev/null &

# ── State ─────────────────────────────────────────────────────────────
power=$(bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2}')

if [ "$power" = "yes" ]; then
    toggle_entry="${BT}  Bluetooth  ·  on"
    scan_entry="${SCAN}  Scan (10s)"
else
    toggle_entry="${BT}  Bluetooth  ·  off"
    scan_entry=""
fi

# ── Device lists ───────────────────────────────────────────────────────
declare -A connected_macs paired_macs entry_to_mac
connected_list=""
paired_list=""
available_list=""

if [ "$power" = "yes" ]; then
    # Which MACs are currently connected (always live — fast D-Bus call)
    while IFS= read -r line; do
        mac=$(awk '{print $2}' <<< "$line")
        [ -n "$mac" ] && connected_macs["$mac"]=1
    done < <(bluetoothctl devices Connected 2>/dev/null)

    # Paired devices — read from cache; fall back to live query
    paired_src="$( [ -s "$BT_PAIRED_CACHE" ] && cat "$BT_PAIRED_CACHE" \
                   || bluetoothctl devices Paired 2>/dev/null )"
    while IFS= read -r line; do
        mac=$(awk '{print $2}' <<< "$line")
        name=$(cut -d' ' -f3- <<< "$line")
        [ -z "$mac" ] && continue
        paired_macs["$mac"]=1

        if [ "${connected_macs[$mac]:-0}" = "1" ]; then
            batt=$(bluetoothctl info "$mac" 2>/dev/null | \
                awk '/Battery Percentage:/{gsub(/[^0-9]/,"",$NF); print $NF}')
            [ -n "$batt" ] \
                && entry="${CHECK}  ${name}  ·  ${batt}%" \
                || entry="${CHECK}  ${name}  ·  connected"
            entry_to_mac["$entry"]="${mac}|${name}"
            connected_list+="${entry}"$'\n'
        else
            entry="${BT}  ${name}"
            entry_to_mac["$entry"]="${mac}|${name}"
            paired_list+="${entry}"$'\n'
        fi
    done <<< "$paired_src"

    # Available — discovered but not paired; read from cache
    all_src="$( [ -s "$BT_ALL_CACHE" ] && cat "$BT_ALL_CACHE" \
                || bluetoothctl devices 2>/dev/null )"
    while IFS= read -r line; do
        mac=$(awk '{print $2}' <<< "$line")
        name=$(cut -d' ' -f3- <<< "$line")
        [ -z "$mac" ] && continue
        [ "${paired_macs[$mac]:-0}" = "1" ] && continue
        entry="${BT}  ${name}"
        [[ -v "entry_to_mac[$entry]" ]] && entry="${BT}  ${name}  (${mac: -5})"
        entry_to_mac["$entry"]="${mac}|${name}|new"
        available_list+="${entry}"$'\n'
    done <<< "$all_src"
fi

# ── Build menu ─────────────────────────────────────────────────────────
menu="${toggle_entry}"$'\n'
[ -n "$scan_entry"     ] && menu+="${scan_entry}"$'\n'
[ -n "$connected_list" ] && menu+="${SEP_CONNECTED}"$'\n'"${connected_list}"
[ -n "$paired_list"    ] && menu+="${SEP_PAIRED}"$'\n'"${paired_list}"
[ -n "$available_list" ] && menu+="${SEP_AVAILABLE}"$'\n'"${available_list}"
menu+="──────────────────────────"$'\n'
menu+="${GEAR}  Bluetooth manager"

# ── Show ───────────────────────────────────────────────────────────────
choice=$(printf '%s' "$menu" | "${WALKER[@]}" -p "$BT")
[ -z "$choice" ] && exit 0

# ── Handle ─────────────────────────────────────────────────────────────
case "$choice" in
    "$toggle_entry")
        [ "$power" = "yes" ] && bluetoothctl power off || bluetoothctl power on
        ;;
    "$scan_entry")
        notify-send -t 2000 "Bluetooth" "Scanning for 10 seconds…"
        bluetoothctl --timeout 10 scan on &>/dev/null &
        ;;
    "${GEAR}  Bluetooth manager")
        blueman-manager &
        ;;
    "──"*)
        exit 0
        ;;
    *)
        IFS='|' read -r mac dev_name is_new <<< "${entry_to_mac[$choice]}"
        [ -z "$mac" ] && exit 0

        if [ "${connected_macs[$mac]:-0}" = "1" ]; then
            bluetoothctl disconnect "$mac" && \
                notify-send "Bluetooth" "Disconnected from ${dev_name}" || \
                notify-send -u critical "Bluetooth" "Disconnect failed"
        elif [ "$is_new" = "new" ]; then
            notify-send -t 3000 "Bluetooth" "Pairing with ${dev_name}…"
            bluetoothctl pair "$mac" && \
            bluetoothctl trust "$mac" && \
            bluetoothctl connect "$mac" && \
                notify-send "Bluetooth" "Paired and connected to ${dev_name}" || \
                notify-send -u critical "Bluetooth" "Failed to pair with ${dev_name}"
        else
            bluetoothctl connect "$mac" && \
                notify-send "Bluetooth" "Connected to ${dev_name}" || \
                notify-send -u critical "Bluetooth" "Failed to connect to ${dev_name}"
        fi
        ;;
esac
