# NixOS install runbook

Follow this top to bottom. Every command is meant to be copy-pasteable.

Rationale for the design decisions lives in `MIGRATION.md`; this file is only
the procedure. Prerequisites were verified against the live machine on
2026-07-28 — see `MIGRATION.md` §8 for what was checked.

**Nothing before Phase 3 modifies the running system.** Arch stays bootable
until Phase 6, which you should not reach for at least a month.

---

## Phase 0 — Fix the blockers

Phase 0 is **done** — every item below is committed and the clone exists. It
is kept here so you can confirm each one rather than rediscover it.

### 0.1 — B1: clone the dotfiles checkout outside `~/.config` — DONE

`dotfiles.nix` sets `dots` to `~/src/arch-config`, and the clone is in place.
It was made from the local repo rather than the remote, because the Gitea
instance sits behind the homelab tunnel; `origin` is set to the real URL, so a
`git pull` will work as soon as that is reachable.

If you ever re-clone somewhere else, update `dots` in
`~/src/arch-config/nixos/modules/home/dotfiles.nix` to match.

### 0.1a — The two working trees, and keeping them in sync

**This is the part that will bite you.** There are now two checkouts of the
same repo, and which one is live depends on which OS you booted:

| Booted | Live config | The other tree |
|---|---|---|
| Arch | `~/.config` — the real directories | `~/src/arch-config` goes stale |
| NixOS | `~/src/arch-config` — via the `~/.config/*` symlinks | `~/.config` is bypassed |

So the earlier advice to "work in `~/src/arch-config` from here on" is wrong
for the period *before* the install: Arch reads `~/.config` directly and will
ignore anything you change in the clone. Keep editing `~/.config` while Arch is
your daily driver.

The consequence: **`nixos-install` reads the clone, so re-sync it immediately
before Phase 4**, or you will install a snapshot of whenever you cloned.

```bash
cd ~/.config && git add -A && git commit -m "..." && git push
cd ~/src/arch-config && git pull
```

Once you are living in NixOS, the direction reverses — edit through the
symlinks (which land in the clone), and `~/.config` stops mattering.

One thing the clone does not carry: `.gitignore` excludes
`/mango/wallpaper/`, so the new system starts with no wallpapers. That is a
deliberate exclusion (4.6 MB of binaries), not an oversight — copy them across
by hand if you want them.

Note the repo layout: the clone root holds `mango/`, `nvim/` and friends, and
the flake itself lives in `nixos/`. So `dots` is the clone root, but every
`nix` command below points at `~/src/arch-config/nixos`.

Verify — the built link must point into `~/src/arch-config`, at a directory
that exists. Confirmed 2026-07-28:

```bash
readlink "$(nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake "/home/henry/src/arch-config/nixos";
  in f.nixosConfigurations.thinkpad.config.home-manager.users.henry.home.file."/home/henry/.config/mango".source')"
# want: /home/henry/src/arch-config/mango
# NOT:  /home/henry/.config/mango   <- self-referential, the B1 bug
```

Check for the other half of the same bug — a link whose target is not in the
clone (B3). Every name `dotfiles.nix` links must exist in the checkout; this
must come back empty:

```bash
cd ~/src/arch-config
grep -oP '"\K[^"]+(?=" *\. *source = link)' nixos/modules/home/dotfiles.nix |
  while read -r p; do [ -e "$p" ] || echo "MISSING: $p"; done
```

A hit means that entry will become a dangling symlink on activation, and — with
`backupFileExtension` set — will do so after moving your real directory aside.

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

### 0.3 — B3: the links B1 missed — DONE

The B1 fix repointed `dots`, which fixed the 26 entries that go through
`link`. Three things did not go through `link` and stayed broken:

- **`~/.scripts`** was `mkOutOfStoreSymlink "${config.home.homeDirectory}/.scripts"`
  — a link to itself, the exact B1 bug. On activation it would have become
  `~/.scripts.hm-bak` plus a dangling `~/.scripts`, silently killing
  `cleantmp`, `lidaction`, `keyd-application-mapper` and the ExecStart of
  `micmute-led.service`. The declaration is gone; `~/.scripts` survives
  because `@home` is reused, and `home.sessionPath` already has it.
- **`gh`, `glab-cli`, `gpu-screen-recorder`, `opencode`** are excluded by the
  `.gitignore` allowlist because they hold credentials, so a clone never
  produces them — each link was a guaranteed dangling link, and §5.1's
  `cp -a` into one would have written your tokens *into the git clone*. Links
  removed; they are restored from the backup drive instead.
- **`mpv`** is allowlisted but empty, so git carries nothing. Link removed.

### 0.4 — Pin the uid *and* the group — DONE

`@home` is reused and Arch keeps mounting it, so both ids are now pinned to
the live values (`uid=1000`, `gid=1000(henry)`) in `hosts/thinkpad/default.nix`.

Pinning only the uid — which is what this file used to advise — was not
enough. `isNormalUser` defaults the primary group to `users` (gid 100), so
every file under `/home/henry` (all gid 1000) would have shown up under an
unmapped group on NixOS, and anything NixOS created would have shown up as
gid 100 on Arch.

### 0.5 — Lock the inputs — DONE

`flake.lock` is committed. Re-lock deliberately with `nix flake update`, not
as a side effect of a build.

### 0.6 — Re-verify

```bash
cd ~/src/arch-config/nixos
./verify-packages.sh          # must pass all 3 stages
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

### 1.2 — Resolve the dirty repos — DONE (2026-07-29)

All of it is now on a remote. `homelab` (9 files: phase 9/11 plans, ADR 013,
the OOM lesson, vaultwarden scaffolding) and `learning` (the golang 03
exercise) were committed and pushed. `paraphrase-detector`'s
`backup/local-main-pre-sync-20260704` branch — 4 commits including the final
thesis report — was pushed as a branch, not merged into `main`; that merge is
still yours to decide.

Two clones were deleted instead: `aur-malware-check` and
`Azure-in-bullet-points` (see MIGRATION.md §2).

Re-check before you install, since this goes stale:

```bash
for r in ~/Projects/* ~/code/*; do
  [ -d "$r/.git" ] || continue
  d=$(git -C "$r" status --short | wc -l)
  u=$(git -C "$r" log --branches --not --remotes --oneline | wc -l)
  [ "$d" = 0 ] && [ "$u" = 0 ] || echo "$r: $d dirty, $u unpushed"
done
```

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

# CLI credentials — gitignored, so a clone does NOT restore them. These are
# also the directories deliberately left out of dotfiles.nix (§0.3), so these
# paths are plain directories, not managed symlinks. Restoring them by hand is
# the intended mechanism.
cp -a "$B/.config/rclone" "$B/.config/gh" "$B/.config/glab-cli" "$B/.config/rbw" ~/.config/

```

Flatpak is deliberately absent — the three apps installed on Arch (Hytale,
Stremio, WiVRn) are not wanted, so neither they nor the daemon are carried
over. See `desktop.nix` if you change your mind.

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
sudo mkdir -p /mnt/btrfs-root      # you are on the installed system now, not
                                   # the installer — this dir won't exist yet
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
