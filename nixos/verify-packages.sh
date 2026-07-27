#!/usr/bin/env bash
# Verify this flake still evaluates and builds against current nixpkgs.
#
# Run this after `nix flake update`, or any time you add packages. It is much
# faster than checking names one at a time because everything happens in a
# single Nix evaluation.
#
#   ./verify-packages.sh          # full check
#   ./verify-packages.sh --quick  # skip the dry-run build sizing
set -uo pipefail

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE="path:${FLAKE_DIR}"
ATTR="nixosConfigurations.thinkpad.config.system.build.toplevel"

export NIX_CONFIG="experimental-features = nix-command flakes"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

bold "1/3  Parsing every .nix file"
fail=0
while IFS= read -r f; do
  if ! nix-instantiate --parse "$f" >/dev/null 2>&1; then
    red "     PARSE FAIL  $f"
    fail=1
  fi
done < <(find "$FLAKE_DIR" -name '*.nix')
[ "$fail" -eq 0 ] && green "     all files parse"

bold "2/3  Evaluating the full system closure"
# This is the real gate: it resolves every package name AND every NixOS option
# in the module system. If this passes, the config is structurally sound.
out=$(nix eval --no-write-lock-file "${FLAKE}#${ATTR}.drvPath" 2>&1)
rc=$?

warnings=$(grep -c '^evaluation warning' <<<"$out")
if [ "$rc" -ne 0 ]; then
  red "     EVALUATION FAILED"
  grep -vE '^ +(To|You|[0-9]+\||\|)' <<<"$out" | tail -20
  exit 1
fi

green "     closure evaluates: $(grep -oE '"/nix/store/[^"]+"' <<<"$out" | tr -d '"')"
if [ "$warnings" -gt 0 ]; then
  printf '\033[33m     %d deprecation warning(s):\033[0m\n' "$warnings"
  grep '^evaluation warning' <<<"$out" | sed 's/^/       /'
else
  green "     no deprecation warnings"
fi

if [ "${1:-}" = "--quick" ]; then
  bold "3/3  skipped (--quick)"
  exit 0
fi

bold "3/3  Dry-run build (what would be downloaded)"
nix build --no-link --dry-run --no-write-lock-file "${FLAKE}#${ATTR}" 2>&1 \
  | grep -E 'will be built|will be fetched' | sed 's/^/     /'

echo
green "Done. If all three stages passed, this flake is ready to install."
