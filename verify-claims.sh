#!/usr/bin/env bash
# Re-check the assertions CLAUDE.md makes that only a live session can answer.
#
# Everything decidable from the source or the build output moved into
# `nix flake check` on 2026-08-03 (checks/static.sh) — it was a manual step
# nobody was forced to run. What is left needs a running compositor, which no
# build can see. Run both:
#
#   nix flake check             the closure, the linters, the static assertions
#   ./verify-claims.sh          these
#
#   ./verify-claims.sh -q       failures only
#
# Exit 0 if every check passes, 1 otherwise. Checks are skipped (not failed)
# when run headless.

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

QUIET=0
[[ ${1:-} == -q ]] && QUIET=1
PASS=0
FAIL=0
SKIP=0

ok() {
	PASS=$((PASS + 1))
	[[ $QUIET == 1 ]] || printf '  \033[32m✓\033[0m %s\n' "$1"
}
bad() {
	FAIL=$((FAIL + 1))
	printf '  \033[31m✗\033[0m %s\n' "$1"
	[[ -n ${2:-} ]] && printf '      %s\n' "$2"
	return 0
}
skip() {
	SKIP=$((SKIP + 1))
	[[ $QUIET == 1 ]] || printf '  \033[33m–\033[0m %s (skipped: %s)\n' "$1" "$2"
}
hdr() { [[ $QUIET == 1 ]] || printf '\n\033[1m%s\033[0m\n' "$1"; }

hdr "Compositor (needs a Wayland session)"

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
	skip "wlopm sees an output" "no WAYLAND_DISPLAY"
	skip "mmsg reports a monitor" "no WAYLAND_DISPLAY"
else
	# CLAUDE.md asserted for months that mango advertised no wl_output, so
	# `wlopm --json` returned []. That became false at some point, and believing
	# it is why sleep blanking was built on the backlight — which cannot idle
	# the display block, so the machine drew 4.1 W through every "suspend" and
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

printf '\n%d passed, %d failed' "$PASS" "$FAIL"
[[ $SKIP -gt 0 ]] && printf ', %d skipped' "$SKIP"
printf '\n'
[[ $FAIL -eq 0 ]]
