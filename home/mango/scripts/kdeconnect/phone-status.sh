#!/usr/bin/env bash
DEVICE="ca2da407b0d74e098414a3a0d76b1502"
DBUS_SVC="org.kde.kdeconnect"
DBUS_DEV="/modules/kdeconnect/devices/$DEVICE"

if ! pgrep -x kdeconnectd >/dev/null 2>&1; then
    echo '{"text":"","tooltip":"KDE Connect not running","class":"offline"}'
    exit 0
fi

REACHABLE=$(qdbus $DBUS_SVC $DBUS_DEV org.kde.kdeconnect.device.isReachable 2>/dev/null)
if [ "$REACHABLE" != "true" ]; then
    echo '{"text":"","tooltip":"Galaxy S22+ (offline)","class":"disconnected"}'
    exit 0
fi

CHARGE=$(qdbus $DBUS_SVC "$DBUS_DEV/battery" charge 2>/dev/null)
CHARGING=$(qdbus $DBUS_SVC "$DBUS_DEV/battery" isCharging 2>/dev/null)

if [ -z "$CHARGE" ]; then
    echo '{"text":"","tooltip":"Galaxy S22+","class":"connected"}'
    exit 0
fi

if [ "$CHARGING" = "true" ]; then
    ICON="󰂄"
elif [ "$CHARGE" -ge 90 ]; then ICON="󰂂"
elif [ "$CHARGE" -ge 80 ]; then ICON="󰂁"
elif [ "$CHARGE" -ge 70 ]; then ICON="󰂀"
elif [ "$CHARGE" -ge 60 ]; then ICON="󰁿"
elif [ "$CHARGE" -ge 50 ]; then ICON="󰁾"
elif [ "$CHARGE" -ge 40 ]; then ICON="󰁽"
elif [ "$CHARGE" -ge 20 ]; then ICON="󰁼"
elif [ "$CHARGE" -ge 10 ]; then ICON="󰁻"
else ICON="󰂎"
fi

CLASS="connected"
[ "$CHARGE" -le 15 ] && CLASS="critical"
[ "$CHARGE" -le 30 ] && [ "$CLASS" != "critical" ] && CLASS="warning"

printf '%s\n' "{\"text\":\" $ICON $CHARGE%\",\"tooltip\":\"Galaxy S22+\\nBattery: $CHARGE%\",\"class\":\"$CLASS\"}"
