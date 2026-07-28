# NixOS install runbook

Rewritten 2026-07-29. Every fact below was checked against the live machine on
that date, not carried over from the previous draft. Rationale for the design
decisions lives in `MIGRATION.md`; this file is only the procedure.

**Status: no blockers. The flake is ready to install.** Phase 0 is a set of
checks that currently all pass — run them again before you start, because the
machine drifts.

Phases 1–3 do not modify the running system. Arch stays bootable until Phase 7,
which you should not reach for at least a month.

---

## The machine, as verified 2026-07-29

| Fact | Value |
|---|---|
| ESP | `nvme0n1p1`, vfat, UUID `32D9-7457`, 1022 MiB, **62 MiB used** |
| Root disk | `nvme0n1p2`, btrfs, UUID `3c2d15a1-3a17-4715-99e5-969f27027571` |
| Existing subvolumes | `@`, `@home`, `@log`, `@pkg`, `swap` — note **`swap` has no `@`** |
| Free space | **110 GiB** (was 149 GiB when the plan was written — it shrank) |
| Closure | ~13.8 GiB download, ~37 GiB unpacked on a cold store |
| Flake | pinned by `flake.lock` to nixpkgs `624af665` (26.11.20260726) |
| Clone | `~/src/arch-config`, in sync with `git.henrydowd.dev/henry/arch-config` |
| Backup | `/run/media/henry/Samsung 128G/backup-2026-07-28` |

110 GiB free against a 37 GiB closure leaves ~73 GiB. That fits, but it is
tighter than the original 149 GiB assessment. With `nix.gc` keeping 30 days of
generations, expect real usage of 60–80 GiB after a few dozen rebuilds — so
this will get snug. Watch it in the first month.

---

## Phase 0 — Pre-flight checks

All of these passed on 2026-07-29. Re-run them; each is fast.

### 0.1 — The flake still evaluates

```bash
cd ~/src/arch-config/nixos && ./verify-packages.sh
```

Must reach "Done" with **no deprecation warnings**.

### 0.2 — No self-referential or dangling dotfile links

This is the bug class that has bitten this migration twice (B1, B3). Both
checks must come back empty.

```bash
cd ~/src/arch-config

# (a) every linked name must actually exist in the checkout
grep -oP '"\K[^"]+(?=" *\. *source = link)' nixos/modules/home/dotfiles.nix |
  while read -r p; do [ -e "$p" ] || echo "DANGLING: $p"; done

# (b) no managed path may sit inside another managed path
nix eval --impure --expr '
let
  f = builtins.getFlake "path:/home/henry/src/arch-config/nixos";
  hm = f.nixosConfigurations.thinkpad.config.home-manager.users.henry;
  n = builtins.attrNames hm.home.file;
in builtins.concatMap (a: builtins.concatMap (b:
     if a != b && builtins.substring 0 (builtins.stringLength a + 1) b == "${a}/"
     then [ "${a} << ${b}" ] else []) n) n'
```

Check (b) matters because `verify-packages.sh` **cannot** catch it — a path
collision only fails when the home-files derivation is built, and building that
directly drags in texlive and logseq.

### 0.3 — The link target resolves into the clone, not into `~/.config`

```bash
readlink "$(nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake "/home/henry/src/arch-config/nixos";
  in f.nixosConfigurations.thinkpad.config.home-manager.users.henry.home.file."/home/henry/.config/mango".source')"
# want: /home/henry/src/arch-config/mango
# NOT:  /home/henry/.config/mango   <- self-referential, the B1 bug
```

### 0.4 — ids are pinned

```bash
nix eval --impure --expr '
let c = (builtins.getFlake "path:/home/henry/src/arch-config/nixos").nixosConfigurations.thinkpad.config;
in { uid = c.users.users.henry.uid; group = c.users.users.henry.group;
     gid = c.users.groups.henry.gid; }'
# want: uid = 1000; group = "henry"; gid = 1000
```

`@home` is reused **and stays mounted by Arch** through the side-by-side
period, so both ids must match `id henry` on the live system. Pinning only the
uid is not enough: `isNormalUser` would default the group to `users` (gid 100)
while every file under `/home/henry` is gid 1000.

### 0.5 — Nothing uncommitted anywhere

```bash
for r in ~/.config ~/src/arch-config ~/Projects/* ~/code/*; do
  [ -d "$r/.git" ] || continue
  d=$(git -C "$r" status --short | wc -l)
  u=$(git -C "$r" log --branches --not --remotes --oneline | wc -l)
  [ "$d" = 0 ] && [ "$u" = 0 ] || echo "$r: $d dirty, $u unpushed"
done
```

### 0.6 — The two working trees are in sync

**This is the one that will catch you out.** There are two checkouts of the
same repo, and which one is live depends on which OS you booted:

| Booted | Live config | The other tree |
|---|---|---|
| Arch | `~/.config` — the real directories | `~/src/arch-config` goes stale |
| NixOS | `~/src/arch-config` — via the `~/.config/*` symlinks | `~/.config` is bypassed |

While Arch is your daily driver, keep editing `~/.config`; it reads those
directories directly and ignores the clone entirely. But **`nixos-install`
reads the clone**, so re-sync immediately before Phase 5:

```bash
cd ~/.config && git add -A && git commit -m "..." && git push
cd ~/src/arch-config && git pull
git -C ~/.config rev-parse HEAD; git -C ~/src/arch-config rev-parse HEAD  # must match
```

After the migration the direction reverses: edit through the symlinks (which
land in the clone), and `~/.config` stops mattering.

---

## Phase 1 — Protect what the install does not carry

### 1.1 — Root-only state

The unprivileged backup could not read these: WiFi credentials for 38 networks
(one is 802.1x/eduroam and painful to rebuild), Bluetooth pairings, CUPS
printers.

```bash
sudo "/run/media/henry/Samsung 128G/backup-2026-07-28/capture-root-state.sh"
```

### 1.2 — Refresh the backup

The drive holds a 2026-07-28 sweep. Anything edited since is not on it.

```bash
cd ~ && rsync -aHAX --relative --exclude='*.log' \
  Documents Projects code vaults .ssh .gnupg .config/rclone \
  "/run/media/henry/Samsung 128G/backup-2026-07-28/"
```

No `--delete`, deliberately. The backup still holds
`Projects/Azure-in-bullet-points`, deleted locally on 2026-07-29 — including
the LaTeX sources and built PDF. Adding `--delete` would destroy the only
remaining copy.

### 1.3 — Snapshot `@home`

Instant, free, and it protects against the actual risk in Phase 3: a mistyped
subvolume command.

```bash
sudo btrfs subvolume snapshot -r /home /home/.snapshot-pre-nixos
```

---

## Phase 2 — Boot the installer

Write a NixOS ISO to a USB stick and boot it. This is the best-tested path and
gives you `nixos-install` and `nixos-generate-config` without fighting the
running system.

Installing from Arch directly is possible — Nix 2.35.1 is already here — but
needs `nixos-install-tools` and has more edge cases.

Once booted, get on the network (`nmtui` or `iwctl`), then continue.

---

## Phase 3 — Create the new subvolumes

**First command that changes the disk.** It only *adds* subvolumes; `@`,
`@home`, `@pkg`, `@log`, `swap` and the ESP are untouched.

```bash
sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume list /mnt/btrfs-root      # expect: @ @home @pkg @log swap
sudo btrfs subvolume create /mnt/btrfs-root/@nixos
sudo btrfs subvolume create /mnt/btrfs-root/@nix
sudo btrfs subvolume list /mnt/btrfs-root      # now also @nixos @nix
sudo umount /mnt/btrfs-root
```

---

## Phase 4 — Mount the target

Options mirror `hosts/thinkpad/hardware-configuration.nix` exactly. Get these
wrong and the installed system will not match its own config.

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

Cross-check the generated hardware config. The installer is the authority on
kernel modules for your exact hardware:

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config \
  | diff -u /mnt/home/henry/src/arch-config/nixos/hosts/thinkpad/hardware-configuration.nix - | head -40
```

Differences in `availableKernelModules` are worth folding in. **Differences in
UUIDs mean something is wrong — stop.**

---

## Phase 5 — Install

Re-sync the clone first (§0.6) if you have touched anything since Phase 0.

```bash
sudo nixos-install --root /mnt --flake /mnt/home/henry/src/arch-config/nixos#thinkpad
```

### What "N derivations will be built" means here

The dry run reports several hundred derivations to build, which looks alarming
and is not. Almost all are trivial `/etc` config files (`etc-fstab`,
`fc-*.conf`, `dbus-1`) that take milliseconds.

The only substantial ones are three Electron apps and their Electron runtimes:

| Package | Electron | Pulled by |
|---|---|---|
| `logseq` | 39.8.10 | itself |
| `winboat` | 40.10.5 | itself |
| `claude-desktop` | 35.5.0 | its own nixpkgs pin |

These are **not** Chromium source builds. Each Electron derivation fetches
upstream's prebuilt `electron-vXX-linux-x64.zip` and unpacks it — verified by
inspecting the derivation. They are missing from `cache.nixos.org` (confirmed
404) only because they are flagged **insecure**, and Hydra does not build
insecure-flagged packages. That is also why `nix-settings.nix` needs its
`permittedInsecurePackages` entries — those two facts are the same fact.

So: a few hundred MB of extra download, minutes of unpacking. If you drop
`logseq`, `winboat` and `claude-desktop` from `packages.nix` it all goes away,
but there is no performance reason to.

`nixos-install` prompts for a root password at the end. Then:

```bash
sudo umount -R /mnt
reboot
```

---

## Phase 6 — First boot

The boot menu now lists both NixOS and Arch. Pick NixOS. You land on
`tuigreet`, a TTY greeter — deliberately, because it cannot fail in a way that
locks you out of a graphical session.

**Goal for the first session is only this: the compositor starts.** Nothing
else matters today. If mango does not come up, pick the previous generation or
Arch from the boot menu and debug from there.

### 6.1 — Restore what the flake does not carry

```bash
B="/run/media/henry/Samsung 128G/backup-2026-07-28"

# WiFi (38 networks, incl. eduroam), Bluetooth pairings, printers
sudo cp -a "$B/system-state/root-only/nm-system-connections/." \
           /etc/NetworkManager/system-connections/
sudo chmod 600 /etc/NetworkManager/system-connections/*
sudo systemctl restart NetworkManager

sudo cp -a "$B/system-state/root-only/bluetooth-pairings/." /var/lib/bluetooth/
sudo systemctl restart bluetooth

# CLI credentials. These are gitignored AND deliberately not linked by
# dotfiles.nix, so they are plain directories here — restoring by hand is the
# intended mechanism, not a workaround.
cp -a "$B/.config/rclone" "$B/.config/gh" "$B/.config/glab-cli" "$B/.config/rbw" ~/.config/
```

Wallpapers are not in the clone either — `.gitignore` excludes
`/mango/wallpaper/` on purpose (4.6 MB of binaries). Copy them across by hand.

### 6.2 — Verify the things that were broken before

```bash
# waybar: title module running, no SIGSEGV
pgrep -a waybar && pgrep -af window-title

# the ath11k suspend workaround
systemctl cat wifi-resume.service

# keyd: the typst layer was dead on Arch and should now work
sudo keyd monitor      # press rightalt

# the rclone ProtonDrive mount (needs ~/.config/rclone restored above)
systemctl --user status rclone-protondrive
mount | grep ProtonDrive

# GTK theme actually resolves — this is the one that would silently fall back
ls ~/.nix-profile/share/themes/ /run/current-system/sw/share/themes/ 2>/dev/null | grep Gruvbox
# want: Gruvbox-Yellow-Dark
```

---

## Phase 7 — Cleanup (not before a month has passed)

Only once you have not booted Arch in weeks and everything works. **This is the
first irreversible step.**

```bash
sudo mkdir -p /mnt/btrfs-root      # you are on the installed system now; this
                                   # dir came from the installer in Phase 3
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume delete /mnt/btrfs-root/@
sudo btrfs subvolume delete /mnt/btrfs-root/@pkg
sudo btrfs subvolume delete /mnt/btrfs-root/swap
sudo btrfs subvolume delete /home/.snapshot-pre-nixos
```

Leave `@home`, `@nixos`, `@nix` and `@log` alone. Note `swap`, not `@swap` —
it is the one subvolume without the prefix.

Deleting `@` leaves Arch's kernel and bootloader entries on the shared ESP.
Clean those out of `/boot` separately or the boot menu keeps offering an Arch
that no longer exists.

---

## If something goes wrong

| Symptom | Action |
|---|---|
| Rebuild fails on "existing file in the way" | A dotfile link is wrong. Do **not** reach for `backupFileExtension` — it renames your real config out from under the symlink. Fix the link; see §0.2 |
| Config directory is empty / app has no settings | Dangling link — §0.2 check (a). Your real config is at `<name>.hm-bak` |
| Compositor will not start | Pick the previous generation at boot. If none, boot Arch — it is untouched |
| GTK apps all look like Adwaita | `Gruvbox-Yellow-Dark` did not resolve. Check the `pkgs/default.nix` override built the yellow variant |
| ESP full during a rebuild | `sudo nix-collect-garbage -d` then `nixos-rebuild boot`. `configurationLimit = 6` should prevent it |
| WiFi dead after resume | `systemctl status wifi-resume.service` — the ath11k workaround from `networking.nix` |
| Home files owned by wrong user/group | uid/gid mismatch — §0.4 was skipped. `sudo chown -R henry:henry /home/henry` |
| Want out entirely | Boot Arch and carry on. Nothing in `@` or `@home` was modified |

---

## Deliberately not carried over

Not gaps — decisions. Recorded so they are not "rediscovered" later.

| Thing | Why |
|---|---|
| Flatpak (daemon and all 3 apps) | Hytale, Stremio, WiVRn not wanted; daemon pointless without them |
| fish | zsh is the login shell per `/etc/passwd`; fish's dotfiles link collided with `programs.fish` anyway |
| `claude-message.timer` | Was failing daily since June — `ExecStart` said `claude-scheduler`, the script is `claude_scheduler`. Disabled on Arch too |
| `gpu-screen-recorder-ui` | No nixpkgs equivalent. Plain CLI kept |
| `elephant.service` | Redundant — `mango/*/autostart.conf` already starts it |
| `rclone-nextcloud.service` | Not enabled on Arch; `~/Nextcloud` uses the desktop sync client |
| `~/.scripts` | In no git repo. Survives via `@home`; already on PATH |
| `gh`, `glab-cli`, `gpu-screen-recorder`, `opencode` configs | Hold credentials, excluded from git on purpose. Restored from backup in §6.1 |
| `mango/wallpaper/` | 4.6 MB of binaries excluded from the repo |

Still genuinely absent from nixpkgs, and still your call: `piavpn-bin`,
`freedownloadmanager` (note `mimeapps.list` still points `magnet:` and
`.torrent` at it, so that handler will be dead), `quickmedia`, `pipemixer`,
`r-quick-share`, `haroopad`, `mdview`, `pdf-compress`, `qrookie-vrp`,
`nerd-fonts-sf-mono`, `ttf-phosphor-icons`. See `MIGRATION.md` §6b.
