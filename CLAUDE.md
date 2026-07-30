# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

Henry's personal dotfiles and application configuration. There is no build system or test suite — changes are applied by restarting or reloading the relevant application.

**Read this first — where the repo lives depends on which OS is booted.** As of 2026-07-29 this ThinkPad dual-boots Arch and NixOS side-by-side, sharing `@home` and the ESP.

| Booted | Repo location | `~/.config/<app>` is |
|---|---|---|
| **NixOS** (current) | `~/src/arch-config` | a symlink into `~/src/arch-config/<app>`, created by home-manager |
| Arch (still bootable) | `~/.config` itself | the real directory |

On NixOS, **edit files under `~/src/arch-config`** — editing through the `~/.config` symlink reaches the same file, but `~/.config/nixos` does not exist there at all (`dotfiles.nix` deliberately never links it), so the flake is only at `~/src/arch-config/nixos`. Rebuild with `nixos-rebuild switch --flake ~/src/arch-config/nixos#thinkpad` (aliases: `rebuild`, `update`).

Only directories tracked in git are linked. `~/.scripts`, and the credential dirs the `.gitignore` allowlist excludes (`gh`, `glab-cli`, `gpu-screen-recorder`, `opencode`), are plain directories surviving via `@home`.

## Shell environment

**The login shell is zsh** (`/etc/passwd`), configured from `~/.config/zsh/conf.d/*.zsh` via `ZDOTDIR`. Fish is installed as a secondary interactive shell with its own `~/.config/fish/config.fish`, but it is **not** what terminals start, and it is being dropped in the NixOS migration (see `nixos/modules/home/shell.nix`).

Aliases common to both, which affect terminal work:

- `cat` → `bat` (syntax-highlighted pager — use Read tool instead of Bash cat)
- `ls` / `ll` / `la` → `eza` variants
- `lf` → `yazi` (file manager)
- `zed` → `zeditor`
- `pacman` → `sudo pacman`; typo alias `pamcan` also works (fish only) — **Arch only; there is no pacman on the booted NixOS system.** Package changes go in `nixos/modules/home/packages.nix` followed by a rebuild
- PATH additions: `~/.config/emacs/bin`, `~/.cargo/bin`, `~/Applications/*/bin`, `~/.local/bin`, `~/.bun/bin`
- `zoxide` is active for `z` directory jumping

Note the fish `lidt` and `cleantmp` aliases point at `$scripts/toggle_lid_action.sh` and `$scripts/clean_tmp.sh` — with `.sh` extensions the real scripts don't have, so both are broken. The zsh equivalents (`lidaction`, `cleantmp`) are correct.

**Home-directory clutter hiding** (added to reduce `ls ~` / file-manager noise, not to move anything):
- `~/.hidden` lists top-level dirs that GTK file managers (Thunar) omit from the `~` view. Toggle back with **Ctrl+H**.
- In zsh (`~/.config/zsh/conf.d/10-aliases.zsh`), `ls`/`l` are a function that applies eza `--ignore-glob="$_HOME_HIDE"` **only when `$PWD == $HOME` and no args are given** — so common names (`share`, `temp`, `log`, `R`) are never hidden inside projects. `ll`/`la`/`lla`/`lls` are unfiltered escape hatches. The file starts with `unalias ls l ll` — NixOS's `/etc/zshrc` (from `programs.zsh.enable`) predefines those three from the `environment.shellAliases` defaults, and an existing `ls` alias makes `ls() { … }` a **parse error that aborts the rest of the file**, silently dropping the `y` yazi function and the zoxide init below it. Don't remove the `unalias`.
- Both surfaces share the same list: `Android Applications blender colors go log R share temp vaults winboat Zomboid`. To un-hide a dir, remove it from **both** `~/.hidden` and `_HOME_HIDE`. Nothing is moved; `cd`/`z`/paths are unaffected.

## Theming architecture

Theming is driven by **Mangowm mode scripts** (`~/.config/mango/scripts/modes/`). Switching modes symlinks the correct theme into `active-theme.*` files:
- `~/.config/kitty/active-theme.conf` — symlinked by mode script, included by `kitty.conf`
- `~/.config/foot/active-theme.ini` — symlinked by mode script, included by `foot.ini`
- Equibop (Discord) CSS theme is also swapped via `jq` on `settings.json`

Current modes: **tiling** (Gruvbox Orange) and **hud**. Active mode is stored in `~/.config/mango/state/current-mode`. (A third `dms` mode was removed in July 2026 along with DankMaterialShell.)

**`mango/config.conf` and `mango/state/` are generated, not configuration** — both are gitignored. The mode script copies `tiling/tiling.conf` (or `hud/hud.conf`) to `config.conf`, and that is the file that `source=`s every keybind, rule and autostart line. A fresh clone therefore has no config.conf, and mango starts on built-in defaults with no waybar and no keybinds until a mode script has been run once. Same for `kitty/active-theme.conf` and `foot/active-theme.ini`.

To reload Mangowm config: `~/.config/mango/scripts/reload.sh` (re-runs the mode script, sends `mmsg reload_config`, restarts elephant).

Static theme baseline: **Gruvbox Dark** across terminals, editors, and shell. Fonts: **Hack Nerd Font Mono** at size 11 in kitty/foot, 0xProto Nerd Font for bold/italic variants.

Default applications are set in `~/.config/mimeapps.list`. Current defaults:

| Type | Application | Desktop file |
|---|---|---|
| Browser (HTTP/HTTPS/HTML) | Zen Browser | `zen.desktop` |
| PDF | Zathura | `org.pwmt.zathura.desktop` |
| Images | imv | `imv.desktop` |
| Video / Audio | mpv | `mpv.desktop` |
| Directories / ZIP | Thunar | `thunar.desktop` |
| Email / calendar | Betterbird | `eu.betterbird.Betterbird.desktop` |
| Shell scripts / Markdown | Neovim | `nvim.desktop` |
| Torrents / magnets | Free Download Manager | `freedownloadmanager_*.desktop` |
| `discord:` scheme | Equibop | `equibop.desktop` |
| `obsidian:` scheme | Obsidian | `obsidian.desktop` |

**LibreWolf is no longer installed** (verified 2026-07-27 — no package, no profile directory). The default browser is **Zen**, whose profile is at `~/.config/zen/` (848 MB). Stale `librewolf.desktop` entries remain in `mimeapps.list` and can be removed. The `userChrome.css` / Sidebery notes below applied to the LibreWolf profile and are kept only for reference if you set up a Firefox-family browser again: chrome customisation requires `toolkit.legacyUserProfileCustomizations.stylesheets=true` in about:config, and Sidebery's custom CSS must be pasted into the extension's settings (Sidebery → Styles → Custom CSS) since it doesn't read from disk.

The `pdf` shell alias opens files via `xdg-open`, deferring to the system default.

## Editor setup

**Neovim** (`~/.config/nvim/`) — minimal hand-rolled config on `lazy.nvim` (~18 plugins; replaced a LazyVim install in June 2026). See `nvim/README.md` for the full map.
- `lua/config/` holds `options.lua`, `keymaps.lua`, `autocmds.lua`, `lazy.lua`; `lua/plugins/` holds one spec file per concern (colorscheme, treesitter, lsp, completion, coding, editor, ui, writing, ai)
- **No mason** — language servers are taken from `$PATH` (install via pacman/npm/AUR; list in `README.md`). LSP uses Neovim 0.11+ native `vim.lsp.enable`; completion is `blink.cmp`
- Tree-sitter is the classic `master` branch; parsers compile with system `cc`. `latex`/`bibtex` parsers are intentionally omitted (vimtex owns `.tex`/`.bib`)
- Writing stack: `render-markdown` (in-buffer), `knap` (live preview: `<leader>ks` once, `<leader>ka` toggle, `<leader>kc` close), `vimtex` (LaTeX, zathura viewer), `typst-preview` (`<leader>tp`). knap converter/wrapper live in `nvim/scripts/`
- `<C-d>` / `<C-u>` centre the cursor after scroll; Copilot ghost-text accept is `<M-l>`
- Old config + plugin data backed up to `~/.config/nvim.bak.*` and `~/.local/share/nvim.bak.*` (delete once settled)

**Zed** (`~/.config/zed/settings.json`) — vim mode on, VSCode base keymap, Gruvbox Dark theme, MCP agent servers configured (opencode, claude-acp, github-copilot-cli).

## Desktop environment

**Mangowm** (`~/.config/mango/`) — Wayland compositor/WM. Config is split into universal settings (shared across modes) and per-mode overrides (`tiling/`, `hud/`). Each mode has its own `autostart.conf` and compositor config that gets copied to `config.conf` on mode switch.

Window rule positioning: `offsetx`/`offsety` are **percentages from the usable-area centre** (range −999 to 999). `±100` = the usable screen edge (i.e. respects the Waybar reserved area). Example: `offsetx:100,offsety:-100` = top-right corner just below the Waybar.

Key components running under Mangowm:
- **Waybar** — status bar, config and styles in `mango/waybar/` (per-mode layouts). The focused-window title comes from **`custom/window`**, backed by `scripts/waybar/window-title.sh` (streams `mmsg watch focusing-client` as waybar JSON). Do **not** reintroduce waybar's built-in `dwl/window` module: mango 0.15.5 (upgraded 2026-07-27) dropped the dwl IPC protocol `zdwl_ipc_manager_v2` that module binds to, and its absence makes waybar SIGSEGV on startup. CSS selector is `#custom-window`, not `#window`
- **fsel** — primary application launcher (`SUPER+Space`), runs in a floating foot terminal pinned to the right side via the `fsel-launcher` window rule. Config at `~/.config/mango/fsel/config.toml` — loaded by passing `XDG_CONFIG_HOME=/home/henry/.config/mango` in the keybind, matching Walker's pattern
- **Walker** — structured menus (bluetooth, clipboard, bitwarden, etc.); provider list bound to `SUPER+W`, configs in `mango/walker/configs/`. The wrapper at `mango/scripts/walker/walker.sh` injects a default `--maxheight 500` for non-HUD modes (so windows shrink to fit short lists) unless the caller passes its own
- **Network menu** (`mango/scripts/menus/network-menu.sh`) — bash dmenu script for WiFi/ethernet/VPN. Bound to `SUPER+CTRL+N` and Waybar network right-click. Supports `--warm` (build cache at startup, in autostart) and `--reload` (rescan + relaunch). Replaces an earlier elephant Lua provider that couldn't preserve section order
- **Rofi** — secondary launcher/menus, themed in `mango/rofi/`
- **Elephant** — shell widget layer, menus in `mango/elephant/`
- **swaync** — notification daemon, styled in `mango/swaync/`. **Autostart owns the process, not systemd**: the `exec=` line in each mode's `autostart.conf` pkills and respawns it with `-s ~/.config/mango/swaync/style.css`, so a restyle takes effect on mode switch. The unit nixpkgs ships is masked in the flake — see NixOS point 7 below. Don't enable both.
- **Wallpaper (awww)** — `mango/scripts/system/wallpaper-restore.sh`, run from `mango/universal/autostart.conf`, starts `awww-daemon` and re-applies `mango/wallpaper/wallpaper.png`. Added 2026-07-30: nothing had started the daemon before, so the wallpaper had to be re-set by hand after every boot (true on Arch too). The binary is **`awww`, not `swww`** — nixpkgs renamed the package to the fork already in use. `mango/scripts/system/set-wallpaper.sh <image>` changes it; the image is gitignored, and the restore script exits 0 when absent so a fresh clone is not an error.
- **Night light (wlsunset)** — the **systemd user service owns the process**; `mango/scripts/menus/night-mode.sh` only drives that unit (`systemctl --user start/stop/restart`). Never go back to `pgrep`/`pkill` + spawning a second wlsunset: only one Wayland client can hold a gamma control, so the loser prints `gamma control of output eDP-1 failed` and silently does nothing. The unit is hand-written in `nixos/modules/home/default.nix` rather than using `services.wlsunset`, because that module bakes temperatures into a static `ExecStart` and wlsunset has no runtime IPC — so the waybar temperature picker could not change them. Instead `ExecStart` is `mango/scripts/system/night-light-run.sh`, which reads the chosen night temperature from `mango/state/night-temp` (gitignored) at start; the picker writes that file and restarts the unit. Location and day temperature stay declared in Nix via `Environment=`. Waybar module: `custom/night-mode`, refreshed by `pkill -RTMIN+9 waybar`.
- **wlogout** — the power menu behind the waybar power icon (`custom/power`). Layout and CSS in `mango/wlogout/`; its five PNGs are **vendored into `mango/wlogout/icons/`** and referenced relatively. See NixOS point 3 below for why.
- **Proton Drive (rclone)** — FUSE mount at **`~/ProtonDrive`**, by the `rclone-protondrive` user service in `nixos/modules/home/default.nix`. Not `~/mnt/ProtonDrive`, which is what Arch used and which silently could not work; see NixOS point 8 below. Credentials are in `~/.config/rclone/rclone.conf`, gitignored and restored by hand.
- **Polkit agent** — **on NixOS this is `polkit_gnome`**, run as the systemd user service `polkit-gnome-authentication-agent-1` (`nixos/modules/system/desktop.nix`), *not* from autostart. The `exec-once=... command -v lxpolkit && lxpolkit` line in `mango/universal/autostart.conf` is an Arch leftover; it is guarded, so on NixOS it is a deliberate no-op — `lxsession`/`lxpolkit` are not installed. On Arch, lxpolkit is the agent and that autostart line is what starts it. Note: `exec-once` only fires on initial compositor startup, not on reload — log out/in after changing autostart.
- **KDE Connect** — `kdePackages.kdeconnect-kde`. Both `autostart.conf` files start `kdeconnectd`, and the Waybar phone module (`mango/scripts/kdeconnect/phone-status.sh`) queries the `org.kde.kdeconnect` D-Bus name and shells out to `kdeconnect-cli`. **Do not swap in `valent`** — it is a different implementation under `ca.andyholmes.Valent` and satisfies none of those call sites. Firewall ports 1714-1764 are opened in `nixos/modules/system/networking.nix`.
DankMaterialShell and Quickshell were **removed in July 2026**, along with the `dms` mode and all its theme files. Two things kept their names deliberately: `kitty/tabs.conf` (renamed from `dank-tabs.conf`; included by `kitty.conf` in every mode) and `yazi/flavors/noctalia.yazi` (still the active yazi theme per `yazi/theme.toml`).

Mangowm is the sole desktop environment. KDE Plasma has been removed from this system.

## Battery charge thresholds

ThinkPad EC thresholds are set by TLP in `nixos/modules/system/power.nix`: **START 40 / STOP 85**. Live values are `/sys/class/power_supply/BAT0/charge_control_{start,end}_threshold` (the older `charge_{start,stop}_threshold` aliases mirror them).

**Two coupled settings, and the coupling is not obvious:**
- `STOP_CHARGE_THRESH_BAT0` must match **`"full-at"` in `mango/waybar/config-focus.jsonc`** (currently **85**). Waybar rescales the reading as `shown = real / full-at × 100`, so with STOP at 80 against a `full-at` of 85 the bar peaked at 94% and displayed 88% at a real 75% — reported as "stuck at 88%". Change one, change the other.
- Only `config-focus.jsonc` carries `full-at`; `config.jsonc`, `config-minimal.jsonc` and `config-hud.jsonc` have none and therefore show the **raw** percentage. Switching layout with `SUPER+/` changes the number you see.

**Expected behaviour that looks like a fault:** with START at 40, a battery on AC parks at whatever charge it had and only tops back up below 40%. `status` then reads `Not charging`, and waybar maps that to `format-plugged` (plug glyph) — the lightning bolt is `format-charging` and appears only for `status = Charging`. So a plug icon with a sub-100% reading that never moves is the hysteresis working. Raising STOP does **not** trigger a charge; the EC only starts below START. To force a top-up: `sudo tlp setcharge 84 85 BAT0`.

Note `upower -i` reports `charge-start-threshold: 75%` regardless of the real value — trust sysfs, not upower, for thresholds.

## Networking

**WiFi card**: Qualcomm QCNFA765 (`wlp1s0`), driver `ath11k_pci`. Connected to `Minerva_2` (enterprise router).

**Known issue — WiFi fails to recover after system suspend**: The ath11k_pci driver does not cleanly reinitialize on resume, and the enterprise router drops the association. NM retries but DHCP times out and the connection never recovers. Manually restarting NetworkManager fixes it.

**Fix in place (two separate layers, both necessary)**:
- TLP config (`/etc/tlp.conf`) — sets `WIFI_PWR_ON_AC=off` and `WIFI_PWR_ON_BAT=off`. Prevents the radio from power-saving during normal runtime. Does *not* affect suspend/resume behaviour.
- `/etc/systemd/system-sleep/wifi-resume.sh` — cycles the WiFi radio off/on 3 seconds after system wake, forcing a clean re-association. This is what actually fixes the resume failure.

These can't be merged: TLP is applied by its service; the sleep hook is executed by systemd. Each covers a different failure mode.

**On NixOS both are declarative — do not edit `/etc` directly**, it is generated and read-only. `networking.wifi.powersave = false` and `systemd.services.wifi-resume` live in `nixos/modules/system/networking.nix`; the TLP settings are in `power.nix`. Change those and `nixos-rebuild switch`.

If the issue recurs, check `journalctl -u NetworkManager` for DHCP timeout after wake. Disabling Fast Transition (`nmcli connection modify Minerva_2 wifi-sec.key-mgmt wpa-psk`) is an additional option if the sleep hook alone doesn't resolve it.

### VPN profiles: autoconnect is off, deliberately

The 9 VPN profiles (`homelab` WireGuard + 8 PIA OpenVPN exits) all came off the backup with `connection.autoconnect=yes` and `ipv4.dns-priority=0`. **All 9 were set to `autoconnect=no` on 2026-07-30.** Don't turn it back on.

The failure mode, seen the moment the profiles were restored: `homelab` auto-activated, claimed `+DefaultRoute`, and pushed its DNS server `192.168.1.5` onto *every* link. Away from `Minerva_2` that server is unreachable, so **all** name resolution failed — `resolvectl query` returned "All attempts to contact name servers or networks failed" for everything. Nothing identifies itself as a VPN problem at that point; it presents as total DNS death, and the visible symptom was rclone reporting `lookup drive-api.proton.me: no such host`. Check `resolvectl status` for a tunnel holding `Default Route: yes` before suspecting anything else.

Bring the tunnel up by hand when you need Gitea: `nmcli connection up homelab`. It is the only route to `git.henrydowd.dev`, so `tea` and `git push` need it.

**These profiles are not in git and not declarative.** They live in `/etc/NetworkManager/system-connections` (root-only, mode 600) and were restored by hand from the backup drive. If you ever re-restore them, the `autoconnect=yes` comes back with them and so does the DNS failure.

## NixOS migration — INSTALLED 2026-07-29, now the booted system

`nixos/` holds the flake that reproduces this machine. **It is live.** `nixos-install` completed on 2026-07-29 and the machine boots NixOS; Arch remains untouched and selectable from the boot menu. `nixos/MIGRATION.md` §8c records the install, `MIGRATION-GUIDE.md` Part 10 the remaining restore steps.

**What is done:** install, bootloader, both EFI entries, root and `henry` passwords, home-manager activation, mango starting. Then, verified on 2026-07-30: CLI credentials (`rclone`, `gh`, `glab-cli`, `rbw`), the printer (`Brother_MFC_L3740CDW_series` — driverless IPP discovery found it, `/etc/cups` never touched), the GTK theme resolving to `Gruvbox-Yellow-Dark`, 3270 Nerd Font, magnet links reaching qBittorrent, and the 8 OpenVPN `.pem` certs which survived via `@home`. `mango/wallpaper/` is restored — it is a single 4.6 MB `wallpaper.png`, not a collection.

**What remains** (nothing blocking; see `MIGRATION-GUIDE.md` Part 10):
- ~~Restore NetworkManager profiles and Bluetooth pairings~~ — **done 2026-07-30**: 35 profiles into `/etc/NetworkManager/system-connections` (37 connections, 8 VPN) and 7 Bluetooth devices into `/var/lib/bluetooth`. See the VPN autoconnect note under Networking — restoring the profiles broke DNS until autoconnect was turned off.
- Clean up `~/.config/*.hm-bak` (21 of them), the originals home-manager moved aside, and `~/.config/systemd/user/micmute-led.service.arch-bak` (see point 1 below). Take the wallpaper out of `mango.hm-bak` first if it has not been restored yet.
- Test suspend/resume — still never exercised on NixOS, and it is this machine's historical failure mode (see Networking above).
- Don't delete the Arch subvolumes (`@`, `@pkg`, `swap`) until a month has passed without booting it.

**Eight things that will surprise you if you don't know them:**
1. **`~/.config/systemd/user/` overrides `/etc/systemd/user/`**, and that directory survived the migration via `@home`, so Arch-era units silently shadow the ones the flake generates. `micmute-led.service` was shadowed this way: the leftover copy had no `PATH=`, so `pactl` was not found and the daemon exited instantly — 6464 restarts deep. Moved aside to `micmute-led.service.arch-bak` on 2026-07-30. To audit: compare `ls ~/.config/systemd/user/` against `/etc/systemd/user/`; that was the only collision. Note a unit's `path`/`Environment=PATH` is its **entire** PATH, so anything a script shells out to must be listed — including **`bash` itself**, since every script here is `#!/usr/bin/env bash`.
2. **There is no `/bin/bash`** — `/bin` holds exactly one entry, `sh`. Every script must use `#!/usr/bin/env bash`; a `#!/bin/bash` shebang fails with `bad interpreter` and exit 127. This bit 13 scripts after the migration (fixed 2026-07-30), and the symptom is *silence*, not an error: a waybar `custom/*` module whose `exec` script exits 127 simply renders as an empty module, which reads as "the module is missing from the bar". `custom/night-mode` disappeared this way. When something in mango is inexplicably absent, run its script by hand first.
3. **`share/<pkgname>` is not in `environment.pathsToLink`**, so a package's data files exist *only* at its versioned `/nix/store` path — `/run/current-system/sw/share/wlogout/` does not exist even though wlogout is in `systemPackages`. Never hardcode `/usr/share/...` or a store path in a config. `mango/wlogout/` vendors its five PNGs into `wlogout/icons/` and references them **relatively** (`url("icons/lock.png")`), which works because GTK resolves CSS `url()` against the stylesheet's own path. GTK draws its missing-image box for a failed `url()` **without logging a warning**, so this class of bug is invisible in logs — it was reported as "the icons are just square boxes".
4. **Generated files are gitignored**, so a fresh clone lacks them. `mango/config.conf` is the big one — it `source=`s every keybind and autostart line, and without it mango runs on built-in defaults (no waybar, no shortcuts). Run `~/.config/mango/scripts/modes/tiling.sh`, then log out and back in. Same for `mango/state/`, `kitty/active-theme.conf`, `foot/active-theme.ini`.
5. **`cc` and `c++` are clang, not gcc** — the reverse of Arch. `packages.nix` carries `(lib.hiPrio clang)` to break a `buildEnv` collision with `gfortran`, which ships its own `cc`/`c++`. `gcc`, `g++` and `gfortran` are all still on PATH.
6. **`buildEnv` collisions are the failure mode to expect** when adding packages. Two packages owning the same file path abort the whole generation. If one supersedes the other, drop it; if they merely contend over a few names, use `lib.hiPrio` on the winner — **not** `lib.lowPrio` on the loser, which silently does nothing when the two priorities are already equal.
7. **nixpkgs packages ship user units that Arch's packages did not**, and they auto-start. `swaync` is the case in point: nixpkgs' SwayNotificationCenter ships `swaync.service` with `WantedBy=graphical-session.target`, so it raced the `exec=` line in `mango/{tiling,hud}/autostart.conf` — which is the copy that matters, because it passes `-s ~/.config/mango/swaync/style.css`. Autostart won the `org.freedesktop.Notifications` bus name and the unit died with `An instance of SwayNotificationCenter is already running!`, five times, then sat in `start-limit-hit`. **Notifications worked the whole time**, which is why it went unnoticed until 2026-07-30. It is now masked in `modules/home/default.nix` via `xdg.configFile."systemd/user/swaync.service".text = ""` — an empty unit file loads as `masked` per systemd.unit(5), and the usual `source = "/dev/null"` is rejected by pure evaluation as an absolute path. When adding a package that has a daemon, check `ls $(nix eval --raw nixpkgs#foo)/share/systemd/user/` before trusting autostart to be the only owner.
8. **A ported unit can carry a path that only worked by accident.** `rclone-protondrive` faithfully reproduced the Arch template's `%h/mnt/%i`, but `~/mnt` is a symlink to `/run/media/henry` — the udisks removable-media directory, which does not exist unless a drive is mounted. `mkdir -p` reports `File exists` for a dangling symlink rather than creating anything, so rclone could not make its mount point, and `Restart=on-failure` retried every 5s until Proton answered **HTTP 429 with a one-hour backoff** — 230 restarts deep when caught on 2026-07-30. Now mounted at `~/ProtonDrive` (matching the `~/Nextcloud` convention), with `RestartSec=30` and `StartLimitBurst=5`/`StartLimitIntervalSec=600`. **Any unit that talks to a remote API needs a start limit**, or a local misconfiguration becomes an unattended request flood against someone else's service.

Inputs are pinned by `nixos/flake.lock` (nixpkgs `624af665`) — re-lock deliberately with `nix flake update`, not as a side effect of a build. `nixos/verify-packages.sh` re-checks that the closure evaluates, but note it only evaluates: it cannot catch profile collisions or a derivation that fails to build.

**Installer media is ready (2026-07-29):** the SK Hynix 256 GB in the AMicro AM8180 USB enclosure carries `nixos-minimal-26.05` as a whole-device `dd` (iso9660, label `nixos-minimal-26.05-x86_64`, plus a `vfat` `EFIBOOT` partition). It previously held a dead `archinstall` system, verified empty before wiping. The Samsung 128 GB backup drive is separate and untouched by that work — one 100 GiB ext4 partition plus a spare ~19.5 GiB unallocated tail. See `nixos/MIGRATION.md` §8b, including why the ISO cannot live on a spare partition and the `parted`-`G`-means-GB trap that briefly truncated the backup drive's filesystem.

- `flake.nix` — inputs: nixpkgs unstable, home-manager, nixos-hardware, plus only two third-party flakes (`zen-browser`, `claude-desktop`). Most AUR software turned out to be in nixpkgs already — `mango`, `fsel`, `walker`, `elephant`, `dsearch`, `weathr`, `sidequest`, `winboat`. (`dms-shell`, `quickshell`, `dgop` and `valent` are packaged too, but are excluded on purpose — DankMaterialShell is being dropped, and `valent` is the wrong KDE Connect implementation for these configs; see below.) Note `claude-desktop` must NOT use `inputs.nixpkgs.follows`; it references the removed `pkgs.nodePackages` and only builds against its own pin.
- `hosts/thinkpad/` — host config and `hardware-configuration.nix` (real UUIDs from the live fstab)
- `modules/system/` — one file per concern: boot, locale, networking, audio, desktop, fonts, power, printing, virtualisation, nix-settings
- `modules/home/` — home-manager: packages, shell, dotfiles, theme
- `pkgs/default.nix` — overlay + templates for packaging AUR software
- `verify-packages.sh` — checks which package names resolve in nixpkgs; run before any rebuild

Design decision worth knowing: `modules/home/dotfiles.nix` uses `mkOutOfStoreSymlink`, so `~/.config/{mango,nvim,kitty,foot,…}` stay writable rather than becoming read-only store paths. This is deliberate — the Mangowm mode scripts symlink `active-theme.*` and `jq`-patch Equibop's `settings.json` at runtime, which requires writable config directories.

Consequence to keep in mind when editing `dotfiles.nix`: the link **source** must be a path outside `~/.config`, because `xdg.configFile.<name>` writes *to* `~/.config/<name>`. The flake therefore expects this repo cloned at **`~/src/arch-config`**, not used in place at `~/.config`. Pointing a link at its own destination produces a symlink to itself, and with `backupFileExtension = "hm-bak"` that fails silently rather than loudly. Two rules follow: only link directories that are actually tracked in git (`gh`, `glab-cli`, `gpu-screen-recorder`, `opencode` are credential dirs excluded by the `.gitignore` allowlist, and `~/.scripts` is in no repo at all — none of them are linked), and `~/.config/nixos` itself is not linked, so `nixos-rebuild` runs against `~/src/arch-config/nixos`.

Planned installation is **side-by-side**: new `@nixos` and `@nix` btrfs subvolumes on the existing `nvme0n1p2`, reusing `@home` and the shared ESP, leaving the Arch install bootable.

## Scripts

Custom scripts live in `~/.scripts/`. **None of them have a file extension** — they are bash scripts named without `.sh`:
- `toggle_lid_action` — toggle lid close behaviour in `/etc/systemd/logind.conf` (run via `lidaction` alias)
- `clean_tmp` — clean tmp files (run via `cleantmp` alias)
- `keyd-application-mapper` — per-application keyd layer switching
- `micmute-led` — daemon that syncs the ThinkPad mic-mute LED with PipeWire's default source mute state; subscribes to PipeWire events via `pactl subscribe`. On NixOS it runs as the user service declared in `nixos/modules/system/audio.nix`, which is also the **only** place `pactl` exists: it comes from `pkgs.pulseaudio` on that unit's `path`, and is deliberately *not* in `systemPackages`, so running this script from an interactive shell fails with `pactl: command not found`. Write access to the LED comes from the udev rule in the same file. Don't add a `.sh` extension — the real filename has none.
- `pdf_to_a4` — converts a PDF to A4 page size using Ghostscript, preserving aspect ratio; usage: `pdf_to_a4 input.pdf [output.pdf]`
- `texpdf` — compiles a LaTeX file to PDF with pdflatex and cleans up the aux/log files; usage: `texpdf input.tex [output.pdf]`

## Keeping this file up to date

When you make any change that affects the system layout described in this file — adding/removing components, changing keybinds, renaming scripts, updating reload procedures, changing themes or fonts, adding new modes — update the relevant section of this file in the same task. Do not wait to be asked. Treat CLAUDE.md as live documentation: it should always reflect the current state of `~/.config`.

## Applying changes

| Component | How to reload |
|---|---|
| fish config | `source ~/.config/fish/config.fish` |
| kitty | `kill -SIGUSR1 $KITTY_PID` or Ctrl+Shift+F5 |
| foot | Restart terminal (no live reload) |
| Neovim plugins | `:Lazy sync` inside nvim |
| Mangowm | `~/.config/mango/scripts/reload.sh` |
| Switch mode | `~/.config/mango/scripts/modes/<mode>.sh` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |

## Agent skills

### Issue tracker

Gitea issues on the self-hosted instance at `git.henrydowd.dev` (repo `henry/arch-config`), driven by the `tea` CLI, which is already authenticated. Reachable only over the `homelab` WireGuard tunnel — when that is down, `tea` and `git push` both fail. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. They do not exist on the Gitea repo yet; `docs/agents/triage-labels.md` has the `tea labels create` commands.

### Domain docs

Single-context — one `CONTEXT.md` and `docs/adr/` at the root. Note that for this repo `CLAUDE.md` itself is the standing system description, so read it before `CONTEXT.md`. See `docs/agents/domain.md`.

Note for anything adding files under `docs/`: `.gitignore` is an allowlist, so a new top-level directory is invisible to git until it gets a `!/dirname/` line.
