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

usage="usage: static.sh <source-root> <home-manager-generation> <system-toplevel>"
SRC=${1:?$usage}
GEN=${2:?$usage}
SYS=${3:?$usage}

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
			keyerr=""
			keys=0
			for f in settings.json settings-pinned.json; do
				n=$(jq -r '[paths] | length' "$MANGO/noctalia/$f" 2>/dev/null || echo 0)
				keys=$((keys + n))
				while read -r p; do
					[[ -z $p ]] && continue
					keyerr+="  $f: $p is not a key noctalia has"$'\n'
				done < <(
					jq -r --slurpfile d "$defaults" \
						'paths as $p | select(($d[0] | getpath($p)) == null) | $p | join(".")' \
						"$MANGO/noctalia/$f" 2>/dev/null
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
			# whatever it last loaded — the machine ends up half Gruvbox and
			# half noctalia purple, which looks like a theme, not a fault.
			# Resolution mirrors ColorSchemeService.resolveSchemePath().
			scheme=$(jq -r '.colorSchemes.predefinedScheme // empty' "$MANGO/noctalia/settings-pinned.json")
			case "$scheme" in
			"Noctalia (default)") schemedir="Noctalia-default" ;;
			"Noctalia (legacy)") schemedir="Noctalia-legacy" ;;
			"Tokyo Night") schemedir="Tokyo-Night" ;;
			"Rose Pine") schemedir="Rosepine" ;;
			*) schemedir="$scheme" ;;
			esac
			if [[ -z $scheme ]]; then
				bad "no predefinedScheme pinned — noctalia would keep its own palette while the rest of the machine is gruvbox"
			elif [[ -f "$NOCT_SHARE/Assets/ColorScheme/$schemedir/$schemedir.json" ]]; then
				ok "noctalia's pinned colour scheme ($scheme) ships with the package"
			else
				bad "noctalia has no colour scheme named $scheme" \
					"Assets/ColorScheme/$schemedir/$schemedir.json"
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

palette_pair "rofi" \
	"$(sed -n 's/^ *\([a-z-]*\): *#[0-9a-f]*;.*/\1/p' "$GEN/home-files/.config/rofi/colors.rasi" 2>/dev/null | sort -u)" \
	"$(grep -ohE '@[a-z-]+' "$SRC/dotfiles/rofi/config.rasi" 2>/dev/null | tr -d '@' | sort -u)"

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
	jq -e '.["modules-right"] | index("idle_inhibitor")' "$cfg" >/dev/null 2>&1 &&
		inhibitor=$((inhibitor + 1))
done
if [[ $inhibitor -eq 0 ]]; then
	bad "no generated waybar config carries idle_inhibitor — nothing can hold the idle ladder off"
else
	ok "idle_inhibitor is on the bar in $inhibitor of ${#CONFIGS[@]} layouts"
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
