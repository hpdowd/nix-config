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
	# No `pkill -RTMIN+10 waybar`: wayle takes no signal, and that line matched
	# nothing and returned 1. custom-vpn re-reads through `on-action`.
	;;
*)
	active=$(nmcli -t -f NAME,TYPE,STATE con show --active 2>/dev/null |
		awk -F: '($2=="wireguard"||$2=="vpn") && $3=="activated"{print $1; exit}')
	if [ -n "$active" ]; then
		printf '{"text":"󰕥  %s","class":"connected","tooltip":"VPN: %s — click to disconnect"}\n' \
			"$active" "$active"
	else
		target=$(cat "$VPN_STATE" 2>/dev/null)
		[ -z "$target" ] && target="$DEFAULT_VPN"
		printf '{"text":"󰕥 ","class":"","tooltip":"VPN: off — click to connect %s"}\n' "$target"
	fi
	;;
esac
