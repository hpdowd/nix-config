# System guide

An operator's manual for this machine: what the pieces are, where each one
lives, and how to change them.

This is the *orientation* document. Two others sit alongside it and answer
different questions:

| Document | Answers |
|---|---|
| **`docs/SYSTEM.md`** (this file) | How is the system laid out, and how do I use it? |
| `CLAUDE.md` | What has bitten us, and what must not be undone? |
| `docs/adr/` | Why is it built this way rather than the obvious way? |
| `docs/WORK-LOG.md` | What changed on 30–31 July 2026, and what state is it in? |

If something here contradicts `CLAUDE.md`, `CLAUDE.md` is the one kept current
against failures — trust it and fix this file.

---

## 1. The machine

| | |
|---|---|
| Hardware | ThinkPad L14 Gen 5, AMD CPU + integrated AMD GPU |
| OS | NixOS unstable (`26.11`), kernel `linuxPackages_latest` |
| Hostname | `thinkpad` |
| User | `henry` |
| Disk | `nvme0n1` — 476 GB, btrfs |
| RAM | 14 GiB, plus zram swap at 50% (zstd). No disk swap, so **no hibernation** |
| Display | eDP-1, 1920×1200 |
| WiFi | Qualcomm QCNFA765 (`wlp1s0`, `ath11k_pci`) |
| Compositor | Mangowm (Wayland) — the only desktop |
| Login | greetd + tuigreet on TTY, launching `mango` |

Installed 2026-07-29, migrating from Arch. **Arch is gone** — subvolumes, boot
entry and EFI residue were all deleted on 2026-07-30. There is no dual boot and
no fallback to it.

### Filesystem layout

One btrfs filesystem, four subvolumes, plus the EFI partition:

| Mount | Subvolume | Notes |
|---|---|---|
| `/` | `@nixos` | The system. Rebuilt, never hand-edited |
| `/nix` | `@nix` | The store. Separate so GC churn doesn't touch `/` snapshots |
| `/home` | `@home` | **Carried across from Arch untouched.** Snapshotted by snapper |
| `/var/log` | `@log` | Kept out of root snapshots |
| `/boot` | — | vfat ESP, 1 GB, shared with the (now removed) Arch entry |

All btrfs mounts use `compress=zstd:3`, `noatime`, `discard=async`.

**`@home` is the important one.** It survived the migration in place, which is
why your browser profile, credentials and pairings are all still there — and
also why a large amount of live data is in **no repository**. See §11.

---

## 2. The mental model

Three layers, and almost every question is "which layer does this belong to?"

```
  ┌─────────────────────────────────────────────────────────────┐
  │ 1. THE FLAKE           ~/src/nix-config                      │
  │    Declares the system: packages, services, kernel, users.   │
  │    Changing it does nothing until you rebuild.               │
  └───────────────┬─────────────────────────────────────────────┘
                  │  nixos-rebuild switch
                  ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ 2. THE ACTIVATED SYSTEM   /run/current-system, /nix/store    │
  │    Read-only. /etc is generated. Home-manager links your     │
  │    dotfiles into ~/.config from here.                        │
  └───────────────┬─────────────────────────────────────────────┘
                  │  programs write at runtime
                  ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ 3. RUNTIME STATE       ~/.local/state, ~/.local/share        │
  │    Mode, waybar layout, wallpaper, credentials. Mutable,     │
  │    deliberately outside the config tree, in no repo.         │
  └─────────────────────────────────────────────────────────────┘
```

Two rules follow from this and explain most of the surprises:

1. **`/etc` is generated and read-only.** Editing `/etc/tlp.conf` or
   `/etc/systemd/...` either fails or is silently reverted on the next rebuild.
   Change the flake instead.
2. **State must never live in the config tree.** A program writing into its own
   config directory is precisely what stops that directory from becoming a
   read-only store path. This is why `~/.local/state/mango/` exists — see
   `docs/adr/0003`.

---

## 3. Repository map

```
~/src/nix-config/
├── flake.nix                  inputs + the thinkpad configuration. AT THE ROOT — see ADR 0001
├── flake.lock                 pinned inputs. Only moves when you run `update`
├── hosts/thinkpad/
│   ├── default.nix            host identity: hostname, user, groups, stateVersion
│   └── hardware-configuration.nix   real UUIDs, subvolume mounts, swap
├── modules/system/            one file per concern, all imported by the host
│   ├── boot.nix               bootloader, kernel, firmware, snapper
│   ├── locale.nix             timezone, keymap, keyd
│   ├── networking.nix         NetworkManager, firewall, avahi, wifi-resume hook
│   ├── audio.nix              pipewire, micmute-led daemon, udev rules
│   ├── desktop.nix            mango, greetd, portals, bluetooth, thunar, polkit, PAM
│   ├── fonts.nix              nerd fonts + fontconfig defaults
│   ├── power.nix              TLP, thresholds, zram, suspend hooks, corectrl
│   ├── printing.nix           CUPS + sane
│   ├── virtualisation.nix     podman, libvirt, steam, gamescope
│   └── nix-settings.nix       flakes, GC, substituters
├── modules/home/              home-manager (user-level)
│   ├── default.nix            imports + user units (wlsunset, swaync mask), xdg.mimeApps
│   ├── options.nix            `local.checkout` — the path this repo lives at
│   ├── packages.nix           every user package. THE list
│   ├── shell.nix              zsh, aliases, PATH, env, git
│   ├── theme.nix              GTK + dconf + Qt theming (owned by Nix, not scripts)
│   └── dotfiles.nix           what gets linked into ~/.config, and how
├── home/                      the dotfiles themselves
│   ├── mango/                 compositor: modes, waybar, walker, wlogout, scripts
│   ├── nvim/ helix/ zed/      editors
│   ├── kitty/ foot/ ghostty/  terminals
│   ├── zsh/conf.d/            shell options, aliases, PATH, prompt
│   ├── scripts/               → ~/.scripts (extensionless bash)
│   └── …                      yazi, lazygit, htop, imv, bottom, glow, …
├── pkgs/default.nix           the overlay — package overrides and local packages
├── verify-packages.sh         checks the closure still evaluates
└── docs/                      this file, ADRs, work log, migration archive
```

**Do not move `flake.nix` down a level.** With it at the root, `home/` is
inside the flake and reachable by relative path — which is the only reason
dotfiles can be store-based at all. See `docs/adr/0001`.

---

## 4. The change loop

Every change follows the same shape: **edit the repo → rebuild → reload.**

### Commands

All defined as zsh aliases in `modules/home/shell.nix`:

| Alias | Does | When |
|---|---|---|
| `rebuild` | `nixos-rebuild switch` | Normal changes |
| `rebuild-test` | `nixos-rebuild test` | **Anything structural.** Applies now but does not touch the boot default — a mistake is one reboot from gone |
| `rebuild-boot` | `nixos-rebuild boot` | Apply at next boot only |
| `update` | `nix flake update` | Deliberately move the pinned inputs |
| `generations` | `nixos-rebuild list-generations` | See what you can roll back to |
| `gc` | `nix-collect-garbage --delete-older-than 30d` | Reclaim store space |
| `search` | `nix search nixpkgs` | Find a package name |

**Always quote the flake ref if you type it by hand.** zsh runs with
`EXTENDED_GLOB`, which makes `#` a pattern operator, so an unquoted
`~/src/nix-config#thinkpad` is parsed as a glob, matches nothing, and dies with
`zsh: no matches found:` before `nixos-rebuild` ever runs. It reads like a
broken path. The aliases already quote it.

### Rolling back

Generations are numbered and every `switch` makes one:

```
generations                      # list them
sudo nixos-rebuild switch --rollback   # previous generation
```

Or pick a specific one from the systemd-boot menu at boot. Currently ~20
generations exist, all from 2026-07-29 onward.

⚠️ **`rebuild-test` does not create a generation.** It activates without a GC
root, so a later `gc` can delete exactly the store path the running system is
using. Use `test` to try things; follow with `switch` once satisfied.

### Reloading, per component

Rebuilding is not always enough — most desktop pieces need a nudge:

| Changed | Apply with |
|---|---|
| Anything under `home/mango/` | `rebuild`, **then** `~/.config/mango/scripts/reload.sh` |
| Waybar config/CSS | `rebuild`, then `~/.config/mango/scripts/waybar/waybar-restart.sh` |
| zsh config | `source ~/.config/zsh/conf.d/<file>.zsh`, or a new shell |
| kitty | `kill -SIGUSR1 $KITTY_PID`, or Ctrl+Shift+F5 |
| foot | Restart the terminal — no live reload |
| Neovim plugins | `:Lazy sync` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |
| Desktop mode | `~/.config/mango/scripts/modes/<mode>.sh` |
| `autostart.conf` | **Log out and back in** — `exec-once` only fires at compositor startup |

**`home/mango/` needs a rebuild now.** It became a store path on 2026-07-30, so
editing the repo no longer takes effect immediately the way it did when it was
a live symlink. This catches everyone once.

**Never `sudo` the mango scripts.** Under sudo `~` is `/root`, so they fail with
what looks like a broken install, and leave a root-owned elephant process your
own `pkill` cannot kill. `reload.sh` refuses to run as root.

---

## 5. Where do I change X?

The routing table. Find the row, edit the file, apply as in §4.

### System

| Want to change | Edit |
|---|---|
| Install/remove a package | `modules/home/packages.nix` (user) or `modules/system/*.nix` (`environment.systemPackages`) |
| A systemd service | `modules/system/<concern>.nix` — **never** `/etc/systemd/` |
| Kernel or boot params | `modules/system/boot.nix` |
| Battery charge thresholds | `modules/system/power.nix` (`services.tlp`) — **and** `full-at` in `waybar/config-focus.jsonc` |
| Timezone, keymap, keyd | `modules/system/locale.nix` |
| Firewall ports | `modules/system/networking.nix` |
| Fonts | `modules/system/fonts.nix` |
| Printer / scanner | `modules/system/printing.nix` |
| VMs, containers, Steam | `modules/system/virtualisation.nix` |

### User environment

| Want to change | Edit |
|---|---|
| Shell aliases | `home/zsh/conf.d/10-aliases.zsh` |
| Shell options | `home/zsh/conf.d/00-options.zsh` |
| `$PATH`, `$EDITOR` | `modules/home/shell.nix` |
| Default applications | `home/mimeapps.list` |
| GTK/Qt theme, icons, cursor | `modules/home/theme.nix` |
| Which dotfiles get linked | `modules/home/dotfiles.nix` |
| Language servers | `modules/home/packages.nix` — shared by nvim **and** helix |

### Desktop

| Want to change | Edit |
|---|---|
| Keybinds | `home/mango/universal/bind.conf` (all modes) or `bind-tiling-hud.conf` |
| Window rules | `home/mango/universal/rule.conf` |
| Per-workspace layout | `home/mango/universal/tag.conf` |
| Startup programs | `home/mango/universal/autostart.conf`, or the per-mode one |
| Waybar modules | `home/mango/waybar/config*.jsonc` (one per layout) |
| Waybar appearance | `home/mango/waybar/style*.css` + `colors.css` |
| Session menu | `home/mango/wlogout/` |
| Launcher entries | `home/mango/walker/configs/`, `home/mango/fsel/config.toml` |
| Wallpaper | `~/.local/share/mango/wallpaper.png` — **not** in the repo |

---

## 6. How dotfiles are linked

`modules/home/dotfiles.nix` is deliberately **mixed**. Which side an entry
falls on is decided by one question:

> *Does a running program rewrite a file that is tracked in this repo?*

### Store-based — `source = ../../home/X`

Reproducible. A fresh clone plus a rebuild reproduces it exactly, and
`~/.config/X` stops depending on this checkout existing at all. The files are
**read-only**, so changes require a rebuild.

Currently: `mango`, `nvim`, `helix`, `kitty`, `foot`, `ghostty`, `zsh/conf.d`,
`yazi`, `bottom`, `lazygit`, `glow`, `imv`, `~/.scripts`.

`mango` and `nvim` got here by **moving the writer** rather than accepting a
mutable directory — nvim's `lazy-lock.json` moved to `stdpath("state")`, and
mango's runtime state moved to `~/.local/state/mango/`. That is the general
technique.

### File-level — `xdg.configFile."X/config".source`

The one to reach for first. Home-manager links a *directory*-valued source as
one symlink, but a *file*-valued one as a real directory containing a file
symlink — so the config is read-only in the store while the directory stays
writable for sibling runtime files.

Currently: `htop`, `ncspot`, `zed`, `Kvantum`, `nwg-look`. The cost is that
these can no longer be configured from inside the app.

### Out-of-store — `mkOutOfStoreSymlink`

A live symlink into this checkout: edits take effect with no rebuild, but a
fresh clone gets a symlink pointing at nothing.

Currently **`corectrl` only** — it writes its own `.ini` and profiles from its
GUI, and that GUI is the entire point of the tool.

### Two traps

⚠️ **`recursive = true` can destroy the repo.** It creates files *inside*
`~/.config/X` rather than one symlink. If `~/.config/X` is already an
out-of-store symlink into the checkout, those writes follow it in — converting
`mango` this way replaced 65 tracked files with self-referential symlinks.
Delete `~/.config/X` first so home-manager builds a fresh directory.

⚠️ **The link source must be outside `~/.config`**, because
`xdg.configFile.<name>` writes *to* `~/.config/<name>`. That is why this repo
lives at `~/src/nix-config` and not at `~/.config` as it did under Arch.

---

## 7. The desktop

### Mangowm

A Wayland compositor in the dwl/dwm lineage: tags (workspaces), a master/stack
layout, keyboard-driven. Config lives in `home/mango/`, split into:

- **`universal/`** — shared across modes: binds, window rules, tags, settings, autostart
- **`tiling/`, `hud/`** — per-mode compositor config and autostart

**`config.conf` is generated, not authored.** A mode script copies
`tiling/tiling.conf` or `hud/hud.conf` over it verbatim; that copy is what mango
reads, and it `source=`s every keybind, rule and autostart file. It is
gitignored because tracking it would mean committing a duplicate that changes
on every mode switch.

> **Fresh clone:** there is no `config.conf`, so mango starts on built-in
> defaults — no waybar, no keybinds — until you run
> `~/.config/mango/scripts/modes/tiling.sh` once and log back in.

### Modes and layouts

Three independent switches, all on the `/` key:

| | Options | Bind | State file |
|---|---|---|---|
| **Desktop mode** | `tiling`, `hud` | `SUPER+CTRL+/` | `~/.local/state/mango/current-mode` |
| **Waybar layout** | `full`, `focus`, `minimal` | `SUPER+/` | `~/.local/state/mango/waybar-layout` |
| **Waybar position** | `top`, `bottom` | `SUPER+SHIFT+/` | `~/.local/state/mango/waybar-position` |

Mode selects the compositor config, autostart set and waybar stylesheet
(`tiling` → `style-solid.css`, otherwise `style.css`). Layout selects which
waybar modules are shown. Position moves the bar between screen edges.

The first two open a walker picker; position is a **straight toggle**, since
with two options a menu costs more keystrokes than the thing it selects.
`waybar-position.sh` also accepts an explicit `top`/`bottom` argument for
scripting.

All three are read by **`scripts/waybar/waybar-restart.sh`**, which is the only
place that knows how they combine — so login, mode switch, layout switch,
position toggle and `reload_config` all land on the same result.

> **How position actually works:** waybar takes only `-c`, `-s` and `-b` on the
> command line — `position` is a config key with no flag. The layout configs are
> read-only store paths, so `waybar-restart.sh` rewrites `position` (and mirrors
> the vertical margins) into a generated copy at
> `~/.local/state/mango/waybar-config.jsonc`. The margin mirroring is not
> cosmetic: the hud layout uses `"margin-bottom": -28` against a 28px bar to
> cancel its exclusive zone, and that has to move edges with the bar.
>
> Styling follows automatically — waybar adds its position as a CSS class on the
> window, so `window#waybar.bottom` in `style-solid.css` moves the separator
> line to the top edge.

> Only the `focus` layout carries `"full-at": 85` on the battery module, so it
> rescales the percentage to your charge limit. The other layouts show the raw
> value — the number changes when you switch layout, and that is expected.

### Keybinds

`SUPER` is the modifier throughout.

**Launching**

| Key | Action |
|---|---|
| `SUPER+Return` | foot (terminal) |
| `SUPER+SHIFT+Return` | kitty |
| `SUPER+Space` | fsel — the main launcher |
| `SUPER+W` | walker provider list (all menus) |
| `SUPER+B` | Zen browser |
| `SUPER+E` | Thunar |
| `SUPER+V` | Clipboard history |
| `SUPER+P` | Bitwarden |
| `SUPER+CTRL+O` | Obsidian notes |
| `SUPER+CTRL+N` / `+V` / `+B` | Network / VPN / Bluetooth menu |

**Windows**

| Key | Action |
|---|---|
| `SUPER+Q` | Close window |
| `SUPER+H/J/K/L` | Focus left/down/up/right |
| `SUPER+SHIFT+H/J/K/L` | Swap window in that direction |
| `SUPER+Tab` / `SUPER+SHIFT+Tab` | Next / previous in stack |
| `ALT+Tab` | Overview |
| `SUPER+F` / `SUPER+SHIFT+F` | Fullscreen / fake fullscreen |
| `SUPER+A` | Maximise to screen |
| `SUPER+SHIFT+O` | Toggle floating |
| `SUPER+I` / `SUPER+SHIFT+I` | Minimise / restore |
| `SUPER+G` | Toggle global (sticky) |
| `ALT+Z` | Scratchpad |
| `SUPER+[` / `SUPER+]` | Spotify / Equibop scratchpad |
| `CTRL+SHIFT+H/J/K/L` | Move a floating window |
| `CTRL+ALT+H/J/K/L` | Resize a floating window |

**Workspaces (tags)**

| Key | Action |
|---|---|
| `SUPER+1…9` | Go to tag |
| `SUPER+SHIFT+1…9` | Move window to tag and follow |
| `SUPER+CTRL+SHIFT+1…9` | Move window to tag silently |
| `SUPER+CTRL+H` / `+L` | Previous / next tag |
| `SUPER+ALT+H` / `+L` | Move window to previous / next tag |

Tags 7 and 9 default to `monocle`; the rest are `tile` (`universal/tag.conf`).

**Layout**

| Key | Action |
|---|---|
| `SUPER+N` | Cycle layout |
| `SUPER+CTRL+Return` | Zoom (promote to master) |
| `SUPER+CTRL+K` / `+J` | More / fewer master windows |
| `SUPER+CTRL+,` / `+.` | Shrink / grow master area |
| `SUPER+SHIFT+X` / `+Z` | More / fewer gaps |
| `SUPER+SHIFT+R` | Toggle gaps |
| `SUPER+X` | Cycle proportion preset |

**System**

| Key | Action |
|---|---|
| `SUPER+R` | Reload mango config |
| `SUPER+/` / `SUPER+CTRL+/` | Waybar layout / desktop mode picker |
| `SUPER+SHIFT+/` | Toggle waybar between top and bottom |
| `SUPER+SHIFT+S` | Lock screen |
| `SUPER+SHIFT+P` | Cycle ACPI power profile |
| `Print` / `CTRL+Print` | Region screenshot / full screen to clipboard |
| `CTRL+ALT+\` / `+Backspace` | Notification panel / clear all |
| `SUPER+SHIFT+CTRL+M` | Quit the compositor |
| Media & brightness keys | Volume, playback, backlight (via wpctl / playerctl / brightnessctl) |

### Waybar

Status bar, four layout files in `home/mango/waybar/`. Notable custom modules —
each is a script under `home/mango/scripts/`, so if one is missing from the bar,
**run its script by hand first**:

| Module | Script | Refresh signal |
|---|---|---|
| `custom/window` | `waybar/window-title.sh` | streams `mmsg watch focusing-client` |
| `custom/power-profile` | `system/power-profile.sh` | `RTMIN+11` |
| `custom/night-mode` | `menus/night-mode.sh` | `RTMIN+9` |
| `custom/phone` | `kdeconnect/phone-status.sh` | 30 s |
| `custom/power` | — opens wlogout | — |

> **Do not reintroduce waybar's built-in `dwl/window` module.** mango 0.15.5
> dropped the dwl IPC protocol it binds to, and its absence makes waybar
> segfault at startup. `custom/window` exists for this reason.

### The rest of the stack

| Piece | Role |
|---|---|
| **fsel** | Primary launcher (`SUPER+Space`), floating foot terminal pinned right |
| **walker** | Structured menus — bluetooth, clipboard, bitwarden, mode pickers |
| **elephant** | Widget/provider backend behind walker |
| **rofi** | Secondary menus |
| **swaync** | Notifications. Started from `autostart.conf`, **not** systemd — the nixpkgs unit is masked |
| **awww** | Wallpaper daemon (the swww fork; the binary is `awww`) |
| **wlsunset** | Night light, owned by a systemd user unit |
| **wlogout** | Session menu behind the waybar power icon |
| **swaylock** | Screen lock. Needs the hand-declared PAM service in `desktop.nix` |
| **KDE Connect** | Phone integration; `kdeconnectd` from autostart |

---

## 8. Shell, terminals, editors

**zsh is the login shell.** Configured from `~/.config/zsh/conf.d/*.zsh` via
`ZDOTDIR`; `programs.zsh` in `modules/home/shell.nix` owns `~/.zshrc`, the
plugins and history, and sources `conf.d/*.zsh` at the end — so `conf.d`
deliberately wins over home-manager's defaults. **Fish is gone.**

Aliases worth knowing: `cat`→`bat`, `ls`/`ll`/`la`→`eza`, `lf`→`yazi`,
`zed`→`zeditor`, `z` for zoxide jumping. In `~` only, bare `ls` hides a fixed
list of clutter directories; `ll`/`la` are the unfiltered escape hatches.

**Terminals:** foot (default, `SUPER+Return`), kitty, ghostty. All Gruvbox Dark,
Hack Nerd Font Mono 11. Each names its theme file directly — there is no
`active-theme` indirection any more, and reintroducing one would block those
directories from being store paths.

**Editors:** Neovim is `$EDITOR`/`$VISUAL`, so it is what git, `sudoedit`,
`systemctl edit`, lazygit and yazi all open. It is a hand-rolled lazy.nvim
config (~18 plugins) — see `home/nvim/README.md`. Helix is installed as a
second option; **its binary is `hx`, not `helix`**.

⚠️ **Neither ships language servers.** There is no mason; both take servers from
`$PATH`, so every server must be declared in `modules/home/packages.nix`. A
missing server is skipped in **silence**. `hx --health` is the fastest audit —
one line per language, `✘` against anything it cannot find. See
`docs/adr/0007`.

---

## 9. Hardware behaviour

Three things look like faults and are not.

### Battery stops below 100%

TLP sets EC thresholds **START 40 / STOP 85** (`modules/system/power.nix`). On
AC the battery parks wherever it is and only tops up below 40%. `status` then
reads `Not charging`, which waybar renders as a **plug** icon rather than a
lightning bolt. A plug with a static sub-100% reading is the hysteresis
working.

Raising STOP does not trigger a charge — the EC only starts below START. To
force one: `sudo tlp setcharge 84 85 BAT0`.

> `upower -i` reports `charge-start-threshold: 75%` regardless of the real
> value. Trust `/sys/class/power_supply/BAT0/charge_control_*_threshold`.

> **Coupled setting:** STOP must match `"full-at"` in
> `waybar/config-focus.jsonc`. Waybar computes `shown = real / full-at × 100`,
> so a mismatch makes the displayed percentage wrong. Change one, change the
> other.

### Suspend leaves the screen lit

The firmware exposes only **s2idle** (`/sys/power/mem_sleep` → `[s2idle]`), not
S3 — so `mem_sleep_default=deep` would achieve nothing. S3 cut power to the
panel in hardware; under s2idle software must do it, and nothing did.

Fixed with `powerManagement.powerDownCommands`/`resumeCommands` in `power.nix`,
which drive the backlight directly. Note **`brightnessctl set 0` is not enough**
— on amdgpu that is the panel's minimum, not off. The hooks also write
`/sys/class/backlight/amdgpu_bl1/bl_power` (4 = power down, 0 = unblank), and
must clear `bl_power` *before* restoring brightness or the panel stays dark.

> **Why not `wlopm` or DPMS:** mango advertises **no `wl_output` global at
> all**. Every output-enumerating client sees nothing — `wlopm --json` returns
> `[]`, `wlr-randr` prints nothing, `mmsg get all-monitors` returns an empty
> list — while the compositor happily reports `eDP-1` elsewhere. The backlight
> is used precisely because it needs no compositor connection. `wlopm` is
> deliberately not installed.

There is no idle daemon, so the screen never blanks on idle either.

### WiFi dies after resume

The `ath11k_pci` driver does not cleanly reinitialise on resume; NM retries but
DHCP times out. Two independent layers fix it, and both are needed:

- **TLP** disables WiFi power saving on AC and battery — covers normal runtime
- **`systemd.services.wifi-resume`** cycles the radio 3 s after wake — this is
  what actually fixes the resume failure

Both are declarative (`networking.nix`, `power.nix`). If it recurs, check
`journalctl -u NetworkManager` for a DHCP timeout after wake.

### VPN — autoconnect is off, deliberately

Nine profiles (`homelab` WireGuard + 8 PIA OpenVPN exits) all came off the
backup with `autoconnect=yes`. **All nine were turned off. Do not turn them back
on.** `homelab` auto-activated, claimed the default route, and pushed DNS
`192.168.1.5` onto every link — so away from the home LAN, *all* name
resolution failed. Nothing identifies itself as a VPN problem at that point; it
presents as total DNS death.

Bring it up by hand when away from home: `nmcli connection up homelab`. On
`192.168.1.0/24` the Gitea host (`192.168.1.200`) is reachable directly and the
tunnel is not involved.

---

## 10. Services inventory

What is running, and who owns it.

**System units (declared in `modules/system/`)**

| Service | Purpose |
|---|---|
| `greetd` + tuigreet | Login, launches mango |
| `NetworkManager` | Networking (**not** networkd) |
| `systemd-resolved` | DNS |
| `avahi` | mDNS, for CUPS printer discovery |
| `tlp` | Power tuning + battery thresholds |
| `thermald`, `fwupd`, `upower` | Thermals, firmware updates, battery reporting |
| `pipewire` (+ pulse/jack) | Audio. PulseAudio proper is off |
| `cups` + `sane` | Brother MFC-L3740CDW, driverless IPP |
| `bluetooth` + blueman | Bluetooth |
| `udisks2`, `gvfs`, `tumbler` | Removable media, thumbnails |
| `snapper` | `/home` timeline snapshots — 5 hourly, 7 daily, 4 weekly, 2 monthly |
| `wifi-resume` | The resume fix above |
| `tor` | Client mode, enabled in `networking.nix` |
| `podman`, `libvirtd` | Containers and VMs |

**User units**

| Unit | Purpose |
|---|---|
| `polkit-gnome-authentication-agent-1` | Polkit prompts (the `lxpolkit` autostart line is a dead Arch leftover) |
| `wlsunset` | Night light — reads its temperature from `~/.local/state/mango/night-temp` |
| `micmute-led` | Syncs the mic-mute LED with PipeWire |
| `nextcloud-client` | Cloud sync |
| `swaync.service` | **Masked** — autostart owns swaync instead |

⚠️ **One owner per daemon.** nixpkgs packages ship user units that Arch's did
not, and they auto-start. swaync raced its own autostart line for a week
before anyone noticed. When adding a package with a daemon, check
`ls $(nix eval --raw nixpkgs#foo)/share/systemd/user/` before assuming
autostart is the only owner. See `docs/adr/0005`.

⚠️ **`Restart=` without `StartLimitBurst=` is a loaded gun.** A misconfigured
rclone unit retried every 5 s until Proton returned an account-level abuse
restriction — the damage landed on the account, not the machine. Any unit that
talks to a remote API needs a start limit. See `docs/adr/0006`.

---

## 11. What is *not* in this repo

The flake reproduces the system. It does **not** reproduce your data. These
live only on `@home` or in root-owned system directories, survived the
migration by luck of the shared subvolume, and need separate backup:

| What | Where | Size |
|---|---|---|
| Zen browser profile | `~/.config/zen/` | **859 MB** — 13 extensions, logins, history |
| NetworkManager profiles | `/etc/NetworkManager/system-connections` | 37 connections, root-only, mode 600 |
| Bluetooth pairings | `/var/lib/bluetooth` | 7 devices |
| Wallpaper | `~/.local/share/mango/wallpaper.png` | 4.6 MB |
| Runtime state | `~/.local/state/mango/` | incl. `pia-auth` (mode 600) |
| CLI credentials | `~/.config/{gh,glab-cli,gpu-screen-recorder,opencode}` | gitignored by name |
| corectrl profiles | `~/.config/corectrl/` | written by its GUI |

Snapper covers `/home` against accidental deletion, but snapshots are on the
same disk — they are not a backup.

> **Zen note:** there are two profiles in `~/.config/zen/` and only one is real
> (`kxsz4wom.Default (release)`, 839 MB). Which is default is selected
> per-installation by executable path, and that path became a store path at the
> migration — so Zen fell back to the legacy `Default=1` flag, which sat on the
> empty profile. Fixed by moving `Default=1` onto `[Profile0]`. **Do not "fix"
> it by adding an `[Install<hash>]` entry** — the store path changes on every
> Zen update, which would orphan the setting again.

---

## 12. Troubleshooting

Nearly every problem on this system fails **silently**. The catalogue:

| Symptom | Likely cause | Check |
|---|---|---|
| A waybar module is missing from the bar | Its script exited 127, or emitted an empty `text` | Run the script by hand. An empty custom module is indistinguishable from an absent one |
| `bad interpreter`, exit 127 | `#!/bin/bash` — **there is no `/bin/bash`**, `/bin` holds only `sh` | Use `#!/usr/bin/env bash` |
| A mango script "succeeds" but does nothing | Old dwl-era `mmsg -s -d` flags. `mmsg` takes verbs (`get`, `dispatch`, `watch`) and returns `{"error":...}` **with exit 0** | `mmsg dispatch <func>`, and check the output |
| Icons render as empty boxes | The font lacks that codepoint, or a CSS `url()` failed — GTK draws its missing-image box **without logging** | `fc-list ':charset=XXXX' family` |
| An icon is off-centre in its cell | Container wider than its content, filled from one end — glyph advance vs ink, or `min-width` vs `icon-size` | Compare the two numbers |
| Duplicate/leaked daemon processes | `pkill -x` against a nixpkgs wrapper — `comm` is `.elephant-wrapp` (truncated at 15 chars), not `elephant` | `pkill -f 'bin/elephant$'` |
| A user unit misbehaves in an Arch-like way | `~/.config/systemd/user/` shadows `/etc/systemd/user/` | Now clean — contains only home-manager symlinks. Keep it that way |
| Lock screen rejects the correct password | Missing `/etc/pam.d/swaylock` → PAM falls through to `other` = deny | `pam_warn(swaylock:auth)` in the journal. Declared in `desktop.nix` |
| Session blank after killing swaylock | `ext-session-lock-v1` **requires** the compositor to stay locked if the client dies. Not a bug | Relaunch swaylock on the same `WAYLAND_DISPLAY` and authenticate, or reboot |
| Total DNS failure | A VPN holding `Default Route: yes` and pushing an unreachable nameserver | `resolvectl status` |
| Rebuild aborts on a file conflict | Two packages owning the same path in `buildEnv` | `lib.hiPrio` on the **winner** — `lowPrio` on the loser silently does nothing when priorities are equal |
| A `/usr/share/...` path doesn't exist | `share/<pkgname>` is not in `environment.pathsToLink` | Vendor the asset and reference it relatively |

**General method:** run the failing thing by hand, in your own shell, and look
at both its output *and* its exit code. Almost every bug in this catalogue was
invisible in logs and reported as "X is missing".

---

## 13. Known rough edges

Things that are true today and worth knowing:

- **`scripts/desktop-mode.sh` reads the old state path.** It still resolves
  `current-mode` under `$MANGO_DIR/state`, which no longer exists — so the mode
  picker always marks `tiling` as current, even in hud mode. Harmless (the
  switch itself works, since `mode.sh` and the mode scripts use the new path),
  but the `•` is wrong. One-line fix.
- **Language servers are incomplete.** `pyright`, `ruff`, `texlab`, `tinymist`,
  `stylua`, `shfmt` and `clangd` are still undeclared. `hx --health` shows the
  gap.
- **Suspend blanking is fixed but only lightly exercised.** Confirm across a few
  more suspend cycles.
- **`~/.config/nvim.bak.*` and `~/.local/share/nvim.bak.*`** are still around
  from the Neovim rewrite and can be deleted once you're settled.
- **`mimeapps.list` still lists `librewolf.desktop`** entries; LibreWolf is not
  installed. Harmless, removable.

---

## 14. Further reading

| Document | Read it when |
|---|---|
| `CLAUDE.md` | Before changing anything — it records what has already failed |
| `docs/adr/0001` … `0008` | Before undoing something that looks redundant |
| `docs/WORK-LOG.md` | To see what the 30–31 July declarative pass covered |
| `docs/archive/MIGRATION.md` | History of the Arch→NixOS install. Not instructions |
| `home/nvim/README.md` | The Neovim config map |
| `docs/agents/` | Issue tracker (Gitea at `git.henrydowd.dev`) and agent conventions |

The ADRs are short and each records the failure that motivated the decision:

| ADR | Decision |
|---|---|
| 0001 | The flake sits at the repo root |
| 0002 | When a dotfile may be out-of-store |
| 0003 | Runtime state lives outside the config tree |
| 0004 | Nix owns GTK theming, not the mode scripts |
| 0005 | One owner per daemon |
| 0006 | Start limits on units that call remote APIs |
| 0007 | Language servers are declared, not discovered |
| 0008 | Arch was removed outright |
