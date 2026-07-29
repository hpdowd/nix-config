# Arch → NixOS: complete step-by-step migration guide

**ThinkPad L14 Gen 5 · written 2026-07-29 · every fact verified against the
live machine on that date.**

This is the standalone guide. You should be able to follow it start to finish
without reading anything else. `MIGRATION.md` holds the *why* behind the
decisions; `INSTALL.md` is a condensed version of this. If they disagree with
each other, trust this file — it is the most recently verified.

A copy lives on the backup drive at
`/run/media/henry/Samsung 128G/MIGRATION-GUIDE.md`, so you can read it from
your phone or another machine while this one is mid-install.

---

## Part 0 — Read before you touch anything

### What this does

Installs NixOS **alongside** Arch on the same disk, in new btrfs subvolumes,
sharing the same EFI partition and reusing the same `/home`. Arch stays
bootable and untouched the whole way through. You pick which one to boot from
the menu.

### The safety net

| Step | Reversible? |
|---|---|
| Parts 1–4 (checks, backup, USB) | Nothing on the disk changes |
| Part 5 (boot installer) | Nothing on the disk changes |
| Part 6 (create subvolumes) | Adds only. `@`, `@home`, `@pkg`, `@log`, `swap` untouched |
| Parts 7–8 (install) | Writes to the new subvolumes and adds a boot entry |
| Parts 9–12 (first boot, restore) | Your Arch install is still there; reboot into it any time |
| **Part 13 (cleanup)** | **Irreversible. Do not do this for at least a month** |

At any point before Part 13, the escape hatch is: reboot, pick Arch, carry on
with your life. Nothing in `@` (your Arch root) or `@home` is modified.

### Time

Budget an evening. The install itself is ~30–60 minutes depending on your
connection; ~13.8 GiB gets downloaded. Getting the desktop *fully* how you
like it is a few weeks of small fixes — that is normal and expected.

### The one thing people get wrong

There will be **two checkouts** of your config repo, and which one is live
depends on which OS you booted:

| Booted | Live config | The other one |
|---|---|---|
| Arch | `~/.config` — real directories | `~/src/arch-config` goes stale |
| NixOS | `~/src/arch-config` — via `~/.config/*` symlinks | `~/.config` is bypassed |

**`nixos-install` reads the clone.** So before you install, the clone must be
up to date. Part 2 Step 5 covers this.

---

## Part 1 — Your machine, as verified

You do not need to look any of this up; it was checked on 2026-07-29.

```
nvme0n1                             476.9 GB
├─nvme0n1p1  vfat   32D9-7457                              1 GB   → /boot (ESP)
└─nvme0n1p2  btrfs  3c2d15a1-3a17-4715-99e5-969f27027571  475.9 GB
      subvolumes: @  @home  @pkg  @log  swap
      365 GB used, 110 GB free
```

Note **`swap` has no `@` prefix** — it is the one subvolume that differs. Get
this wrong in Part 13 and the delete command fails.

| Thing | Value |
|---|---|
| Config repo | `git.henrydowd.dev/henry/arch-config` |
| Working copy (Arch) | `~/.config` |
| Clone the flake reads | `~/src/arch-config` |
| Flake | `~/src/arch-config/nixos`, attribute `thinkpad` |
| Pinned nixpkgs | `624af665` (26.11pre) via `flake.lock` |
| Backup drive | `/run/media/henry/Samsung 128G` (ext4) |
| Backup set | `backup-2026-07-28/` |
| Your ids | `uid=1000 gid=1000(henry)` — pinned in the flake to match |

Nix is **already installed on Arch** (2.35.1, daemon running, flakes enabled
in `~/.config/nix/nix.conf`). You do not need to install it again. It is only
used here for verification; the actual install is done by the NixOS installer.

---

## Part 2 — Pre-flight checks (on Arch, ~5 minutes)

All of these passed on 2026-07-29. Run them again — the machine drifts.

### Step 1 — The flake still evaluates

```bash
cd ~/src/arch-config/nixos
./verify-packages.sh
```

Must reach `Done.` with **no deprecation warnings**. If it fails, stop and fix
that before anything else; nothing later will work.

### Step 1b — The overridden packages still *build*

Evaluation only proves names resolve. It does not compile anything, and a
package that evaluates fine can still fail to build — which during
`nixos-install` means aborting partway, after the disk has been written to.
This exact thing was caught in the `fsel` override on 2026-07-29.

Only two packages in the closure come from `pkgs/default.nix`. Build both:

```bash
nix build --no-link path:.#nixosConfigurations.thinkpad.pkgs.fsel
nix build --no-link path:.#nixosConfigurations.thinkpad.pkgs.gruvbox-gtk-theme
```

Both should finish without error. If you ever add `curseforge` or
`brother-mfc-l3740cdw` from that file, build them the same way first — neither
has ever been compiled.

### Step 2 — No broken dotfile links

This is the bug class that has bitten this migration twice. Both must print
nothing.

```bash
cd ~/src/arch-config

# (a) every linked name must exist in the checkout
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

Check (b) must be done separately because `verify-packages.sh` **cannot** catch
it — a path collision only fails when the home files are built.

### Step 3 — Links point into the clone, not at themselves

```bash
readlink "$(nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake "/home/henry/src/arch-config/nixos";
  in f.nixosConfigurations.thinkpad.config.home-manager.users.henry.home.file."/home/henry/.config/mango".source')"
```

Must print `/home/henry/src/arch-config/mango`. If it prints
`/home/henry/.config/mango`, the link points at its own destination and your
config will silently vanish on first boot. Do not continue.

### Step 4 — Your ids are pinned

```bash
nix eval --impure --expr '
let c = (builtins.getFlake "path:/home/henry/src/arch-config/nixos").nixosConfigurations.thinkpad.config;
in { uid = c.users.users.henry.uid; group = c.users.users.henry.group;
     gid = c.users.groups.henry.gid; }'
```

Must print `{ gid = 1000; group = "henry"; uid = 1000; }`. These have to match
`id henry` on Arch, because `@home` is shared between both systems.

### Step 5 — Sync the two checkouts

```bash
cd ~/.config && git status --short          # commit anything outstanding
git add -A && git commit -m "pre-install snapshot" && git push

cd ~/src/arch-config && git pull

# these two must match:
git -C ~/.config rev-parse HEAD
git -C ~/src/arch-config rev-parse HEAD
```

> The Gitea remote is on your homelab network. If `git push` hangs, you are off
> that network — check with `git ls-remote origin`. You can still install: the
> clone is what matters, and you can sync it directly with
> `git -C ~/src/arch-config pull /home/henry/.config main`.

### Step 6 — Nothing uncommitted anywhere else

```bash
for r in ~/.config ~/src/arch-config ~/Projects/* ~/code/*; do
  [ -d "$r/.git" ] || continue
  d=$(git -C "$r" status --short | wc -l)
  u=$(git -C "$r" log --branches --not --remotes --oneline | wc -l)
  [ "$d" = 0 ] && [ "$u" = 0 ] || echo "$r: $d dirty, $u unpushed"
done
```

---

## Part 3 — Protect what the install does not carry

### Step 1 — Root-only state

Your backup ran unprivileged and could not read these. This captures WiFi
credentials for 38 networks (one is 802.1x/eduroam and genuinely painful to
rebuild by hand), Bluetooth pairings, and CUPS printers.

```bash
sudo "/run/media/henry/Samsung 128G/backup-2026-07-28/capture-root-state.sh"
```

Confirm it produced something:

```bash
ls "/run/media/henry/Samsung 128G/backup-2026-07-28/system-state/root-only/"
```

### Step 2 — Refresh the file backup

```bash
cd ~ && rsync -aHAX --relative --exclude='*.log' \
  Documents Projects code vaults .ssh .gnupg .config/rclone \
  "/run/media/henry/Samsung 128G/backup-2026-07-28/"
```

**Do not add `--delete`.** The backup still holds
`Projects/Azure-in-bullet-points`, which was deleted locally on 2026-07-29 —
including LaTeX sources and a built PDF that exist nowhere else. `--delete`
would destroy the only copy.

### Step 3 — Snapshot `/home`

Instant, free, and it protects against the one realistic risk in Part 6: a
mistyped subvolume command.

```bash
sudo btrfs subvolume snapshot -r /home /home/.snapshot-pre-nixos
sudo btrfs subvolume list / | grep snapshot-pre-nixos
```

---

## Part 4 — Make the installer USB

Use the **unstable** minimal ISO. This is not the usual advice, and the reason
is specific: `channels.nixos.org/nixos-unstable` currently resolves to
`nixos-minimal-26.11pre1042126.624af665418d`, and `624af665` is the exact
nixpkgs revision your `flake.lock` pins. Matching them means the installer can
substitute almost everything from the binary cache instead of rebuilding.

```bash
curl -L -o ~/nixos-minimal.iso \
  https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso
```

Write it to a USB stick. **`lsblk` first** — this erases the target device.

```bash
lsblk -o NAME,SIZE,MODEL,TRAN            # identify your stick, e.g. sdb
sudo dd if=~/nixos-minimal.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

`/dev/sda` is currently your backup drive. Do not write to it.

---

## Part 5 — Boot the installer

1. Reboot, hold **F12** (ThinkPad boot menu), pick the USB stick.
2. You land at a shell. Depending on the image you may be `root` or the
   `nixos` user; every command here uses `sudo`, which works either way.
3. Get on the network. **Ethernet is by far the least hassle** — plug in and
   it works. For WiFi, try in this order:

   ```bash
   nmtui                      # if NetworkManager is on the image
   # otherwise:
   sudo systemctl start wpa_supplicant
   wpa_cli                    # then: add_network / set_network / enable_network
   ```

   The minimal ISO is deliberately sparse, so do not assume `nmtui` exists.
4. Confirm you can reach the cache — the install is ~13.8 GiB of downloads and
   will fail without it:

   ```bash
   ping -c2 cache.nixos.org
   ```

**Enable flakes.** The installer ISO does *not* enable them by default, and
every command below needs them:

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
```

You must re-export this in every new shell on the installer.

---

## Part 6 — Create the new subvolumes

**First command that changes the disk.** It only adds; nothing existing is
touched.

```bash
sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume list /mnt/btrfs-root
```

You should see `@`, `@home`, `@pkg`, `@log`, `swap`. If you see something
different, **stop** — you are on the wrong disk.

```bash
sudo btrfs subvolume create /mnt/btrfs-root/@nixos
sudo btrfs subvolume create /mnt/btrfs-root/@nix
sudo btrfs subvolume list /mnt/btrfs-root      # now also @nixos and @nix
sudo umount /mnt/btrfs-root
```

---

## Part 7 — Mount the target

These options mirror `hosts/thinkpad/hardware-configuration.nix` exactly. If
they differ, the installed system will not match its own config and will
remount things oddly on first boot.

```bash
OPTS="compress=zstd:3,ssd,discard=async,space_cache=v2,relatime"

sudo mount -o subvol=@nixos,$OPTS /dev/nvme0n1p2 /mnt
sudo mkdir -p /mnt/nix /mnt/home /mnt/var/log /mnt/boot

# noatime on the store: it is read constantly and never needs access times
sudo mount -o subvol=@nix,compress=zstd:3,ssd,discard=async,space_cache=v2,noatime \
     /dev/nvme0n1p2 /mnt/nix
sudo mount -o subvol=@home,$OPTS /dev/nvme0n1p2 /mnt/home
sudo mount -o subvol=@log,$OPTS  /dev/nvme0n1p2 /mnt/var/log
sudo mount /dev/nvme0n1p1 /mnt/boot
```

Verify all five:

```bash
findmnt -R /mnt
```

Confirm Arch's bootloader is still on the ESP you just mounted — you are
sharing it, and you must not clobber it:

```bash
ls /mnt/boot/EFI /mnt/boot/vmlinuz-linux
```

Confirm your home is really there:

```bash
ls /mnt/home/henry/src/arch-config/nixos/flake.nix
```

If that file is missing, the clone did not exist or `@home` is not mounted.
Do not continue.

---

## Part 8 — Install

### Step 8.1 — Cross-check the hardware config

The installer is the authority on kernel modules for your exact hardware.

A raw `diff` against the committed file is not useful — that file is
hand-written with a `let` block and long comments, so the diff is almost all
formatting noise. Compare the two things that actually matter instead:

```bash
HW=/mnt/home/henry/src/arch-config/nixos/hosts/thinkpad/hardware-configuration.nix
sudo nixos-generate-config --root /mnt --show-hardware-config > /tmp/hw-generated.nix

# the committed file lists modules one per line, so -A9 is needed to see them;
# nixos-generate-config emits them on a single line
echo "--- generated:"; grep -E 'availableKernelModules|kernelModules' /tmp/hw-generated.nix
echo "--- committed:"; grep -A9 'availableKernelModules' "$HW"; grep -E '^\s+boot\.(initrd\.)?kernelModules' "$HW"

echo "--- generated UUIDs:"; grep -oE '[0-9a-fA-F-]{8,}' /tmp/hw-generated.nix | sort -u
echo "--- committed UUIDs:"; grep -oE '(3c2d15a1[a-f0-9-]*|32D9-7457)' "$HW" | sort -u
```

- A module in the generated list that is missing from the committed one is
  worth adding (it goes in `boot.initrd.availableKernelModules`).
- **Any UUID mismatch: stop.** The committed values are `32D9-7457` (ESP) and
  `3c2d15a1-3a17-4715-99e5-969f27027571` (btrfs). If the installer sees
  something else, you are looking at a different disk and must not continue.

### Step 8.2 — Run the install

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
sudo nixos-install --root /mnt \
  --flake /mnt/home/henry/src/arch-config/nixos#thinkpad
```

You may see `warning: Git tree ... is dirty` — harmless, it just means the
working tree has edits. Nix uses them.

At the end it prompts for a **root** password. Set one you will remember.

**If it looks like it is building a lot:** it is fine. Several hundred
derivations get "built", but nearly all are tiny `/etc` files. The only
substantial ones are three Electron runtimes (for `logseq`, `winboat` and
`claude-desktop`). Those are prebuilt binaries that get unpacked, not
compiled — they are absent from the binary cache only because they are flagged
insecure, and Hydra does not build insecure-flagged packages. Minutes, not
hours.

### Step 8.3 — Set your user password ⚠️ DO NOT SKIP

`nixos-install` sets the **root** password only. Your `henry` account has no
password declared anywhere in the flake (deliberately — a hash in git is worse
than this step), and the new root subvolume has a fresh `/etc/shadow`. **Skip
this and the greeter will refuse your login on first boot.**

```bash
sudo nixos-enter --root /mnt -c 'passwd henry'
```

Verify it took:

```bash
sudo nixos-enter --root /mnt -c 'passwd -S henry'
# want the second field to be P (password set), not L (locked) or NP (none)
```

> Forgot? Not fatal. Boot Arch, or boot the installer again, remount as in
> Part 7, and run the same command.

### Step 8.4 — Reboot

```bash
sudo umount -R /mnt
reboot
```

Remove the USB stick.

---

## Part 9 — First boot

The boot menu now lists NixOS generations **and** Arch. Pick NixOS.

You land on `tuigreet`, a plain text greeter. This is deliberate: a TTY greeter
cannot fail in a way that locks you out of a graphical session. Log in as
`henry` with the password from Step 8.3.

**The only goal today is that the compositor starts.** Nothing else matters.
If mango does not come up, pick the previous generation at the boot menu, or
boot Arch — it is completely untouched.

### What you will notice immediately, and should not panic about

- **Your `~/.config` directories have been renamed to `*.hm-bak`.** This is
  expected. home-manager moved the real ones aside and replaced them with
  symlinks into `~/src/arch-config`. Your data is fine. Clean them up later
  with `find ~/.config -maxdepth 1 -name '*.hm-bak'`.
- **No wallpaper.** `mango/wallpaper/` is excluded from the repo on purpose
  (4.6 MB of binaries). Copy it from the backup or from `~/.config`.
- **Some apps have no settings** — the ones holding credentials were
  deliberately not linked. Part 10 restores them.

---

## Part 10 — Restore what the flake does not carry

```bash
B="/run/media/henry/Samsung 128G/backup-2026-07-28"
```

### Step 1 — Network, Bluetooth, printers

```bash
sudo cp -a "$B/system-state/root-only/nm-system-connections/." \
           /etc/NetworkManager/system-connections/
sudo chmod 600 /etc/NetworkManager/system-connections/*
sudo systemctl restart NetworkManager

sudo cp -a "$B/system-state/root-only/bluetooth-pairings/." /var/lib/bluetooth/
sudo systemctl restart bluetooth
```

**Printers — do not bulk-copy.** The capture script also saved `/etc/cups`,
but NixOS generates most of that directory from the `services.printing`
module, so copying the Arch version over it will fight the module. Your Brother
MFC-L3740CDW supports driverless IPP Everywhere and `avahi` is enabled, so try
discovery first:

```bash
lpinfo -v                       # should list the Brother over dnssd
lpstat -p                       # what is already configured
```

If it is not found, add it from the saved queue definition by hand:

```bash
grep -A5 DeviceURI "$B/system-state/root-only/cups/printers.conf"
# then: lpadmin -p <name> -E -v <uri> -m everywhere
```

### Step 2 — CLI credentials

These are gitignored **and** deliberately excluded from the dotfiles links,
because linking a credential directory into a git repo is how tokens end up
committed. Restoring by hand is the intended mechanism, not a workaround.

```bash
cp -a "$B/.config/rclone" "$B/.config/gh" "$B/.config/glab-cli" "$B/.config/rbw" ~/.config/
```

### Step 3 — Wallpapers (4.6 MB, gitignored so the clone has none)

Careful here: by this point `~/.config/mango` **is a symlink to
`~/src/arch-config/mango`**, so copying from one to the other is a no-op onto
itself. The real Arch directory is the one home-manager moved aside:

```bash
cp -a ~/.config/mango.hm-bak/wallpaper ~/src/arch-config/mango/
ls ~/src/arch-config/mango/wallpaper | head
```

If you already deleted the `.hm-bak` directories, take them from the backup
drive or from the Arch install (`/mnt` it from a live boot). They stay
untracked — `.gitignore` line 96 excludes `/mango/wallpaper/` on purpose.

---

## Part 11 — Verify the things that were previously broken

```bash
# waybar: the title module runs and waybar does not segfault
pgrep -a waybar && pgrep -af window-title

# the ath11k WiFi-after-suspend workaround exists
systemctl cat wifi-resume.service

# keyd: the typst layer was dead on Arch and should now work
sudo keyd monitor        # press rightalt, then Ctrl-C

# the rclone Proton Drive mount (needs Part 10 Step 2 first)
systemctl --user status rclone-protondrive
mount | grep ProtonDrive

# the GTK theme actually resolves. This is the one that would silently
# fall back to Adwaita if the overlay were wrong.
ls /run/current-system/sw/share/themes/ | grep Gruvbox
# want: Gruvbox-Yellow-Dark

# your ids survived, and /home is not misowned
id henry                 # want uid=1000(henry) gid=1000(henry)
ls -ld ~/Documents       # want henry henry
```

Then test suspend/resume once — it is the failure mode this machine has a
history of.

---

## Part 12 — Living with it

The flake lives at `~/src/arch-config/nixos` and you edit it **there
directly** — `dotfiles.nix` does not link `nixos/`, so `~/.config/nixos` does
not exist on the new system.

Your *application* config is the other way round: `~/.config/mango`,
`~/.config/nvim` and the rest are symlinks into the same clone, and they are
writable, so the mango mode scripts can still rewrite `active-theme.*` at
runtime. Editing either path edits the same repo.

```bash
rebuild        # sudo nixos-rebuild switch --flake ~/src/arch-config/nixos#thinkpad
rebuild-test   # try it without making it the boot default
rebuild-boot   # apply on next boot only
update         # nix flake update  (moves the pins; re-run verify after)
generations    # list what you can roll back to
gc             # delete generations older than 30 days
```

These aliases are defined in `modules/home/shell.nix`.

**Rolling back:** pick an older generation at the boot menu. That is the whole
procedure.

**After editing config,** commit and push so `~/.config` on Arch and the clone
do not drift:

```bash
cd ~/src/arch-config && git add -A && git commit -m "..." && git push
```

---

## Part 13 — Cleanup ⚠️ IRREVERSIBLE — not for at least a month

Only once you have not booted Arch in weeks and everything you need works.

```bash
sudo mkdir -p /mnt/btrfs-root
sudo mount -o subvolid=5 /dev/nvme0n1p2 /mnt/btrfs-root
sudo btrfs subvolume list /mnt/btrfs-root       # look before you delete

sudo btrfs subvolume delete /mnt/btrfs-root/@
sudo btrfs subvolume delete /mnt/btrfs-root/@pkg
sudo btrfs subvolume delete /mnt/btrfs-root/swap
sudo btrfs subvolume delete /home/.snapshot-pre-nixos
sudo umount /mnt/btrfs-root
```

**Keep `@home`, `@nixos`, `@nix`, `@log`.** Note `swap`, not `@swap`.

Then clean Arch's leftovers off the shared ESP, or the boot menu keeps
offering an Arch that no longer exists:

As of 2026-07-29 the Arch files on the shared ESP are exactly these:

```bash
ls /boot
#   amd-ucode.img  EFI  initramfs-linux.img  loader  vmlinuz-linux
ls /boot/loader/entries
#   2025-11-29_15-37-31_linux.conf
#   2025-11-29_15-37-31_linux-fallback.conf

sudo rm /boot/vmlinuz-linux /boot/initramfs-linux.img /boot/amd-ucode.img
sudo rm /boot/loader/entries/2025-11-29_15-37-31_linux*.conf
```

Leave `/boot/EFI` and `/boot/loader/loader.conf` alone — systemd-boot itself
lives there and NixOS is now using it. Re-check the filenames before deleting;
a kernel update on Arch would have changed them.

---

## Part 14 — Troubleshooting

| Symptom | What it means / what to do |
|---|---|
| Greeter rejects your password | Step 8.3 was skipped. Boot Arch or the installer, remount per Part 7, `sudo nixos-enter --root /mnt -c 'passwd henry'` |
| `error: experimental Nix feature 'nix-command' is disabled` | You are in a new shell on the installer. Re-run the `export NIX_CONFIG=...` from Part 5 |
| Rebuild fails: "existing file is in the way" | A dotfile link is wrong. **Do not** reach for `backupFileExtension` — it renames your real config out from under the symlink. Fix the link; see Part 2 Step 2 |
| An app has no config, directory is a broken symlink | Dangling link. Your real config is at `<name>.hm-bak`. Part 2 Step 2 check (a) |
| Compositor will not start | Previous generation at the boot menu. If none works, boot Arch |
| Every GTK app looks like Adwaita | `Gruvbox-Yellow-Dark` did not resolve. The `pkgs/default.nix` override builds that variant; stock nixpkgs has only `Gruvbox-Dark` |
| ESP full during a rebuild | `sudo nix-collect-garbage -d`, then `nixos-rebuild boot`. `configurationLimit = 6` is meant to prevent this |
| WiFi dead after resume | `systemctl status wifi-resume.service` — the ath11k workaround |
| Files in `/home` owned by a wrong group | uid/gid mismatch; Part 2 Step 4 was skipped. `sudo chown -R henry:henry /home/henry` |
| `/nix` filling the disk | `nix-collect-garbage --delete-older-than 7d`. You have ~73 GiB of headroom, less than the plan originally assumed |
| Want out entirely | Boot Arch. Nothing in `@` or `@home` was modified |

---

## Part 15 — Deliberately not carried over

Decisions, not oversights. Recorded so they are not "rediscovered" as bugs.

| Thing | Why |
|---|---|
| Flatpak (daemon + Hytale, Stremio, WiVRn) | Not wanted; daemon pointless with no apps |
| fish | zsh is the login shell per `/etc/passwd`; fish's dotfiles link also collided with `programs.fish` |
| `claude-message.timer` | Was failing daily since June — ExecStart said `claude-scheduler`, the script is `claude_scheduler`. Disabled on Arch too |
| `gpu-screen-recorder-ui` | No nixpkgs equivalent; plain CLI kept |
| `elephant.service` | Redundant — `mango/*/autostart.conf` already starts it |
| `rclone-nextcloud.service` | Not enabled on Arch; `~/Nextcloud` uses the desktop sync client |
| `~/.scripts` | In no git repo. Survives via `@home`, already on `PATH` |
| `gh`/`glab-cli`/`opencode`/`gpu-screen-recorder` configs | Hold credentials; restored by hand in Part 10 |
| `mango/wallpaper/` | 4.6 MB of binaries, excluded from the repo |
| DankMaterialShell, Quickshell, the `dms` mode | Dropped in July 2026 |

Still absent from nixpkgs, still your call: `piavpn-bin`,
`freedownloadmanager` (**note**: `mimeapps.list` still points `magnet:` and
`.torrent` at it, so that handler will be dead — `qbittorrent` is packaged),
`quickmedia`, `pipemixer`, `r-quick-share`, `haroopad`, `mdview`,
`pdf-compress`, `qrookie-vrp`, `nerd-fonts-sf-mono`, `ttf-phosphor-icons`.

---

## Appendix — Installing without a USB stick

Possible, since Nix is already on Arch, but less well trodden. Use it only if
making a USB stick is genuinely inconvenient.

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
nix shell nixpkgs#nixos-install-tools
```

Then follow Parts 6, 7 and 8 unchanged — `nixos-install`, `nixos-enter` and
`nixos-generate-config` all come from that shell.

Caveats: you are partitioning and mounting from the system you are migrating,
`/mnt` paths must not collide with anything Arch has mounted, and you cannot
cross-check against the installer's `nixos-generate-config` view of your
hardware as easily. The USB route avoids all of this.
