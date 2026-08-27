#!/usr/bin/env bash
# WireGuard VPN status/toggle. Emits waybar's `{text,class,tooltip}` JSON, which
# wayle reads unchanged — the format outlived the bar. docs/adr/0045.

VPN_STATE="/run/user/$(id -u)/mango-vpn"
DEFAULT_VPN="homelab"

case "$1" in
toggle)
	active=$(nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null |
		awk -F: '($2=="wireguard"||$2=="vpn") && $3=="activated"{print $1; exit}')
	if [ -n "$active" ]; then
		nmcli con down "$active" &>/dev/null
	else
		target=$(cat "$VPN_STATE" 2>/dev/null)
		[ -z "$target" ] && target="$DEFAULT_VPN"
		nmcli con up "$target" &>/dev/null
	fi
	# custom/vpn declares `signal = 10` and polls every 5 s. `|| true` because
	# the same script runs in noctalia mode, where the pkill matches nothing.
	# docs/adr/0056.
	pkill -RTMIN+10 waybar 2>/dev/null || true
	;;
*)
	active=$(nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null |
		awk -F: '($2=="wireguard"||$2=="vpn") && $3=="activated"{print $1; exit}')
	if [ -n "$active" ]; then
		printf '{"text":"󰕥 %s","class":"connected","tooltip":"VPN: %s — click to disconnect"}\n' \
			"$active" "$active"
	else
		target=$(cat "$VPN_STATE" 2>/dev/null)
		[ -z "$target" ] && target="$DEFAULT_VPN"
		printf '{"text":"󰕥","class":"off","tooltip":"VPN: off — click to connect %s"}\n' "$target"
	fi
	;;
esac
