#!/usr/bin/env bash
# VPN menu — WireGuard + PIA OpenVPN server picker

. "$HOME/.config/mango/scripts/lib.sh"

WALKER=("$MANGO_DIR/scripts/walker/walker.sh" -d)
OVPN_DIR="$HOME/Downloads/openvpn"
VPN_STATE="/run/user/$(id -u)/mango-vpn"

# sops installs these mode 0400, so there is no in-session setter any more —
# credentials change in secrets/secrets.yaml. See docs/adr/0012.
PIA_USER_FILE=/run/secrets/pia/username
PIA_PASS_FILE=/run/secrets/pia/password

SHIELD=$'\uf132 '
GLOBE=$'\uf0ac  '
SEP=$'────────────────────────'

# ── Collect state ──────────────────────────────────────────────────────
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

nmcli -t -f NAME,TYPE,STATE con show --active >"$tmpdir/active" 2>/dev/null &
nmcli -t -f NAME,TYPE con show >"$tmpdir/all" 2>/dev/null &
wait

# ── Parse active VPNs ──────────────────────────────────────────────────
declare -A active_vpn
while IFS= read -r line; do
  name=$(awk -F: '{gsub(/\\:/,":",$1); print $1}' <<<"$line")
  type=$(awk -F: '{print $2}' <<<"$line")
  [[ "$type" == "vpn" || "$type" == "wireguard" ]] && active_vpn["$name"]=1
done <"$tmpdir/active"

# ── Parse all configured VPN connections ──────────────────────────────
declare -A vpn_entry_map
vpn_list=""
while IFS= read -r line; do
  name=$(awk -F: '{gsub(/\\:/,":",$1); print $1}' <<<"$line")
  type=$(awk -F: '{print $2}' <<<"$line")
  [[ "$type" == "vpn" || "$type" == "wireguard" ]] || continue
  [ -z "$name" ] && continue
  if [ "${active_vpn[$name]:-0}" = "1" ]; then
    entry="${SHIELD} ${name}  ·  on"
  else
    entry="${SHIELD} ${name}"
  fi
  vpn_entry_map["$entry"]="$name"
  vpn_list+="${entry}"$'\n'
done <"$tmpdir/all"

# ── Build PIA server list ──────────────────────────────────────────────
declare -A pia_entry_map
pia_list=""
if [ -d "$OVPN_DIR" ]; then
  while IFS= read -r f; do
    name=$(basename "$f" .ovpn)
    label=$(echo "$name" | sed 's/_/ /g; s/\b\(.\)/\u\1/g')
    entry="${GLOBE}${label}"
    pia_entry_map["$entry"]="$f"
    pia_list+="${entry}"$'\n'
  done < <(find "$OVPN_DIR" -name "*.ovpn" | sort)
fi

# ── Build menu ─────────────────────────────────────────────────────────
menu=""
[ -n "$vpn_list" ] && menu+="$vpn_list"
if [ -n "$vpn_list" ] && [ -n "$pia_list" ]; then
  menu+="${SEP}"$'\n'
fi
menu+="$pia_list"
menu="${menu%$'\n'}"

# ── Show ───────────────────────────────────────────────────────────────
choice=$(printf '%s' "$menu" | "${WALKER[@]}" -p "${SHIELD}")
[ -z "$choice" ] && exit 0

# ── Helpers ────────────────────────────────────────────────────────────
ensure_credentials() {
  if [ -r "$PIA_USER_FILE" ] && [ -r "$PIA_PASS_FILE" ]; then
    return 0
  fi
  notify-send -u critical "VPN" "PIA credentials missing — add them to secrets/secrets.yaml and rebuild"
  return 1
}

disconnect_all() {
  nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null \
    | awk -F: '($2=="wireguard"||$2=="vpn") && $3=="activated"{print $1}' \
    | while IFS= read -r n; do nmcli con down "$n" &>/dev/null; done
}

# ── Handle ─────────────────────────────────────────────────────────────
case "$choice" in

"$SEP")
  exit 0
  ;;

*)
  # Existing NM VPN connection
  if [ -n "${vpn_entry_map[$choice]+x}" ]; then
    name="${vpn_entry_map[$choice]}"
    if [ "${active_vpn[$name]:-0}" = "1" ]; then
      if nmcli con down "$name"; then
        notify-send "VPN" "Disconnected: ${name}"
      else
        notify-send -u critical "VPN" "Disconnect failed"
      fi
    else
      disconnect_all
      if nmcli con up "$name"; then
        echo "$name" > "$VPN_STATE"
        notify-send "VPN" "Connected: ${name}"
      else
        notify-send -u critical "VPN" "Connection failed"
      fi
    fi
    pkill -RTMIN+10 waybar

  # PIA OpenVPN server
  elif [ -n "${pia_entry_map[$choice]+x}" ]; then
    ovpn_file="${pia_entry_map[$choice]}"
    conn_name=$(basename "$ovpn_file" .ovpn)

    ensure_credentials || exit 0
    user=$(<"$PIA_USER_FILE")
    pass=$(<"$PIA_PASS_FILE")

    disconnect_all

    # Import into NM if not already present
    if ! nmcli -t -f NAME con show 2>/dev/null | grep -qxF "$conn_name"; then
      notify-send "VPN" "Importing ${conn_name}…"
      if ! nmcli connection import type openvpn file "$ovpn_file" &>/dev/null; then
        notify-send -u critical "VPN" "Failed to import ${conn_name}"
        exit 1
      fi
    fi

    # Set credentials
    nmcli con modify "$conn_name" +vpn.data "username=${user}" &>/dev/null
    nmcli con modify "$conn_name" +vpn.data "password-flags=0" &>/dev/null
    nmcli con modify "$conn_name" vpn.secrets "password=${pass}" &>/dev/null

    notify-send "VPN" "Connecting to ${conn_name}…"
    if nmcli con up "$conn_name"; then
      echo "$conn_name" > "$VPN_STATE"
      notify-send "VPN" "Connected: ${conn_name}"
    else
      notify-send -u critical "VPN" "Connection failed: ${conn_name}"
    fi
    pkill -RTMIN+10 waybar
  fi
  ;;
esac
