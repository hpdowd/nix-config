#!/usr/bin/env bash

CHOICE=$(printf "lock\nsuspend\nreboot\nshutdown\nlogout" | \
    ~/.config/mango/scripts/walker/walker.sh --dmenu --placeholder "power" \
        --width 160 --maxheight 120) || exit 0

case "$CHOICE" in
    lock)     lockscreen -f ;;
    suspend)  systemctl suspend ;;
    reboot)   systemctl reboot ;;
    shutdown) systemctl poweroff ;;
    logout)   mmsg dispatch quit ;;
esac
