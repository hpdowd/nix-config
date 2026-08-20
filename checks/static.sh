#!/usr/bin/env bash
# Static assertion checks — everything decidable from the repo source and the
# build outputs, with no live session. Run by `nix flake check`; the checks
# that need a running compositor stay in verify-claims.sh.
#
#   checks/static.sh <source-root> <home-manager-generation> <system-toplevel>
#
# All three arguments are required. Nothing here is allowed to skip: a check
# that quietly finds nothing is this repo's recurring failure, not a pass.

set -uo pipefail

usage="usage: static.sh <source-root> <home-manager-generation> <system-toplevel> <schemes-json>"
SRC=${1:?$usage}
GEN=${2:?$usage}
SYS=${3:?$usage}
# Every scheme this machine WEARS, resolved by Nix:
#
#   .artefact          modules/home/scheme.nix — the widget art, icons, cursor,
#                      yazi flavor, nvim plugin and Zed theme
#   .modes.<mode>      modules/home/modes.nix — the colour-only scheme that mode
#                      wears (docs/adr/0034)
#   .schemes.<name>    the resolved theme file for each name either names
#
# Resolved by Nix rather than read out of the theme files with sed, because an
# aliased role (`okColor = green;`) read as "role absent" — four of them did,
# and went unaudited. docs/adr/0032.
#
# PLURAL, and that is the point of the shape: a legibility floor that only ever
# audited scheme.nix's would pass a mode nobody can read. Whatever `.schemes`
# holds gets audited, so a scheme cannot enter service unaudited.
SCHEMES=${4:?$usage}

# `pal <jq-path>` reads the scheme named by $PAL_SCHEME, which defaults to the
# artefact one. The floor audit re-points it per scheme; nothing else should.
# A path that does not exist yields empty, and every consumer of it has a floor,
# so a renamed key fails loudly rather than scanning for nothing.
PAL_SCHEME=$(jq -r '.artefact // empty' "$SCHEMES" 2>/dev/null)
pal() { jq -r ".schemes.\"$PAL_SCHEME\"$1 // empty" "$SCHEMES" 2>/dev/null; }

WAYBAR_DIR="$GEN/home-files/.config/mango/waybar"
# What home-manager actually wrote. Anything generated is read from HERE rather
# than from its source under dotfiles/ — several files have no source any more.
GEN_CFG="$GEN/home-files/.config"
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

# Generated at runtime, so tracking them means two owners for one path. A list
# of one since walker left (docs/adr/0021) — kept as a loop because the shape
# recurs every time an autostart.conf learns to write something.
GENERATED=(dotfiles/mango/config.conf)
for f in "${GENERATED[@]}"; do
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
if mmsg_flags=$(grep -rn 'mmsg[[:space:]]\+-' "$SRC/dotfiles" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#'); then
	bad "mmsg called with dash-flags (unknown command, exit 0)" "$(echo "$mmsg_flags" | head -3)"
else
	ok "no script calls mmsg with dash-flags"
fi

# desktop-mode.sh kept reading $MANGO_DIR/state after the move and the mode
# switch silently became one-way.
stale=$(grep -rn 'MANGO[_A-Z]*/state\|config/mango/state' "$SRC/dotfiles/mango/scripts/" 2>/dev/null \
	| grep -vE ':[0-9]+:[[:space:]]*#')
if [[ -z $stale ]]; then
	ok "no script reads the old state path"
else
	bad "scripts still reading ~/.config/mango/state" "$(echo "$stale" | head -3)"
fi

# nixpkgs wraps some binaries, so `comm` becomes .foo-wrapped, truncated to 15
# chars. `-x` matches comm exactly and never fires. `pgrep` is checked alongside
# `pkill` because the read-only form fails just as quietly and in both
# directions: a guard that never matches respawns a running daemon, and a
# liveness test that never matches exits a healthy loop. Resolve each target
# rather than flagging every -x: a check that cries wolf gets ignored.
pk_bad=""
pk_n=0
while read -r line; do
	[[ -z $line ]] && continue
	name=${line##*-x }
	name=${name%% *}
	name=${name%%;*}
	[[ -z $name ]] && continue
	pk_n=$((pk_n + 1))
	# System packages are not in the home profile — mango and elephant live in
	# the system one, so checking only $PROFILE reports "cannot verify" for the
	# targets most likely to be wrapped.
	bin=""
	for d in "$PROFILE" "$SYS/sw/bin"; do
		[[ -e "$d/$name" ]] && {
			bin="$d/$name"
			break
		}
	done
	if [[ -z $bin ]]; then
		pk_bad+="  $name: in neither profile — cannot verify: ${line%%:*}"$'\n'
		continue
	fi
	real=$(readlink -f "$bin")
	[[ -e "$(dirname "$real")/.${name}-wrapped" ]] \
		&& pk_bad+="  $name is wrapped — -x will never match: ${line%%:*}"$'\n'
done < <(grep -rnE 'p(kill|grep) -x' "$SRC/dotfiles" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')

if [[ $pk_n -eq 0 ]]; then
	bad "no 'pkill -x'/'pgrep -x' found at all — the scan is broken, not the repo"
elif [[ -z $pk_bad ]]; then
	ok "all $pk_n 'pkill -x'/'pgrep -x' targets are unwrapped binaries"
else
	bad "'-x' against a nixpkgs wrapper never matches" "$(echo "$pk_bad" | head -4)"
fi

printf '\nSecrets\n'

# An unencrypted secrets file committed to git reads exactly like an encrypted
# one at a glance, and the mistake is unrecoverable once pushed. sops always
# writes the `sops:` metadata block, so its absence means plaintext.
mapfile -t SECRET_FILES < <(find "$SRC/secrets" -type f -name '*.yaml' 2>/dev/null | sort)
if [[ ${#SECRET_FILES[@]} -eq 0 ]]; then
	bad "no secrets/*.yaml found — the scan is broken, not the repo"
else
	plain=""
	for f in "${SECRET_FILES[@]}"; do
		if ! grep -q '^sops:' "$f" || ! grep -q 'age:' "$f"; then
			plain+="  ${f#"$SRC"/}"$'\n'
		fi
	done
	if [[ -z $plain ]]; then
		ok "all ${#SECRET_FILES[@]} secrets/*.yaml are sops-encrypted"
	else
		bad "UNENCRYPTED file under secrets/" "$plain"
	fi
fi

# The plaintext credential file is gone. A script still reading that path would
# find nothing and fall through without saying so.
pia_stale=$(grep -rn 'pia-auth' "$SRC/dotfiles" "$SRC/modules" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')
if [[ -z $pia_stale ]]; then
	ok "no script reads the old plaintext pia-auth path"
else
	bad "script still reads the old plaintext pia-auth path" "$(echo "$pia_stale" | head -3)"
fi

printf '\nRuntime-selected files\n'

# A file chosen by a shell conditional is never evaluated, so an unreachable
# branch is invisible — four instances so far, the largest 765 lines, every one
# looking maintained and two of them documented as the default. Checked BOTH
# ways per selector: every value the selector can take must have a file, and
# every file must be a value the selector can take. One direction alone misses
# half the class — a missing file is a runtime fallback, a surplus file is dead
# weight that still looks maintained.
MANGO="$SRC/dotfiles/mango"

# The one lock path, checked in two places below: for the noctalia ipc call it
# makes, and for the background pool it points at.
LOCKBIN="$GEN/home-path/bin/lockscreen"

# Desktop mode. desktop-mode.sh validates against this list, so it is the
# complete set of values current-mode can hold.
mapfile -t MODES < <(
	sed -n 's/^MODES=(\(.*\))$/\1/p' "$MANGO/scripts/desktop-mode.sh" | tr -d '"' | tr ' ' '\n' | sed '/^$/d'
)
if [[ ${#MODES[@]} -eq 0 ]]; then
	bad "could not read MODES from desktop-mode.sh — the scan is broken, not the repo"
else
	missing=""
	for m in "${MODES[@]}"; do
		[[ -f "$MANGO/$m/$m.conf" ]] || missing+="  $m/$m.conf"$'\n'
		[[ -f "$MANGO/scripts/modes/$m.sh" ]] || missing+="  scripts/modes/$m.sh"$'\n'
	done
	# And nothing surplus, in both directions: a <m>/<m>.conf naming no mode is
	# a config nothing can select. (walker/configs/<m>.toml was the third
	# per-mode file until 2026-08-14; rofi has one config for every mode.)
	for d in "$MANGO"/*/; do
		n=$(basename "$d")
		[[ -f "$d/$n.conf" ]] || continue
		printf '%s\n' "${MODES[@]}" | grep -qxF "$n" || missing+="  $n/$n.conf names no mode"$'\n'
	done
	if [[ -z $missing ]]; then
		ok "each of the ${#MODES[@]} modes has its conf and its mode script, and no others exist"
	else
		bad "mode/file mismatch" "$missing"
	fi
fi

# And every mode has a colour scheme, both ways. modules/home/dotfiles.nix
# resolves each as `import ./themes/${modes.${mode}}.nix`, so a MISSING key is
# already an eval error — what this catches is the direction eval cannot see: a
# key naming no mode, which is a colour scheme nothing can ever select while
# reading like a mode that exists. docs/adr/0034.
mapfile -t MODE_KEYS < <(jq -r '.modes | keys[]' "$SCHEMES" 2>/dev/null)
if [[ ${#MODE_KEYS[@]} -eq 0 ]]; then
	bad "no modes read from modules/home/modes.nix — the scan is broken, not the repo"
elif [[ ${#MODES[@]} -gt 0 ]]; then
	memiss=""
	for m in "${MODES[@]}"; do
		printf '%s\n' "${MODE_KEYS[@]}" | grep -qxF "$m" || memiss+="  $m has no entry in modes.nix"$'\n'
	done
	for k in "${MODE_KEYS[@]}"; do
		printf '%s\n' "${MODES[@]}" | grep -qxF "$k" || memiss+="  modes.nix names '$k', which is not a mode"$'\n'
	done
	if [[ -z $memiss ]]; then
		ok "each of the ${#MODES[@]} modes has a colour scheme in modes.nix, and no others do"
	else
		bad "mode/scheme mismatch" "$memiss"
	fi
fi

# The ceiling on how far modes.nix may diverge. waybar and swaync are the two
# consumers NOT on the runtime swap — generated once, from scheme.nix — and
# noctalia runs neither. So every OTHER mode has to wear the artefact scheme,
# or it gets a bar from a scheme it is not wearing.
#
# noctalia may differ, and does: everything it runs — its own shell, mango's
# chrome, kitty, foot, rofi, ncspot and Equibop — follows modes.nix.
#
# Derived from modes.nix rather than naming `tiling`, so a mode added later is
# asserted with nothing to remember. Until hud left (docs/adr/0035) this also
# had to check tiling and hud against EACH OTHER, because two modes shared one
# generated bar; with one bar-bearing mode that half is gone.
#
# If waybar or swaync ever needs to differ by mode, it joins the swap first;
# this assertion is what makes that a decision rather than a silent half.
barmodes=0
barerr=""
while IFS='|' read -r m msch; do
	[[ -z $m || $m == noctalia ]] && continue
	barmodes=$((barmodes + 1))
	[[ $msch == "$PAL_SCHEME" ]] || barerr+="  $m wears '$msch'"$'\n'
done < <(jq -r '.modes | to_entries[] | "\(.key)|\(.value)"' "$SCHEMES" 2>/dev/null)
if [[ $barmodes -eq 0 ]]; then
	bad "no bar-bearing mode read from modes.nix — the scan is broken, not the repo"
elif [[ -n $barerr ]]; then
	bad "a mode running waybar and swaync does not wear the artefact scheme '$PAL_SCHEME'" \
		"those are generated once, from scheme.nix, so the mode would be half one scheme and half the other:"$'\n'"$barerr"
else
	ok "the $barmodes mode(s) running waybar and swaync wear '$PAL_SCHEME', which is what those are generated from"
fi

# Same check the waybar configs get below, for the mango tree: a `bind=` or
# `exec=` naming a script that is missing — or present but not executable — is
# a key that does nothing and a daemon that never starts, both exiting 0. Nix
# preserves the mode bit, so a script committed 644 arrives 444 and fails only
# at runtime. That is how notify.sh shipped dead on 2026-08-14.
missing=""
refs=0
while read -r ref; do
	[[ -z $ref ]] && continue
	refs=$((refs + 1))
	# `#*scripts/` covers both spellings — the `~/.config/mango/scripts/` of a
	# conf and the `$MANGO_DIR/scripts/` of a script.
	[[ -x "$MANGO/scripts/${ref#*scripts/}" ]] || missing+="  $ref"$'\n'
done < <(
	{
		# `~/.config/…` in a bind= or exec= line.
		grep -rho '[~]/\.config/mango/scripts/[^ "]*' "$MANGO" --include='*.conf'
		# `"$MANGO_DIR/scripts/…"` from one script to another. Added when
		# shell.sh took over the network and bluetooth menus: their only
		# callers stopped being .conf files, and they fell out of this scan
		# without any count reaching zero to say so.
		# SC2016: `$MANGO_DIR` is the literal text being searched for, not a
		# variable to expand — the scripts spell the path that way.
		# shellcheck disable=SC2016
		grep -rho '\$MANGO_DIR/scripts/[^" ]*' "$MANGO/scripts"
		# mode.sh's `modes/$MODE.sh` is decided at runtime and cannot be
		# resolved here — and does not need to be: the mode/file check above
		# already asserts a script exists for every value $MODE can hold.
	} | grep -v 'scripts/[^ ]*\$' | sort -u
)

if [[ $refs -eq 0 ]]; then
	bad "no script references found in the mango configs — the scan is broken, not the repo"
elif [[ -z $missing ]]; then
	ok "all $refs scripts named by a bind or autostart exist and are executable"
else
	bad "a mango config names a missing or non-executable script" "$missing"
fi

# Two binds on one key: mango prints `[WARNING] Key binding conflict` naming
# both files and lines, then runs whichever was parsed FIRST (src/mango.c,
# "only match the first keybind"). That warning goes to mango's stderr, where
# nothing reads it — so the second bind looks installed and never fires. Built
# per mode from the `source=` lines of its own conf, which is exactly the set
# mango parses. Keys are lowercased first: the dispatcher compares with
# xkb_keysym_to_lower(), so `SUPER,O` and `SUPER,o` are one key, not two.
if [[ ${#MODES[@]} -gt 0 ]]; then
	duperr=""
	binds_seen=0
	for m in "${MODES[@]}"; do
		conf="$MANGO/$m/$m.conf"
		[[ -f $conf ]] || continue
		mapfile -t srcs < <(sed -n 's|^source=\./||p' "$conf")
		dups=$(
			{
				for s in "${srcs[@]}"; do
					[[ -f "$MANGO/$s" ]] && grep -h '^bind=' "$MANGO/$s"
				done
				grep -h '^bind=' "$conf"
			} | cut -d, -f1,2 | tr '[:upper:]' '[:lower:]' | sort | uniq -d
		)
		binds_seen=$((binds_seen + 1))
		[[ -n $dups ]] && duperr+="  $m: $(echo "$dups" | tr '\n' ' ')"$'\n'
	done
	if [[ $binds_seen -eq 0 ]]; then
		bad "no mode confs read for the bind scan — the scan is broken, not the repo"
	elif [[ -z $duperr ]]; then
		ok "no key is bound twice in any of the $binds_seen modes"
	else
		bad "a key is bound twice — mango warns to a stderr nobody reads, then runs the first" "$duperr"
	fi
fi

# scripts/menus/shell.sh is a selector like any other (docs/adr/0014): a bind
# naming an action its case table lacks hits the `usage:` branch on a stderr
# nobody reads, and an action in the table that no bind names is a mode-specific
# path nothing can reach — the shape that hid four unreachable files here. Both
# directions, and both sides must be non-empty.
# `^bind=` first, then the action: an unfiltered scan reads the prose in the
# comments too, and "shell.sh rather than calling" duly arrived as an action
# named `rather`.
mapfile -t BIND_ACTIONS < <(
	grep -rh '^bind=' "$MANGO" --include='*.conf' |
		grep -oE 'menus/shell\.sh [a-z-]+' | awk '{print $2}' | sort -u
)
mapfile -t TABLE_ACTIONS < <(
	sed -n 's/^\([a-z-]*\))[[:space:]]*ipc=.*/\1/p' "$MANGO/scripts/menus/shell.sh" | sort -u
)
if [[ ${#BIND_ACTIONS[@]} -eq 0 || ${#TABLE_ACTIONS[@]} -eq 0 ]]; then
	bad "shell.sh actions or the binds naming them came back empty — the scan is broken, not the repo"
else
	acterr=""
	for a in "${BIND_ACTIONS[@]}"; do
		printf '%s\n' "${TABLE_ACTIONS[@]}" | grep -qxF "$a" ||
			acterr+="  a bind calls shell.sh $a, which its case table does not have"$'\n'
	done
	for a in "${TABLE_ACTIONS[@]}"; do
		printf '%s\n' "${BIND_ACTIONS[@]}" | grep -qxF "$a" ||
			acterr+="  shell.sh handles $a, which no bind reaches"$'\n'
	done
	if [[ -z $acterr ]]; then
		ok "all ${#TABLE_ACTIONS[@]} shell.sh actions are reached by a bind, and no bind names another"
	else
		bad "shell.sh action mismatch" "$acterr"
	fi
fi

# menus/control-center.sh builds its rows from one ROWS array and dispatches by
# calling `state_<id>` and `act_<id>`. A row whose label or either function is
# missing RENDERS AND THEN DOES NOTHING: bash reports "command not found" on a
# stderr nobody reads, and the entry sits there looking installed. The script
# checks this itself before drawing, which catches it at the first press — this
# catches it at `nix flake check`, which is before the press.
#
# Floor at zero both ways: a renamed array or a changed function prefix would
# empty one side, and a check that passes by finding nothing is this repo's
# recurring failure, not a pass. docs/adr/0033.
CC="$MANGO/scripts/menus/control-center.sh"
if [[ -f $CC ]]; then
	# The ids between `ROWS=(` and its closing paren, minus the `-` separators.
	mapfile -t CC_ROWS < <(
		sed -n '/^ROWS=(/,/^)/p' "$CC" | sed -n 's/^\t\([a-z][a-z-]*\)$/\1/p' | sort -u
	)
	mapfile -t CC_LABELS < <(
		sed -n 's/^\t\[\([a-z][a-z-]*\)\]=.*/\1/p' "$CC" | sort -u
	)
	mapfile -t CC_FNS < <(
		sed -n 's/^\(state\|act\)_\([a-z][a-z-]*\)() {.*/\1 \2/p' "$CC" | sort -u
	)
	if [[ ${#CC_ROWS[@]} -eq 0 || ${#CC_LABELS[@]} -eq 0 || ${#CC_FNS[@]} -eq 0 ]]; then
		bad "the control centre's rows, labels or functions came back empty — the scan is broken, not the repo" \
			"rows=${#CC_ROWS[@]} labels=${#CC_LABELS[@]} fns=${#CC_FNS[@]}"
	else
		ccerr=""
		for id in "${CC_ROWS[@]}"; do
			printf '%s\n' "${CC_LABELS[@]}" | grep -qxF "$id" ||
				ccerr+="  row $id has no entry in LABEL"$'\n'
			for half in state act; do
				printf '%s\n' "${CC_FNS[@]}" | grep -qxF "$half $id" ||
					ccerr+="  row $id has no ${half}_$id()"$'\n'
			done
		done
		# The other direction: a function or a label with no row is dead code
		# that reads as a working feature — the shape that hid four unreachable
		# files here (docs/adr/0014).
		for id in "${CC_LABELS[@]}"; do
			printf '%s\n' "${CC_ROWS[@]}" | grep -qxF "$id" ||
				ccerr+="  LABEL has $id, which ROWS does not list"$'\n'
		done
		for pair in "${CC_FNS[@]}"; do
			printf '%s\n' "${CC_ROWS[@]}" | grep -qxF "${pair##* }" ||
				ccerr+="  ${pair// /_}() exists, but ROWS does not list ${pair##* }"$'\n'
		done
		if [[ -z $ccerr ]]; then
			ok "all ${#CC_ROWS[@]} control-centre rows have a label, a state_* and an act_*"
		else
			bad "control-centre row mismatch" "$ccerr"
		fi
	fi
fi

# --- Weather ----------------------------------------------------------------
# Four things each invisible when wrong. docs/adr/0038.
WEATHER_SH="$MANGO/scripts/system/weather.sh"
if [[ -f $WEATHER_SH ]]; then
	# 1. THE COORDINATES REACH THE SCRIPT. Drifted variable names leave
	#    WEATHER_LAT unset and send `latitude=&longitude=` — which open-meteo
	#    answers, with the weather at 0°N 0°E. gotchas.md -> Scripts.
	LOC_ENV="$GEN_CFG/mango/universal/weather-location.env"
	if [[ ! -s $LOC_ENV ]]; then
		bad "weather-location.env is not in the generation" \
			"weather.sh has no coordinates and every reading is an error row: $LOC_ENV"
	else
		locmiss=""
		for v in WEATHER_LAT WEATHER_LON WEATHER_NAME; do
			grep -q "^$v=" "$LOC_ENV" || locmiss+="  $v"$'\n'
			grep -q "\$$v" "$WEATHER_SH" || locmiss+="  $v is generated but weather.sh never reads it"$'\n'
		done
		# The path from both ends — two spellings fail as "coordinates missing"
		# pointing at a file that is right there.
		grep -q 'weather-location\.env' "$WEATHER_SH" \
			|| locmiss+="  weather.sh does not name weather-location.env"$'\n'
		if [[ -z $locmiss ]]; then
			ok "weather-location.env is generated and weather.sh reads all three of its values"
		else
			bad "the generated coordinates and weather.sh disagree" "$locmiss"
		fi
	fi

	# 2. THE SIGNAL NUMBER, from both sides. waybar drops an RT signal nothing
	#    subscribes to in silence, so a mismatch updates the row and not the bar.
	wsig_script=$(grep -oE 'pkill -RTMIN\+([0-9]+) waybar' "$WEATHER_SH" | grep -oE '[0-9]+' | head -1)
	wsig_bar=$(jq -r '.["custom/weather"].signal // empty' "$WAYBAR_DIR/config-full-top.jsonc" 2>/dev/null)
	if [[ -z $wsig_script || -z $wsig_bar ]]; then
		bad "could not read the weather refresh signal from both sides — the scan is broken, not the repo" \
			"script=[$wsig_script] bar=[$wsig_bar]"
	elif [[ $wsig_script != "$wsig_bar" ]]; then
		bad "weather.sh signals RTMIN+$wsig_script but custom/weather listens on $wsig_bar" \
			"waybar drops a real-time signal nothing subscribes to without logging"
	else
		ok "weather.sh and custom/weather agree on SIGRTMIN+$wsig_script"
	fi

	# 3. THE CONTROL-CENTRE ROW MUST NOT FETCH. That render is parallel and
	#    costs its slowest row (73 ms); only `read` never opens a socket. The
	#    symptom of getting it wrong is a menu that does not appear.
	if [[ -f $CC ]]; then
		wverb=$(sed -n '/^state_weather() {/,/^}/p' "$CC" | grep -oE 'weather\.sh" (status|read|refresh)' | awk '{print $2}')
		if [[ -z $wverb ]]; then
			bad "state_weather does not call weather.sh — the scan is broken, not the repo"
		elif [[ $wverb != read ]]; then
			bad "the control-centre weather row calls weather.sh '$wverb'" \
				"only 'read' is cache-only; the others can block the whole menu on a 10s curl"
		else
			ok "the control-centre weather row calls weather.sh read — no socket on the render path"
		fi
	fi

	# 4. EVERY WMO CODE WITH A PHRASE HAS A GLYPH. `icon_for` ends in `*`, so a
	#    code it does not know draws na and nothing complains — the row renders,
	#    wearing the wrong weather.
	mapfile -t wmo_desc < <(
		sed -n '/^describe() {/,/^}/p' "$WEATHER_SH" |
			sed -n 's/^\t\([0-9 |]*[0-9]\)).*/\1/p' | tr -d ' ' | tr '|' '\n' | sort -un
	)
	wmo_icons=$(
		sed -n '/^icon_for() {/,/^}/p' "$WEATHER_SH" |
			sed -n 's/^\t\([0-9 |]*[0-9]\)).*/\1/p' | tr -d ' ' | tr '|' '\n' | sort -un
	)
	if [[ ${#wmo_desc[@]} -eq 0 || -z $wmo_icons ]]; then
		bad "no WMO codes read out of weather.sh — the scan is broken, not the repo" \
			"describe=${#wmo_desc[@]}"
	else
		wmomiss=""
		for c in "${wmo_desc[@]}"; do
			grep -qxF "$c" <<<"$wmo_icons" || wmomiss+=" $c"
		done
		for c in $wmo_icons; do
			printf '%s\n' "${wmo_desc[@]}" | grep -qxF "$c" || wmomiss+=" $c(icon only)"
		done
		if [[ -z $wmomiss ]]; then
			ok "all ${#wmo_desc[@]} WMO codes weather.sh describes also have a glyph"
		else
			bad "weather.sh's describe() and icon_for() cover different WMO codes" \
				"a code with a phrase and no glyph draws nf-weather-na and looks merely unsettled:$wmomiss"
		fi
	fi
fi

# --- noctalia mode ----------------------------------------------------------
# All of this is gated on the mode's directory existing, so removing noctalia
# (docs/SYSTEM.md §6) removes the checks with it rather than leaving three
# failures behind. Inside the gate nothing is allowed to skip.
if [[ -d "$MANGO/noctalia" ]]; then
	# The mode without the package is a mode that starts nothing. Resolve the
	# store path off the binary rather than looking under $SYS/sw/share:
	# environment.pathsToLink does not link share/noctalia-shell, so the QML
	# and the Assets are reachable only through the package itself.
	NOCT_BIN="$SYS/sw/bin/noctalia-shell"
	NOCT_SHARE=""
	if [[ ! -x $NOCT_BIN ]]; then
		bad "the noctalia mode exists but noctalia-shell is not in the system profile" "$NOCT_BIN"
	else
		NOCT_SHARE="$(readlink -f "$NOCT_BIN")"
		NOCT_SHARE="${NOCT_SHARE%/bin/noctalia-shell}/share/noctalia-shell"
		[[ -d $NOCT_SHARE ]] || {
			bad "noctalia-shell has no share/noctalia-shell — the scan is broken, not the repo" "$NOCT_SHARE"
			NOCT_SHARE=""
		}
	fi

	# noctalia IGNORES a settings key it does not know, in silence, so a key
	# renamed upstream stops applying and reads exactly like a key that was
	# never set. Both halves of docs/adr/0022 are checked: the first-run seed
	# and the pin merged on every mode entry.
	if [[ -n $NOCT_SHARE ]]; then
		defaults="$NOCT_SHARE/Assets/settings-default.json"
		if [[ ! -f $defaults ]]; then
			bad "noctalia ships no Assets/settings-default.json — the scan is broken, not the repo"
		else
			# settings.json is hand-written under dotfiles/; settings-pinned.json
			# is GENERATED, because one of its keys is the colour scheme's name.
			# Both are read from where they actually land, not from one place.
			keyerr=""
			keys=0
			for f in "$MANGO/noctalia/settings.json" \
				"$GEN_CFG/mango/noctalia/settings-pinned.json"; do
				n=$(jq -r '[paths] | length' "$f" 2>/dev/null || echo 0)
				keys=$((keys + n))
				while read -r p; do
					[[ -z $p ]] && continue
					keyerr+="  $(basename "$f"): $p is not a key noctalia has"$'\n'
				done < <(
					jq -r --slurpfile d "$defaults" \
						'paths as $p | select(($d[0] | getpath($p)) == null) | $p | join(".")' \
						"$f" 2>/dev/null
				)
			done
			if [[ $keys -eq 0 ]]; then
				bad "no keys read from the noctalia settings files — the scan is broken, not the repo"
			elif [[ -z $keyerr ]]; then
				ok "all $keys noctalia settings keys exist in the shipped defaults"
			else
				bad "noctalia settings key mismatch" "$keyerr"
			fi

			# A scheme name that resolves to no file leaves the shell on
			# whatever it last loaded — the machine ends up half this palette and
			# half noctalia purple, which looks like a theme, not a fault.
			# Resolution mirrors ColorSchemeService.resolveSchemePath().
			scheme=$(jq -r '.colorSchemes.predefinedScheme // empty' \
				"$GEN_CFG/mango/noctalia/settings-pinned.json" 2>/dev/null)
			case "$scheme" in
			"Noctalia (default)") schemedir="Noctalia-default" ;;
			"Noctalia (legacy)") schemedir="Noctalia-legacy" ;;
			"Tokyo Night") schemedir="Tokyo-Night" ;;
			"Rose Pine") schemedir="Rosepine" ;;
			*) schemedir="$scheme" ;;
			esac
			if [[ -z $scheme ]]; then
				bad "no predefinedScheme pinned — noctalia would keep its own palette while the rest of the machine follows palette.nix"
			elif [[ -f "$NOCT_SHARE/Assets/ColorScheme/$schemedir/$schemedir.json" ]]; then
				ok "noctalia's pinned colour scheme ($scheme) ships with the package"
			else
				bad "noctalia has no colour scheme named $scheme" \
					"Assets/ColorScheme/$schemedir/$schemedir.json"
			fi

			# And it must be the scheme modes.nix gives the noctalia MODE, not the
			# artefact one. Both halves of that mode's colour now come from the same
			# line — the shell's own palette here, mango's chrome in
			# colors-noctalia.conf — and they are generated in different languages in
			# different files, which is the gap a scheme change walks into. A drift
			# here is a shell in one scheme inside borders in another, and that reads
			# as a design rather than a fault. docs/adr/0034.
			nsch=$(jq -r '.modes.noctalia // empty' "$SCHEMES" 2>/dev/null)
			nwant=$(jq -r ".schemes.\"$nsch\".apps.noctalia // empty" "$SCHEMES" 2>/dev/null)
			if [[ -z $nsch || -z $nwant ]]; then
				bad "could not read the noctalia mode's scheme from modes.nix" \
					"mode='$nsch' name='$nwant' — the agreement below would be asserted about nothing"
			elif [[ $scheme != "$nwant" ]]; then
				bad "noctalia pins '$scheme' but modes.nix gives its mode '$nsch' (= '$nwant')" \
					"the shell and the mango chrome drawn around it would be in different schemes"
			else
				ok "noctalia's pinned scheme matches modes.nix's '$nsch' for its mode"
			fi

			# noctalia's TEMPLATE engine stays off, and that is a decision with a
			# record: docs/adr/0036. Asserted rather than merely written, because
			# its symptom is not an error — a template renders a sidecar and its
			# post-hook edits the app's real config to point at it, so enabling
			# one puts a second writer on `kitty/current-theme.conf` and
			# `foot/themes/noctalia` (both apply_theme's, docs/adr/0034), and the
			# gtk/mango/yazi hooks REPLACE a read-only store symlink with a local
			# copy. Nothing crashes; the repo just stops owning the file.
			#
			# Blunt on purpose: any non-empty list fails, not a blocklist of the
			# harmful names. A blocklist needs updating whenever upstream adds a
			# template and passes by finding nothing when one is renamed.
			tmpl_on=$(jq -r '.templates.enableUserTheming // false' \
				"$GEN_CFG/mango/noctalia/settings-pinned.json" 2>/dev/null)
			tmpl_n=$(jq -r '(.templates.activeTemplates // []) | length' \
				"$GEN_CFG/mango/noctalia/settings-pinned.json" 2>/dev/null)
			if [[ -z $tmpl_on || -z $tmpl_n ]]; then
				bad "could not read noctalia's templates pin — the scan is broken, not the repo" \
					"enableUserTheming='$tmpl_on' activeTemplates='$tmpl_n'"
			elif [[ $tmpl_on != false ]]; then
				bad "noctalia pins enableUserTheming=$tmpl_on" \
					"its templates write kitty's and foot's colours, which apply_theme owns — docs/adr/0036"
			elif [[ $tmpl_n -ne 0 ]]; then
				bad "noctalia pins $tmpl_n active template(s)" \
					"every one either writes a path apply_theme owns or a file nothing here reads — docs/adr/0036"
			else
				ok "noctalia's template engine is off and its template list is empty"
			fi
		fi
	fi

	# `noctalia-shell ipc call <target> <fn>` prints "Target not found." or
	# "Function not found." and EXITS 0 — the dwl-era `mmsg -s -d` shape, which
	# broke five scripts here without a word. The names live in shell.sh's case
	# table and in the `lockscreen` wrapper; the shell declares them as
	# `IpcHandler { target: … function x() }` in its QML. Neither side can see
	# the other, so pair them here.
	#
	# The wrapper is scanned as a BUILT script rather than as a source file:
	# it is generated in pkgs/default.nix, and the unattended lock is the one
	# caller nobody is watching when it fails (docs/adr/0024).
	if [[ -n $NOCT_SHARE ]]; then
		SHELL_SH="$MANGO/scripts/menus/shell.sh"
		mapfile -t IPC_WRAPPER < <(
			sed -n 's/.*noctalia-shell ipc call \([A-Za-z]* [A-Za-z]*\).*/\1/p' \
				"$LOCKBIN" 2>/dev/null
		)
		mapfile -t IPC_PAIRS < <(
			{
				sed -n 's/^[a-z-]*)[[:space:]]*ipc="\([^"]*\)".*/\1/p' "$SHELL_SH"
				printf '%s\n' "${IPC_WRAPPER[@]}"
			} | grep . | sort -u
		)
		if [[ ${#IPC_PAIRS[@]} -eq 0 ]]; then
			bad "no ipc pairs read from shell.sh — the scan is broken, not the repo"
		elif [[ ${#IPC_WRAPPER[@]} -eq 0 ]]; then
			# The wrapper's own floor. Without it the pairs all come from
			# shell.sh and the check passes by finding nothing, while the
			# unattended lock has quietly gone back to swaylock in noctalia mode
			# — a difference you only see at 3am, on the screen you are trying
			# to unlock.
			bad "lockscreen makes no noctalia ipc call — the sleep lock is no longer noctalia's in noctalia mode" \
				"$LOCKBIN"
		else
			mapfile -t IPC_QML < <(grep -rl 'IpcHandler' "$NOCT_SHARE")
			ipcerr=""
			for pair in "${IPC_PAIRS[@]}"; do
				t=${pair%% *}
				f=${pair##* }
				# The function must be inside THAT target's block. Two
				# independent greps would pass `dock clear`, since some other
				# target does declare `clear`. `intgt` is recomputed on every
				# `target:` line, so it closes at the next one.
				awk -v t="$t" -v f="$f" '
					/target: "/ { intgt = ($0 ~ "target: \"" t "\"") }
					intgt && $0 ~ "function " f "\\(" { found = 1; exit }
					END { exit !found }
				' "${IPC_QML[@]}" ||
					ipcerr+="  $t $f is called by shell.sh but noctalia has no such handler"$'\n'
			done
			if [[ -z $ipcerr ]]; then
				ok "all ${#IPC_PAIRS[@]} noctalia ipc calls name a handler the shell declares"
			else
				bad "noctalia ipc mismatch" "$ipcerr"
			fi
		fi
	fi

	# The overlay rewrites noctalia's dwl-era `mmsg -s -d <func>` to mango's verb
	# form (docs/adr/0025). Both halves of that can rot in silence: the patch
	# could stop applying, and a verb could stop being a function mango has —
	# `mmsg` answers an unknown one with `{"error":…}` and exits 0, which is the
	# failure the patch exists to remove, not a new one.
	if [[ -n $NOCT_SHARE ]]; then
		MANGO_BIN="$SYS/sw/bin/mango"
		mapfile -t MMSG_FUNCS < <(
			grep -ohE 'mmsg", "dispatch", "[a-z_]+|mmsg dispatch [a-z_]+' \
				"$NOCT_SHARE/Services/Compositor/MangoService.qml" 2>/dev/null |
				grep -oE '[a-z_]+$' | sort -u
		)
		if [[ ${#MMSG_FUNCS[@]} -lt 5 ]]; then
			# The floor. An unapplied patch leaves every call in the flag form,
			# so this list empties rather than mismatching — the launcher would
			# go back to doing nothing at all, reported by nobody.
			bad "only ${#MMSG_FUNCS[@]} mmsg verb calls in MangoService.qml, expected 5 — the overlay patch is not applied" \
				"$NOCT_SHARE/Services/Compositor/MangoService.qml"
		elif [[ ! -e $MANGO_BIN ]]; then
			bad "no mango binary to check the verbs against — the scan is broken, not the repo" "$MANGO_BIN"
		else
			# mango's own strings are the function table. Extracting whole
			# tokens rather than grepping for each name means `quit` cannot
			# match inside `quitting`.
			#
			# Through a FILE, not a pipe into `grep -q`: `-q` exits at the first
			# match, which SIGPIPEs the writer part-way through a 2,000-line
			# list. That is noise on a hit and a WRONG ANSWER on a miss, since
			# the reader never sees the rest.
			mango_words="${TMPDIR:-/tmp}/mango-words.$$"
			grep -aoE '[a-z_]{3,}' "$MANGO_BIN" | sort -u >"$mango_words"
			mmsgerr=""
			for f in "${MMSG_FUNCS[@]}"; do
				grep -qxF "$f" "$mango_words" ||
					mmsgerr+="  $f is dispatched by noctalia but mango declares no such function"$'\n'
			done
			rm -f "$mango_words"
			if [[ -z $mmsgerr ]]; then
				ok "all ${#MMSG_FUNCS[@]} mmsg verbs noctalia dispatches are functions mango has"
			else
				bad "noctalia dispatches a function mango does not have" "$mmsgerr"
			fi
		fi

		# The lock wrapper calls `noctalia-shell ipc call` by absolute path, and
		# quickshell resolves an instance by the shell.qml PATH it was started
		# from — so a wrapper built against a DIFFERENT derivation than the unit
		# runs finds "No running instances" and hands every unattended lock back
		# to swaylock (docs/adr/0024, 0025). One `prev.` where a `final.` belongs
		# is all it takes, and at runtime that is indistinguishable from noctalia
		# simply being down.
		lock_noct=$(grep -oE '/nix/store/[^ :"]*noctalia-shell[^ :"]*/bin' "$LOCKBIN" 2>/dev/null | head -1)
		sys_noct=$(readlink -f "$SYS/sw/bin/noctalia-shell" 2>/dev/null)
		if [[ -z $lock_noct ]]; then
			bad "lockscreen has no noctalia-shell on its PATH — its ipc call would exit 127" "$LOCKBIN"
		elif [[ ${sys_noct%/bin/noctalia-shell} != "${lock_noct%/bin}" ]]; then
			bad "lockscreen and the system disagree on which noctalia-shell — the lock ipc will never find the running shell" \
				"$lock_noct vs $sys_noct"
		else
			ok "lockscreen's noctalia-shell is the one the unit runs"
		fi
	fi

	# Three files must agree on one unit name — the home-manager unit,
	# night-mode.sh's `UNIT=`, and the stop in noctalia-start.sh — and nothing
	# errors when they stop: `is-active` answers "inactive" for a unit that does
	# not exist, so the guard silently stops matching. docs/adr/0037.
	NOCT_START="$MANGO/scripts/modes/noctalia-start.sh"
	NIGHT_SH="$MANGO/scripts/menus/night-mode.sh"
	nl_unit=$(sed -n 's/^UNIT=\([A-Za-z0-9@._-]*\).*/\1/p' "$NIGHT_SH" | head -1)
	if [[ -z $nl_unit ]]; then
		bad "no UNIT= read from night-mode.sh — the scan is broken, not the repo" "$NIGHT_SH"
	elif [[ ! -f "$GEN_CFG/systemd/user/$nl_unit" ]]; then
		bad "night-mode.sh drives $nl_unit but the generation has no such user unit" \
			"$GEN_CFG/systemd/user/$nl_unit"
	elif ! grep -q "systemctl --user stop ${nl_unit%.service}" "$NOCT_START"; then
		bad "noctalia mode does not stop $nl_unit — night light would stay on in the one mode that cannot reach it" \
			"$NOCT_START"
	elif grep -v '^[[:space:]]*#' "$NOCT_START" | grep -q "pkill.*${nl_unit%.service}"; then
		# Restart=always undoes a kill three seconds later — docs/gotchas.md →
		# night light. Comments stripped first: the script explains that
		# noctalia pkills wlsunset, and this matched that sentence.
		bad "noctalia-start.sh pkills ${nl_unit%.service}; Restart=always brings it straight back" \
			"$NOCT_START"
	else
		ok "noctalia mode stops $nl_unit, the unit night-mode.sh drives"
	fi

	# `layerrule=…,layer_name:X` naming a namespace nothing creates is a rule
	# that never fires and never says so — the same class as the rofi layer
	# rules that matched nothing for months (docs/WORK-LOG.md). noctalia's
	# namespaces are `<name>-<screen>`, so the configs carry an anchored prefix
	# and this asserts the prefix still matches a namespace the shipped QML
	# declares.
	if [[ -n $NOCT_SHARE ]]; then
		mapfile -t NOCT_LAYERS < <(
			grep -rhoE 'layer_name:\^?noctalia[a-z-]*' "$MANGO" --include='*.conf' |
				sed 's/^layer_name:\^\?//' | sort -u
		)
		if [[ ${#NOCT_LAYERS[@]} -eq 0 ]]; then
			bad "no noctalia layer rules found — mango would double every panel animation noctalia plays"
		else
			layererr=""
			for l in "${NOCT_LAYERS[@]}"; do
				grep -rqF "namespace: \"$l" "$NOCT_SHARE" ||
					layererr+="  $l matches no namespace noctalia declares"$'\n'
			done
			if [[ -z $layererr ]]; then
				ok "every noctalia layer rule (${#NOCT_LAYERS[@]}) matches a namespace the shell declares"
			else
				bad "noctalia layer rule mismatch" "$layererr"
			fi
		fi
	fi
fi

# --- power profiles ---------------------------------------------------------
# power-profiles-tlp translates between three things that live in three files
# and have no compiler between them: TLP's numeric state, `power-mode`'s
# argument list, and the PPD bus name. Every one of them fails silently when it
# drifts — a wrong profile name is exit 2 at click time, a wrong code renders a
# stale profile forever, a wrong bus name is a service nothing finds, which is
# indistinguishable from the state this daemon was written to fix.
# docs/adr/0026.
PPD_SRC="$SRC/pkgs/power-profiles-tlp/daemon.py"
PPD_POLICY="$SRC/pkgs/power-profiles-tlp/dbus-policy.conf"
if [[ ! -f $PPD_SRC || ! -f $PPD_POLICY ]]; then
	bad "power-profiles-tlp is missing a source or policy file" "$PPD_SRC $PPD_POLICY"
else
	# 1. The daemon and power-mode must accept the same three profile names.
	#    power-mode rejects anything else with exit 2, which reaches the user as
	#    a slider that snaps back.
	mapfile -t PPD_PROFILES < <(
		sed -n 's/^PROFILES = (\(.*\))$/\1/p' "$PPD_SRC" |
			grep -oE '"[a-z-]+"' | tr -d '"' | sort -u
	)
	mapfile -t MODE_PROFILES < <(
		sed -n 's/^[[:space:]]*\(performance | balanced | power-saver\)) ;;$/\1/p' \
			"$SRC/modules/system/power.nix" | tr -d ' ' | tr '|' '\n' | sort -u
	)
	if [[ ${#PPD_PROFILES[@]} -eq 0 || ${#MODE_PROFILES[@]} -eq 0 ]]; then
		bad "no profile names read from the daemon or from power-mode — the scan is broken, not the repo"
	elif [[ ${PPD_PROFILES[*]} != "${MODE_PROFILES[*]}" ]]; then
		bad "power-profiles-tlp and power-mode disagree on the profile names" \
			"daemon: ${PPD_PROFILES[*]} / power-mode: ${MODE_PROFILES[*]}"
	else
		ok "power-profiles-tlp and power-mode accept the same ${#PPD_PROFILES[@]} profiles"
	fi

	# 2. The daemon and the waybar module both decode /run/tlp/last_pwr, and
	#    nothing makes them agree. `fanless` is this repo's name for TLP's
	#    `power-saver` (docs/adr/0017) and is the ONE deliberate difference, so
	#    it is normalised here rather than tolerated by a looser comparison.
	mapfile -t PPD_CODES < <(
		sed -n 's/^CODE_TO_PROFILE = {\(.*\)}$/\1/p' "$PPD_SRC" |
			grep -oE '"[0-9]": "[a-z-]+"' | tr -d '"' | tr -d ' ' | sort -u
	)
	mapfile -t BAR_CODES < <(
		sed -nE 's/^[[:space:]]*([0-9])\) name=([a-z-]+).*$/\1:\2/p' \
			"$MANGO/scripts/system/power-profile.sh" | sed 's/fanless/power-saver/' | sort -u
	)
	if [[ ${#PPD_CODES[@]} -eq 0 || ${#BAR_CODES[@]} -eq 0 ]]; then
		bad "no last_pwr codes read from the daemon or the waybar module — the scan is broken, not the repo"
	elif [[ ${PPD_CODES[*]} != "${BAR_CODES[*]}" ]]; then
		bad "power-profiles-tlp and the waybar module decode last_pwr differently" \
			"daemon: ${PPD_CODES[*]} / bar: ${BAR_CODES[*]}"
	else
		ok "power-profiles-tlp and the waybar module decode all ${#PPD_CODES[@]} last_pwr codes alike"
	fi

	# 3. One bus name, spelled the same in the daemon and in every rule of the
	#    policy. PPD's name is a fixed external contract, so it is asserted
	#    literally too — a typo made consistently in both files still reaches
	#    no client.
	PPD_NAME=org.freedesktop.UPower.PowerProfiles
	mapfile -t PPD_NAMES < <(
		{
			sed -n 's/^BUS_NAME = "\(.*\)"$/\1/p' "$PPD_SRC"
			grep -oE '(own|send_destination)="[^"]+"' "$PPD_POLICY" | cut -d'"' -f2
		} | sort -u
	)
	if [[ ${#PPD_NAMES[@]} -eq 0 ]]; then
		bad "no bus name read from the daemon or the policy — the scan is broken, not the repo"
	elif [[ ${#PPD_NAMES[@]} -ne 1 || ${PPD_NAMES[0]} != "$PPD_NAME" ]]; then
		bad "the daemon and its dbus policy do not all name $PPD_NAME" "${PPD_NAMES[*]}"
	else
		ok "the daemon and its dbus policy all name $PPD_NAME"
	fi

	# 4. dbus rejects a malformed policy file, and an XML comment containing a
	#    double hyphen is malformed — which this file's first draft was. The
	#    file is loaded by the system bus, so the blast radius is every service
	#    on it, not just this one.
	if ! command -v xmllint >/dev/null; then
		bad "xmllint is absent — the dbus policy went unchecked, which is not a pass"
	elif ! xmllint --noout "$PPD_POLICY" 2>/dev/null; then
		bad "the dbus policy is not well-formed XML — the system bus would reject it" "$PPD_POLICY"
	else
		ok "the dbus policy parses as XML"
	fi

	# 5. The unit must exist in the built system and must pass --power-mode.
	#    Left to a PATH lookup the daemon refuses to start, which is honest but
	#    is a boot-time failure for a thing decided at build time.
	PPD_UNIT="$SYS/etc/systemd/system/power-profiles-tlp.service"
	PPD_PKG=""
	if [[ ! -f $PPD_UNIT ]]; then
		bad "power-profiles-tlp is packaged but no unit runs it — the PPD name would stay unowned" "$PPD_UNIT"
	else
		ppd_exec=$(sed -n 's/^ExecStart=//p' "$PPD_UNIT")
		# The store path the unit actually runs, so check 6 reads the same
		# package rather than one the overlay merely could produce.
		PPD_PKG=${ppd_exec%%/bin/power-profiles-tlp*}
		ppd_mode=$(grep -oE '\-\-power-mode [^ ]+' <<<"$ppd_exec" | awk '{print $2}')
		if [[ -z $ppd_mode ]]; then
			bad "the power-profiles-tlp unit passes no --power-mode — it would start and switch nothing" "$ppd_exec"
		elif [[ ! -x $ppd_mode ]]; then
			bad "the power-profiles-tlp unit names a power-mode that is not executable" "$ppd_mode"
		else
			ok "the power-profiles-tlp unit runs an executable power-mode"
		fi
	fi

	# 6. A running unit is NOT the same as an activatable name, and the
	#    difference is invisible from `systemctl status`. quickshell probes the
	#    name at startup and, finding it unowned, tries to ACTIVATE it — then
	#    gives up for the life of the process when that fails. Observed exactly
	#    once, on the first live run: "The name is not activatable", after which
	#    every noctalia profile call returned early and printed nothing.
	PPD_ACT="$PPD_PKG/share/dbus-1/system-services/$PPD_NAME.service"
	if [[ -z $PPD_PKG ]]; then
		bad "could not resolve the power-profiles-tlp package from the unit — the scan is broken, not the repo"
	elif [[ ! -f $PPD_ACT ]]; then
		bad "power-profiles-tlp ships no dbus activation file — a client that starts first gives up permanently" "$PPD_ACT"
	else
		act_name=$(sed -n 's/^Name=//p' "$PPD_ACT")
		act_unit=$(sed -n 's/^SystemdService=//p' "$PPD_ACT")
		act_exec=$(sed -n 's/^Exec=//p' "$PPD_ACT")
		if [[ $act_name != "$PPD_NAME" ]]; then
			bad "the activation file names $act_name, not $PPD_NAME — dbus would activate nothing"
		elif [[ $act_unit != power-profiles-tlp.service ]]; then
			bad "the activation file names unit $act_unit, which is not the one that serves the name" "$PPD_ACT"
		elif [[ ! -x $act_exec ]]; then
			bad "the activation file's Exec is not executable — the non-systemd fallback would 127" "$act_exec"
		else
			ok "the dbus activation file names $PPD_NAME and an executable power-profiles-tlp.service"
		fi
	fi

	# 7. Two owners for one bus name is docs/adr/0005 verbatim, and the loser
	#    here is whichever starts second — silently, since ours exits 1 into the
	#    journal and PPD would simply serve profiles TLP never applied.
	if [[ -f "$SYS/etc/systemd/system/power-profiles-daemon.service" ]]; then
		bad "power-profiles-daemon is enabled alongside power-profiles-tlp — two owners for $PPD_NAME"
	else
		ok "power-profiles-daemon is absent, so power-profiles-tlp owns $PPD_NAME alone"
	fi
fi

# rofi reads ~/.config/rofi/config.rasi, which is in a different tree from the
# mango configs that use it — the .rasi landing in the repo says nothing about
# rofi finding it. Same shape as elephant's menus.toml before it (docs/adr/0014).
rasi_decl=$(grep -rh 'rofi/config.rasi' "$SRC/modules/home/dotfiles.nix" 2>/dev/null)
if [[ -z $rasi_decl ]]; then
	bad "nothing declares rofi/config.rasi — rofi would fall back to its built-in theme"
elif [[ ! -f "$SRC/dotfiles/rofi/config.rasi" ]]; then
	bad "config.rasi is declared but absent from the source — the scan is broken"
else
	ok "rofi's config.rasi is declared and present"
fi

# rofi's modes come from two places that cannot see each other: the built-ins,
# and the plugins listed in modules/system/desktop.nix. A mode named by
# config.rasi or by a `-show` bind whose plugin is not built makes rofi print
# "Mode <x> is not found" to a stderr nobody is reading and exit 1 — a key that
# does nothing, which is this repo's signature failure. Read what the BUILT
# binary reports rather than the Nix that asked for it: `-h` lists exactly what
# dlopens, so a plugin that builds but fails to load is caught too. `-no-config`
# so the check does not depend on a home directory.
ROFI="$SYS/sw/bin/rofi"
if [[ ! -x $ROFI ]]; then
	bad "no rofi in the system profile — every menu bind would exit 127" "$ROFI"
else
	# 2>&1, not 2>/dev/null: if rofi cannot start, its reason is the only thing
	# separating "the config is wrong" from "the scan is broken", and throwing
	# it away is how a check comes to pass by finding nothing.
	# HOME/XDG_CACHE_HOME: rofi creates a runtime directory before it does
	# anything else, and under the build sandbox `$HOME` is /homeless-shelter.
	# It cannot, warns, and prints no help at all — so the list came back empty
	# and the check read as "the scan is broken", which is exactly what it said.
	rofi_help=$(HOME="$TMPDIR" XDG_CACHE_HOME="$TMPDIR" "$ROFI" -no-config -h 2>&1)
	mapfile -t DETECTED < <(
		printf '%s\n' "$rofi_help" | sed -n '/Detected modes/,/^$/p' |
			sed -n 's/^[[:space:]]*• *+\?\([a-z]*\).*/\1/p'
	)
	mapfile -t WANTED < <(
		{
			# config.rasi's `modes:` list, comma-separated.
			sed -n 's/^ *modes: *"\([^"]*\)".*/\1/p' "$SRC/dotfiles/rofi/config.rasi" | tr ',' '\n'
			# `rofi -show <mode>` in a bind, a script or a waybar click.
			grep -rhoE -- '-show [a-z]+' "$MANGO" "$SRC/modules/home/waybar.nix" 2>/dev/null |
				cut -d' ' -f2
		} | tr -d ' ' | sort -u | sed '/^$/d'
	)
	# The reverse direction needs the Nix: `-h` cannot say which of the modes it
	# lists came from a plugin, so a plugin nothing reaches would hide among the
	# built-ins.
	mapfile -t PLUGINS < <(
		sed -n '/plugins = \[/,/\];/p' "$SRC/modules/system/desktop.nix" |
			sed -n 's/^ *rofi-\([a-z]*\).*/\1/p'
	)
	if [[ ${#DETECTED[@]} -lt 5 ]]; then
		bad "rofi reports only ${#DETECTED[@]} modes — the scan is broken, not the config" \
			"$(printf '%s\n' "$rofi_help" | head -3)"
	elif [[ ${#WANTED[@]} -eq 0 || ${#PLUGINS[@]} -eq 0 ]]; then
		bad "no rofi modes or plugins found in the source — the scan is broken, not the repo"
	else
		moderr=""
		for w in "${WANTED[@]}"; do
			printf '%s\n' "${DETECTED[@]}" | grep -qxF "$w" ||
				moderr+="  $w is named by config.rasi or a bind but rofi does not have it"$'\n'
		done
		for p in "${PLUGINS[@]}"; do
			printf '%s\n' "${DETECTED[@]}" | grep -qxF "$p" ||
				moderr+="  rofi-$p is built but rofi does not load it"$'\n'
			printf '%s\n' "${WANTED[@]}" | grep -qxF "$p" ||
				moderr+="  rofi-$p is built but nothing reaches it"$'\n'
		done
		if [[ -z $moderr ]]; then
			ok "all ${#WANTED[@]} rofi modes reached are loaded, and both ${#PLUGINS[@]} plugins are reached"
		else
			bad "rofi mode mismatch" "$moderr"
		fi
	fi
fi

printf '\nGenerated palette\n'

# waybar/colors.css and rofi/colors.rasi are derived from
# modules/home/palette.nix; the stylesheets that consume them are hand-written
# and reference the names. Both sides fail quietly when they disagree — GTK
# drops a rule naming an undefined @colour and carries on, so the module simply
# renders in the inherited colour, and rofi falls back to its built-in
# Solarized role rather than erroring. Neither writes anywhere anyone reads.
# So: every name used must be defined, and every name defined must be used —
# an unused entry is a colour someone will later assume is live.
palette_pair() {
	local label=$1 defined=$2 used=$3 err=""
	# `@import`, `@keyframes` and friends are CSS/rasi at-rules, not colours.
	used=$(printf '%s\n' "$used" | grep -vxE 'import|keyframes|media|theme|define-color')
	if [[ -z $defined ]]; then
		bad "$label: no colours defined — the generated file is missing or the scan is broken"
		return
	fi
	if [[ -z $used ]]; then
		bad "$label: no colour references found in the stylesheets — the scan is broken"
		return
	fi
	while IFS= read -r n; do
		[[ -z $n ]] && continue
		printf '%s\n' "$defined" | grep -qxF "$n" || err+="  @$n is used but not defined"$'\n'
	done <<<"$used"
	while IFS= read -r n; do
		[[ -z $n ]] && continue
		printf '%s\n' "$used" | grep -qxF "$n" || err+="  @$n is defined but nothing uses it"$'\n'
	done <<<"$defined"
	if [[ -z $err ]]; then
		ok "$label: all $(printf '%s\n' "$defined" | grep -c .) generated colours are used, and every reference resolves"
	else
		bad "$label palette mismatch" "$err"
	fi
}

palette_pair "waybar" \
	"$(sed -n 's/^@define-color \([a-z-]*\) .*/\1/p' "$WAYBAR_DIR/colors.css" 2>/dev/null | sort -u)" \
	"$(grep -ohE '@[a-z-]+' "$SRC"/dotfiles/mango/waybar/style-*.css 2>/dev/null | tr -d '@' | sort -u)"

# rofi, ONCE PER MODE. `colors.rasi` is a runtime symlink since docs/adr/0034
# and does not exist in the generation at all; what home-manager writes is one
# `colors-<mode>.rasi` per mode, and each is a separate file that could
# separately drop a name. `config.rasi` is shared by every menu in every mode
# (and holds behaviour as well as colour), so the USED side is the same for all.
rofi_used=$(grep -ohE '@[a-z-]+' "$SRC/dotfiles/rofi/config.rasi" 2>/dev/null | tr -d '@' | sort -u)
for m in "${MODE_KEYS[@]}"; do
	palette_pair "rofi ($m)" \
		"$(sed -n 's/^ *\([a-z-]*\): *#[0-9a-f]*;.*/\1/p' "$GEN_CFG/rofi/colors-$m.rasi" 2>/dev/null | sort -u)" \
		"$rofi_used"
done

# Every file that is supposed to be derived from the palette, and the colour it
# must contain. A generated file that goes missing or renders empty is this
# repo's signature bug: the app falls back to its own defaults and looks merely
# unstyled, which is indistinguishable from a theme someone chose.
#
# The value checked is the accent in each consumer's own spelling, because the
# spelling is where copies hid — `d79921` is `0xd79921ff` to mango and
# `rgb(215, 153, 33)` to fsel and swaync, and a repo-wide grep for the hex found
# neither.
# Read the accent from the RESOLVED palette, not from a hex typed here — a
# check carrying its own copy of the value it is checking passes forever and
# proves nothing. It used to be read back out of `rofi/colors.rasi`, one of the
# generated consumers, because that was the only Nix-resolved value available;
# `$SCHEMES` is now that value at the source, and `colors.rasi` stopped being a
# generated file when it became a runtime symlink (docs/adr/0034). Nothing is
# lost by moving up: the scans below are what prove the generation, and they
# prove it in each consumer's own spelling.
ACCENT=$(pal .accent)

# Everything else comes from the RESOLVED palette, via `pal` (defined at the top
# of this file, alongside the schemes JSON it reads).

# The name is still read out of scheme.nix by hand, and cross-checked against
# what Nix resolved. Nix would fail to import a theme file that does not exist,
# so this cannot catch a typo — what it catches is the two drifting apart: a
# scheme.nix that stopped being the file the build actually read, which would
# make every message below name the wrong scheme while passing.
SCHEME=$(sed -n 's/^"\(.*\)"$/\1/p' "$SRC/modules/home/scheme.nix" 2>/dev/null | tail -1)
THEME_FILE="$SRC/modules/home/themes/$SCHEME.nix"
if [[ -z $SCHEME || ! -s $THEME_FILE ]]; then
	bad "scheme.nix names '$SCHEME', which is not a file in modules/home/themes/" \
		"every palette scan below would read an empty file"
elif [[ $SCHEME != "$PAL_SCHEME" ]]; then
	bad "scheme.nix says '$SCHEME' but the build resolved '$PAL_SCHEME'" \
		"every scan below would audit a scheme this machine is not wearing"
else
	ok "scheme.nix selects '$SCHEME' as the artefact scheme, and themes/$SCHEME.nix exists"
fi
# The artefact scheme's muted accent used to be read here too, for ncspot. It
# is per mode now (docs/adr/0034 phase 3) and resolved per scheme inside the
# swap loop; a copy here would only be a value nothing reads.
if [[ $ACCENT =~ ^[0-9a-f]{6}$ ]]; then
	ACCENT_RGB="rgb($((16#${ACCENT:0:2})), $((16#${ACCENT:2:2})), $((16#${ACCENT:4:2})))"
else
	bad "could not read the accent from the palette" \
		"accent='$ACCENT' — every scan below would pass on an empty needle"
	ACCENT="__unreadable__"
	ACCENT_RGB="__unreadable__"
fi

while IFS='|' read -r path want label; do
	[[ -z $path ]] && continue
	if [[ ! -s "$GEN_CFG/$path" ]]; then
		bad "$label: $path is missing or empty — the consumer falls back to its own theme, silently"
	elif ! grep -qF "$want" "$GEN_CFG/$path"; then
		bad "$label: $path does not contain $want" "generated, but not from modules/home/palette.nix"
	else
		ok "$label: $path is generated from the palette"
	fi
done <<-EOF
	fsel/config.toml|${ACCENT_RGB}|fsel
	swaync/style.css|${ACCENT_RGB}|swaync
EOF
# ncspot and Equibop used to be two more rows here, against the ARTEFACT accent.
# They are per mode since docs/adr/0034 phase 3 and are checked in the swap loop
# below instead — a row here would now audit whichever mode `tiling` happens to
# be, and pass a mode nobody had looked at.

# mango's chrome, per mode, each in the scheme modes.nix gives that mode
# (docs/adr/0034). Deliberately NOT a row in the table above: the needle differs
# per file now, and checking all three against the artefact accent would pass a
# mode whose generated colours had silently stayed on the wrong scheme — which
# is the whole drift the split exists to make visible.
#
# `focuscolor`, not `bordercolor`. The border role differs by mode BY DESIGN
# (surface in tiling, overlay in noctalia — docs/adr/0022), so it is the
# one line that proves nothing about which scheme produced the file. The accent
# is the same role in all three.
modes_seen=0
while IFS='|' read -r m mscheme; do
	[[ -z $m ]] && continue
	modes_seen=$((modes_seen + 1))
	macc=$(jq -r ".schemes.\"$mscheme\".accent // empty" "$SCHEMES" 2>/dev/null)
	mconf="$GEN_CFG/mango/universal/colors-$m.conf"
	if [[ ! $macc =~ ^[0-9a-f]{6}$ ]]; then
		bad "mango ($m): modes.nix names '$mscheme', which has no accent in the resolved schemes" \
			"the scan below would pass on an empty needle"
	elif [[ ! -s $mconf ]]; then
		bad "mango ($m): colors-$m.conf is missing or empty" \
			"mango skips a source= it cannot resolve without a word and keeps its own built-in colours"
	elif ! grep -qxF "focuscolor=0x${macc}ff" "$mconf"; then
		bad "mango ($m): colors-$m.conf does not carry the accent of '$mscheme' (0x${macc}ff)" \
			"generated, but not from the scheme modes.nix gives this mode"
	else
		ok "mango ($m): colors-$m.conf is generated from '$mscheme'"
	fi
done < <(jq -r '.modes | to_entries[] | "\(.key)|\(.value)"' "$SCHEMES" 2>/dev/null)
if [[ $modes_seen -eq 0 ]]; then
	bad "no modes read from modules/home/modes.nix — the scan is broken, not the repo"
fi

# The runtime colour swap — docs/adr/0034. Three things have to hold, each
# silent on its own:
#
#   1. the sidecar exists and carries THAT mode's accent in that consumer's own
#      spelling — copies have hidden in the spelling before;
#   2. the config that reads it still contains the include;
#   3. the LINK path is not also an xdg.configFile — two owners for one path is
#      an activation failure, and `rofi/colors.rasi` was one until adr/0034.
swap_seen=0
while IFS='|' read -r m mscheme; do
	[[ -z $m ]] && continue
	macc=$(jq -r ".schemes.\"$mscheme\".accent // empty" "$SCHEMES" 2>/dev/null)
	if [[ ! $macc =~ ^[0-9a-f]{6}$ ]]; then
		bad "swap ($m): no accent resolved for '$mscheme' — the scans below would pass on an empty needle"
		continue
	fi
	# ncspot draws its rows in the `muted` set, not the canonical ramp, so its
	# needle is a different colour from the same scheme — the one row here where
	# the main accent would pass a file generated from the wrong palette half.
	mmacc=$(jq -r ".schemes.\"$mscheme\".muted.accent // empty" "$SCHEMES" 2>/dev/null)
	if [[ ! $mmacc =~ ^[0-9a-f]{6}$ ]]; then
		bad "swap ($m): no muted accent resolved for '$mscheme' — the ncspot scan would pass on an empty needle"
		continue
	fi
	# <path>|<needle>|<label>. The needle differs by consumer on purpose.
	while IFS='|' read -r path want label; do
		[[ -z $path ]] && continue
		swap_seen=$((swap_seen + 1))
		if [[ ! -s "$GEN_CFG/$path" ]]; then
			bad "swap ($m): $path is missing or empty" \
				"apply_theme refuses to link a target it cannot find, so the mode switch would leave the colours where they were and say so"
		elif ! grep -qF "$want" "$GEN_CFG/$path"; then
			bad "swap ($m): $path does not carry '$mscheme'\''s accent as $want" \
				"generated, but not from the scheme modes.nix gives this mode"
		else
			ok "swap ($m): $label is generated from '$mscheme'"
		fi
	done <<-EOF
		kitty/colors-$m.conf|#${macc}|kitty
		foot/colors-$m|${macc}|foot
		rofi/colors-$m.rasi|#${macc}|rofi
		ncspot/colors-$m.toml|#${mmacc}|ncspot
		equibop/themes/$m.theme.css|#${macc}|equibop
	EOF

	# Equibop DISPLAYS `@name`, and a name is not a colour — it read `Catppuccin
	# Mocha` through two scheme changes because every scan here greps for hex.
	eqfile="$GEN_CFG/equibop/themes/$m.theme.css"
	if [[ ! -s $eqfile ]]; then
		: # already reported as missing by the loop above
	elif grep -qF "@name $m ($mscheme)" "$eqfile"; then
		ok "swap ($m): equibop announces itself as '$m ($mscheme)'"
	else
		bad "swap ($m): equibop's @name is not '$m ($mscheme)'" \
			"the name Equibop shows has drifted from the mode and scheme that generated the file"
	fi

	# ncspot is drawn ENTIRELY from `muted`, and the needle above only proves
	# that half was reached. `p.accent` where `m.accent` was meant is the right
	# scheme and the wrong half — measured, it passed every other check here.
	# So every hex in the file must be a `muted` value.
	nfile="$GEN_CFG/ncspot/colors-$m.toml"
	mapfile -t mvals < <(jq -r ".schemes.\"$mscheme\".muted | to_entries[] | .value" "$SCHEMES" 2>/dev/null)
	if [[ ${#mvals[@]} -eq 0 ]]; then
		bad "swap ($m): '$mscheme' resolved no muted colours — the scan below would call every hex a stray"
	elif [[ ! -s $nfile ]]; then
		: # already reported as missing by the loop above
	else
		stray=""
		while read -r hex; do
			[[ -z $hex ]] && continue
			printf '%s\n' "${mvals[@]}" | grep -qxF "$hex" || stray+=" $hex"
		done < <(grep -oE '#[0-9a-f]{6}' "$nfile" | tr -d '#' | sort -u)
		if [[ -z $stray ]]; then
			ok "swap ($m): every colour in ncspot's config is from '$mscheme''s muted set"
		else
			bad "swap ($m): ncspot's config carries colours outside '$mscheme''s muted set:$stray" \
				"the right scheme and the wrong half of it — the accent scan above cannot see this"
		fi
	fi
done < <(jq -r '.modes | to_entries[] | "\(.key)|\(.value)"' "$SCHEMES" 2>/dev/null)
if [[ $swap_seen -eq 0 ]]; then
	bad "no per-mode colour sidecars scanned — the scan is broken, not the repo"
else
	ok "$swap_seen per-mode colour sidecars scanned"
fi

# 2. The include lines. A sidecar nothing reads is the same as no sidecar, and
# neither kitty nor foot says anything about a colour file it never opened.
while IFS='|' read -r path want label; do
	[[ -z $path ]] && continue
	if [[ ! -s "$GEN_CFG/$path" ]]; then
		bad "$label: $path is missing — the swap has nothing to reach it through"
	elif ! grep -qF "$want" "$GEN_CFG/$path"; then
		bad "$label: $path does not contain '$want'" \
			"the per-mode colours are generated and then read by nothing; the app keeps its built-in palette"
	else
		ok "$label: reads its colours through the runtime link"
	fi
done <<-EOF
	kitty/kitty.conf|include current-theme.conf|kitty
	foot/foot.ini|include=~/.config/foot/themes/noctalia|foot
	rofi/config.rasi|@import "colors"|rofi
EOF

# 3. The four link paths must NOT be in the generation. home-manager would own
# a path apply_theme re-points on every mode switch, which is two owners for one
# file — and the rebuild after would either fight it or back it up forever.
ownerr=""
for link in kitty/current-theme.conf foot/themes/noctalia rofi/colors.rasi ncspot/config.toml; do
	[[ -e "$GEN_CFG/$link" ]] && ownerr+="  $link"$'\n'
done
if [[ -z $ownerr ]]; then
	ok "the four runtime colour links are owned by apply_theme alone, not by home-manager"
else
	bad "a runtime colour link is also an xdg.configFile — two owners for one path" "$ownerr"
fi

# And apply_mode has to CALL it. The rows above prove every file exists; this is
# the one that proves anything reads them at a mode switch. Same shape as the
# idle-inhibitor assertion, and for the same reason: a mode switch that quietly
# skips a step looks exactly like a mode switch.
# SC2016: `$mode` is the literal text being searched for in lib.sh, not a
# variable to expand here.
# shellcheck disable=SC2016
if grep -qE '^\s*apply_theme "\$mode"' "$MANGO/scripts/lib.sh"; then
	ok "apply_mode re-points the colour links on every mode switch"
else
	bad "apply_mode does not call apply_theme" \
		"the per-mode colours would be generated and the links would never move"
fi

# nvim is the one consumer whose generated file is CONDITIONAL. A scheme that
# matches its own plugin takes upstream's colours and emits no palette.lua at
# all (THEME-MIGRATION §3) — so "the file is missing" is correct for three of
# the five schemes and a failure for the other two. Which case applies is read
# from the theme, not assumed.
#
# The plugin spec is checked either way, because that file is always generated
# and naming the wrong plugin is the failure that produces a hybrid.
NVIM_SPEC=$(pal .apps.nvim.spec)
NVIM_NAME=$(pal .apps.nvim.name)
NVIM_OVERRIDES=$(jq -r "(.schemes.\"$PAL_SCHEME\".apps.nvim.palette | length) > 0" "$SCHEMES" 2>/dev/null)
CS="$GEN_CFG/nvim/lua/plugins/colorscheme.lua"

if [[ -z $NVIM_SPEC || -z $NVIM_NAME ]]; then
	bad "could not read apps.nvim from the palette" \
		"spec='$NVIM_SPEC' name='$NVIM_NAME' — the scans below would pass on an empty needle"
elif [[ ! -s $CS ]]; then
	bad "nvim: lua/plugins/colorscheme.lua is missing or empty" \
		"lazy.nvim would load no colourscheme and nvim would look merely unstyled"
elif ! grep -qF "\"$NVIM_SPEC\"" "$CS"; then
	bad "nvim: colorscheme.lua does not name $NVIM_SPEC" "generated, but not from the theme file"
elif ! grep -qF "vim.cmd.colorscheme(\"$NVIM_NAME\")" "$CS"; then
	bad "nvim: colorscheme.lua never applies '$NVIM_NAME'" \
		"the plugin loads and the scheme is never set — nvim falls back in silence"
else
	ok "nvim: colorscheme.lua loads $NVIM_SPEC and applies '$NVIM_NAME'"
fi

# lualine throws at startup on a theme name it cannot resolve, rather than
# falling back, so the generated names file has to carry one.
if [[ -z $(sed -n 's/.*lualine = "\([^"]*\)".*/\1/p' "$GEN_CFG/nvim/lua/config/scheme.lua" 2>/dev/null) ]]; then
	bad "nvim: lua/config/scheme.lua carries no lualine theme" \
		"lualine errors on an unresolvable theme instead of falling back"
else
	ok "nvim: scheme.lua names a lualine theme"
fi

if [[ $NVIM_OVERRIDES == true ]]; then
	if [[ ! -s "$GEN_CFG/nvim/lua/config/palette.lua" ]]; then
		bad "nvim: '$SCHEME' declares palette overrides but no palette.lua was generated"
	elif ! grep -qF "#${ACCENT}" "$GEN_CFG/nvim/lua/config/palette.lua"; then
		bad "nvim: palette.lua does not contain #${ACCENT}" "generated, but not from the palette"
	else
		ok "nvim: palette.lua is generated from the palette"
	fi
elif [[ -e "$GEN_CFG/nvim/lua/config/palette.lua" ]]; then
	bad "nvim: '$SCHEME' declares no palette overrides, but palette.lua exists" \
		"a stale override file would recolour the plugin behind the scheme's back"
else
	ok "nvim: '$SCHEME' takes its plugin's own colours, and no palette.lua is generated"
fi

# The mode configs must actually `source=` the generated file. mango skips an
# include it cannot resolve without a word, so a renamed file or a dropped line
# leaves the colours at mango's built-in defaults — which are also dark, also
# plausible, and nowhere stated to be wrong.
for mode in "${MODES[@]}"; do
	if grep -qxF "source=./universal/colors-$mode.conf" "$SRC/dotfiles/mango/$mode/$mode.conf" 2>/dev/null; then
		ok "mango: $mode.conf sources its generated colours"
	else
		bad "mango: $mode/$mode.conf does not source ./universal/colors-$mode.conf" \
			"the generated palette is built and then never read"
	fi
done

# Equibop enables its theme BY FILENAME and ignores a name matching no file,
# without logging. The name apply_theme writes must be one home-manager
# generates — two languages, two directories, one string. The name is the
# MODE's since adr/0034, so what must agree is the suffix, for every mode.
# SC2016: `$mode` is the literal text being searched for in lib.sh, not a
# variable to expand here.
# shellcheck disable=SC2016
eq_suffix=$(sed -n 's/.*--arg t "\$mode\(\.[^"]*\)".*/\1/p' \
	"$SRC/dotfiles/mango/scripts/lib.sh" 2>/dev/null | head -1)
if [[ -z $eq_suffix ]]; then
	bad "could not read the Equibop theme name from lib.sh" \
		"it is no longer '--arg t \"\$mode<suffix>\"' — the agreement check would pass on an empty needle"
else
	eqmiss=""
	for m in "${MODES[@]}"; do
		[[ -s "$GEN_CFG/equibop/themes/$m$eq_suffix" ]] || eqmiss+="  $m$eq_suffix"$'\n'
	done
	if [[ -z $eqmiss ]]; then
		ok "equibop: lib.sh enables <mode>$eq_suffix, and every mode has one generated"
	else
		bad "equibop: lib.sh enables '<mode>$eq_suffix', which home-manager does not generate for every mode" \
			"Equibop ignores a missing theme silently — Discord just stays unstyled:"$'\n'"$eqmiss"
	fi
fi

# The ceiling. Every palette hex has exactly one home now; a copy reappearing
# in a hand-written file is the drift the whole arrangement exists to prevent,
# and it reads as deliberate once it is there.
#
# The needles are READ FROM palette.nix rather than listed here. A hardcoded
# list is fine until the scheme changes, at which point it scans for colours the
# machine no longer uses, matches nothing, and reports success — this repo's
# signature bug, in the check that exists to catch it. Whoever changes the
# palette should not also have to remember to change the scanner.
#
# Hence the floor immediately below: an empty or short list means the sed
# stopped matching (a reformat, a renamed block), and every scan after it would
# pass on an empty needle.
#
# Exempt, deliberately (docs/SYSTEM.md §6): the Kvantum theme and the GTK
# colors.css files, which are Breeze's palette and not this one. The yazi flavor
# used to be exempt too and is now fetched into the store instead, so it is no
# longer under dotfiles/ to be scanned.
#
# Tracked files only, via is_tracked — mango/config.conf is written at runtime
# by the mode scripts from the generated file, so it legitimately holds a copy
# of the colours and is deliberately untracked (docs/adr/0002). Without this
# filter a working-tree run reports a failure that `nix flake check`, which sees
# only tracked files, does not — and a check that disagrees with the gate is
# worse than no check.
PALETTE_HEX=$(
	sed -n 's/.*= "\([0-9a-f]\{6\}\)";.*/\1/p' "$SRC"/modules/home/themes/*.nix 2>/dev/null |
		sort -u
)
PALETTE_N=$(printf '%s\n' "$PALETTE_HEX" | grep -c . || true)
if ((PALETTE_N < 16)); then
	bad "only $PALETTE_N hex values read from modules/home/themes/, expected at least 16" \
		"the scan below would pass by finding nothing"
	PALETTE_HEX="__unreadable__"
else
	ok "read $PALETTE_N palette values to scan for"
fi

stray=$(
	grep -rlniE "($(printf '%s\n' "$PALETTE_HEX" | paste -sd'|'))" \
		"$SRC/dotfiles" 2>/dev/null |
		grep -vE '/(Kvantum|gtk-3\.0|gtk-4\.0)/' |
		grep -vE '/rofi/config\.rasi$' |
		while IFS= read -r f; do
			rel=${f#"$SRC"/}
			is_tracked "$rel" && printf '%s\n' "$f"
		done || true
)
if [[ -z $stray ]]; then
	ok "no palette hex outside modules/home/themes/ and the exempt theme data"
else
	bad "palette hex found in hand-written files" "$(printf '%s\n' "$stray" | sed "s|^$SRC/||")"
fi

# The ceiling above has a blind spot, and it is structural rather than a bug:
# it greps for the hexes the CURRENT themes declare, so a colour NO theme names
# matches nothing and reads as a pass. `#d5c4a1` — gruvbox's `fg2`, which this
# palette does not have a role for — sat in programs.nix as kitty's inactive tab
# foreground through gruvbox -> Catppuccin -> gruvbox, wearing a scheme the
# machine had stopped running. Found by hand on 2026-08-19 while moving kitty's
# colours out; nothing in the repo could have found it.
#
# So: no six-digit hex literal in any .nix outside modules/home/themes/, which
# is where colours are declared and the only place they may be spelled. The pass
# state is zero matches, so the floor is on the number of FILES scanned.
mapfile -t NIXSCAN < <(
	find "$SRC/modules" "$SRC/pkgs" -name '*.nix' -not -path '*/themes/*' 2>/dev/null
)
if [[ ${#NIXSCAN[@]} -lt 10 ]]; then
	bad "only ${#NIXSCAN[@]} .nix files found outside themes/ — the scan is broken, not the repo"
else
	lithex=$(grep -nHoE '"#?[0-9a-fA-F]{6}"' "${NIXSCAN[@]}" 2>/dev/null | sed "s|^$SRC/||")
	if [[ -z $lithex ]]; then
		ok "no hex literal in ${#NIXSCAN[@]} .nix files outside modules/home/themes/"
	else
		bad "a colour is spelled outside modules/home/themes/" \
			"$(printf '%s\n' "$lithex" | tr '\n' ' ') — a hex no theme declares is invisible to the drift ceiling above"
	fi
fi

# The artefacts the palette cannot colour: GTK, Kvantum, icon and cursor themes.
# Each is a NAME some other program resolves internally, and every one of them
# fails the same way — the program falls back to its own default and looks
# merely unstyled, which is indistinguishable from a theme someone chose. GTK
# drops to Adwaita, Kvantum to its built-in style, and a cursor name that
# matches nothing leaves the X11 default.
#
# So: the name a theme declares must exist as a real directory in the built
# closure. `attr = null` means a toolkit built-in with nothing to install — that
# is not checkable here and is exempt, which is exactly why the count of them is
# reported rather than passed over.
printf '\nTheme packages\n'

# Where each artefact actually LANDS, which is not one place — and for Kvantum
# it is not ONE place either. A scheme's own Kvantum theme is linked into
# ~/.config/Kvantum by dotfiles.nix (Kvantum reads that, not XDG_DATA_DIRS),
# while the built-ins the stand-in schemes name ship inside the style plugin on
# the profile. Both are searched, so a built-in is verified rather than waved
# through — which is the whole point of having this check at all.
pkg_roots() {
	case $1 in
	gtk) printf '%s\n' "$GEN/home-path/share/themes" ;;
	kvantum) printf '%s\n%s\n' "$GEN_CFG/Kvantum" "$GEN/home-path/share/Kvantum" ;;
	icons | cursor) printf '%s\n' "$GEN/home-path/share/icons" ;;
	esac
}

declared=0
standins=""
for kind in gtk kvantum icons cursor; do
	name=$(pal ".packages.$kind.name")
	attr=$(pal ".packages.$kind.attr")
	native=$(pal ".packages.$kind.native")
	if [[ -z $name ]]; then
		bad "theme packages: '$SCHEME' declares no name for $kind" \
			"the consumer would fall back to its own default, silently"
		continue
	fi
	declared=$((declared + 1))
	[[ $native == true ]] || standins+="  $kind → $name ($(pal ".packages.$kind.why"))"$'\n'

	# Search where the running session reads, not the store path the theme file
	# implies: a package that is declared but never installed fails here. This
	# runs for `attr = null` too — a toolkit built-in still has to BE there, and
	# "Adwaita-dark" was caught by exactly this: GTK3 renders it from compiled-in
	# resources, so it works and no directory for it exists anywhere. A name only
	# GTK can resolve is a name no check can, so the theme files name a real
	# package instead.
	#
	# `find -L`, and the -L is load-bearing. buildEnv collapses a share/
	# subdirectory with a single contributor into a SYMLINK to that package, and
	# merges it into a real directory when several contribute. So share/themes is
	# a symlink (only the GTK theme provides one) while share/icons is a real
	# directory — and a plain `find` silently returns nothing for the first and
	# works for the second. Which of the two you get depends on the scheme, which
	# is the worst possible way for a check to fail.
	hit=""
	hit_path=""
	while IFS= read -r root; do
		[[ -z $root ]] && continue
		found=$(find -L "$root" -maxdepth 1 -name "$name" 2>/dev/null | head -1)
		if [[ -n $found ]]; then
			hit=${root#"$GEN/"}
			hit_path=$found
			break
		fi
	done < <(pkg_roots "$kind")

	if [[ -n $hit ]]; then
		ok "$kind: '$name' resolves in $hit"
	else
		bad "$kind: '$name' is in none of $(pkg_roots "$kind" | tr '\n' ' ')" \
			"declared by themes/$SCHEME.nix from '${attr:-a toolkit built-in}' — the app falls back in silence"
	fi

	# One level below the scan above, and the level that actually bit: GTK4
	# ignores `gtk-theme-name` outright, so home-manager themes it by writing an
	# `@import` of `<theme>/gtk-4.0/gtk.css` into ~/.config/gtk-4.0/gtk.css.
	# A theme with no gtk-4.0 directory makes that import fail at parse time and
	# drops every libadwaita app to Adwaita — with GTK3 still themed, so the two
	# toolkits merely LOOK different. `gruvbox-dark-gtk` shipped exactly that,
	# and the directory check above passed it. docs/gotchas.md → Theming.
	if [[ $kind == gtk && -n $hit_path ]]; then
		if [[ -r "$hit_path/gtk-4.0/gtk.css" ]]; then
			ok "gtk: '$name' ships gtk-4.0/gtk.css, so GTK4 apps are themed too"
		else
			bad "gtk: '$name' has no gtk-4.0/gtk.css" \
				"the @import home-manager writes into ~/.config/gtk-4.0/gtk.css fails and libadwaita apps fall back to Adwaita, while GTK3 stays themed"
		fi
	fi
done

if [[ $declared -lt 4 ]]; then
	bad "only $declared of 4 theme packages declared by '$SCHEME'" \
		"the scan above would pass by finding nothing"
elif [[ -z $standins ]]; then
	ok "all 4 theme packages follow '$SCHEME'"
else
	# NOT a failure. A stand-in is a deliberate, declared choice — but it is one
	# nobody can see on screen without knowing to look, so it is stated on every
	# run rather than left to be discovered.
	ok "$declared theme packages declared for '$SCHEME'; stand-ins:"$'\n'"$standins"
fi

# The cursor has a second consumer the scan above cannot see. mango takes the
# theme by name in its own config and, finding nothing, hands the name to
# wlroots and carries on — then `setenv`s XCURSOR_THEME from it for every client
# it spawns, so a stale name silently overrides home.pointerCursor for the whole
# session. It sat at `catppuccin-mocha-mauve-cursors` through two scheme changes
# because nothing here read it. So: the compositor's name must be the SAME name
# that just resolved, and no hand-written mango file may set it again.
cursor_name=$(pal '.packages.cursor.name')
cursor_conf="$GEN_CFG/mango/universal/cursor.conf"
if [[ ! -f $cursor_conf ]]; then
	bad "mango cursor: $cursor_conf is not in the built closure" \
		"universal/settings.conf source=s it; mango would leave the wlroots default"
else
	mango_cursor=$(sed -n 's/^cursor_theme=//p' "$cursor_conf")
	if [[ $mango_cursor == "$cursor_name" ]]; then
		ok "mango cursor: '$mango_cursor' matches the scheme's cursor theme"
	else
		bad "mango cursor: names '$mango_cursor', scheme declares '$cursor_name'" \
			"the pointer falls back in silence and XCURSOR_THEME follows it"
	fi
fi

stray_cursor=$(grep -rln '^[[:space:]]*cursor_theme=' "$SRC/dotfiles/mango" 2>/dev/null || true)
if [[ -z $stray_cursor ]]; then
	ok "no hand-written cursor_theme under dotfiles/mango"
else
	bad "cursor_theme hardcoded in a hand-written mango file" \
		"$(printf '%s\n' "$stray_cursor" | sed "s|^$SRC/||") — generate it from home.pointerCursor instead"
fi

# Contrast. THE ONE PROPERTY NOTHING USED TO CHECK — docs/THEME-MIGRATION.md §4
# said so in as many words: "what it does not catch: whether the new colours are
# legible". That gap shipped a scheme whose comments sat at 3.36:1, which reads
# as a considered choice rather than a mistake, because every colour in it was
# individually plausible.
#
# Ratios are WCAG 2.x relative luminance, recomputed here from the RESOLVED
# palette on every run rather than copied from whoever last did the arithmetic.
#
# TWO FLOORS, because two different promises are being made:
#
#   contrastFloor  what THIS MACHINE draws text with — the bar, the menus,
#                  notifications, editor chrome, ncspot's rows
#   ansiFloor      the sixteen terminal slots, which nothing here draws text in;
#                  they are what OTHER programs print with, and they are the
#                  scheme's published identity
#
# They were one number until 2026-08-18, which worked only because Catppuccin's
# ANSI set IS its accent set. Gruvbox's normal red is 2.69:1 by upstream's
# design, so one combined floor would have had to be 2.6 for that scheme — and
# `comment`, the role the whole check exists for, could then have rotted to the
# same place unnoticed. docs/adr/0032.
#
# Both floors are declared BY the theme, and there is NO global minimum under
# them. There was one — 3.0 — and it was removed on 2026-08-18 as an invention:
# it came in with `mocha-high-contrast`, out of a request for more readable text,
# and then read like an external requirement. It is not one. Nord ships its
# comment colour at 1.69:1 and that is Nord; a floor that forbids it is this
# repo overruling upstream rather than recording it.
#
# What the assertion means is therefore exactly and only: **this theme is as
# legible as it claims to be**. That still catches the thing worth catching — a
# future edit that dims a role below what its own theme file declares — without
# deciding for anyone which schemes are allowed to exist.

contrast() {
	awk -v a="$1" -v b="$2" '
		function lin(c) { c = c / 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
		function lum(h,   r, g, b) {
			r = lin(strtonum("0x" substr(h, 1, 2)))
			g = lin(strtonum("0x" substr(h, 3, 2)))
			b = lin(strtonum("0x" substr(h, 5, 2)))
			return 0.2126 * r + 0.7152 * g + 0.0722 * b
		}
		BEGIN {
			la = lum(a); lb = lum(b)
			hi = la > lb ? la : lb; lo = la > lb ? lb : la
			printf "%.2f", (hi + 0.05) / (lo + 0.05)
		}'
}

# Audited for EVERY scheme this machine wears, not only the artefact one.
# modes.nix can put a second scheme on screen (docs/adr/0034), and a floor that
# only ever measured scheme.nix's would report a clean bill of health for a mode
# nobody can read — the check passing by never looking, which is the failure
# this whole file is built against. `.schemes` holds exactly the in-use set, so
# a scheme cannot enter service unaudited.
#
# Each scheme is measured against ITS OWN declared floors. There is no global
# minimum under them: the assertion is "this theme is as legible as it claims",
# and Nord's comment colour is 1.69:1 and that is Nord (docs/adr/0032).
mapfile -t IN_USE < <(jq -r '.schemes | keys[]' "$SCHEMES" 2>/dev/null)
if [[ ${#IN_USE[@]} -eq 0 ]]; then
	bad "no schemes read from the resolved schemes JSON — the scan is broken, not the repo"
fi
for PAL_SCHEME in "${IN_USE[@]}"; do
	FLOOR=$(pal .contrastFloor)
	AFLOOR=$(pal .ansiFloor)
	THEME_BG=$(pal .bg0)
	MUTED_SURFACE=$(pal .muted.surface)
	MUTED_FG=$(pal .muted.fg)
	MUTED_ERR=$(pal .muted.err)

	if [[ -z $FLOOR || -z $AFLOOR || -z $THEME_BG || -z $MUTED_SURFACE || -z $MUTED_FG || -z $MUTED_ERR ]]; then
		bad "could not read the floors or reference colours from themes/$PAL_SCHEME.nix" \
			"floor='$FLOOR' ansi='$AFLOOR' bg0='$THEME_BG' muted.surface='$MUTED_SURFACE' muted.fg='$MUTED_FG' muted.err='$MUTED_ERR' — every ratio below would be computed against nothing"
	else
		worst=""
		worst_n=""
		fails=""

		audit() { # <ratio> <label> <floor>
			awk -v r="$1" -v f="$3" 'BEGIN { exit !(r < f) }' &&
				fails+="  $2: $1 < $3"$'\n'
			if [[ -z $worst ]] || awk -v r="$1" -v w="$worst" 'BEGIN { exit !(r < w) }'; then
				worst=$1
				worst_n=$2
			fi
		}

		# What this machine draws text with, against `bg0`.
		for role in fg0 fg1 fg4 brBlack brWhite comment accent okColor warnColor errColor infoColor; do
			h=$(pal ".$role")
			if [[ ! $h =~ ^[0-9a-f]{6}$ ]]; then
				fails+="  $role: not a colour in the resolved palette ('$h')"$'\n'
				continue
			fi
			audit "$(contrast "$h" "$THEME_BG")" "$role #$h on bg0" "$FLOOR"
		done

		# ncspot's muted set against ITS OWN surface — ncspot fills whole rows with
		# that colour, so bg0 is the wrong reference and using it passes values that
		# fail where they are actually drawn.
		for role in fg dim accent ok; do
			h=$(pal ".muted.$role")
			if [[ ! $h =~ ^[0-9a-f]{6}$ ]]; then
				fails+="  muted.$role: not a colour in the resolved palette ('$h')"$'\n'
				continue
			fi
			audit "$(contrast "$h" "$MUTED_SURFACE")" "muted.$role #$h on muted.surface" "$FLOOR"
		done

		# `muted.err` is a BACKGROUND — ncspot sets `error_bg` from it and draws
		# `error_fg` (= `muted.fg`) on top. Auditing it as a foreground against
		# `surface` is a pair ncspot never draws, and it passed a live theme whose
		# error row was **1.28:1**: light grey-blue text on light pink. The check was
		# not lenient, it was measuring the wrong two colours. docs/adr/0032.
		audit "$(contrast "$MUTED_FG" "$MUTED_ERR")" "muted.fg on muted.err (ncspot's error row)" "$FLOOR"

		if [[ -n $fails ]]; then
			bad "themes/$PAL_SCHEME.nix has text below its own declared floor of $FLOOR:1" "$fails"
		else
			ok "contrast: every UI text role in '$PAL_SCHEME' clears its floor of $FLOOR:1 (worst: $worst_n at $worst)"
		fi

		# The sixteen terminal slots. `black` is excluded — it is ANSI 0, a
		# background tone, and nothing prints text in it.
		aworst=""
		aworst_n=""
		afails=""
		for role in red green yellow blue magenta cyan white \
			brRed brGreen brYellow brBlue brMagenta brCyan brWhite; do
			h=$(pal ".$role")
			if [[ ! $h =~ ^[0-9a-f]{6}$ ]]; then
				afails+="  $role: not a colour in the resolved palette ('$h')"$'\n'
				continue
			fi
			r=$(contrast "$h" "$THEME_BG")
			awk -v r="$r" -v f="$AFLOOR" 'BEGIN { exit !(r < f) }' &&
				afails+="  $role #$h on bg0: $r < $AFLOOR"$'\n'
			if [[ -z $aworst ]] || awk -v r="$r" -v w="$aworst" 'BEGIN { exit !(r < w) }'; then
				aworst=$r
				aworst_n=$role
			fi
		done
		if [[ -n $afails ]]; then
			bad "themes/$PAL_SCHEME.nix has ANSI colours below its own declared ansiFloor of $AFLOOR:1" "$afails"
		else
			ok "contrast: every ANSI slot in '$PAL_SCHEME' clears its floor of $AFLOOR:1 (worst: $aworst_n at $aworst)"
		fi
	fi
done
# Back to the artefact scheme, so anything added after this reads the same
# palette as everything before it.
PAL_SCHEME=$(jq -r '.artefact // empty' "$SCHEMES" 2>/dev/null)

printf '\nNetworkManager profiles\n'

# Read the keyfiles the unit will actually write, not the option that produced
# them — the envsubst placeholders only survive to /run if they survive here.
NM_UNIT="$SYS/etc/systemd/system/NetworkManager-ensure-profiles.service"
mapfile -t NM_PROFILES < <(
	if [[ -f $NM_UNIT ]]; then
		exec=$(grep -m1 '^ExecStart=' "$NM_UNIT" | cut -d= -f2- | awk '{print $1}')
		[[ -f $exec ]] && grep -o 'envsubst -i [^ ]*' "$exec" | cut -d' ' -f3
	fi
)

if [[ ${#NM_PROFILES[@]} -lt 9 ]]; then
	bad "expected 9 declared NM profiles (8 PIA exits + homelab), found ${#NM_PROFILES[@]}"
else
	ok "${#NM_PROFILES[@]} declared NM profiles"

	# A VPN that autoconnects grabs the default route and pushes a nameserver
	# onto every link, which presents as total DNS failure naming nothing.
	on=""
	for p in "${NM_PROFILES[@]}"; do
		grep -q '^autoconnect=false$' "$p" || on+="  $(basename "$p")"$'\n'
	done
	if [[ -z $on ]]; then
		ok "every declared profile sets autoconnect=false"
	else
		bad "declared profile without autoconnect=false" "$on"
	fi

	# /nix/store is world-readable, so an inlined credential is a leak that
	# looks identical to a working profile. Every one must be an envsubst
	# placeholder resolved at runtime from the sops-rendered env file.
	leaked=""
	creds=0
	for p in "${NM_PROFILES[@]}"; do
		while IFS= read -r line; do
			creds=$((creds + 1))
			[[ ${line#*=} == \$* ]] || leaked+="  $(basename "$p"): ${line%%=*}"$'\n'
		done < <(grep -E '^(password|private-key|psk|preshared-key)=' "$p")
	done
	if [[ $creds -eq 0 ]]; then
		bad "no credential fields found in the profiles — the scan is broken"
	elif [[ -z $leaked ]]; then
		ok "all $creds profile credentials are \$-placeholders, not literals"
	else
		bad "PLAINTEXT credential in a world-readable store path" "$leaked"
	fi
fi

printf '\nGenerated waybar configs\n'

# Every layout, in both positions. Named rather than counted: a count alone
# passes when one layout vanishes and another is added twice, and the layout
# NAMES are what waybar-restart.sh builds its filename from — a missing one is
# the fallback-to-full path, which logs but keeps running. Was 4 layouts until
# hud left (docs/adr/0035).
# CONFIGS stays FULL PATHS — every scan below this point reads the files.
mapfile -t CONFIGS < <(find "$WAYBAR_DIR" -name 'config-*.jsonc' | sort)
cfgmiss=""
for l in full focus minimal; do
	for pos in top bottom; do
		[[ -s "$WAYBAR_DIR/config-$l-$pos.jsonc" ]] || cfgmiss+="  config-$l-$pos.jsonc"$'\n'
	done
done
if [[ -n $cfgmiss ]]; then
	bad "a generated waybar config is missing" "$cfgmiss"
elif [[ ${#CONFIGS[@]} -ne 6 ]]; then
	bad "expected 6 generated waybar configs (3 layouts x 2 positions), found ${#CONFIGS[@]}" \
		"$(printf '%s ' "${CONFIGS[@]##*/}")"
else
	ok "6 generated waybar configs — full, focus and minimal, each top and bottom"
fi

# Every module a layout carries needs a CSS rule, and every `format` needs
# something in it. Both are INVISIBLE — waybar renders the bar either way — and
# both were made in one sitting adding `custom/control-center`: the glyph was
# dropped writing the Nix (no \uXXXX escape, so it is literal UTF-8), and a new
# module has no rule until someone writes one. docs/gotchas.md -> Waybar.
#
# Ids are waybar's own: `custom/foo` -> `#custom-foo`, other prefixes dropped.
css_seen=0
cssmiss=""
fmtempty=""
STYLE_CSS="$WAYBAR_DIR/style-solid.css"
if [[ ! -s $STYLE_CSS ]]; then
	bad "style-solid.css is missing from the generation — every rule scan below would find nothing"
else
	for cfg in "${CONFIGS[@]}"; do
		while IFS= read -r m; do
			[[ -z $m ]] && continue
			css_seen=$((css_seen + 1))
			case $m in
			custom/*) id="#custom-${m#custom/}" ;;
			*/*) id="#${m#*/}" ;;
			*) id="#$m" ;;
			esac
			grep -qE "^\s*${id}[ ,{:]" "$STYLE_CSS" \
				|| grep -qxF "$id," "$STYLE_CSS" \
				|| cssmiss+="  $m -> $id (${cfg##*/})"$'\n'
			# Quoted keys: `.modules-left` is jq for `.modules` MINUS `left`,
			# which yields null rather than an error and would empty the scan.
		done < <(jq -r '(.["modules-left"] // []) + (.["modules-center"] // []) + (.["modules-right"] // []) | .[]' "$cfg" 2>/dev/null)

		while IFS= read -r m; do
			[[ -z $m ]] && continue
			fmtempty+="  $m has an empty format (${cfg##*/})"$'\n'
		done < <(jq -r 'to_entries[] | select(.value | type == "object") | select(.value.format? == "") | .key' "$cfg" 2>/dev/null)
	done
	cssmiss=$(printf '%s' "$cssmiss" | sort -u)
	fmtempty=$(printf '%s' "$fmtempty" | sort -u)

	if [[ $css_seen -eq 0 ]]; then
		bad "no modules read from the generated waybar configs — the scan is broken, not the repo"
	elif [[ -n $cssmiss ]]; then
		bad "a waybar module a layout carries has no rule in style-solid.css" \
			"it renders in the bar's defaults, which looks like a styling choice:"$'\n'"$cssmiss"
	else
		ok "$css_seen module slots across the layouts all have a rule in style-solid.css"
	fi

	if [[ -n $fmtempty ]]; then
		bad "a waybar module has an empty format string" \
			"it renders as an empty module, which is indistinguishable from one that is merely missing:"$'\n'"$fmtempty"
	else
		ok "no waybar module renders an empty format"
	fi
fi

# A module whose exec is missing or non-executable renders as an empty module,
# which reads as the module being absent from the bar.
missing=""
refs=0
for cfg in "${CONFIGS[@]}"; do
	while read -r ref; do
		[[ -z $ref ]] && continue
		refs=$((refs + 1))
		script="$SRC/dotfiles/mango/scripts/${ref#*mango/scripts/}"
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

printf '\nBattery\n'

# `full-at` rescales the reading as shown = real / full-at * 100, so the bar
# disagrees with fastfetch, upower and sysfs by a constant factor. Dropped on
# 2026-08-09 because that mismatch masked a frozen module twice. Reintroducing
# it is silent, hence the assertion.
checked=0
rescaled=""
for cfg in "${CONFIGS[@]}"; do
	jq -e 'has("battery")' "$cfg" >/dev/null || continue
	checked=$((checked + 1))
	full=$(jq -r '.battery["full-at"] // empty' "$cfg")
	[[ -z $full ]] || rescaled+="  $(basename "$cfg"): full-at=$full"$'\n'
done

if [[ $checked -eq 0 ]]; then
	bad "no generated config carries a battery module — the scan is broken"
elif [[ -z $rescaled ]]; then
	ok "battery shows the raw percentage in all $checked configs (no full-at)"
else
	bad "generated waybar config rescales the battery reading" "$rescaled"
fi

# upower is what acts on a low battery; waybar only recolours. The two drifted —
# waybar warned at 30/15 while upower acted at 20/5 — so the colour change marked
# nothing in particular. Read from the built /etc, not from the Nix.
UPOWER_CONF="$SYS/etc/UPower/UPower.conf"
low="" crit=""
if [[ -f $UPOWER_CONF ]]; then
	while IFS='=' read -r key value; do
		case $key in
		PercentageLow) low=$value ;;
		PercentageCritical) crit=$value ;;
		esac
	done <"$UPOWER_CONF"
fi

checked=0
drifted=""
for cfg in "${CONFIGS[@]}"; do
	jq -e 'has("battery")' "$cfg" >/dev/null || continue
	warn=$(jq -r '.battery.states.warning // empty' "$cfg")
	critical=$(jq -r '.battery.states.critical // empty' "$cfg")
	if [[ -z $warn || -z $critical ]]; then
		drifted+="  $(basename "$cfg"): battery module has no states"$'\n'
		continue
	fi
	checked=$((checked + 1))
	[[ $warn == "$low" && $critical == "$crit" ]] ||
		drifted+="  $(basename "$cfg"): waybar $warn/$critical, upower $low/$crit"$'\n'
done

if [[ -z $low || -z $crit ]]; then
	bad "no PercentageLow/Critical in the built UPower.conf — the scan is broken" "$UPOWER_CONF"
elif [[ $checked -eq 0 ]]; then
	bad "no generated config carries battery states — the scan is broken"
elif [[ -z $drifted ]]; then
	ok "waybar's battery states match upower's $low/$crit in all $checked configs"
else
	bad "waybar's battery states have drifted from upower" "$drifted"
fi

# Night light is killed from outside this repo: noctalia runs `pkill -x wlsunset`
# in `Component.onCompleted`, unconditionally, on every start. systemd counts a
# SIGTERM as a CLEAN exit, so `Restart=on-failure` did not bring it back and one
# entry into noctalia mode ended night light for the session, silently.
# docs/gotchas.md → night light.
NIGHT_UNIT="$GEN/home-files/.config/systemd/user/wlsunset.service"
if [[ ! -f $NIGHT_UNIT ]]; then
	bad "no generated wlsunset.service — the scan is broken" "$NIGHT_UNIT"
elif ! grep -qx 'Restart=always' "$NIGHT_UNIT"; then
	bad "wlsunset is not Restart=always — an outside SIGTERM ends night light for the session" \
		"$(grep -m1 '^Restart=' "$NIGHT_UNIT" || echo 'no Restart= at all')"
else
	ok "wlsunset restarts even when something else SIGTERMs it"
fi

# `mmsg watch` is a long-lived stream, and the script running it is killed from
# outside — `pkill waybar` on every mode switch and every waybar-reload. The
# watcher does not go with it: four orphans were alive at once on 2026-08-16, up
# to fourteen hours old, each holding an IPC socket to a compositor nothing was
# reading from. A trap that reaps this script's own children is the fix, and its
# absence is invisible until you count processes.
mapfile -t WATCHERS < <(grep -rl 'mmsg watch' "$SRC/dotfiles" 2>/dev/null | sort)
if [[ ${#WATCHERS[@]} -eq 0 ]]; then
	bad "no script runs 'mmsg watch' — the scan is broken, not the repo"
else
	watcherr=""
	for w in "${WATCHERS[@]}"; do
		grep -q 'pkill -P \$\$' "$w" ||
			watcherr+="  ${w#"$SRC"/} streams mmsg watch but never reaps it"$'\n'
	done
	if [[ -z $watcherr ]]; then
		ok "all ${#WATCHERS[@]} 'mmsg watch' streams are reaped when their script exits"
	else
		bad "an mmsg watch stream outlives its script" "$watcherr"
	fi
fi

printf '\nIdle\n'

# swayidle carried no timeouts at all until 2026-08-11 while the docs described
# an idle ladder, so this is the floor for the reverse: with none, nothing dims,
# locks or sleeps on idle and an open lid costs ~7 W until the 3% hibernate.
IDLE_UNIT="$GEN/home-files/.config/systemd/user/swayidle.service"
if [[ ! -f $IDLE_UNIT ]]; then
	bad "no generated swayidle.service — the scan is broken" "$IDLE_UNIT"
else
	# -o then `wc -l`, not `grep -c`: the whole ExecStart is ONE line, so `grep -c`
	# reports 1 however many timeouts are on it, and a ladder cut to a single
	# timeout would still pass.
	timeouts=$(grep -o ' timeout ' "$IDLE_UNIT" | wc -l)
	if [[ $timeouts -eq 0 ]]; then
		bad "swayidle carries no idle timeouts — nothing dims, locks or sleeps on idle"
	else
		ok "swayidle carries $timeouts idle timeouts"
	fi

	# `&&` skips the blank whenever the lock exits non-zero, which is every time
	# the screen was already locked by hand — only one client may hold an
	# ext-session-lock-v1 lock. docs/gotchas.md → swaylock.
	#
	# `lockscreen`, not `swaylock`: the wrapper is what swayidle calls now
	# (docs/adr/0018). Matching the old name here would pass by finding nothing.
	if ! grep -q 'wlopm' "$IDLE_UNIT"; then
		bad "swayidle never calls wlopm — the panel stays lit through the idle blank"
	elif ! grep -q 'lockscreen' "$IDLE_UNIT"; then
		bad "swayidle does not lock via lockscreen — the idle lock has lost its background pool"
	elif grep -qE 'lockscreen[^;]*&&[^;]*wlopm' "$IDLE_UNIT"; then
		bad "swayidle chains lockscreen to wlopm with && — a manual lock leaves the panel lit"
	else
		ok "swayidle's idle blank is not gated on the lock's exit status"
	fi
fi

# The background pool is invisible when it is missing: lockscreen falls back to
# the solid colour deliberately, so an empty pool looks exactly like the config
# before this existed. Assert the floor — the pool the wrapper actually points
# at, not merely that some pool was built.
if [[ ! -x $LOCKBIN ]]; then
	bad "no lockscreen on PATH — the mango binds call it by name and would exit 127" "$LOCKBIN"
else
	pool_dir=$(grep -oE '/nix/store/[^ )"]*/share/lock-backgrounds' "$LOCKBIN" | head -1)
	if [[ -z $pool_dir ]]; then
		bad "lockscreen references no background pool" "$LOCKBIN"
	else
		members=$(find "$pool_dir" -name '*.png' 2>/dev/null | wc -l)
		if [[ $members -eq 0 ]]; then
			bad "lockscreen's background pool is empty — every lock falls back to flat #282828" "$pool_dir"
		else
			ok "lockscreen's background pool carries $members members"
		fi
	fi
fi

# The only in-session way to hold the ladder off: swayidle takes its idle signal
# from the compositor, so `systemd-inhibit --what=idle` does not reach it and a
# long build on battery hits the 30-minute suspend regardless. Dropping the
# module from every layout is silent — the bar is just one icon shorter.
inhibitor=0
for cfg in "${CONFIGS[@]}"; do
	jq -e '.["modules-right"] | index("custom/idle-inhibitor")' "$cfg" >/dev/null 2>&1 &&
		inhibitor=$((inhibitor + 1))
done
if [[ $inhibitor -eq 0 ]]; then
	bad "no generated waybar config carries custom/idle-inhibitor — nothing can hold the idle ladder off"
else
	ok "custom/idle-inhibitor is on the bar in $inhibitor of ${#CONFIGS[@]} layouts"
fi

# ...and the module only REPORTS the inhibitor now; the unit is what holds it.
# Two ways that pairing breaks silently, so both are asserted. An [Install]
# section would arm the inhibitor at every login, which is the failure the
# whole thing exists to prevent and looks from the bar exactly like someone
# having pressed the key. docs/adr/0031.
INHIBIT_UNIT="$GEN/home-files/.config/systemd/user/wlinhibit.service"
if [[ ! -f $INHIBIT_UNIT ]]; then
	bad "no generated wlinhibit.service — the keep-awake key and the bar toggle both do nothing" "$INHIBIT_UNIT"
elif grep -q '^WantedBy=' "$INHIBIT_UNIT"; then
	bad "wlinhibit.service is wanted by a target — the machine would come up already inhibited" \
		"$(grep -m1 '^WantedBy=' "$INHIBIT_UNIT")"
else
	ok "wlinhibit.service exists and starts only on request"
fi

# ...and apply_mode hands it over on the way into noctalia, which holds its own
# inhibitor over quickshell with no getter to read it back. Dropping this line
# is invisible: both inhibitors are real, so the machine still stays awake — it
# is the OTHER shell's indicator that starts lying. docs/adr/0031.
LIBSH="$MANGO/scripts/lib.sh"
if ! grep -q 'idle-inhibit\.sh' "$LIBSH"; then
	bad "apply_mode does not hand the idle inhibitor over — entering noctalia would leave wlinhibit holding behind its indicator" \
		"$LIBSH"
elif ! grep -q 'idle-inhibit\.sh" off' "$LIBSH"; then
	bad "lib.sh names idle-inhibit.sh but never stops it — the handover tests a state it does not act on" "$LIBSH"
else
	ok "apply_mode releases the inhibitor entering noctalia"
fi

printf '\nFonts\n'

# A font family that resolves to nothing renders as a silent fallback: bold text
# just looks normal, a bar glyph just looks like a box. It has bitten twice —
# "3270 Nerd Font" undeclared, then `_0xproto` (family "0xProto") standing in for
# `nerd-fonts._0xproto` (family "0xProto Nerd Font Mono"). fc-match cannot check
# this: it matches on family alone, so a "<family> Bold" spelling always looks
# like a fallback. Match family+style out of fc-scan instead.
mapfile -t FONT_DIRS < <(
	grep -rhoE '<dir>[^<]+</dir>' "$SYS/etc/fonts/conf.d/"*.conf "$SYS/etc/fonts/fonts.conf" 2>/dev/null \
		| sed -E 's#</?dir>##g' | grep '^/nix/store' | sort -u
)
if [[ ${#FONT_DIRS[@]} -lt 5 ]]; then
	bad "only ${#FONT_DIRS[@]} font dirs found in the system closure — the scan is broken, not the config"
else
	FAMILIES=$(fc-scan --format '%{family}|%{style}\n' "${FONT_DIRS[@]}" 2>/dev/null | sort -u)
	fam_count=$(printf '%s\n' "$FAMILIES" | grep -c .)
	if [[ $fam_count -lt 100 ]]; then
		bad "fc-scan returned only $fam_count families — the scan is broken, not the config"
	else
		ok "$fam_count font family/style pairs across ${#FONT_DIRS[@]} dirs"

		# Every family name the terminals and the bar ask for by name.
		KITTY="$GEN/home-files/.config/kitty/kitty.conf"
		FOOT="$GEN/home-files/.config/foot/foot.ini"
		wanted=$(
			# font_family/bold_font/italic_font/bold_italic_font: rest of line.
			sed -nE 's/^(font_family|bold_font|italic_font|bold_italic_font)[[:space:]]+(.*)$/\2/p' "$KITTY" 2>/dev/null
			# symbol_map: codepoint ranges first, family last.
			sed -nE 's/^symbol_map[[:space:]]+[^[:space:]]+[[:space:]]+(.*)$/\1/p' "$KITTY" 2>/dev/null
			# foot: font=<family>:size=N
			sed -nE 's/^font=([^:]+).*$/\1/p' "$FOOT" 2>/dev/null
			# waybar CSS font-family, comma-separated, quoted or bare.
			grep -rhoE 'font-family:[^;]+;' "$WAYBAR_DIR"/*.css 2>/dev/null \
				| sed -E 's/font-family://; s/;//' | tr ',' '\n' | sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//'
			# rofi: `font: "<family> <size>";`. Every menu entry carries Font
			# Awesome glyphs in the string itself, so a fallback here is a
			# window full of boxes rather than a slightly different typeface.
			sed -nE 's/^[[:space:]]*font:[[:space:]]*"(.*) [0-9]+"[[:space:]]*;.*/\1/p' \
				"$SRC/dotfiles/rofi/config.rasi" 2>/dev/null
		)
		wanted=$(printf '%s\n' "$wanted" | grep -vE '^(auto|monospace|sans-serif|serif|inherit)?$' | sort -u)

		want_count=$(printf '%s\n' "$wanted" | grep -c .)
		if [[ $want_count -lt 3 ]]; then
			bad "only $want_count font names extracted from the configs — the scan is broken, not the config"
		else
			missing=()
			while IFS= read -r name; do
				[[ -z $name ]] && continue
				# Either a bare family, or "<family> <style>".
				if ! printf '%s\n' "$FAMILIES" | awk -F'|' -v n="$name" \
					'$1 == n || $1 " " $2 == n { found = 1 } END { exit !found }'; then
					missing+=("$name")
				fi
			done <<<"$wanted"

			if [[ ${#missing[@]} -gt 0 ]]; then
				bad "font names that resolve to nothing (silent fallback)" "${missing[*]}"
			else
				ok "all $want_count font names referenced by kitty, foot and waybar resolve"
			fi
		fi
	fi
fi

printf '\nShell completions\n'

# `programs.zsh.enableCompletion = false` is deliberate (it drops a duplicate
# compinit) but it also gates `pathsToLink`, so it silently unlinks share/zsh
# from both profiles. A missing fpath entry is not an error — completion keeps
# working on zsh's bundled functions, so nothing reports the loss. Assert a
# floor on each profile. docs/gotchas.md → nixpkgs and NixOS.
for spec in "home:$GEN/home-path/share/zsh/site-functions:100" \
	"system:$SYS/sw/share/zsh/site-functions:20"; do
	IFS=: read -r label dir floor <<<"$spec"

	if [[ ! -d $dir ]]; then
		bad "$label profile has no share/zsh/site-functions" \
			"pathsToLink is missing /share/zsh — every package completion is gone"
		continue
	fi

	count=$(find "$dir" -maxdepth 1 -name '_*' -printf . | wc -c)
	if [[ $count -lt $floor ]]; then
		bad "$label profile ships only $count completions (floor $floor)" "$dir"
	else
		ok "$label profile ships $count completions"
	fi
done

# The two that motivated the floor: both came from the NixOS module and both
# vanished with it.
for fn in _nix-shell _nixos-option; do
	if [[ -e "$GEN/home-path/share/zsh/site-functions/$fn" ]]; then
		ok "$fn is in fpath"
	else
		bad "$fn missing — nix-zsh-completions is not in home.packages"
	fi
done

# --- signal traps -----------------------------------------------------------
# A handler trapped on a terminating signal REPLACES that signal's default
# action — bash runs it and then resumes. Two mango watchers written that way
# ignored logind's SIGTERM, kept looping, and held the session scope open until
# systemd SIGKILLed them 90 s later, on every shutdown and reboot. The shape is
# one line from the correct one and reads as the more careful of the two, so it
# gets a check rather than a convention. docs/gotchas.md → Scripts.
printf '\nSignal traps\n'

# The body of function `$2` in file `$1`, by brace depth — the handlers here are
# one-liners, so a `sed` range ending at `^}` would run past them into the next
# function and find its `exit` instead.
fn_body() {
	awk -v fn="$2" '
		!open && $0 ~ "^[[:space:]]*(function[[:space:]]+)?" fn "[[:space:]]*\\(\\)" { open = 1 }
		open {
			print
			depth += gsub(/\{/, "{") - gsub(/\}/, "}")
			if (depth > 0) seen = 1
			if (seen && depth <= 0) exit
		}
	' "$1"
}

traps_seen=0
traps_bad=()
for f in "${SCRIPTS[@]}"; do
	# Read once rather than redirecting the loop: `fn_body` below opens the same
	# file, and a loop whose stdin IS that file is one refactor away from having
	# its input consumed out from under it (SC2094).
	mapfile -t lines < "$f"
	for line in "${lines[@]}"; do
		# `trap ACTION SIGSPEC...`. `trap -p` and `trap - SIG` reset rather than
		# handle, so they carry no obligation to exit.
		[[ $line =~ ^[[:space:]]*trap[[:space:]]+(\'[^\']*\'|\"[^\"]*\"|[^[:space:]]+)[[:space:]]+([A-Za-z0-9[:space:]]+)$ ]] || continue
		action=${BASH_REMATCH[1]}
		signals=${BASH_REMATCH[2]}

		# Only signals whose default action terminates. EXIT is the right home
		# for cleanup and must NOT exit. The `[A-Za-z0-9…]` above also drops the
		# `RTMIN+8` form on purpose: a real-time signal here is waybar asking a
		# module to refresh, where carrying on IS the point.
		[[ $signals == *TERM* || $signals == *INT* || $signals == *HUP* || $signals == *QUIT* || $signals == *PIPE* ]] || continue
		traps_seen=$((traps_seen + 1))

		action=${action#[\'\"]}
		action=${action%[\'\"]}
		[[ $action == - || -z $action ]] && continue
		[[ $action == *exit* ]] && continue

		# A bare function name — resolve it and look for `exit` in the body.
		if [[ $action =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
			&& fn_body "$f" "$action" | grep -qw exit; then
			continue
		fi

		traps_bad+=("${f#"$SRC"/}: ${line#"${line%%[![:space:]]*}"}")
	done
done

# The scan finding nothing is the failure mode it exists to catch. The floor
# guards the regex, not the population — set below today's 3 so that removing a
# trap is a code change rather than a check failure, but above 0 so a regex that
# stops matching cannot pass by finding nothing.
if [[ $traps_seen -lt 2 ]]; then
	bad "only $traps_seen terminating-signal traps found — the scan is broken, not the repo"
elif [[ ${#traps_bad[@]} -gt 0 ]]; then
	bad "${#traps_bad[@]} signal trap(s) never exit, so the signal no longer kills the script" \
		"$(printf '%s; ' "${traps_bad[@]}")"
else
	ok "$traps_seen terminating-signal traps all exit"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
