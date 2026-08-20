#!/usr/bin/env bash

. "$HOME/.config/mango/scripts/lib.sh"

CHOICE=$(printf "lock\nsuspend\nreboot\nshutdown\nlogout" |
	rofi_menu 20 -no-custom -p "power") || exit 0

case "$CHOICE" in
lock) lockscreen -f ;;
suspend) systemctl suspend ;;
reboot) systemctl reboot ;;
shutdown) systemctl poweroff ;;
logout) mmsg dispatch quit ;;
esac
