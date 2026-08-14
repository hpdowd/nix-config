#!/usr/bin/env bash
# Network manager menu — WiFi, Ethernet, VPN
# Instant open via cache; rescan re-launches with fresh data.

MENU=(rofi -dmenu -no-custom)
CACHE=/tmp/network-menu-cache.txt

SEP=$'────────────────────────'
WIFI=$' '   # fa-wifi
LOCK=$' '   # fa-lock
SHIELD=$' ' # fa-shield (FA4)
NET=$' '    # fa-network-wired
SCAN=$' '   # fa-refresh
DISC=$' '   # fa-unlink
GEAR=$' '   # fa-cog
CHECK=$' '  # fa-check

# ── Build menu (data collection + formatting) ──────────────────────────
build_menu() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  nmcli radio wifi >"$tmpdir/wifi_state" 2>/dev/null &
  nmcli -t -f ACTIVE,SSID dev wifi >"$tmpdir/current_ssid" 2>/dev/null &
  nmcli -t -f DEVICE,TYPE,STATE dev >"$tmpdir/devices" 2>/dev/null &
  nmcli -t -f NAME,TYPE con show --active >"$tmpdir/vpn_active" 2>/dev/null &
  nmcli -t -f NAME,TYPE con show >"$tmpdir/vpn_all" 2>/dev/null &
  nmcli -t -f SSID,SIGNAL,ACTIVE dev wifi list 2>/dev/null |
    sort -t: -k2 -rn >"$tmpdir/wifi_list" &
  wait

  local wifi_state current_ssid eth_dev eth_info eth_name eth_ip eth_line
  wifi_state=$(cat "$tmpdir/wifi_state")
  current_ssid=$(awk -F: '/^yes:/{gsub(/\\:/,":",$2); print $2; exit}' "$tmpdir/current_ssid")

  eth_dev=$(awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}' "$tmpdir/devices")
  if [ -n "$eth_dev" ]; then
    eth_info=$(nmcli -t -f GENERAL.CONNECTION,IP4.ADDRESS dev show "$eth_dev" 2>/dev/null)
    eth_name=$(awk -F: '/^GENERAL\.CONNECTION:/{gsub(/\\:/,":",$2); print $2; exit}' <<<"$eth_info")
    eth_ip=$(awk -F: '/^IP4\.ADDRESS/{sub(/\/[0-9]+$/,"",$2); print $2; exit}' <<<"$eth_info")
    eth_line="${NET}  ${eth_name}  ·  ${eth_ip}"
  fi

  local wifi_toggle scan_entry disconnect_entry
  if [ "$wifi_state" = "enabled" ]; then
    wifi_toggle="${WIFI}  WiFi (on)"
    scan_entry="${SCAN}  Scan"
    [ -n "$current_ssid" ] && disconnect_entry="${DISC}  Disconnect  ·  ${current_ssid}"
  else
    wifi_toggle="${WIFI}  WiFi (off)"
  fi

  local wifi_list=""
  if [ "$wifi_state" = "enabled" ]; then
    wifi_list=$(awk -F: -v chk="$CHECK" '
      {
        ssid=$1; signal=$2; active=$3
        gsub(/\\:/, ":", ssid)
        if (ssid == "" || seen[ssid]++) next
        s = signal + 0
        if      (s >= 75) sig = "▪▪▪▪"
        else if (s >= 50) sig = "▪▪▪·"
        else if (s >= 25) sig = "▪▪··"
        else              sig = "▪···"
        mark = (active == "yes") ? "  " chk : ""
        printf "%s  %s%s\n", sig, ssid, mark
      }' "$tmpdir/wifi_list")
  fi

  local vpn_list=""
  declare -A active_vpns
  while IFS= read -r name; do
    [ -n "$name" ] && active_vpns["$name"]=1
  done < <(awk -F: '($2=="vpn"||$2=="wireguard"){gsub(/\\:/,":",$1); print $1}' "$tmpdir/vpn_active")

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if [ "${active_vpns[$name]:-0}" = "1" ]; then
      vpn_list+="${SHIELD}  ${name}  ·  on"$'\n'
    else
      vpn_list+="${SHIELD}  ${name}"$'\n'
    fi
  done < <(awk -F: '($2=="vpn"||$2=="wireguard"){gsub(/\\:/,":",$1); print $1}' "$tmpdir/vpn_all")

  local menu=""
  [ -n "$eth_line" ] && menu+="${eth_line}"$'\n'"${SEP}"$'\n'
  menu+="${wifi_toggle}"$'\n'
  [ -n "$scan_entry" ] && menu+="${scan_entry}"$'\n'
  [ -n "$disconnect_entry" ] && menu+="${disconnect_entry}"$'\n'
  [ -n "$wifi_list" ] && menu+="${SEP}"$'\n'"${wifi_list}"$'\n'
  [ -n "$vpn_list" ] && menu+="${SEP}"$'\n'"${vpn_list}"
  menu+="${SEP}"$'\n'"${GEAR}  Connection editor"

  printf '%s' "$menu"
}

# ── Modes ─────────────────────────────────────────────────────────────
case "$1" in
  --warm)
    build_menu >"$CACHE"
    exit 0
    ;;
  --reload)
    # Trigger rescan, rebuild cache with fresh data, then re-launch
    nmcli dev wifi rescan 2>/dev/null
    sleep 1.5
    build_menu >"$CACHE"
    exec "$0"
    ;;
esac

# ── Normal flow: show cached menu instantly, refresh in background ────
if [ -s "$CACHE" ]; then
  menu=$(cat "$CACHE")
  (build_menu >"$CACHE.new" && mv "$CACHE.new" "$CACHE") &
else
  menu=$(build_menu)
  echo "$menu" >"$CACHE"
fi

choice=$(printf '%s' "$menu" | "${MENU[@]}" -p "$WIFI")
[ -z "$choice" ] && exit 0

# ── Helpers for handling choice ───────────────────────────────────────
extract_ssid_from_entry() {
  # entry format: "▪▪▪▪  ${ssid}" or "▪▪▪▪  ${ssid}  ${CHECK}"
  local entry="$1"
  entry="${entry#* }"   # strip signal bars
  entry="${entry# }"    # strip leading spaces
  entry="${entry%"  ${CHECK}"}"  # strip trailing check mark if present
  printf '%s' "$entry"
}

extract_vpn_name() {
  # entry format: "${SHIELD}  ${name}" or "${SHIELD}  ${name}  ·  on"
  local entry="$1"
  entry="${entry#"${SHIELD}  "}"
  entry="${entry%  ·  on}"
  printf '%s' "$entry"
}

# ── Handle ────────────────────────────────────────────────────────────
case "$choice" in
  *"WiFi (on)"|*"WiFi (off)")
    state=$(nmcli radio wifi 2>/dev/null)
    if [ "$state" = "enabled" ]; then
      if nmcli radio wifi off; then
        notify-send "Network" "WiFi turned off"
      else
        notify-send -u critical "Network" "Failed to turn off WiFi"
      fi
    else
      if nmcli radio wifi on; then
        notify-send "Network" "WiFi turned on"
      else
        notify-send -u critical "Network" "Failed to turn on WiFi"
      fi
    fi
    ;;
  *"  Scan")
    notify-send -t 1500 "Network" "Scanning…"
    exec "$0" --reload
    ;;
  *"Disconnect  ·  "*)
    ssid="${choice##*Disconnect  ·  }"
    if nmcli con down "$ssid"; then
      notify-send "Network" "Disconnected from ${ssid}"
    else
      notify-send -u critical "Network" "Disconnect failed"
    fi
    ;;
  "$SEP")
    exit 0
    ;;
  *"Connection editor")
    nm-connection-editor &
    ;;
  "${SHIELD}  "*)
    name=$(extract_vpn_name "$choice")
    if nmcli -t -f NAME,TYPE con show --active | grep -qE "^${name}:(vpn|wireguard)$"; then
      if nmcli con down "$name"; then
        notify-send "Network" "VPN off: ${name}"
      else
        notify-send -u critical "Network" "VPN disconnect failed"
      fi
    else
      if nmcli con up "$name"; then
        notify-send "Network" "VPN on: ${name}"
      else
        notify-send -u critical "Network" "VPN connect failed"
      fi
    fi
    ;;
  *)
    # WiFi network entry
    ssid=$(extract_ssid_from_entry "$choice")
    [ -z "$ssid" ] && exit 0
    if nmcli connection show "$ssid" &>/dev/null; then
      # Saved network — try to connect, retry once on failure
      if ! nmcli connection up "$ssid" 2>/dev/null; then
        sleep 0.5
        if nmcli connection up "$ssid"; then
          notify-send "Network" "Connected to ${ssid}"
        else
          notify-send -u critical "Network" "Failed to connect to ${ssid}"
        fi
      else
        notify-send "Network" "Connected to ${ssid}"
      fi
    else
      # Unknown network — prompt for password
      # NOT "${MENU[@]}": this is the one prompt where the typed string is the
      # answer, so it must not carry `-no-custom` — with it, Enter returns
      # nothing and the connection attempt runs with an empty password. Empty
      # stdin is deliberate; rofi returns the input when no row matches.
      pass=$(printf '' | rofi -dmenu -password -p "${LOCK}  ${ssid}")
      [ -z "$pass" ] && exit 0
      if ! nmcli dev wifi connect "$ssid" password "$pass" 2>/dev/null; then
        sleep 0.5
        if nmcli dev wifi connect "$ssid" password "$pass"; then
          notify-send "Network" "Connected to ${ssid}"
        else
          notify-send -u critical "Network" "Failed to connect to ${ssid}"
        fi
      else
        notify-send "Network" "Connected to ${ssid}"
      fi
    fi
    ;;
esac
