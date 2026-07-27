#!/bin/bash
# Usage: night-mode.sh <toggle|menu|status>

TEMP_FILE="${XDG_RUNTIME_DIR:-/tmp}/night-mode-temp"
DEFAULT_TEMP=3700

get_temp() {
  cat "$TEMP_FILE" 2>/dev/null || echo "$DEFAULT_TEMP"
}

do_toggle() {
  if pgrep -x wlsunset >/dev/null; then
    pkill -x wlsunset
  else
    wlsunset -t 0 -T "$(get_temp)" &
  fi
  pkill -RTMIN+9 waybar
}

do_menu() {
  CHOICE=$(printf \
    "  2700K   Candlelight\n  3000K   Warm\n  3500K   Evening\n  3700K   Soft white\n  4500K   Neutral\n  6500K   (off)" |
    ~/.config/mango/scripts/walker/walker.sh -d -p "Night mode" --maxheight 220)

  [ -z "$CHOICE" ] && exit 0

  TEMP=$(echo "$CHOICE" | grep -oE '[0-9]+K' | tr -d 'K')
  [ -z "$TEMP" ] && exit 0

  echo "$TEMP" >"$TEMP_FILE"
  pkill -x wlsunset

  [ "$TEMP" != "6500" ] && do_toggle || pkill -RTMIN+9 waybar
}

do_status() {
  MOON=$(printf '\xef\x86\x86')
  if pgrep -x wlsunset >/dev/null; then
    printf '{"text":"%s ","class":"on"}\n' "$MOON"
  else
    printf '{"text":"%s ","class":"off"}\n' "$MOON"
  fi
}

case "$1" in
toggle) do_toggle ;;
menu) do_menu ;;
status) do_status ;;
*)
  echo "Usage: $0 <toggle|menu|status>"
  exit 1
  ;;
esac
