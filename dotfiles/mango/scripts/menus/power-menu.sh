#!/usr/bin/env bash

CHOICE=$(printf "lock\nsuspend\nreboot\nshutdown\nlogout" | \
    rofi -dmenu -no-custom -p "power") || exit 0

case "$CHOICE" in
    lock)     lockscreen -f ;;
    suspend)  systemctl suspend ;;
    reboot)   systemctl reboot ;;
    shutdown) systemctl poweroff ;;
    logout)   mmsg dispatch quit ;;
esac
