# Arch → NixOS migration: ThinkPad L14 Gen 5

Written 2026-07-26 from a live survey of the running Arch system.

---

## 1. What you actually gain

Judged against *your* setup specifically, not the generic pitch.

**Rollback that covers the whole system.** You already run snapper on btrfs, so
you have this partially. The difference is that NixOS generations are entries
in the boot menu: a kernel update that breaks `ath11k_pci` again means picking
the previous generation at boot, not chrooting from a USB stick. Given that
you've already been bitten by a WiFi driver regression across suspend, this is
the concrete win.

**Your desktop becomes reproducible.** Right now, the knowledge of how this
machine works is split between `~/.config` (in files), `/etc` (tlp.conf, the
sleep hook, keyd, logind.conf), `pacman -Qe` (282 packages), and CLAUDE.md
(prose). If the SSD dies, CLAUDE.md is a recipe you follow by hand. After
migration it's one `nixos-rebuild` from a git clone.

**Config drift stops.** Two examples this survey turned up, both invisible on
Arch and both impossible in the Nix version:
- `systemd-networkd` *and* `NetworkManager` are both enabled. NM is doing the
  work; networkd is enabled by preset and doing nothing useful.
- `/etc/keyd/default.conf` binds `rightalt` to `layer(typst)`, but no `typst`
  layer is defined — `greek-typst.conf` is never included (the `#include` is
  commented out). That binding is currently dead. The flake defines the layer,
  so it will start working.

**Trying things stops being scary.** `nix shell nixpkgs#foo` gets you a
package for one shell session and leaves nothing behind. No `pacman -R`
dependency archaeology.

**Per-project toolchains.** You have Python 3.10/3.11/3.13, rustup, node, R,
kubectl, and TeX Live installed globally. `nix develop` / direnv gives each
project exactly its own versions without a global install.

### What you lose — read this before committing

- **The AUR.** This is the big one, and for your system it's a real cost: ~100
  of your packages are AUR, including your launcher (`fsel-bin`), your shell
  (`dms-shell-git`), and your compositor (`mangowm-git`). nixpkgs is large, but
  it is not the AUR. See §5.
- **Time.** Expect a couple of evenings to a working desktop, and a few weeks
  of "oh, that too" before it's genuinely finished.
- **Nix the language.** It's small but genuinely strange, and the error
  messages are poor. Budget frustration.
- **Anything expecting FHS.** Downloaded binaries, `pip install --user`
  wheels with compiled extensions, and AppImages need wrapping. You do a lot
  of this — Cursor, PyCharm, RStudio, CurseForge, SideQuest.
- **Disk.** `/nix/store` with 30 days of generations will use 40–80 GiB. You
  have 149 GiB free, so it fits, but it's not nothing.

**Honest recommendation:** your setup is unusually deep in AUR territory for a
NixOS migration. It's very doable, but do §2 (side-by-side install) rather
than a clean wipe. You want to be able to reboot into Arch while you sort out
`fsel` and `mango`.

---

## 2. The install plan: side-by-side, not a wipe

Your disk:

```
nvme0n1p1  vfat   1 GiB   ESP        -> /boot
nvme0n1p2  btrfs  475 GiB            -> subvols @ @home @pkg @log @swap
                                        321 GiB used, 149 GiB free
```

You do **not** need to repartition. NixOS installs into new subvolumes on the
same btrfs filesystem, shares the ESP, and reuses `@home`. Arch stays bootable
the whole time.

### Step 0 — before you touch anything

```bash
# Back up. Non-negotiable. You already have restic installed.
restic -r /path/to/external backup /home/henry

# Snapshot the current state of the system
pacman -Qe > ~/arch-packages-explicit.txt
pacman -Qm > ~/arch-packages-aur.txt
sudo cp -a /etc/tlp.conf /etc/keyd /etc/systemd/system-sleep ~/etc-backup/

# Put ~/.config under git — the flake's dotfiles depend on it (see
# modules/home/dotfiles.nix). This directory is NOT currently a git repo.
cd ~/.config && git init && git add -A && git commit -m "pre-nixos snapshot"
```

### Step 0b — the backup, sized properly

**`@home` is reused by the install, so this is insurance against a mistake,
not a data migration.** The realistic threat is a mistyped
`btrfs subvolume delete` or formatting the wrong partition — not the install
working as designed.

`/home/henry` is 236 GB, but only **~34 GB** cannot be recreated. Run:

```bash
./backup-before-migration.sh --dry-run /path/to/drive   # see what it'd take
./backup-before-migration.sh /run/media/henry/MyDrive/backup
```

The script refuses to write to the same physical disk as `/home`, because a
copy on `nvme0n1` dies with the original in every scenario that matters.

**Backed up (~34 GB):** `Nextcloud`, `Documents`, `Pictures`, `vaults`,
`Android`, `R`, `code`, `Projects`, `.ssh`, `.gnupg`,
`.local/share/keyrings`, `.thunderbird`, and the browser/Obsidian profiles
under `.config`.

**Skipped (~200 GB):** Steam (30G), Trash (20G — just empty it), `winboat`
(39G VM disk), `.cache` (26G), containers (7G), PrismLauncher (6.9G), Hytale
flatpak (8G), `Games` (20G), `.wine` (3.6G), `nvim.bak.*` (1.3G).

Source trees shrink from 9.1 GB to 448 MB once `node_modules`, `target`,
`.venv` and friends are excluded.

#### Three things this survey turned up

1. **`~/Nextcloud` is not syncing.** No sync config exists and the client is
   inactive. Those 22 GB are local-only despite the folder name — do not
   assume the server has a copy. This is the single biggest risk in your
   current setup, migration or not.
2. **Four git repos have unpushed work:** `code/paraphrase-detector`
   (6 commits ahead), `Projects/homelab` (9 dirty), `Projects/aur-malware-check`
   (2 dirty), `Projects/Azure-in-bullet-points` (5 dirty). Push these; it's
   faster than restoring them.
3. **`.local/share/Trash` is 20 GB.** Empty it and reclaim the space before
   you do anything else.

#### Also take a btrfs snapshot

Instant, free, and it protects against the actual failure mode (a bad
subvolume command during Step 2). It does *not* replace the off-disk backup:

```bash
sudo btrfs subvolume snapshot -r /home /home/.snapshot-pre-nixos
```

Delete it after you're settled: `sudo btrfs subvolume delete /home/.snapshot-pre-nixos`

#### Store the restic password off-machine

A restic repo whose password only exists on the laptop you're reinstalling is
not a backup. Put it in Bitwarden (which you have) or on paper.

### Step 1 — try Nix on Arch first (zero risk, do this today)

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
# then, in a new shell:
cd ~/.config/nixos && ./verify-packages.sh
```

This tells you exactly which of the ~200 package names in this flake resolve
and which don't, *before* you've reinstalled anything. It is the single
highest-value step in this document.

### Step 2 — create the NixOS subvolumes

From a NixOS live USB (or from Arch — btrfs doesn't care):

```bash
sudo mount /dev/nvme0n1p2 /mnt
sudo btrfs subvolume create /mnt/@nixos
sudo btrfs subvolume create /mnt/@nix
sudo umount /mnt

# Mount the new layout for the installer
sudo mount -o subvol=@nixos,compress=zstd:3,ssd,discard=async /dev/nvme0n1p2 /mnt
sudo mkdir -p /mnt/{nix,home,boot,var/log}
sudo mount -o subvol=@nix,compress=zstd:3,noatime      /dev/nvme0n1p2 /mnt/nix
sudo mount -o subvol=@home,compress=zstd:3             /dev/nvme0n1p2 /mnt/home
sudo mount -o subvol=@log,compress=zstd:3              /dev/nvme0n1p2 /mnt/var/log
sudo mount /dev/nvme0n1p1 /mnt/boot
```

### Step 3 — install

```bash
sudo mkdir -p /mnt/etc/nixos
sudo cp -r /mnt/home/henry/.config/nixos/* /mnt/etc/nixos/   # or clone from git

# Sanity-check the generated hardware config against the committed one
sudo nixos-generate-config --root /mnt --show-hardware-config

sudo nixos-install --flake /mnt/etc/nixos#thinkpad
```

systemd-boot will pick up Arch's existing entries in `/boot/loader/entries/`
automatically, so the boot menu offers both.

### Step 4 — first boot

Log in on a TTY first (`Ctrl+Alt+F2`) rather than trusting greetd on attempt
one. Then:

```bash
sudo nixos-rebuild switch --flake ~/.config/nixos#thinkpad
```

### Rolling back

- **A bad rebuild:** pick the previous generation in the boot menu, or
  `sudo nixos-rebuild switch --rollback`.
- **Giving up entirely:** boot the Arch entry. It's untouched. Delete `@nixos`
  and `@nix` to reclaim the space.

---

## 3. What this flake covers

```
~/.config/nixos/
├── flake.nix                       inputs + the `thinkpad` system
├── hosts/thinkpad/
│   ├── default.nix                 user, hostname, stateVersion
│   └── hardware-configuration.nix  real UUIDs from your fstab
├── modules/system/
│   ├── boot.nix          systemd-boot (capped at 6 gens — 1 GiB ESP!), snapper
│   ├── locale.nix        en_GB, Europe/Dublin, uk/gb keymap, keyd rules
│   ├── networking.nix    NM, resolved, avahi, firewall, WiFi resume fix, tor
│   ├── audio.nix         PipeWire stack, mic-mute LED service, swayosd
│   ├── desktop.nix       mango, greetd/tuigreet, portals, theming, thunar, flatpak
│   ├── fonts.nix         Nerd Fonts, Noto, IBM Plex, fontconfig defaults
│   ├── power.nix         TLP (incl. WiFi powersave off), zram, lid, corectrl
│   ├── printing.nix      CUPS, Brother MFC-L3740CDW notes, SANE
│   ├── virtualisation.nix podman, libvirt/qemu, steam, gamescope, gamemode
│   └── nix-settings.nix  flakes, GC, substituters, unfree
├── modules/home/
│   ├── default.nix       XDG, mimeapps (your full default-app table)
│   ├── packages.nix      ~185 packages, + an explicit NOT-MIGRATED list
│   ├── shell.nix         zsh (ZDOTDIR=~/.config/zsh), fish, aliases, PATH
│   ├── dotfiles.nix      out-of-store symlinks for ~/.config subdirs
│   └── theme.nix         GTK/Qt Gruvbox Dark, cursor
├── pkgs/default.nix      overlay: fsel bump, brother driver, curseforge
└── verify-packages.sh    parse -> evaluate closure -> size the build
```

**System state translated out of `/etc`:**

| Arch | NixOS |
|---|---|
| `/etc/tlp.conf` | `modules/system/power.nix` |
| `/etc/systemd/system-sleep/wifi-resume.sh` | `systemd.services.wifi-resume` |
| `/etc/keyd/*.conf` | `services.keyd.keyboards.default.extraConfig` |
| `/etc/locale.conf`, `/etc/vconsole.conf` | `modules/system/locale.nix` |
| `/etc/fstab` | `hardware-configuration.nix` |
| `/etc/systemd/zram-generator.conf` | `zramSwap` |
| `~/.scripts/toggle_lid_action.sh` | `services.logind.settings` (rebuild to change) |
| `~/.config/mimeapps.list` | `xdg.mimeApps` |

---

## 4. Deliberate design decisions

**Dotfiles stay editable.** `modules/home/dotfiles.nix` uses
`mkOutOfStoreSymlink`, so `~/.config/mango`, `~/.config/nvim` etc. remain real,
writable directories rather than read-only store paths. This is a trade-off:
you lose reproducibility of the *contents* (you must clone `~/.config`
separately) but you keep the ability to tweak your compositor without a
rebuild, and — critically — your Mangowm mode scripts keep working. Those
scripts symlink `active-theme.conf` into place and `jq`-patch Equibop's
`settings.json` at runtime; both would fail with EACCES against a store path.

Convert configs to native home-manager modules one at a time, later, if ever.

**ESP generation limit.** Your `/boot` is 1 GiB and shared with Arch. NixOS
writes ~120 MiB per generation. `configurationLimit = 6` keeps this from
filling the partition and wedging `nixos-rebuild`. This is the most common way
a NixOS laptop breaks, and it's silent until it isn't.

**Swapfile dropped.** You currently run zram *and* a btrfs swapfile in
`@swap`. With 14 GiB of RAM, zram at 50% is enough. Re-add the swapfile in
`hardware-configuration.nix` only if you want hibernation (which also needs a
`resume_offset` kernel param — btrfs swapfiles make this fiddly).

**networkd disabled.** See §1.

---

## 5. The AUR problem — your actual work queue

This is where the migration will be won or lost. Ordered by how much it
matters to a working desktop.

### Tier 1 — you cannot log in without these

> **RESOLVED — see §6b.** Every Tier-1 package turned out to be in nixpkgs
> (`mango`, `fsel`, `walker`, `elephant`), and DMS/quickshell/dgop were
> dropped by choice (§6c). This section is kept only as a record of what the
> risk looked like before verification. Nothing here is outstanding.

| Package | Outcome |
|---|---|
| `mangowm-git` | `mango` 0.15.5 in nixpkgs |
| `fsel-bin` | `fsel` 3.1.0 in nixpkgs (overlay bumps to 3.5.2) |
| `dms-shell-git` + `greetd-dms-greeter-git` | dropped; greeter is `tuigreet` |
| `quickshell-git` | dropped with DMS |

### Tier 2 — visible daily, but you can live a week without them

Also all resolved: `walker`, `elephant`, `equibop`, `cloudflare-warp` and
`spicetify-cli` are in nixpkgs; `zen-browser` has a flake input. Only
`betterbird` (use `thunderbird`) and `piavpn` remain genuinely absent.

### Tier 3 — nice to have, deal with them whenever

Everything else in the NOT-MIGRATED list at the bottom of
`modules/home/packages.nix`: `pipemixer`, `wayfreeze`, `dsearch`, `weathr`,
`awww`, `quickmedia`, `qrookie`, `sidequest`, `winboat`, `haroopad`, `mdview`,
`silverbullet`, `r-quick-share`, `curseforge`, `pdf-compress`.

### The three escape hatches, in order of preference

1. **Check nixpkgs properly.** `nix search nixpkgs <keyword>` — names differ
   (`github-cli`→`gh`, `swaync`→`swaynotificationcenter`, `adw-gtk-theme`→
   `adw-gtk3`). ~180 of your 282 map cleanly.
2. **Package it.** For a Go/Rust binary release this is ~10 lines; see the
   templates in `pkgs/default.nix`. AppImages are ~6 lines with
   `appimageTools.wrapType2`.
3. **`distrobox` an Arch container.** Already in the package list. For the
   long tail — CurseForge, SideQuest, a proprietary VPN client — running them
   in an Arch box with AUR access is a completely legitimate answer, not a
   failure. Don't spend a weekend packaging `qrookie`.

---

## 6a. Verified on 2026-07-27

Second pass, checked against the live filesystem rather than assumed:

- **All 28 dotfile paths** referenced by `modules/home/dotfiles.nix` exist. No
  broken symlinks on first rebuild.
- **`~/.hidden`** matches the flake's declaration exactly.
- **Scripts have no `.sh` extension.** CLAUDE.md claimed they did, and the
  flake had inherited the error — `micmute-led.sh` in the systemd unit and
  `clean_tmp.sh` in the aliases would both have silently failed. Fixed in
  `audio.nix` and `shell.nix`; CLAUDE.md corrected too. Also found an
  undocumented seventh script, `texpdf`.
- **Bluetooth was entirely missing** from the flake despite `bluetooth.service`
  being enabled on Arch and the Waybar menu calling `bluetoothctl` 19 times.
  Added `hardware.bluetooth` + `services.blueman`.
- **Four binaries your mode scripts depend on were unpackaged**, found by
  grepping `mango/scripts` and `mango/waybar` for invocations rather than
  guessing: `notify-send` (libnotify — **38 call sites**), `gsettings` (glib —
  `gtk-apply.sh` is entirely built on it), `jq`, and `qdbus`
  (`libsForQt5.qttools`). All added to `desktop.nix`.
- **A theming conflict** between home-manager's `gtk` module and
  `gtk-apply.sh`, which fight over the same dconf keys. Documented at the top
  of `theme.nix` with a recommended resolution — this would have shown up as
  "my mode switches don't change the GTK theme any more" and been genuinely
  annoying to diagnose.
- **Real derivations written** for `fsel` (your Tier-1 launcher),
  `brother-mfc-l3740cdw`, `curseforge` and `silverbullet` — reconstructed from
  the PKGBUILDs cached in `~/.cache/paru/clone/`, so the URLs and hashes are
  the actual ones your system installed from. `pkgs/default.nix` no longer
  contains placeholder hashes. 44 PKGBUILDs are cached there; mine the rest
  the same way.

Still unverified: everything requiring the Nix daemon (below).

## 6b. VERIFIED — the flake builds (2026-07-27)

Nix is installed on the Arch box, and the full system closure now evaluates
cleanly with **zero errors and zero deprecation warnings**:

```
/nix/store/9w9pg4gjfp2bcdpiixv03isgbyi1q4a6-nixos-system-arch-26.11.20260726.624af66.drv
```

`nix build --dry-run` reports **842 derivations to build, 5622 paths to fetch
(13.9 GiB download, 37.4 GiB unpacked)**. Everything resolves; nothing needs
a source build beyond small wrappers. Re-check any time with
`./verify-packages.sh`.

### The AUR problem was much smaller than feared

§5 below was written before I could query nixpkgs, and it is now too
pessimistic. **Every Tier-1 blocker is already in nixpkgs:**

| Feared missing | Actually in nixpkgs |
|---|---|
| `mangowm-git` | `mango` 0.15.5 |
| `fsel-bin` | `fsel` 3.1.0 |
| `walker-bin` + 20× `elephant-*` | `walker` 2.17.0, `elephant` 2.22.0 |
| `dms-shell-git` | `dms-shell` 1.5.2 — *packaged, but dropped by choice (§6c)* |
| `quickshell-git` | `quickshell` 0.3.0 — *dropped with DMS* |
| `dgop` | `dgop` 0.2.3 — *dropped with DMS* |

Also present and unexpected: `dsearch`, `weathr`, `sidequest`, `winboat`,
`valent`, `silverbullet`, `proton-authenticator`, `cursor-cli`,
`github-copilot-cli`, `cloudflare-warp`, `equibop`, `itch`, `rstudio`,
`spicetify-cli`, `wayfreeze`, `matugen`.

Consequence: **four flake inputs were deleted** (DankMaterialShell,
quickshell, walker, elephant) and the custom `fsel` and `silverbullet`
derivations were dropped. Only `zen-browser` and `claude-desktop` remain as
external flakes.

### Genuinely absent from nixpkgs

`piavpn-bin`, `freedownloadmanager`, `betterbird` (use `thunderbird`),
`torbrowser-launcher` (use `tor-browser`), `quickmedia`, `pipemixer`,
`r-quick-share`, `haroopad`, `mdview`, `pdf-compress`, `qrookie-vrp`,
`ttf-phosphor-icons`, `nerd-fonts-sf-mono`.

### Name corrections found

`rofi-wayland`→`rofi` (the wayland fork merged upstream at 2.0.0) ·
`qt6ct`→`kdePackages.qt6ct` · `noto-fonts-emoji`→`noto-fonts-color-emoji` ·
`charis-sil`→`charis` · `jetbrains.pycharm-professional`→`jetbrains.pycharm` ·
`swww`→`awww` (nixpkgs renamed it to the fork you already run) ·
`wineWowPackages`→`wineWow64Packages` · `xfce.thunar-*`→ top-level.

### Real errors the evaluation caught

1. `virtualisation.libvirtd.qemu.ovmf` — submodule removed from NixOS.
2. `vaapiVdpau` — renamed to `libva-vdpau-driver` (I had listed both).
3. **`logseq` needs Electron 39.8.10, which nixpkgs marks insecure.** Now
   opted into explicitly in `nix-settings.nix`. Arch shipped you the same
   vulnerable binary silently — this isn't new risk, just newly visible.
4. **`claude-desktop` cannot use `inputs.nixpkgs.follows`** — it references
   the removed `pkgs.nodePackages` and only evaluates against its own pinned
   nixpkgs. This one took bisecting to find; the error surfaced from
   home-manager's man-db module, nowhere near the actual cause.
5. Nine home-manager/NixOS option renames (`programs.git.userName` →
   `programs.git.settings.user.name`, `programs.corectrl.gpuOverclock` →
   `hardware.amdgpu.overdrive`, relative `dotDir`, and others).

### One sizing decision

`texliveFull` was my over-approximation of your four Arch TeX collections.
Replaced with an explicit `texlive.withPackages` set matching
`texlive-{latex,latexextra,xetex,fontsrecommended}` — saves 2.2 GiB of
download and ~2,900 store paths.

## 6c. DankMaterialShell is deliberately dropped

You'd been intending to remove DMS, so the migration is the natural point to
do it — a package you never install can't rot.

**Removed from the flake:** `dms-shell`, `dgop` (its stats backend),
`quickshell` (its rendering engine), and the `~/.config/DankMaterialShell`
and `~/.config/quickshell` dotfile symlinks. The greeter was already
`tuigreet` rather than `greetd-dms-greeter`, so nothing there changes.

`quickshell` goes too because it had no other consumer: its only config is
`~/.config/quickshell/noctalia-shell`, and Noctalia isn't installed. Nothing
in `~/.config/mango` launches `qs` or `quickshell` directly — DMS spawned it
internally.

### Arch side — cleaned up 2026-07-27

`~/.config` is now a git repo (commit `51c18e1` is the pre-removal baseline,
`60b6e68` the removal), so all of this is recoverable with
`git checkout 51c18e1 -- <path>`.

**Deleted:** `mango/dms/`, `mango/scripts/modes/dms.sh`,
`DankMaterialShell/`, `danksearch/`, `quickshell/noctalia-shell/`,
`systemd/user/dms.service.d/`, and the dank/dms theme files for kitty, foot,
gtk-3.0, gtk-4.0, equibop, zed, qt5ct and qt6ct — 10,312 lines across 24
files.

**Edited:** `desktop-mode.sh` (`MODES=("tiling" "hud")`), `gtk-apply.sh`
(dropped its `dms` branch), and the `exec=pkill -x dms` lines in both
`tiling/` and `hud/autostart.conf`.

**Kept on purpose** — these looked like DMS leftovers but are live
dependencies of the remaining modes:

| Path | Why |
|---|---|
| `kitty/tabs.conf` | included by `kitty.conf` in *every* mode. Renamed from `dank-tabs.conf`; the include was updated to match. |
| `yazi/flavors/noctalia.yazi` | still the active yazi theme (`yazi/theme.toml` sets `dark = "noctalia"`). |
| `~/.local/share/color-schemes/DankMatugen.colors` | qt5ct's active `color_scheme_path`. Outside `~/.config`, so untouched — rename it yourself if the name bothers you, but update `qt5ct/qt5ct.conf` too. |

### A note on Noctalia

Considered as a DMS replacement and rejected. nixpkgs does carry it
(`noctalia` 5.0.0-beta.5, `noctalia-shell` 4.7.7, `noctalia-greeter` 1.0.0),
so it would have been easy to install — but `~/.config/quickshell/noctalia-shell`
turned out to be a **stale upstream source checkout** from January, not a
configuration, and there were no Noctalia settings anywhere on the system.
Adopting it would have meant theming a shell from scratch, not swapping one
in. Two modes it is.

## 6d. Original status note (superseded)

This section recorded what was unverified when the flake was first written —
before Nix was installed. All of it has since been checked: see §6a
(filesystem facts), §6b (nixpkgs + full closure evaluation) and §6c (DMS
removal). The flake now evaluates with zero errors and zero warnings, so the
caveats that lived here no longer apply.

Two things from the original note are worth keeping:

- `nixpkgs-fmt` is set as the formatter; `nixfmt-rfc-style` is the newer
  community default if you prefer it.
- `hardware-configuration.nix` is still written from your Arch `/etc/fstab`
  rather than generated by the installer. Diff it against
  `nixos-generate-config --root /mnt --show-hardware-config` before
  installing — the installer is the authority on kernel modules.

## 7. Remaining order of work

Phases 1 and 2 of the original plan are **done** — the flake evaluates and
every Tier-1 package resolves. What's left:

1. ~~Install Nix, verify packages~~ — done, see §6b.
2. ~~Resolve Tier 1 (`mango`, `fsel`)~~ — both in nixpkgs.
3. **Decide on the greeter.** `greetd-dms-greeter` is not packaged, so
   `desktop.nix` currently uses `tuigreet`. It's a TTY greeter, which is
   deliberately boring for a first boot. `regreet` and `gtkgreet` are both
   packaged if you want graphical.
4. **Transcribe your keyd `[typst]` layer** if you want it — `locale.nix` has
   the layer defined from `greek-typst.conf`, but check it matches your
   intent, since it was never actually active on Arch.
5. **Put `~/.config` in git and push it.** Still not done, and the flake's
   out-of-store dotfile symlinks depend on it.
6. `restic` backup.
7. Create `@nixos`/`@nix` subvolumes, `nixos-install --flake`, boot to a TTY.
8. Get the compositor up. Nothing else matters on day one.
9. Decide the `theme.nix` vs `gtk-apply.sh` ownership question (§6a) the first
   time a mode switch doesn't change your GTK theme.
10. Work the genuinely-absent list (§6b) down over the following weeks —
    `distrobox` with an Arch container is a legitimate answer for most of it.
11. Once you haven't booted Arch in a month: delete `@`, `@pkg`, `@swap`.

### A caution on 37.4 GiB

The closure is 37.4 GiB unpacked and you have 149 GiB free. That fits, but
with `nix.gc` keeping 30 days of generations you should expect real usage
around 60–80 GiB once you've rebuilt a few dozen times. Keep an eye on it for
the first month; `nix-collect-garbage --delete-older-than 7d` if it gets tight.
