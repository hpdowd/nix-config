#!/usr/bin/env bash
# Back up the irreplaceable parts of /home/henry before the NixOS migration.
#
# Sizing, re-measured 2026-07-28: /home/henry is 236 GB, but only ~7 GB of it
# is both irreplaceable and not already protected somewhere else. This script
# backs up that ~7 GB and skips the rest — the ~200 GB of Steam libraries,
# caches, container images, VM disks and trash, plus Nextcloud and Android
# (see the exclusion notes below for why each is safe to drop).
#
# Usage:
#   ./backup-before-migration.sh /run/media/henry/MyDrive/backup
#   ./backup-before-migration.sh --dry-run /path/to/target
#
# Requires: restic (already installed).
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
    echo "Use an external drive, or a remote (restic supports sftp:, s3:, rclone:)." >&2
    echo "Override with FORCE_SAME_DISK=1 if you really mean it." >&2
    [ "${FORCE_SAME_DISK:-0}" = "1" ] || exit 1
  fi
fi

export RESTIC_REPOSITORY="$TARGET"

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
#
# Total skipped: ~227 GB.

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
# pipefail` that killed the whole script here — before restic ever ran.
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

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "Dry run — nothing written. Target would be: $TARGET"
  exit 0
fi

echo
echo "=== Repository ==="
if restic cat config >/dev/null 2>&1; then
  echo "  using existing repo at $TARGET"
else
  echo "  initialising new repo at $TARGET"
  restic init
fi

echo
echo "=== Backup ==="
restic backup --verbose "${EXCLUDE[@]}" "${INCLUDE[@]}"

echo
echo "=== Verify ==="
# Checks repository structure and 5% of pack data. Do NOT skip this: an
# unverified backup is a hope, not a backup.
restic check --read-data-subset=5%
restic snapshots

echo
echo "Done. Before you install, also:"
echo "  1. Push the git repos flagged in the pre-flight output above."
echo "  2. Take a btrfs snapshot of @home (see MIGRATION.md §2)."
echo "  3. Record the restic password somewhere OFF this machine."
