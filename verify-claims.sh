#!/usr/bin/env bash
# Re-check the assertions CLAUDE.md makes about this system.
#
# Every check here exists because a documented claim silently stopped being
# true and cost real debugging time. Prose cannot be trusted to stay correct;
# these can be run. Companion to verify-packages.sh, which checks the closure.
#
#   ./verify-claims.sh          all checks
#   ./verify-claims.sh -q       failures only
#
# Exit 0 if every check passes, 1 otherwise. Checks needing a Wayland session
# are SKIPPED (not failed) when run headless.

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

QUIET=0; [[ ${1:-} == -q ]] && QUIET=1
PASS=0; FAIL=0; SKIP=0

ok()   { PASS=$((PASS+1)); [[ $QUIET == 1 ]] || printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$1"; [[ -n ${2:-} ]] && printf '      %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); [[ $QUIET == 1 ]] || printf '  \033[33m–\033[0m %s (skipped: %s)\n' "$1" "$2"; }
hdr()  { [[ $QUIET == 1 ]] || printf '\n\033[1m%s\033[0m\n' "$1"; }

# --- Repo hygiene ----------------------------------------------------------
hdr "Repo"

# home/mango/walker/config.toml was a tracked symlink holding an ABSOLUTE path
# into $HOME, while autostart.conf rewrote that same path with `ln -sf` on every
# mode switch. Home-manager and the mode scripts both claimed it; activation
# died with "would be clobbered". A tracked symlink is almost always this bug.
syms=$(git ls-files -s | awk '$1=="120000" {print $4}')
if [[ -z $syms ]]; then
    ok "no tracked symlinks"
else
    bad "tracked symlinks (absolute paths break other clones; runtime writers clobber)" "$(echo "$syms" | tr '\n' ' ')"
fi

# Generated files must not be tracked, or home-manager fights whatever writes them.
for f in home/mango/config.conf home/mango/walker/config.toml; do
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        bad "$f is tracked but is generated at runtime"
    elif git check-ignore -q "$f"; then
        ok "$(basename "$f") generated + gitignored"
    else
        bad "$f is neither tracked nor ignored — add a .gitignore rule"
    fi
done

# --- Paths that moved ------------------------------------------------------
hdr "Runtime state (~/.local/state/mango since 2026-07-30)"

# desktop-mode.sh kept reading $MANGO_DIR/state after the move. current_mode()
# fell back to "tiling", the menu always bulleted tiling, and the guard treated
# picking it as "already there" — hud was reachable, tiling was not, silently.
stale=$(grep -rn 'MANGO[_A-Z]*/state\|config/mango/state' home/mango/scripts/ 2>/dev/null \
        | grep -vE ':[0-9]+:[[:space:]]*#')
if [[ -z $stale ]]; then
    ok "no script reads the old state path"
else
    bad "scripts still reading ~/.config/mango/state" "$(echo "$stale" | head -3)"
fi

# --- NixOS wrapper trap ----------------------------------------------------
hdr "pkill patterns"

# nixpkgs wraps SOME binaries, so `comm` becomes .foo-wrapped (truncated by the
# kernel to 15 chars). `pkill -x foo` matches comm EXACTLY and therefore never
# fires against a wrapped target. This silently broke elephant (leaked a process
# per reload) and swaync (restyle on mode switch never applied).
#
# Only wrapped targets are affected, so resolve each one rather than flagging
# every `pkill -x` — dsearch is unwrapped and perfectly fine. A check that cries
# wolf gets ignored, which defeats the point of having it.
pk_bad=""; pk_n=0
while read -r line; do
    [[ -z $line ]] && continue
    name=${line##*pkill -x }; name=${name%% *}; name=${name%%;*}
    [[ -z $name ]] && continue
    pk_n=$((pk_n+1))
    bin=$(command -v "$name" 2>/dev/null) || { pk_bad+="  $name: not installed — cannot verify"$'\n'; continue; }
    real=$(readlink -f "$bin")
    [[ -e "$(dirname "$real")/.${name}-wrapped" ]] && \
        pk_bad+="  $name is wrapped (.${name}-wrapped) — pkill -x will never match: ${line%%:*}"$'\n'
done < <(grep -rn 'pkill -x' home/ 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')

if [[ -z $pk_bad ]]; then
    ok "all $pk_n 'pkill -x' targets are unwrapped binaries"
else
    bad "'pkill -x' against a nixpkgs wrapper never matches" "$(echo "$pk_bad" | head -4)"
fi

# --- Coupled values --------------------------------------------------------
hdr "Couplings"

# waybar rescales as shown = real / full-at * 100. A mismatch makes the bar peak
# below 100% and read wrong everywhere — presented once as "stuck at 88%".
stop=$(grep -oP 'STOP_CHARGE_THRESH_BAT0\s*=\s*\K[0-9]+' modules/system/power.nix 2>/dev/null | head -1)
full=$(grep -oP '"full-at"\s*:\s*\K[0-9]+' home/mango/waybar/config-focus.jsonc 2>/dev/null | head -1)
if [[ -z $stop || -z $full ]]; then
    bad "could not read STOP_CHARGE_THRESH_BAT0 ($stop) or full-at ($full)"
elif [[ $stop == "$full" ]]; then
    ok "battery STOP ($stop) == waybar full-at ($full)"
else
    bad "battery STOP ($stop) != waybar full-at ($full) — bar will misreport"
fi

# --- Live session ----------------------------------------------------------
hdr "Compositor (needs a Wayland session)"

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
    skip "wlopm sees an output" "no WAYLAND_DISPLAY"
    skip "mmsg reports a monitor" "no WAYLAND_DISPLAY"
else
    # CLAUDE.md asserted for months that mango advertised no wl_output, so
    # `wlopm --json` returned []. That became false at some point, and believing
    # it is why sleep blanking was built on the backlight — which cannot idle
    # the DISPLAY block, so the machine drew 4.1 W through every "suspend" and
    # died overnight. If this check fails, re-read the Suspend section.
    if command -v wlopm >/dev/null && [[ $(wlopm --json 2>/dev/null) == *'"output"'* ]]; then
        ok "wlopm enumerates an output (sleep blanking depends on this)"
    else
        bad "wlopm returns no outputs — powerDownCommands is a silent no-op"
    fi

    if [[ $(mmsg get all-monitors 2>/dev/null) == *'"name"'* ]]; then
        ok "mmsg reports a monitor"
    else
        bad "mmsg get all-monitors returned nothing"
    fi
fi

# --- Summary ---------------------------------------------------------------
printf '\n%d passed, %d failed' "$PASS" "$FAIL"
[[ $SKIP -gt 0 ]] && printf ', %d skipped' "$SKIP"
printf '\n'
[[ $FAIL -eq 0 ]]
