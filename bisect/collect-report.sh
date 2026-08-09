#!/usr/bin/env bash
# Collects the artefacts for an amd-gfx bug report into one directory.
# Needs root: the crash dumps in /var/lib/systemd/pstore and the pre-migration
# Arch journals are both root-only.
#
#   sudo bisect/collect-report.sh [outdir]

set -euo pipefail

OUT=${1:-./ttm-crash-report}
mkdir -p "$OUT"

if [[ $EUID -ne 0 ]]; then
	printf 'error: run under sudo — pstore and the Arch journals are root-only,\n' >&2
	printf '       and without them the report has no full backtrace.\n' >&2
	exit 1
fi

say() { printf '  → %s\n' "$1"; }

printf 'Collecting into %s\n' "$OUT"

# 1. Hardware. Every amd-gfx report is asked for this first.
say "hardware.txt"
{
	printf '=== DMI ===\n'
	cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name \
		/sys/class/dmi/id/product_version /sys/class/dmi/id/bios_version 2>/dev/null
	printf '\n=== CPU ===\n'
	grep -m1 'model name' /proc/cpuinfo || true
	printf '\n=== GPU (lspci) ===\n'
	lspci -nnk | grep -A3 -iE 'VGA|Display|3D' || true
	printf '\n=== amdgpu firmware versions ===\n'
	cat /sys/kernel/debug/dri/*/amdgpu_firmware_info 2>/dev/null || printf '(needs debugfs)\n'
} >"$OUT/hardware.txt" 2>&1

# 2. Kernel identity and taint. A tainted kernel gets a report closed, so state
#    it up front rather than letting a maintainer find it.
say "kernel.txt"
{
	printf '=== version ===\n'
	uname -a
	printf '\n=== cmdline ===\n'
	cat /proc/cmdline
	printf '\n=== taint (0 is what you want) ===\n'
	cat /proc/sys/kernel/tainted
	printf '\n'
	# Decode rather than make the reader look it up.
	t=$(cat /proc/sys/kernel/tainted)
	if [[ $t -ne 0 ]]; then
		printf 'NOT CLEAN. Check for CPU_OUT_OF_SPEC from amdgpu.ppfeaturemask\n'
		printf '(hardware.amdgpu.overdrive) before sending anything upstream.\n'
	fi
} >"$OUT/kernel.txt" 2>&1

# 3. Every crash the current journal holds. The three signatures to expect are
#    ttm_lru_bulk_move_tail GPFs, NULL derefs at +0x8, and the soft-lockup
#    cascade that follows from the leaked lru_lock.
say "crashes-journal.txt"
{
	for b in $(journalctl --list-boots -q 2>/dev/null | awk '{print $1}'); do
		if journalctl -b "$b" -k --no-pager 2>/dev/null \
			| grep -qE 'Oops:|BUG: kernel NULL|general protection fault|soft lockup'; then
			printf '\n########## boot %s ##########\n' "$b"
			journalctl -b "$b" -k --no-pager 2>/dev/null \
				| grep -E 'Oops:|BUG:|RIP:|Call Trace|Tainted:|ttm_|amdgpu_|drm_|Comm:|preempt_count|end trace|suspend exit|hibernation exit'
		fi
	done
} >"$OUT/crashes-journal.txt" 2>&1

# 4. pstore holds the full trace for freezes that died before journald could
#    flush — which is every one of them here.
say "pstore/"
mkdir -p "$OUT/pstore"
found=0
for d in /var/lib/systemd/pstore/*/; do
	[[ -d $d ]] || continue
	ts=$(basename "$d")
	# Records land in numbered subdirs — 001, and 002+ when one crash spans
	# several pstore entries. Globbing all of them avoids missing the tail.
	for f in "$d"*/dmesg.txt; do
		[[ -f $f ]] || continue
		seq=$(basename "$(dirname "$f")")
		cp "$f" "$OUT/pstore/dmesg-$ts-$seq.txt"
		printf '# %s/%s = %s\n' "$ts" "$seq" \
			"$(date -d "@$ts" 2>/dev/null || echo unknown)" \
			>>"$OUT/pstore/INDEX.txt"
		found=$((found + 1))
	done
done
if [[ $found -eq 0 ]]; then
	printf 'no pstore dumps found — check /sys/fs/pstore is mounted\n' >"$OUT/pstore/EMPTY"
	say "WARNING: no pstore dumps"
else
	say "$found pstore dump(s)"
fi

# 5. The pre-migration Arch journal is the evidence for "did this happen on the
#    older kernel" — the single most useful fact for dating the regression.
say "arch-history.txt"
{
	shopt -s nullglob
	mine=$(cat /etc/machine-id)
	for d in /var/log/journal/*/; do
		id=$(basename "$d")
		[[ $id == "$mine" || $id == remote ]] && continue
		printf '=== machine-id %s ===\n' "$id"
		printf '\n--- kernels used ---\n'
		journalctl -D "$d" -k --no-pager 2>/dev/null \
			| grep -oE 'Linux version [0-9][^ ]*' | sort -u
		printf '\n--- cmdline (unique) ---\n'
		journalctl -D "$d" -k --no-pager 2>/dev/null \
			| grep -oE 'Kernel command line: .*' | sort -u
		printf '\n--- ppfeaturemask / Overdrive present? ---\n'
		c=$(journalctl -D "$d" -k --no-pager 2>/dev/null \
			| grep -ciE 'ppfeaturemask|Overdrive is enabled' || true)
		printf 'matches: %s\n' "$c"
		printf '\n--- crash count on this install ---\n'
		n=$(journalctl -D "$d" -k --no-pager 2>/dev/null \
			| grep -cE 'ttm_lru_bulk_move|Oops:|general protection fault|BUG: kernel NULL|soft lockup' || true)
		printf 'crash-signature lines: %s\n' "$n"
		if [[ $n -eq 0 ]]; then
			printf '(0 here is meaningful ONLY if the kernel lines above are non-empty;\n'
			printf ' an unreadable journal also greps to zero.)\n'
		fi
		printf '\n'
	done
} >"$OUT/arch-history.txt" 2>&1

# `cp` from pstore preserves root-only modes, so without this the bundle this
# script exists to produce is unreadable by the person who asked for it.
if [[ -n ${SUDO_USER:-} ]]; then
	chown -R "$SUDO_USER" "$OUT"
	chmod -R u+rw "$OUT"
	say "chowned to $SUDO_USER"
fi

printf '\nDone. Read arch-history.txt first — it dates the regression.\n'
printf 'Then check kernel.txt taint is 0 before sending anything upstream.\n'
