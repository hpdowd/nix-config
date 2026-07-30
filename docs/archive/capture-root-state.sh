#!/usr/bin/env bash
# Capture the root-only system state that the unprivileged backup could not read.
#
# Run from the backup drive:
#   sudo "/run/media/henry/Samsung 128G/backup-2026-07-28/capture-root-state.sh"
#
# Everything it collects is either a credential or hardware pairing state, so
# the output is written 0700 root-owned. The drive is unencrypted — see the
# warning in README.md.
set -uo pipefail

[ "$(id -u)" -eq 0 ] || { echo "must run as root (sudo)" >&2; exit 1; }

OUT="$(dirname "$(readlink -f "$0")")/system-state/root-only"
mkdir -p "$OUT"
chmod 700 "$OUT"

copy() {  # copy <src> <label>
  if [ -e "$1" ]; then
    cp -a "$1" "$OUT/$2" 2>/dev/null && echo "  ok        $1"
  else
    echo "  absent    $1"
  fi
}

echo "Capturing root-only state:"

# WiFi credentials — 38 saved networks including an 802.1x/eduroam profile that
# is genuinely painful to reconstruct by hand.
copy /etc/NetworkManager/system-connections nm-system-connections

# Bluetooth device pairings — avoids re-pairing every peripheral.
copy /var/lib/bluetooth bluetooth-pairings

# CUPS is enabled on this machine, so printer definitions are real config.
copy /etc/cups cups

# Sudo customisations and root's own home.
copy /etc/sudoers.d sudoers.d
copy /root root-home

# SSH host keys — only meaningful if this box ever accepts connections.
copy /etc/ssh ssh

# Which package-owned files under /etc were modified locally. This is the
# authoritative answer to "what did I change in /etc", rather than guessing.
echo "  scanning /etc for locally modified package files..."
pacman -Qii 2>/dev/null | awk '/^MODIFIED/ {print $2}' > "$OUT/etc-modified-files.txt"
echo "  ok        $(wc -l < "$OUT/etc-modified-files.txt") modified files listed"

chmod -R go-rwx "$OUT" 2>/dev/null
echo
echo "Done. Written to: $OUT"
echo "Owned by root, mode 0700. The drive itself is NOT encrypted."
