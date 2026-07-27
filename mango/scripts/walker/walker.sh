#!/usr/bin/env bash
MODE=$(cat "$HOME/.config/mango/state/current-mode" 2>/dev/null || echo "tiling")

# Detect which sizing flags the caller already passed
has_width=false; has_maxheight=false; has_minheight=false
prev_maxheight=""
prev=""
for a in "$@"; do
    case "$prev" in --maxheight) prev_maxheight="$a" ;; esac
    [[ "$a" == "--width" ]]     && has_width=true
    [[ "$a" == "--maxheight" ]] && has_maxheight=true
    [[ "$a" == "--minheight" ]] && has_minheight=true
    prev="$a"
done

extra_args=()
if [ "$MODE" = "hud" ]; then
    effective_maxheight="${prev_maxheight:-220}"
    $has_width     || extra_args+=(--width 200)
    $has_maxheight || extra_args+=(--maxheight 220)
    $has_minheight || extra_args+=(--minheight "$effective_maxheight")
else
    $has_maxheight || extra_args+=(--maxheight 500)
fi

exec walker "${extra_args[@]}" "$@"
