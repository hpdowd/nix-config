#!/usr/bin/env bash
# Lists the drm/ttm + amdgpu commits between two kernel tags — the candidate set
# for the TTM bulk-move crash. A stable point release usually has only a handful,
# so read these before committing to a full bisect: inspecting five commits beats
# building ten kernels.
#
#   bisect/candidates.sh <linux-checkout> [good-tag] [bad-tag]
#
# Requires the stable tree, not torvalds/linux — point-release tags only exist
# in linux-stable:
#   git clone https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git

set -euo pipefail

TREE=${1:?usage: candidates.sh <linux-checkout> [good-tag] [bad-tag]}
GOOD=${2:-v7.1.4}
BAD=${3:-v7.1.5}

cd "$TREE"

for t in "$GOOD" "$BAD"; do
	if ! git rev-parse --verify --quiet "$t^{commit}" >/dev/null; then
		printf 'error: tag %s not in %s — is this linux-stable, and fetched?\n' "$t" "$TREE" >&2
		exit 1
	fi
done

# The paths that carry the bug: ttm owns the bulk-move/LRU lists, amdgpu is the
# only caller here (amdgpu_vm_move_to_lru_tail -> ttm_lru_bulk_move_tail).
PATHS=(
	drivers/gpu/drm/ttm
	drivers/gpu/drm/amd/amdgpu
	drivers/gpu/drm/drm_gem.c
	include/drm/ttm
)

printf '=== %s..%s — drm/ttm + amdgpu ===\n\n' "$GOOD" "$BAD"
git log --no-merges --oneline "$GOOD..$BAD" -- "${PATHS[@]}"

n=$(git rev-list --no-merges --count "$GOOD..$BAD" -- "${PATHS[@]}")
total=$(git rev-list --no-merges --count "$GOOD..$BAD")
printf '\n%s candidate commits (of %s total in range)\n' "$n" "$total"

if [[ $n -eq 0 ]]; then
	printf '\nNo commits touch those paths. The regression is either outside them\n'
	printf 'or not in this range at all — widen before bisecting.\n'
elif [[ $n -le 8 ]]; then
	printf '\nFew enough to read directly:\n'
	printf '  git -C %q show <sha>\n' "$TREE"
	printf 'Look for changes to bulk_move handling, ttm_resource_init, or the\n'
	printf 'lru_lock discipline around ttm_lru_bulk_move_{add,del,tail}.\n'
fi

printf '\nFull-range bisect needs ~%s steps.\n' "$(python3 -c "import math;print(max(1,math.ceil(math.log2($total or 1))))" 2>/dev/null || echo '?')"
