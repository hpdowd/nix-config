#!/usr/bin/env bash
# Static assertion checks — everything decidable from the repo source and the
# build outputs, with no live session. Run by `nix flake check`; the checks
# that need a running compositor stay in verify-claims.sh.
#
#   checks/static.sh <source-root> <home-manager-generation>
#
# Both arguments are required. Nothing here is allowed to skip: a check that
# quietly finds nothing is this repo's recurring failure, not a pass.

set -uo pipefail

SRC=${1:?usage: static.sh <source-root> <home-manager-generation>}
GEN=${2:?usage: static.sh <source-root> <home-manager-generation>}

WAYBAR_DIR="$GEN/home-files/.config/mango/waybar"
PROFILE="$GEN/home-path/bin"

PASS=0
FAIL=0

ok() {
	PASS=$((PASS + 1))
	printf '  ✓ %s\n' "$1"
}
bad() {
	FAIL=$((FAIL + 1))
	printf '  ✗ %s\n' "$1"
	[[ -n ${2:-} ]] && printf '      %s\n' "$2"
	return 0
}

# Only tracked files reach the flake source, so under `nix flake check` every
# scan below sees exactly what a fresh clone would. Run against a working tree
# the prune list keeps build and tool artefacts out.
prune=(-name .git -o -name .direnv -o -name result)

is_tracked() {
	if [[ -d "$SRC/.git" ]]; then
		git -C "$SRC" ls-files --error-unmatch "$1" >/dev/null 2>&1
	else
		[[ -e "$SRC/$1" ]]
	fi
}

mapfile -t SCRIPTS < <(
	find "$SRC" \( "${prune[@]}" \) -prune -o -type f -not -path '*/docs/archive/*' -print0 \
		| while IFS= read -r -d "" f; do
			case "$(head -c 64 "$f" 2>/dev/null | tr -d '\0' | head -1)" in
			'#!'*) printf '%s\n' "$f" ;;
			esac
		done
)
if [[ ${#SCRIPTS[@]} -lt 30 ]]; then
	bad "only ${#SCRIPTS[@]} scripts found — the shebang scan is broken, not the repo"
else
	ok "${#SCRIPTS[@]} scripts found to scan"
fi

printf '\nRepo\n'

# A tracked symlink holds an absolute path that is wrong in every other clone,
# and home-manager fights whatever rewrites it at runtime.
syms=$(find "$SRC" \( "${prune[@]}" \) -prune -o -type l -print)
if [[ -z $syms ]]; then
	ok "no symlinks in the source"
else
	bad "symlinks in the source" "$(echo "$syms" | tr '\n' ' ')"
fi

# Generated at runtime, so tracking them means two owners for one path.
for f in home/mango/config.conf home/mango/walker/config.toml; do
	if is_tracked "$f"; then
		bad "$f is tracked but is generated at runtime"
	elif grep -qF "$f" "$SRC/.gitignore"; then
		ok "$(basename "$f") generated + gitignored"
	else
		bad "$f is untracked but has no .gitignore rule"
	fi
done

printf '\nScripts\n'

# There is no /bin/bash on NixOS; the shebang fails with exit 127, and a waybar
# custom module whose exec exits 127 renders as an empty module.
if bad_sheb=$(grep -l '^#!/bin/bash' "${SCRIPTS[@]}" 2>/dev/null); then
	bad "#!/bin/bash shebang (there is no /bin/bash — exit 127)" "$(echo "$bad_sheb" | tr '\n' ' ')"
else
	ok "every script uses #!/usr/bin/env bash"
fi

# mmsg takes verbs. The dwl-era dash-flags return {"error":...} AND exit 0, so
# a script using them reports success while doing nothing.
if mmsg_flags=$(grep -rn 'mmsg[[:space:]]\+-' "$SRC/home" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#'); then
	bad "mmsg called with dash-flags (unknown command, exit 0)" "$(echo "$mmsg_flags" | head -3)"
else
	ok "no script calls mmsg with dash-flags"
fi

# desktop-mode.sh kept reading $MANGO_DIR/state after the move and the mode
# switch silently became one-way.
stale=$(grep -rn 'MANGO[_A-Z]*/state\|config/mango/state' "$SRC/home/mango/scripts/" 2>/dev/null \
	| grep -vE ':[0-9]+:[[:space:]]*#')
if [[ -z $stale ]]; then
	ok "no script reads the old state path"
else
	bad "scripts still reading ~/.config/mango/state" "$(echo "$stale" | head -3)"
fi

# nixpkgs wraps some binaries, so `comm` becomes .foo-wrapped, truncated to 15
# chars. `pkill -x` matches comm exactly and never fires. Resolve each target
# rather than flagging every -x: a check that cries wolf gets ignored.
pk_bad=""
pk_n=0
while read -r line; do
	[[ -z $line ]] && continue
	name=${line##*pkill -x }
	name=${name%% *}
	name=${name%%;*}
	[[ -z $name ]] && continue
	pk_n=$((pk_n + 1))
	if [[ ! -e "$PROFILE/$name" ]]; then
		pk_bad+="  $name: not in the home profile — cannot verify"$'\n'
		continue
	fi
	real=$(readlink -f "$PROFILE/$name")
	[[ -e "$(dirname "$real")/.${name}-wrapped" ]] \
		&& pk_bad+="  $name is wrapped — pkill -x will never match: ${line%%:*}"$'\n'
done < <(grep -rn 'pkill -x' "$SRC/home" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')

if [[ -z $pk_bad ]]; then
	ok "all $pk_n 'pkill -x' targets are unwrapped binaries"
else
	bad "'pkill -x' against a nixpkgs wrapper never matches" "$(echo "$pk_bad" | head -4)"
fi

printf '\nGenerated waybar configs\n'

mapfile -t CONFIGS < <(find "$WAYBAR_DIR" -name 'config-*.jsonc' | sort)
if [[ ${#CONFIGS[@]} -ne 8 ]]; then
	bad "expected 8 generated waybar configs (4 layouts x 2 positions), found ${#CONFIGS[@]}"
else
	ok "8 generated waybar configs"
fi

# A module whose exec is missing or non-executable renders as an empty module,
# which reads as the module being absent from the bar.
missing=""
refs=0
for cfg in "${CONFIGS[@]}"; do
	while read -r ref; do
		[[ -z $ref ]] && continue
		refs=$((refs + 1))
		script="$SRC/home/mango/scripts/${ref#*mango/scripts/}"
		[[ -x $script ]] || missing+="  $(basename "$cfg"): $ref"$'\n'
	done < <(jq -r '..|strings' "$cfg" | grep -o '[~]/\.config/mango/scripts/[^ "]*' | sort -u)
done

if [[ $refs -eq 0 ]]; then
	bad "no script references found in the generated configs — the scan is broken"
elif [[ -z $missing ]]; then
	ok "all $refs referenced scripts exist and are executable"
else
	bad "waybar references a missing or non-executable script" "$(echo "$missing" | sort -u | head -4)"
fi

printf '\nCouplings\n'

# waybar rescales as shown = real / full-at * 100, so a mismatch makes the bar
# peak below 100%. waybar.nix reads the threshold through osConfig, so this
# checks the enforcement reached the GENERATED output — the part that can still
# break — rather than comparing two hand-maintained numbers.
stop=$(grep -oE 'STOP_CHARGE_THRESH_BAT0[[:space:]]*=[[:space:]]*[0-9]+' "$SRC/modules/system/power.nix" \
	| grep -oE '[0-9]+$' | head -1)
full=$(jq -r '.battery["full-at"] // empty' "$WAYBAR_DIR/config-focus-top.jsonc" 2>/dev/null)
if [[ -z $stop || -z $full ]]; then
	bad "could not read STOP_CHARGE_THRESH_BAT0 ($stop) or generated full-at ($full)"
elif [[ $stop == "$full" ]]; then
	ok "battery STOP ($stop) == generated waybar full-at ($full)"
else
	bad "battery STOP ($stop) != generated waybar full-at ($full) — osConfig wiring is broken"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
