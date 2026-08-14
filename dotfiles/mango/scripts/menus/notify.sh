#!/usr/bin/env bash
# Notification panel control, bound to CTRL+ALT+\ (toggle) and CTRL+ALT+
# BackSpace (clear). Dispatches on the desktop mode because the daemon is not
# the same one in every mode: swaync in tiling and hud, noctalia-shell in
# noctalia. The binds used to call `swaync-client` directly, which made both
# keys dead in noctalia mode — a key that does nothing and exits 0 is this
# repo's signature bug, so the branch lives here rather than in the binds.
set -u

. "$HOME/.config/mango/scripts/lib.sh"

case "${1:-toggle}" in
    toggle) swaync_arg="-t"; noctalia_fn="toggleHistory" ;;
    clear) swaync_arg="-C"; noctalia_fn="clear" ;;
    *)
        echo "usage: ${0##*/} [toggle|clear]" >&2
        exit 1
        ;;
esac

if [ "$(current_mode)" = noctalia ]; then
    exec noctalia-shell ipc call notifications "$noctalia_fn"
else
    exec swaync-client "$swaync_arg"
fi
