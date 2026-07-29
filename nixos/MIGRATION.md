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
  have 110 GiB free (2026-07-29; it was 149 GiB when this was written), so it's
  a tighter fit than it looks.

**Honest recommendation:** your setup is unusually deep in AUR territory for a
NixOS migration. It's very doable, but do §2 (side-by-side install) rather
than a clean wipe. You want to be able to reboot into Arch while you sort out
`fsel` and `mango`.

---

## 2. The install plan: side-by-side, not a wipe

Your disk:

```
nvme0n1p1  vfat   1 GiB   ESP        -> /boot
nvme0n1p2  btrfs  475 GiB            -> subvols @ @home @pkg @log swap
                                        365 GiB used, 110 GiB free
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

`/home/henry` is 236 GB, but only **~6.8 GB** is both irreplaceable and not
already protected elsewhere. Run:

```bash
./backup-before-migration.sh --dry-run /path/to/drive   # see what it'd take
./backup-before-migration.sh /run/media/henry/MyDrive/backup
```

The script refuses to write to the same physical disk as `/home`, because a
copy on `nvme0n1` dies with the original in every scenario that matters.

> **Resolved 2026-07-29 — the script now uses `rsync`.** It previously built a
> **restic repository**, which no restore step in `MIGRATION-GUIDE.md` could
> read (Part 10 uses `cp -a "$B/..."`, and the drive holds a plain tree). Raw
> files won on the merits: the drive is local and offline, so a repository
> format buys encryption and dedup you do not need, at the cost of a password
> and a tool standing between you and your data mid-install. Re-running is
> incremental — refreshing a days-old backup moves only the delta.
>
> Pass the **tree** path, not the drive root:
>
> ```bash
> ./backup-before-migration.sh "/run/media/henry/Samsung 128G/backup-2026-07-28"
> ```
>
> There is no `--delete`. A file removed from `$HOME` stays in the backup,
> which is the right default for something whose whole purpose is protecting
> against a mistake.

**Backed up (~6.8 GB):** `Documents` (3.7G), `.config/zen` (853M), `Projects`
+ `code` (523M), `R` (424M), `.thunderbird` (411M), `Pictures` (395M),
`.config/chromium` (261M), `.config/obsidian` (174M), `vaults` (127M),
`.ssh`, `.gnupg`, `.local/share/keyrings`, `.scripts`, `.hidden`, and this
flake.

**Skipped (~227 GB):** Steam (30G), Trash (20G — just empty it), `winboat`
(39G VM disk), `.cache` (26G), containers (7G), PrismLauncher (6.9G), Hytale
flatpak (8G), `Games` (20G), `.wine` (3.6G), `nvim.bak.*` (1.3G), plus three
dropped 2026-07-28:

- **`Nextcloud` (22G)** — syncs to `nextcloud.henrydowd.dev`, and the sync
  journal confirms the 21.8 GB `ATM9NF_march26.zip` reached the server at
  full size. The replication-is-not-backup caveat below still applies and is
  accepted knowingly; server-side trash/versioning is the safety net now.
- **`Android` (4.8G)** — Android Studio build output and SDK/AVD state,
  regenerated on next build.
- **`.config/vivaldi` (283M)** — secondary browser, profile not wanted.

Source trees shrink from 9.1 GB to 523 MB once `node_modules`, `target`,
`.venv` and friends are excluded. They stay in the set despite every repo
having an origin remote — see the unpushed-work finding below.

#### Things this survey turned up

1. **`~/Nextcloud` IS syncing** — correcting an earlier note in this file that
   said otherwise. The client is configured against
   `https://nextcloud.henrydowd.dev` (account `henry`, folder
   `/home/henry/Nextcloud/` → `/`, `paused=false`), runs from
   `~/.config/autostart/Nextcloud.desktop`, and its journal and logs show
   active PROPFIND traffic. Dropped from the backup set on 2026-07-28 on that
   basis. Know the tradeoff you accepted: sync is replication, not backup — it
   propagates deletions to the server, so a local `rm` is not recoverable from
   the server unless its trash/versioning still holds the file.
2. **Five git repos hold work that exists only on this machine** (as of
   2026-07-28): `code/paraphrase-detector` (5 unpushed commits),
   ~~`Projects/homelab` (9 uncommitted) and `Projects/learning` (1)~~ — **all
   pushed 2026-07-29**, along with `code/paraphrase-detector`'s
   `backup/local-main-pre-sync-20260704` branch (4 commits, including the final
   thesis report), which went up as a branch rather than being merged into
   `main`. Nothing in `~/Projects` or `~/code` is now dirty or unpushed. The
   backup script re-checks this on every run rather than relying on this list
   staying accurate.

   Two of the original five are **deleted** (2026-07-29):
   `Projects/aur-malware-check` and `Projects/Azure-in-bullet-points`, both
   third-party clones. The Azure one carried ~4.3 MB of untracked work that was
   not upstream's — a LaTeX build (`AZ-900_Study_Notes.tex`, `diagrams.tex`), a
   `CLAUDE.md` describing it, the built PDF and a compiled `Complete.md` —
   discarded knowingly on the basis that the notes are re-clonable and the
   build easy to redo.

   **It is recoverable after all** — checked 2026-07-29. The 2026-07-28 sweep
   copied `~/Projects` wholesale, so
   `<backup>/Projects/Azure-in-bullet-points/` still holds the `.tex` sources,
   `diagrams.tex`, `CLAUDE.md`, the built PDF and the `build/` tree. The
   refresh step in `INSTALL.md` §1.2 is a plain `rsync` with no `--delete`, so
   it will not remove them; only re-running the backup script from scratch, or
   adding `--delete`, would.
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

> **Superseded — do not use the `cp -r` line below.** It predates the B1 fix
> (§8). Two things are wrong with it now: the flake is read from the clone at
> `~/src/arch-config/nixos`, not `~/.config/nixos`; and `~/.config/nixos` can
> contain `system-state/root-only`, so that copy would deposit 38 cleartext
> WiFi PSKs and SSH host keys onto the new system's `/etc/nixos`. Install from
> the clone instead — see §8 step 9 and `MIGRATION-GUIDE.md`:
>
> ```bash
> sudo nixos-install --flake /mnt/home/henry/src/arch-config/nixos#thinkpad
> ```

```bash
# Sanity-check the generated hardware config against the committed one
sudo nixos-generate-config --root /mnt --show-hardware-config
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
`swap` (note: no `@` prefix — unlike the other four subvolumes, per
`/etc/fstab`). With 14 GiB of RAM, zram at 50% is enough. Re-add the swapfile in
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
5. ~~**Put `~/.config` in git and push it.**~~ Done — pushed to
   `git.henrydowd.dev/henry/arch-config`. What remains is cloning it to
   `~/src/arch-config`, which is where the flake now expects it (§8, B1).
6. `restic` backup.
7. Create `@nixos`/`@nix` subvolumes, `nixos-install --flake`, boot to a TTY.
8. Get the compositor up. Nothing else matters on day one.
9. ~~Decide the `theme.nix` vs `gtk-apply.sh` ownership question (§6a)~~ —
   **decided 2026-07-28: the mode scripts own it.** The `gtk` block is gone
   from `theme.nix`; the theme *packages*, the Qt platform theme and the cursor
   stay declared in Nix. See §7c.
10. Work the genuinely-absent list (§6b) down over the following weeks —
    `distrobox` with an Arch container is a legitimate answer for most of it.
11. Once you haven't booted Arch in a month: delete `@`, `@pkg`, `swap`.

## 7b. Gaps found in the 2026-07-28 sweep

A backup protects data. These are things the **flake** does not reproduce, so
they are lost on first boot even though the files survive. Ordered by how
badly they bite.

### Will visibly break

1. ~~**`mango-session.target` is not reproduced.**~~ **FIXED** — declared as
   `systemd.user.targets.mango-session` in `modules/home/default.nix`.
   `mango/universal/autostart.conf` line 2 runs
   `systemctl --user start mango-session.target`; the unit lived only in
   `~/.config/systemd/user/`, which is not on the dotfiles allowlist, so the
   exec-once failed silently on every boot.
2. ~~**Five `dotfiles.nix` symlinks point at paths not in git**~~ **FIXED** —
   the `mpv`, `gpu-screen-recorder`, `gh`, `glab-cli` and `opencode` links are
   removed (§8, B3). Four of the five are credential directories the
   `.gitignore` allowlist excludes on purpose, so tracking them was never the
   right answer; they are restored from the backup drive instead. `mpv` is
   allowlisted but empty, so git carries nothing.
3. ~~**`~/.config/environment.d/` is not referenced anywhere in the flake.**~~
   **FIXED** — reproduced as `systemd.user.sessionVariables` in
   `modules/home/default.nix`, which writes
   `~/.config/environment.d/10-home-manager.conf`.

   It had to be that option and not `home.sessionVariables`: the latter writes
   `hm-session-vars.sh`, which interactive shells source and systemd user units
   do not — and the entire reason the file exists is
   `xdg-desktop-portal-gtk`, which *is* a user unit and ignores `settings.ini`
   without `GTK_THEME`.

   The value is `Gruvbox-Yellow-Dark`, copied verbatim. `theme.nix` used to
   disagree with it; that is resolved — the `gtk` block is gone and
   `pkgs/default.nix` now builds the yellow variant, which stock nixpkgs does
   not. See §7c.

### Silently absent

4. ~~**`rclone-nextcloud.service` is not reproduced**~~ **WRONG UNIT — see
   §7c.** `rclone-nextcloud.service` exists on disk but is *not enabled*. The
   enabled unit is the template instance `rclone@ProtonDrive.service`, which
   the sweep missed entirely. That one is now ported as
   `systemd.user.services.rclone-protondrive`. Its config,
   `~/.config/rclone/rclone.conf`, holds the remote credentials and was in
   neither git nor the backup until 2026-07-28.
5. ~~**`claude-message.service` / `.timer` not reproduced.**~~ **DROPPED on
   purpose** (2026-07-28). The timer was enabled and fired daily at 08:45, but
   its `ExecStart` pointed at `~/.local/bin/claude-scheduler` while the script
   on disk is `claude_scheduler` — a one-character mismatch that had it failing
   silently since June. Decision was to drop it rather than repair it; the
   timer is now disabled on Arch and the script is left in place.
6. ~~**Three installed flatpaks are not declared**~~ **DROPPED on purpose**
   (2026-07-28). `com.hypixel.HytaleLauncher`, `com.stremio.Stremio` and
   `io.github.wivrn.wivrn` are not wanted on the new system, so
   `services.flatpak.enable` is now off too and the daemon is not installed.
7. **38 saved NetworkManager connections**, including an 802.1x/eduroam
   profile, exist only in `/etc/NetworkManager/system-connections`. Capture
   them with `capture-root-state.sh` on the backup drive, or re-enter by hand.
8. **Bluetooth pairings** (`/var/lib/bluetooth`) — same situation.
9. Not referenced by the flake, each minor on its own: `starship.toml`,
   `trashrc`, `user-dirs.dirs`/`.locale`, `QtProject.conf`, `Trolltech.conf`,
   `gtkrc`/`gtkrc-2.0` (GTK2 theming), `qt5ct`/`qt6ct` (Qt theming).

### Root cause worth fixing once (units)

The sweep read `~/.config/systemd/user/*.service` and assumed every file there
was live. It isn't — the directory holds units that are enabled, units that
were superseded, and units that were never enabled at all. **Check
`*.target.wants/` before porting anything**, because that is the only place
that records what actually runs:

```bash
ls ~/.config/systemd/user/{default,timers,multi-user}.target.wants/
```

### Root cause worth fixing once (files)

`~/.config/.gitignore` is an **allowlist**. Anything not explicitly un-ignored
is invisible to git *and* was invisible to a backup that copied only tracked
paths. That is how `rclone.conf`, `gh/hosts.yml`, `glab-cli/config.yml`,
`rbw/config.json`, `autostart/`, `dconf/` and the user systemd units all fell
through both nets simultaneously. When adding a tool that stores config in
`~/.config`, add a `!/toolname/` line at the same time.

## 7c. What the sweep got wrong (checked 2026-07-28, second pass)

§7b was written from the *contents* of `~/.config/systemd/user/`. Checking the
`*.target.wants/` symlinks instead — the only record of what is actually
enabled — changes three of its conclusions.

**Enabled on Arch, and what each needs:**

| Unit | Status |
|---|---|
| `rclone@ProtonDrive.service` | **Missed by the sweep.** Now ported. |
| `micmute-led.service` | Already ported (`modules/system/audio.nix`). |
| `gpu-screen-recorder-ui.service` | **Missed by the sweep.** Dropped — see below. |
| `claude-message.timer` | Dropped on purpose; disabled on Arch. |

**Listed as gaps but needing no work:**

- **`elephant.service`** — not enabled, and it would be redundant anyway:
  `mango/{tiling,hud}/autostart.conf` line 8 already starts it with
  `exec=pgrep -x elephant || elephant`. Nothing to port.
- **`rclone-nextcloud.service`** — not enabled. `~/Nextcloud` is handled by the
  desktop sync client (`services.nextcloud-client`), not a FUSE mount, which
  matches the §2 finding that the client is running and syncing.

**`gpu-screen-recorder-ui`** is a package-provided unit
(`/usr/lib/systemd/user/`), not a hand-written one. nixpkgs has
`gpu-screen-recorder` and `gpu-screen-recorder-gtk` but **no**
`gpu-screen-recorder-ui`, so the always-running overlay/hotkey daemon has no
equivalent. Decision: drop it, keep the plain CLI already in `packages.nix`,
and bind a key in mango if you want a capture shortcut. Left enabled on Arch.

### Two owners on one path — a collision class worth checking for

`verify-packages.sh` evaluates the closure, which catches bad option names and
unresolvable packages. It does **not** catch two home-manager entries claiming
overlapping paths, because that only fails when the home-files derivation is
built. Two such collisions existed:

- **`gtk`** — `dotfiles.nix` links `~/.config/gtk-3.0` out-of-store while the
  `gtk` module wanted to write `~/.config/gtk-3.0/settings.ini` inside it.
  Removed as a side effect of settling the ownership question.
- **`fish`** — `dotfiles.nix` linked all of `~/.config/fish` while
  `programs.fish.enable` writes `~/.config/fish/config.fish`. Fish is now
  dropped entirely (2026-07-28): zsh is and always was the login shell per
  `/etc/passwd`, so fish was only ever secondary.

`zsh` avoids the trap by linking `zsh/conf.d`, the subdirectory, rather than
`zsh` — home-manager owns `.zshrc`. **That is the pattern to follow**: when
home-manager owns any file inside a directory, link the subdirectory, never the
parent.

Building the home-files derivation to check is slow (it drags in texlive and
logseq via shell completions). This is quick and catches the same thing:

```bash
nix eval --impure --expr '
let
  f = builtins.getFlake "path:/home/henry/src/arch-config/nixos";
  hm = f.nixosConfigurations.thinkpad.config.home-manager.users.henry;
  names = builtins.attrNames hm.home.file;
in builtins.concatMap (a: builtins.concatMap (b:
     if a != b && builtins.substring 0 (builtins.stringLength a + 1) b == "${a}/"
     then [ "${a} << ${b}" ] else []) names) names'
# want: [ ]
```

### The GTK theme would have fallen back to Adwaita

Found while settling the ownership question. Your GTK theme is
`Gruvbox-Yellow-Dark`, named in seven places: `gtk-{3,4}.0/settings.ini`, both
`settings-tiling.ini` files, `xsettingsd.conf`, `environment.d/gtk.conf`, and
`mango/scripts/system/gtk-apply.sh` line 9.

The stock nixpkgs `gruvbox-gtk-theme` builds **only** `Gruvbox-Dark` and
`Gruvbox-Light` — verified by building it and listing `share/themes`. On Arch
the yellow variant comes from the AUR build, which passes `-t yellow` to
`install.sh`. Without an override, every GTK app on the new system would have
asked for a theme that does not exist and silently fallen back to Adwaita.

`pkgs/default.nix` now overrides the package with
`themeVariants = [ "yellow" ]; colorVariants = [ "dark" ]`, which produces
`Gruvbox-Yellow-Dark` — confirmed by building the override and listing the
output. The upstream derivation takes those flags as arguments, so this is a
plain override, not a fork.

The same check turned up a smaller mismatch: `theme.nix` declared the cursor as
`Adwaita` while `gtk-3.0/settings.ini` asks for `Capitaine Cursors (Gruvbox)`
at size 24. With GTK ownership handed to the scripts, `settings.ini` wins for
GTK apps, so the Nix declaration would have produced a split — Capitaine in GTK
apps, Adwaita for Wayland cursors. `home.pointerCursor` now names the same
theme, from `capitaine-cursors-themed`, which provides it under exactly that
name.

## 8. Install walkthrough, with blockers verified (2026-07-28)

Every prerequisite below was checked against the live machine on 2026-07-28,
not assumed. Two blockers were found; **B1 must be fixed before you install**.

### Verified clear

| Check | Result |
|---|---|
| Flake evaluates | `verify-packages.sh` passes all 3 stages, **no deprecation warnings**. Re-confirmed 2026-07-28 after the B3/uid/lock fixes |
| Inputs pinned | `flake.lock` committed 2026-07-28 — nixpkgs `624af665` (26.11.20260726) |
| Build size | 842 derivations, 5622 paths, 13.8 GiB download / 37.1 GiB unpacked |
| Free space | **110 GiB** on `nvme0n1p2` as of 2026-07-29 — fits, with ~73 GiB spare |
| ESP capacity | 1022 MiB, 62 MiB used by Arch. `configurationLimit = 6` → ~450–720 MiB. Fits |
| Partition UUIDs | `hardware-configuration.nix` matches live `blkid` exactly (`32D9-7457`, `3c2d15a1-…`) |
| Greeter | decided — `tuigreet`, a TTY greeter that cannot lock you out |
| Nix on host | 2.35.1, flakes enabled in `~/.config/nix/nix.conf` |
| Config repo | pushed to `git.henrydowd.dev/henry/arch-config`, HEAD `1f7d427` |

### B1 — BLOCKER: `dotfiles.nix` symlinks point at themselves

`dotfiles.nix` sets `dots = "${config.home.homeDirectory}/.config"` and then
does `xdg.configFile."mango".source = link "mango"`. But `xdg.configFile.<name>`
*writes to* `~/.config/<name>`. So the target and the source are the same path.

Verified by evaluating and building the real derivation:

```
target: .config/mango
source: /nix/store/…-hm_mango
$ readlink /nix/store/…-hm_mango
/home/henry/.config/mango
```

`~/.config/mango` → store path → `~/.config/mango`. A loop. This affects **all
26 entries**, not just mango.

What happens if you install as-is — and it is worse than an error, because
`flake.nix` line 73 already sets `backupFileExtension = "hm-bak"`:

1. home-manager renames `~/.config/mango` → `~/.config/mango.hm-bak`
2. it creates `~/.config/mango` → store path → `/home/henry/.config/mango`
3. that target no longer exists, because step 1 moved it

The result is a dangling symlink and a compositor with no config, **with no
error printed**. Had `backupFileExtension` been unset, activation would at
least have aborted loudly with "existing file is in the way".

**Fix.** The repo must live somewhere other than `~/.config`. Clone it to
`~/src/arch-config`, then in `dotfiles.nix`:

```nix
dots = "${config.home.homeDirectory}/src/arch-config";
```

`~/.config/mango` → `~/src/arch-config/mango`. Everything else in the file
stays as written. Do this **before** the first `nixos-rebuild`, and re-run
`verify-packages.sh` after.

### B2 — `mango-session.target` is not declared

`mango/universal/autostart.conf` line 2 runs
`systemctl --user start mango-session.target`. That unit exists only in
`~/.config/systemd/user/`, which is neither allowlisted in git nor declared in
the flake. On first boot the exec-once fails silently. See §7b.

### B3 — the entries the B1 fix missed (2026-07-28 audit)

B1 was fixed by repointing `dots`, which corrected the 26 entries built with
`link`. Three did not go through `link` and so stayed broken:

- **`home.file.".scripts"` was still self-referential.** It read
  `mkOutOfStoreSymlink "${config.home.homeDirectory}/.scripts"`, and
  `home.file.".scripts"` *writes to* `~/.scripts` — the same loop B1
  described, in the one entry the B1 diff did not touch. Activation would have
  produced `~/.scripts.hm-bak` plus a dangling `~/.scripts`, taking out
  `cleantmp`, `lidaction`, `keyd-application-mapper` and the ExecStart of
  `micmute-led.service` (`%h/.scripts/micmute-led`) — silently, as before.

  Removed rather than repointed: `~/.scripts` is in no git repo at all, it
  survives because `@home` is reused, and `home.sessionPath` already carries
  it. Moving those scripts into this repo is the way to make it reproducible.

- **The four credential directories** (`gh`, `glab-cli`,
  `gpu-screen-recorder`, `opencode`) were §7b.2's known dangling links, and
  linking them was worse than dangling: `INSTALL.md` §5.1 restores them with
  `cp -a "$B/.config/gh" ~/.config/`, and `cp -a` onto a dangling symlink
  writes through to the *resolved* path — so the restore step would have
  deposited `hosts.yml`, `restore_token` and friends inside the git clone at
  `~/src/arch-config/`. Links removed.

- **`mpv`** is un-ignored by the allowlist but the directory is empty, so git
  carries nothing and the clone has no `mpv/`. Link removed.

### Hardening — done in the same pass

- **Pin the uid *and* the primary group.** `uid` was unset, and pinning it
  alone (which this section previously advised) would not have been enough:
  `isNormalUser` defaults the primary group to `users` (gid 100), while every
  file under `/home/henry` is gid 1000 (`henry`) and `@home` stays mounted by
  Arch throughout the side-by-side period. Verified by evaluating the closure:
  `uid = null; group = "users"; hasHenryGroup = false`. Now pinned to
  `uid = 1000` with `users.groups.henry.gid = 1000`.
- **Lock the flake.** `flake.lock` is committed, pinning nixpkgs to
  `624af665` (26.11.20260726). Before this, every build floated and the
  "verified on 2026-07-27" result described whatever nixpkgs happened to be
  current that day.
- **The `rebuild`/`update` aliases pointed at `~/.config/nixos`**, which the
  B1 fix made wrong — the flake now lives in the clone, and `dotfiles.nix`
  never linked `nixos/`, so that path does not exist on the installed system.
  Repointed at `~/src/arch-config/nixos`.

### Order of operations

1. **B1** — the flake side is fixed; what remains is to actually
   `git clone` the repo to `~/src/arch-config` and re-run
   `./verify-packages.sh` from there.
2. ~~Fix **B2** and pin `uid`~~ — done, along with **B3** and the group pin.
3. ~~`nix flake lock`~~ — done, `flake.lock` is committed.
4. Capture root-only state: run `capture-root-state.sh` **from the backup
   drive** (WiFi credentials for 38 networks incl. eduroam, Bluetooth
   pairings, CUPS). A copy now lives at `nixos/capture-root-state.sh` so it
   is no longer a single file on removable media — but run the drive's copy,
   because the script writes its output next to itself and the repo is the
   wrong place for cleartext PSKs.
5. ~~Commit or discard the dirty repos~~ — **done 2026-07-29.** `homelab` and
   `learning` pushed; `paraphrase-detector`'s backup branch pushed;
   `aur-malware-check` and `Azure-in-bullet-points` deleted. See §2.
6. ~~Snapshot `@home` (§2) and confirm the backup drive is current.~~ —
   **done 2026-07-29.** `@home/.snapshot-pre-nixos` (ID 6036) exists, and the
   backup drive verified clean with browser and mail profiles quiescent.

   **Know what that snapshot does not contain.** `@home/henry/Downloads`
   (ID 4808) and `@home/henry/Nextcloud` (ID 4843) are *nested subvolumes*,
   and a btrfs snapshot does not recurse into those — both appear as empty
   directories inside `.snapshot-pre-nixos`. Neither is in the rsync backup
   either, and both are deliberate (§0b: Nextcloud replicates to the server,
   Downloads is transient). So nothing is newly at risk — but "I have a
   snapshot of `@home`" is not true in the way it sounds, and that is exactly
   the belief that becomes a nasty surprise during a restore.
7. ~~**Write the installer ISO to removable media.**~~ — **done 2026-07-29.**
   See §8b. The SK Hynix 256 GB in the USB enclosure carries
   `nixos-minimal-26.05` as a whole-device `dd`.
8. Create `@nixos` and `@nix` subvolumes on `nvme0n1p2`. Do **not** touch `@`,
   `@home`, `@pkg`, `@log`, or the ESP.
9. `nixos-install --flake ~/src/arch-config/nixos#thinkpad`. Arch stays
   bootable throughout — that is the whole point of side-by-side.
10. Boot to the TTY greeter. Get the compositor up. Nothing else matters today.
11. Restore what the flake does not carry: NetworkManager profiles, Bluetooth
    pairings, the 3 flatpaks, `rclone.conf` and the CLI tokens from the drive.
12. Work the genuinely-absent package list (§6b) down over the following weeks.
13. Once you have not booted Arch in a month: delete `@`, `@pkg`, `swap`.

### Rollback

At every point up to step 13, Arch is intact and selectable from the boot
menu. Steps 1–7 change nothing about the running system. Step 8 adds
subvolumes without touching existing ones. The first genuinely
hard-to-reverse action is step 13.

### A caution on 37 GiB — and it got tighter

The closure is ~37 GiB unpacked. Free space was 149 GiB when this was written
and is **110 GiB as of 2026-07-29**, so the margin has shrunk from ~112 GiB to
~73 GiB while nothing about the plan changed. With `nix.gc` keeping 30 days of
generations, expect real usage of 60–80 GiB once you have rebuilt a few dozen
times — which lands uncomfortably close to 73 GiB.

Re-measure before you install rather than trusting this number; it has already
moved once. `nix-collect-garbage --delete-older-than 7d` if it gets tight, and
note `.local/share/Trash` was 20 GiB at last check.

### Evaluation is not buildability — the `fsel` near-miss

`verify-packages.sh` passing means every option name and package name
*resolves*. It does **not** mean anything compiles. That gap nearly cost the
install.

The `fsel` override in `pkgs/default.nix` set `src` to the release **binary**
tarball (`fsel-x86_64-unknown-linux-gnu.tar.xz`). But nixpkgs builds fsel with
`rustPlatform.buildRustPackage` **from source**, so the cargo vendor step had
no `Cargo.lock` to read and failed with a Python traceback. Every evaluation
had passed for weeks; the first actual `nix build` failed instantly.

`fsel` is the `SUPER+Space` launcher, and it is in the system closure — so
`nixos-install` would have aborted partway through, after the disk had already
been written to.

Fixed by overriding with the GitHub *source* for the tag and regenerating
`cargoDeps` via `rustPlatform.fetchCargoVendor`, with both hashes obtained by
building. While doing it, the version turned out to be stale too: the comment
claimed Arch runs 3.5.2, but `fsel --version` says **3.6.0**. The override now
builds 3.6.0 and the binary reports the same version as the live one.

**The rule:** any hand-written or overridden derivation must be *built* at
least once, not merely evaluated. Of the four in `pkgs/default.nix`, only
`fsel` and `gruvbox-gtk-theme` are in the closure — both have now been built.
`curseforge` and `brother-mfc-l3740cdw` are defined but not installed, so they
remain untested and will need this treatment if you ever add them.

```bash
nix build --no-link path:.#nixosConfigurations.thinkpad.pkgs.<name>
```

### The several-hundred-derivation build list is not what it looks like

`nix build --dry-run` reports a few hundred derivations "will be built", which
reads as though the installer is about to compile the world. It is not. Almost
all are trivial `/etc` files (`etc-fstab`, `fc-*.conf`, `dbus-1`).

The only substantial entries are three Electron runtimes — 39.8.10 (`logseq`),
40.10.5 (`winboat`) and 35.5.0 (`claude-desktop`, via its own nixpkgs pin).
Checked on 2026-07-29: these are **prebuilt binaries**, not source builds. Each
derivation fetches upstream's `electron-vXX-linux-x64.zip` and unpacks it; the
only other inputs are the runtime libraries autoPatchelf needs.

They are absent from `cache.nixos.org` (confirmed 404) purely because they are
flagged **insecure**, and Hydra does not build insecure-flagged packages. That
is the same fact as `nix-settings.nix` needing `permittedInsecurePackages` —
worth stating plainly, because "not cached" plus "Electron" invites the wrong
conclusion that a Chromium compile is about to happen.

**Settled empirically on 2026-07-29.** All three were built:

```
/nix/store/...-claude-desktop-0.14.10    41 MB
/nix/store/...-logseq-0.10.15           290 MB
/nix/store/...-winboat-0.9.0             82 MB
```

Nine derivations in total — the three apps, `electron-40.10.5` (288 MB), a Go
toolchain for `winboat-guest-server`, and four small Rust/NAPI helpers. **The
whole set finished in about nine minutes.** A Chromium source build would have
been many hours on this hardware and would likely have exhausted 14 GiB of RAM
at link time. Nothing in the closure now needs proving; every package that the
installer must build locally has been built at least once.

---

## 8b. Installer media, and the drive shuffle behind it (2026-07-29)

The plan never said where the installer ISO would live. Getting it there
turned up two drives' worth of surprises, so the outcome is recorded here.

### The finished state

```
sdb  SK Hynix 256 GB in an AMicro AM8180 USB enclosure
     whole-device dd of nixos-minimal-26.05.6282.2f5a153c270b-x86_64-linux.iso
     iso9660  label nixos-minimal-26.05-x86_64   + vfat EFIBOOT

sda  Samsung 128 GB — the backup drive, UNTOUCHED by the install media work
     sda1  ext4  100 GiB  "Samsung 128G"   (17 GB backup + docs)
     free        ~19.5 GiB unallocated tail
```

### Why the ISO could not go on a spare partition

The obvious idea — carve the backup drive's free tail into a partition and
`dd` the ISO there — does not boot, for two independent reasons:

1. **The ISO is isohybrid.** Its EFI partition lives at sector 284 *inside*
   the image. Written to `/dev/sdX2`, that nested partition table is invisible
   to firmware, which only enumerates partitions listed in the disk's own GPT.
2. **Extracting the ISO to a FAT32 ESP fails later.** The initrd's fstab is
   hardcoded:

   ```
   /dev/disk/by-label/nixos-minimal-26.05-x86_64  /iso  iso9660  x-initrd.mount 0 0
   /sysroot/iso/nix-store.squashfs  /nix/.ro-store  squashfs  loop 0 0
   ```

   Stage-1 demands an **iso9660** filesystem labelled with all 26 characters
   of that volume ID. FAT32 labels cap at 11. GRUB itself would have been
   fine — `EFI/BOOT/grub.cfg` finds its root with
   `search --set=root --file /EFI/nixos-installer-image`, a marker file, not a
   label — so the failure would have arrived late, after the kernel loaded.

A whole-device `dd` sidesteps both: the ISO's MBR becomes the disk's MBR, so
`EFIBOOT` is a real partition firmware can boot, and the iso9660 label is
present on a real block device.

### The target drive was a dead Arch install

`sdb` held `ArchinstallVg` — an `archinstall`-created system, not the flashed
ISO it was assumed to be. Verified disposable before wiping:

| Check | Result |
|---|---|
| Hostname / user | `archpad`, single user `henry` (uid 1000) |
| Created | 2025-09-04, 15:04:06 → 15:08:06 UTC — a 4-minute installer run |
| Ever booted | twice, both 2025-09-04, ~5 minutes of uptime in total |
| `pacman.log` | 914 lines, all of it the installer; nothing installed after |
| `/home/henry` | 2.2 MB of default skel dotfiles; largest file was a mesa shader cache |
| `/root` | empty |

An empty `ly-session.log` next to two boots of one and four minutes is the
whole story: the display manager did not come up and the install was
abandoned that afternoon.

`vgchange -an` before `wipefs`/`dd` is not optional — device-mapper holds the
partitions open. `wipefs` was run on `sdb1`/`sdb2`/`sdb3` as well as `sdb`,
because a 1.6 GB ISO write never reaches the LVM signatures further into the
disk, and a half-assembled `ArchinstallVg` would keep reappearing.

### The backup drive was resized first, and it went wrong once

Before the SK Hynix was found, the backup drive was shrunk to make room. The
ext4 shrink itself was uneventful — `resize2fs` relocates extents, so
fragmentation is irrelevant — but the partition step truncated the filesystem:

```
resize2fs 98G   → 98 GiB  (2^30)
parted    100G  → 93.131 GiB  (10^9)   ← fs now overhangs the partition by 4.869 GiB
```

**`G` means GiB to `resize2fs` and GB to `parted`.** `e2fsck` refused to run,
which was correct. Recovery was `parted resizepart 1 100%` to put the
partition back around the filesystem, then `e2fsck -f`, then a redo with
`unit GiB` throughout. No data was lost — the file count was 217,286 before
and after — but the lesson is to write `GiB` explicitly in `parted`, always.

The drive now sits at 100 GiB with a ~19.5 GiB unallocated tail. That tail is
spare; nothing needs it.

### Also cleared up

`Lee_old` on the backup drive — 13.6 GB, root-owned, unreadable to `du`, and
briefly suspected of being someone else's data — is
`/home/henry/Pictures/Lee_old`, copied on 2026-07-28 with `sudo cp -r`. It is
duplicated on the internal drive and can be dropped from the backup if the
space is ever wanted.

## 8c. First `nixos-install` run — vscode/vscodium collision (2026-07-29)

The first real `sudo nixos-install --root /mnt --flake …#thinkpad` got past
flake evaluation and died in the **home-manager profile build**, not in
anything NixOS-specific:

```
error: builder failed with exit code 25
> pkgs.buildEnv error: two given paths contain a conflicting subpath:
>   …-vscodium-1.126.04524/lib/vscode/LICENSES.chromium.html  and
>   …-vscode-1.129.1/lib/vscode/LICENSES.chromium.html
```

`modules/home/packages.nix` listed **both `vscode` and `vscodium`**. On Arch
that is fine — `visual-studio-code-bin` and `vscodium-bin` ship under separate
prefixes. In Nix they both unpack to `lib/vscode/`, and `home.packages` merges
every package into one `buildEnv`, so the shared paths collide and the whole
generation fails.

`lib.lowPrio` would silence it but is the wrong fix: `buildEnv` recurses into
directories, so the surviving `lib/vscode` would be a merge of two different
Electron builds. **Fixed by dropping `vscodium` and keeping `vscode`** (the MS
build is the one that can reach the official extension marketplace, which the
`github-copilot-cli` / `code-cursor` side of the list assumes).

Two things worth carrying forward:

- `verify-packages.sh` and `nix build --dry-run` do **not** catch this. They
  evaluate and fetch; profile collisions only surface when the `buildEnv` is
  actually realised. Expect more of these to appear one at a time — `buildEnv`
  aborts on the *first* conflict, so a clean run after a fix is not proof that
  the rest of the list is collision-free.
- Editing a **tracked** file under `/mnt/home/henry/src/arch-config` is enough
  to re-run the install; Nix reads dirty git trees (with a `Git tree is dirty`
  warning) and no commit is needed on the installer. **New untracked files are
  ignored** — anything genuinely new has to be `git add`ed before the flake
  will see it.
