#!/usr/bin/env bash
# Back up the irreplaceable parts of /home/henry before the NixOS migration.
#
# Sizing, measured 2026-07-27: /home/henry is 236 GB, but only ~33 GB of that
# is data you cannot recreate. This script backs up that 33 GB and skips the
# ~200 GB of Steam libraries, caches, container images, VM disks and trash.
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
  "$HOME_DIR/Nextcloud"          # 22G. NOTE: despite the name this is NOT
                                 # syncing — no sync config, client inactive.
                                 # It is local-only data. Verify before trusting.
  "$HOME_DIR/Documents"          # 3.7G — contracts, CV, licences
  "$HOME_DIR/Pictures"           # 395M
  "$HOME_DIR/vaults"             # 127M — Obsidian
  "$HOME_DIR/Android"            # 4.8G
  "$HOME_DIR/R"                  # 424M

  # --- Credentials. Tiny, catastrophic to lose. ---
  "$HOME_DIR/.ssh"               # 76K
  "$HOME_DIR/.gnupg"             # 144K
  "$HOME_DIR/.local/share/keyrings"  # 32K — gnome-keyring secrets

  # --- Source. Small once build artifacts are excluded (448M, not 9.1G). ---
  "$HOME_DIR/code"
  "$HOME_DIR/Projects"

  # --- Application state worth keeping ---
  "$HOME_DIR/.thunderbird"       # 411M — mail. Critical if any account is POP.
  "$HOME_DIR/.config/zen"        # 848M — your actual default browser
                                 # (xdg-settings confirms zen.desktop).
                                 # LibreWolf is NOT installed despite what
                                 # CLAUDE.md and mimeapps.list claim.
  "$HOME_DIR/.config/vivaldi"    # 283M — has a real profile
  "$HOME_DIR/.config/chromium"   # 261M
  "$HOME_DIR/.config/obsidian"   # 666M
  "$HOME_DIR/.config/nixos"      # this flake
  "$HOME_DIR/.scripts"
  "$HOME_DIR/.hidden"
)

# ---------------------------------------------------------------------------
# What is deliberately NOT backed up, and why.
# ---------------------------------------------------------------------------
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
# Total skipped: ~200 GB.

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
du -shc --exclude=node_modules --exclude=target --exclude=.venv \
        --exclude=__pycache__ --exclude=Cache \
        "${INCLUDE[@]}" 2>/dev/null | tail -1

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
echo "  1. Push the 4 git repos flagged below."
echo "  2. Take a btrfs snapshot of @home (see MIGRATION.md §2)."
echo "  3. Record the restic password somewhere OFF this machine."
