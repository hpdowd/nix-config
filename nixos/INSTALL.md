# NixOS install runbook

Follow this top to bottom. Every command is meant to be copy-pasteable.

Rationale for the design decisions lives in `MIGRATION.md`; this file is only
the procedure. Prerequisites were verified against the live machine on
2026-07-28 — see `MIGRATION.md` §8 for what was checked.

**Nothing before Phase 3 modifies the running system.** Arch stays bootable
until Phase 6, which you should not reach for at least a month.

---

## Phase 0 — Fix the two blockers

These are not optional. B1 makes the first rebuild fail.

### 0.1 — B1: clone the dotfiles checkout outside `~/.config`

**The flake side of this is already fixed** (commit `b1/b2`): `dotfiles.nix`
now sets `dots` to `~/src/arch-config`. What remains is to actually put the
clone there.

Clone the repo to its new home:

```bash
mkdir -p ~/src
git clone https://git.henrydowd.dev/henry/arch-config ~/src/arch-config
```

If you clone anywhere else, update `dots` in
`~/src/arch-config/nixos/modules/home/dotfiles.nix` to match.

From here on, **work in `~/src/arch-config`**, not `~/.config/nixos`.

Note the repo layout: the clone root holds `mango/`, `nvim/` and friends, and
the flake itself lives in `nixos/`. So `dots` is the clone root, but every
`nix` command below points at `~/src/arch-config/nixos`.

Verify the fix — the built link must point into `~/src/arch-config`:

```bash
readlink "$(nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake "/home/henry/src/arch-config/nixos";
  in f.nixosConfigurations.thinkpad.config.home-manager.users.henry.home.file."/home/henry/.config/mango".source')"
# want: /home/henry/src/arch-config/mango
# NOT:  /home/henry/.config/mango   <- still broken
```

### 0.1b — Why B1 fails silently rather than loudly

`flake.nix` line 73 already sets `backupFileExtension = "hm-bak"`. That makes
B1 **more** dangerous, not less.

Without it, activation would stop with "existing file is in the way" — annoying
but obvious. With it set, and `dots` still pointing at `~/.config`, first boot
does this instead:

1. renames `~/.config/mango` → `~/.config/mango.hm-bak`
2. creates `~/.config/mango` → store path → `/home/henry/.config/mango`
3. that target no longer exists, because step 1 moved it

Result: a dangling symlink, mango starts with no config, and **no error is
printed**. Your real config is still there under `.hm-bak`, but nothing points
at it.

Once `dots` points at `~/src/arch-config`, this same setting becomes exactly
what you want: `@home` is reused, so the old real directories are still present
on first boot, and home-manager moves each aside to `.hm-bak` before linking
the clone. Delete the `.hm-bak` leftovers once you are happy:

```bash
find ~/.config -maxdepth 1 -name '*.hm-bak'
```

### 0.2 — B2: `mango-session.target` — DONE

Already declared in `modules/home/default.nix`. No action needed.

Still worth porting the other hand-written units the same way:
`micmute-led` (already handled in `modules/system/audio.nix`),
`rclone-nextcloud`, `elephant`, `claude-message.{service,timer}`.

### 0.3 — Pin the UID

`@home` is reused, so a UID mismatch would misown every file in `/home/henry`.
You are `uid=1000` today. In `hosts/thinkpad/default.nix`:

```diff
   users.users.henry = {
     isNormalUser = true;
+    uid = 1000;
```

### 0.4 — Lock the inputs

There is no `flake.lock`, so inputs float on every build and the install is not
reproducible.

```bash
cd ~/src/arch-config/nixos && nix flake lock
```

### 0.5 — Re-verify and push

```bash
cd ~/src/arch-config/nixos
./verify-packages.sh          # must pass all 3 stages
cd ~/src/arch-config && git add -A && git commit -m "Fix dotfiles self-symlink, declare mango-session, pin uid, lock inputs"
git push
```

**Checkpoint:** do not continue until `verify-packages.sh` passes.

---

## Phase 1 — Protect what the install does not carry

### 1.1 — Root-only state

The unprivileged backup could not read these. Includes WiFi credentials for 38
networks (one is 802.1x/eduroam and painful to rebuild), Bluetooth pairings and
CUPS printers.

```bash
sudo "/run/media/henry/Samsung 128G/backup-2026-07-28/capture-root-state.sh"
```

### 1.2 — Resolve the dirty repos

These hold work that exists nowhere else:

```bash
for r in ~/Projects/homelab ~/Projects/Azure-in-bullet-points \
         ~/Projects/aur-malware-check ~/Projects/learning; do
  echo "=== $r"; git -C "$r" status --short
done
```

Commit and push, or decide it is debris. Also decide on
`code/paraphrase-detector`'s `backup/local-main-pre-sync-20260704` branch —
4 commits that exist on no remote.

### 1.3 — Refresh the backup drive

Anything edited since the 2026-07-28 sweep is not on the drive yet.

```bash
cd ~ && rsync -aHAX --relative --exclude='*.log' \
  Documents Projects code vaults .ssh .gnupg .config/rclone \
  "/run/media/henry/Samsung 128G/backup-2026-07-28/"
```

### 1.4 — Snapshot `@home`

Instant and free. Protects against a mistyped subvolume command in Phase 3.

```bash
sudo btrfs subvolume snapshot -r /home /home/.snapshot-pre-nixos
```

---

## Phase 2 — Boot the installer

Recommended: write a NixOS ISO to a USB stick and boot it. This is the
best-tested path, and it gives you `nixos-install` and
`nixos-generate-config` without fighting your running system.

Installing from Arch directly is possible — you have Nix 2.35.1 — but needs
`nixos-install-tools` and has more edge cases. If the ISO is inconvenient,
that path works; just expect to troubleshoot more.

Once booted, get on the network (`nmtui` or `iwctl`), then continue.

---

## Phase 3 — Create the new subvolumes

**First command that changes the disk.** It only *adds* subvolumes; `@`,
`@home`, `@pkg`, `@log` and the ESP are untouched.

```bash
sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume list /mnt/btrfs-root        # expect @ @home @pkg @log swap
sudo btrfs subvolume create /mnt/btrfs-root/@nixos
sudo btrfs subvolume create /mnt/btrfs-root/@nix
sudo btrfs subvolume list /mnt/btrfs-root        # now also @nixos @nix
sudo umount /mnt/btrfs-root
```

---

## Phase 4 — Mount the target and install

Mount options mirror `hosts/thinkpad/hardware-configuration.nix` exactly. Get
these wrong and the installed system will not match its own config.

```bash
OPTS="compress=zstd:3,ssd,discard=async,space_cache=v2,relatime"

sudo mount -o subvol=@nixos,$OPTS /dev/nvme0n1p2 /mnt
sudo mkdir -p /mnt/{nix,home,var/log,boot}

# noatime on the store: read constantly, never needs atimes
sudo mount -o subvol=@nix,compress=zstd:3,ssd,discard=async,space_cache=v2,noatime \
     /dev/nvme0n1p2 /mnt/nix
sudo mount -o subvol=@home,$OPTS /dev/nvme0n1p2 /mnt/home
sudo mount -o subvol=@log,$OPTS  /dev/nvme0n1p2 /mnt/var/log
sudo mount /dev/nvme0n1p1 /mnt/boot

findmnt -R /mnt      # confirm all five before continuing
```

Sanity-check the ESP still holds Arch's bootloader — you are sharing it:

```bash
ls /mnt/boot/EFI /mnt/boot/vmlinuz-linux
```

Cross-check the generated hardware config against the committed one. The
installer is the authority on kernel modules for your exact hardware:

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config \
  | diff -u ~/src/arch-config/nixos/hosts/thinkpad/hardware-configuration.nix - | head -40
```

Differences in `availableKernelModules` are worth folding in. Differences in
UUIDs mean something is wrong — stop and re-check.

Install:

```bash
sudo nixos-install --root /mnt --flake /mnt/home/henry/src/arch-config/nixos#thinkpad
```

It will prompt for a root password at the end. Then:

```bash
sudo umount -R /mnt
reboot
```

---

## Phase 5 — First boot

The boot menu now lists both NixOS and Arch. Pick NixOS.

You land on `tuigreet`, a TTY greeter — deliberately, because it cannot fail
in a way that locks you out of a graphical session.

Goal for the first session is only this: **the compositor starts.** Nothing
else matters today. If mango does not come up, pick the previous generation or
Arch from the boot menu and debug from there.

### 5.1 — Restore what the flake does not carry

```bash
B="/run/media/henry/Samsung 128G/backup-2026-07-28"

# WiFi (38 networks, incl. eduroam), Bluetooth pairings, printers
sudo cp -a "$B/system-state/root-only/nm-system-connections/." \
           /etc/NetworkManager/system-connections/
sudo chmod 600 /etc/NetworkManager/system-connections/*
sudo systemctl restart NetworkManager

sudo cp -a "$B/system-state/root-only/bluetooth-pairings/." /var/lib/bluetooth/
sudo systemctl restart bluetooth

# CLI credentials — gitignored, so a clone does NOT restore them
cp -a "$B/.config/rclone" "$B/.config/gh" "$B/.config/glab-cli" "$B/.config/rbw" ~/.config/

# Flatpaks (services.flatpak.enable installs the daemon, not the apps)
flatpak install -y flathub com.hypixel.HytaleLauncher com.stremio.Stremio io.github.wivrn.wivrn
```

### 5.2 — Verify the things that were broken before

```bash
# The waybar fix: title module should be running, no crash
pgrep -a waybar && pgrep -af window-title

# The ath11k suspend workaround
systemctl cat wifi-resume.service

# keyd: the typst layer was dead on Arch and should now work
sudo keyd monitor      # press rightalt
```

---

## Phase 6 — Cleanup (not before a month has passed)

Only once you have not booted Arch in weeks and everything you need works.
**This is the first irreversible step.**

```bash
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume delete /mnt/btrfs-root/@
sudo btrfs subvolume delete /mnt/btrfs-root/@pkg
sudo btrfs subvolume delete /mnt/btrfs-root/swap
sudo btrfs subvolume delete /home/.snapshot-pre-nixos
```

Leave `@home`, `@nixos`, `@nix` and `@log` alone.

---

## If something goes wrong

| Symptom | Action |
|---|---|
| Rebuild fails on "existing file in the way" | B1 is not fixed. Do **not** reach for `backupFileExtension` — it renames your real config out from under the symlink. Fix `dots` instead |
| Compositor will not start | Pick the previous generation at boot. If none, boot Arch — it is untouched |
| ESP full during a rebuild | `sudo nix-collect-garbage -d` then `nixos-rebuild boot`. `configurationLimit = 6` should prevent this |
| WiFi dead after resume | Check `systemctl status wifi-resume.service`. This is the ath11k workaround from `networking.nix` |
| Home files owned by wrong user | UID mismatch — 0.3 was skipped. `sudo chown -R henry:users /home/henry` after fixing `uid` |
| Want out entirely | Boot Arch and carry on. Nothing in `@` or `@home` was modified |
