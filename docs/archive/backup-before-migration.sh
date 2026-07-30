#!/usr/bin/env bash
# Back up the irreplaceable parts of /home/henry before the NixOS migration.
#
# Sizing, re-measured 2026-07-28: /home/henry is 236 GB, but only ~7 GB of it
# is both irreplaceable and not already protected somewhere else. This script
# backs up that ~7 GB and skips the rest — the ~200 GB of Steam libraries,
# caches, container images, VM disks and trash, plus Nextcloud and Android
# (see the exclusion notes below for why each is safe to drop).
#
# Produces a PLAIN FILE TREE mirroring /home/henry — not an archive, not a
# restic repo. No password, no tooling to restore: browse it, or copy it back.
# That is deliberate. The drive is local and offline, and the restore steps in
# MIGRATION-GUIDE.md Part 10 use `cp -a "$B/.config/gh"`, which only works
# against plain files. (This script built a restic repository until
# 2026-07-29, which no restore step in the guide could read.)
#
# Re-running is cheap: rsync transfers only what changed, so refreshing a
# backup taken days ago costs seconds, not the full ~7 GB.
#
# Usage:
#   ./backup-before-migration.sh "/run/media/henry/Samsung 128G/backup-2026-07-28"
#   ./backup-before-migration.sh --dry-run /path/to/target
#
# Requires: rsync.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=1; shift; }

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "usage: $0 [--dry-run] <backup-target-dir>" >&2
  exit 2
fi

HOME_DIR="/home/henry"

# ---------------------------------------------------------------------------
# Refuse to back up onto the same physical disk.
# ---------------------------------------------------------------------------
# A backup on nvme0n1 protects against nothing that actually threatens you
# here: if you mistype a `btrfs subvolume delete` or format the partition, the
# backup dies with the original. Same-disk copies are a convenience, not a
# backup.
if [ "$DRY_RUN" -eq 0 ]; then
  src_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE --target "$HOME_DIR" | sed 's/\[.*//')" 2>/dev/null | head -1)
  mkdir -p "$TARGET"
  dst_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE --target "$TARGET" | sed 's/\[.*//')" 2>/dev/null | head -1)
  if [ -n "$src_disk" ] && [ "$src_disk" = "$dst_disk" ]; then
    echo "REFUSING: target is on the same physical disk ($src_disk) as /home." >&2
    echo "Use an external drive." >&2
    echo "Override with FORCE_SAME_DISK=1 if you really mean it." >&2
    [ "${FORCE_SAME_DISK:-0}" = "1" ] || exit 1
  fi
fi

# ---------------------------------------------------------------------------
# What gets backed up — the irreplaceable set.
# ---------------------------------------------------------------------------
INCLUDE=(
  # --- Cannot be recreated at any price ---
  "$HOME_DIR/Documents"          # 3.7G — contracts, CV, licences
  "$HOME_DIR/Pictures"           # 395M
  "$HOME_DIR/vaults"             # 127M — Obsidian
  "$HOME_DIR/R"                  # 424M

  # --- Credentials. Tiny, catastrophic to lose. ---
  "$HOME_DIR/.ssh"               # 76K
  "$HOME_DIR/.gnupg"             # 144K
  "$HOME_DIR/.local/share/keyrings"  # 32K — gnome-keyring secrets

  # --- Source. Small once build artifacts are excluded (523M, not 9.1G). ---
  # Kept deliberately even though every repo here has an origin remote: as of
  # 2026-07-28 five of them carry work that exists nowhere else — see the
  # unpushed-work check below. At half a gigabyte this is the cheapest
  # insurance in the set.
  "$HOME_DIR/code"
  "$HOME_DIR/Projects"

  # --- Application state worth keeping ---
  "$HOME_DIR/.thunderbird"       # 411M — mail. Critical if any account is POP.
  "$HOME_DIR/.config/zen"        # 848M — your actual default browser
                                 # (xdg-settings confirms zen.desktop).
                                 # LibreWolf is NOT installed despite what
                                 # CLAUDE.md and mimeapps.list claim.
  "$HOME_DIR/.config/chromium"   # 261M
  "$HOME_DIR/.config/obsidian"   # 666M
  "$HOME_DIR/.config/nixos"      # this flake
  "$HOME_DIR/.scripts"
  "$HOME_DIR/.hidden"
)

# ---------------------------------------------------------------------------
# What is deliberately NOT backed up, and why.
# ---------------------------------------------------------------------------
#   Nextcloud                 22G  syncs to nextcloud.henrydowd.dev, and the
#                                  sync journal confirms the 21.8G
#                                  ATM9NF_march26.zip reached the server at
#                                  full size. Caveat accepted knowingly: sync
#                                  is replication, so a local delete
#                                  propagates. Server-side trash/versioning is
#                                  the safety net, not this script.
#   Android                  4.8G  Android Studio build output and SDK/AVD
#                                  state — regenerated on next build.
#   .config/vivaldi          283M  secondary browser, profile not wanted.
#   .local/share/Steam        30G  re-downloadable from Steam
#   .local/share/Trash        20G  it's the bin. Empty it instead.
#   winboat                   39G  Windows VM disk — recreate it
#   .cache                    26G  by definition disposable
#   .local/share/containers    7G  podman images — re-pull
#   .local/share/PrismLauncher 6.9G  Minecraft instances (back up saves only
#                                    if you care: PrismLauncher/instances/*/
#                                    .minecraft/saves)
#   .var/app/...Hytale         8G  flatpak game data
#   .local/share/lutris      3.5G  re-installable
#   Games                     20G  re-downloadable
#   .wine                    3.6G  recreate prefixes
#   nvim.bak.*               1.3G  old backup, delete it
#   Downloads                2.6G  transient — review manually first
#   Pictures/Lee_old        13.6G  backed up by hand 2026-07-29. Mode 311
#                                  owner root:henry, so unreadable to rsync
#                                  regardless — see the EXCLUDE note.
#
# Total skipped: ~241 GB.

EXCLUDE=(
  --exclude="node_modules"
  --exclude="target"
  --exclude=".venv"
  --exclude="venv"
  --exclude="__pycache__"
  --exclude=".mypy_cache"
  --exclude=".pytest_cache"
  --exclude="*.pyc"
  --exclude=".gradle"
  --exclude="build/intermediates"
  --exclude="dist"
  --exclude=".next"
  --exclude="*.iso"
  --exclude="*.qcow2"
  --exclude="Cache"
  --exclude="cache2"
  --exclude="*.log"
  # capture-root-state.sh's output. It is root-owned 0700, so an unprivileged
  # rsync cannot read it anyway — excluding it says so deliberately rather
  # than failing on it. The authoritative copy lives on the backup drive at
  # backup-*/system-state/root-only; it must NOT be duplicated into a git
  # working tree (see .gitignore /nixos/system-state/).
  --exclude="system-state/root-only"
  # Pictures/Lee_old — ~13.6 GB, backed up by hand (confirmed 2026-07-29), so
  # this is a deliberate exclusion rather than the permissions failure it used
  # to be. The directory is mode 311 owner root:henry and unreadable even to
  # its owner, so rsync could never have copied it anyway; excluding it keeps
  # the run clean instead of raising a warning on every backup. If you ever
  # fix the mode and want it included again, delete this line.
  --exclude="/Pictures/Lee_old"
)

# ---------------------------------------------------------------------------
echo "=== Pre-flight ==="
missing=0
for p in "${INCLUDE[@]}"; do
  if [ -e "$p" ]; then
    printf '  ok       %s\n' "${p#$HOME_DIR/}"
  else
    printf '  MISSING  %s\n' "${p#$HOME_DIR/}"; missing=1
  fi
done
[ "$missing" -eq 1 ] && echo "  (missing paths are skipped, not fatal)"

echo
echo "=== Estimated size ==="
# `|| true` is load-bearing: du exits non-zero on any unreadable file (sockets
# and lock files inside the browser and gnupg dirs), and under `set -o
# pipefail` that killed the whole script here — before the copy ever ran.
du -shc --exclude=node_modules --exclude=target --exclude=.venv \
        --exclude=__pycache__ --exclude=Cache \
        "${INCLUDE[@]}" 2>/dev/null | tail -1 || true

# ---------------------------------------------------------------------------
# Unpushed work. "It's in git" only protects what actually reached the remote.
# ---------------------------------------------------------------------------
echo
echo "=== Git repos with work that exists only on this machine ==="
found_risk=0
while IFS= read -r g; do
  repo="${g%/.git}"
  git -C "$repo" remote get-url origin >/dev/null 2>&1 || {
    printf '  NO REMOTE   %s\n' "${repo#$HOME_DIR/}"; found_risk=1; continue
  }
  dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)
  unpushed=$(git -C "$repo" log --branches --not --remotes --oneline 2>/dev/null | wc -l)
  stashed=$(git -C "$repo" stash list 2>/dev/null | wc -l)
  if [ "$dirty" -gt 0 ] || [ "$unpushed" -gt 0 ] || [ "$stashed" -gt 0 ]; then
    printf '  %-42s uncommitted=%-4s unpushed=%-4s stashed=%s\n' \
           "${repo#$HOME_DIR/}" "$dirty" "$unpushed" "$stashed"
    found_risk=1
  fi
done < <(find "$HOME_DIR/code" "$HOME_DIR/Projects" -maxdepth 3 -name .git -type d 2>/dev/null)
if [ "$found_risk" -eq 0 ]; then
  echo "  none — every repo is clean and pushed"
fi

# ---------------------------------------------------------------------------
# Applications writing into the backup set.
# ---------------------------------------------------------------------------
# Browser and mail profiles are live SQLite databases. Copying one while its
# owner is running gets you a torn snapshot: the .sqlite and its -wal are
# copied at different instants, and the verify pass below will flag them as
# differing because they genuinely changed mid-run. Nothing is corrupted on
# the source, but the *copy* may not open cleanly on restore.
#
# For a routine refresh this is noise. For the final pre-install backup, quit
# these first.
echo
echo "=== Applications writing into the backup set ==="
live=0
for proc in zen-bin chromium thunderbird betterbird obsidian; do
  if pgrep -x "$proc" >/dev/null 2>&1; then
    printf '  RUNNING  %s — its profile will be copied mid-write\n' "$proc"
    live=1
  fi
done
[ "$live" -eq 0 ] && echo "  none — profiles are quiescent"

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "Dry run — nothing written. Target would be: $TARGET"
  exit 0
fi

# ---------------------------------------------------------------------------
# Build the rsync source list.
# ---------------------------------------------------------------------------
# The `/./` marker is what makes `-R` write $TARGET/Documents rather than
# $TARGET/home/henry/Documents: rsync treats everything after it as the path
# to recreate at the destination.
RSYNC_SRC=()
for p in "${INCLUDE[@]}"; do
  [ -e "$p" ] || continue
  RSYNC_SRC+=( "$HOME_DIR/./${p#$HOME_DIR/}" )
done

echo
echo "=== Copying ==="
echo "  $TARGET"
# -a  archive          -H  hardlinks        -A  ACLs
# -X  xattrs           -R  relative paths (see the /./ marker above)
#
# No --delete. A path removed from $HOME stays in the backup, which is the
# safer default for a one-shot pre-migration copy: this exists to protect
# against a mistake, and "I deleted it and rsync propagated that" is one of
# the mistakes. Add --delete by hand if you want a true mirror.
#
# --info=progress2 gives a single overall progress line rather than per-file.
#
# rsync exits 23 ("some files/attrs were not transferred") when it hits a path
# it cannot read. That is not a reason to abort before verifying — but it IS a
# reason to say loudly which paths were skipped, because a backup with a silent
# hole in it is worse than no backup. `set -e` would kill the script here, so
# the exit code is captured rather than allowed to propagate.
ERRLOG=$(mktemp); trap 'rm -f "$ERRLOG"' EXIT
rc=0
rsync -aHAX -R --info=progress2 --human-readable \
      "${EXCLUDE[@]}" "${RSYNC_SRC[@]}" "$TARGET/" 2>"$ERRLOG" || rc=$?
[ -s "$ERRLOG" ] && cat "$ERRLOG" >&2

if [ "$rc" -eq 23 ] || [ "$rc" -eq 24 ]; then
  echo
  echo "  PARTIAL — these paths could not be read and are NOT in the backup:"
  sed -n 's/.*opendir "\([^"]*\)".*/    \1/p' "$ERRLOG" | sort -u
  echo
  echo "  Each is a permissions problem, not an rsync problem. Fix the mode"
  echo "  or accept the gap knowingly — do not ignore this line."
elif [ "$rc" -ne 0 ]; then
  echo "  rsync failed with exit code $rc" >&2
  exit "$rc"
fi

echo
echo "=== Verify ==="
# An unverified backup is a hope, not a backup. Re-running rsync in dry-run
# with --itemize-changes lists anything that did NOT make it across; silence
# means source and destination agree. This reads both sides, so it catches a
# truncated or failed transfer, not merely a non-zero exit code.
# Unreadable paths reported above surface on stderr, not stdout, so they do
# not pollute this comparison — but the dry-run still exits 23 because of
# them, hence `|| true`.
# The trailing `|| true` is load-bearing twice over: the dry-run exits 23 on
# any unreadable path, and `grep -v` exits 1 when it filters out *everything*
# — which is the success case. Under `set -o pipefail` either one aborts the
# assignment, so without this the script fails exactly when the backup is
# perfect.
leftover=$( { rsync -aHAX -R --dry-run --itemize-changes \
                    "${EXCLUDE[@]}" "${RSYNC_SRC[@]}" "$TARGET/" 2>/dev/null \
              || true; } \
           | grep -vE '^$|^\.d\.\.t|^cd\+\+\+\+\+\+\+\+\+ \./$' | head -20 ) || true
if [ -z "$leftover" ]; then
  echo "  verified — destination matches source"
else
  echo "  MISMATCH — these differ after the copy:" >&2
  printf '%s\n' "$leftover" >&2
  if [ "$live" -eq 1 ]; then
    echo >&2
    echo "  An application above was running while this ran. If every path" >&2
    echo "  listed belongs to its profile, that is the cause: the file changed" >&2
    echo "  between the copy and the check. Quit it and re-run to get a clean" >&2
    echo "  verification — do that for the final pre-install backup." >&2
  fi
  exit 1
fi

echo
echo "=== Size on target ==="
du -sh "$TARGET" 2>/dev/null | tail -1 || true

echo
echo "Done. Before you install, also:"
echo "  1. Push the git repos flagged in the pre-flight output above."
echo "  2. Take a btrfs snapshot of @home (see MIGRATION.md §2)."
echo "  3. Run capture-root-state.sh from the drive, as root, if you have not."
