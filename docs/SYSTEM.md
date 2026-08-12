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
| `docs/WORK-LOG.md` | What changed since 30 July 2026, and what did it cost? |

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
| RAM | 14 GiB. zram (zstd, 50%, priority 5) is the working swap; a 20 GiB btrfs swapfile on `@swap` exists only to hold a **hibernation** image |
| Display | eDP-1, 1920×1200 |
| WiFi | Qualcomm QCNFA765 (`wlp1s0`, `ath11k_pci`) |
| Compositor | Mangowm (Wayland) — the only desktop |
| Login | greetd + tuigreet on TTY, launching `mango` |

Installed 2026-07-29, migrating from Arch. **Arch is gone** — subvolumes, boot
entry and EFI residue were all deleted on 2026-07-30. There is no dual boot and
no fallback to it.

### Filesystem layout

One btrfs filesystem, five subvolumes, plus the EFI partition:

| Mount | Subvolume | Notes |
|---|---|---|
| `/` | `@nixos` | The system. Rebuilt, never hand-edited |
| `/nix` | `@nix` | The store. Separate so GC churn doesn't touch `/` snapshots |
| `/home` | `@home` | **Carried across from Arch untouched.** Snapshotted by snapper |
| `/var/log` | `@log` | Kept out of root snapshots |
| `/swap` | `@swap` | The 20 GiB hibernation swapfile. **Mounted without compression** |
| `/boot` | — | vfat ESP, 1 GB, shared with the (now removed) Arch entry |

All btrfs mounts use `compress=zstd:3`, `noatime`, `discard=async` — **except
`@swap`**, which must not be compressed. btrfs refuses a compressed swapfile
and `swapon` reports `Invalid argument`, which reads like file corruption
rather than a wrong mount option. See §9.

**`@home` is the important one.** It survived the migration in place, which is
why your browser profile, credentials and pairings are all still there — and
also why a large amount of live data is in **no repository**. See §11.

---

## 2. The mental model

Three layers, and almost every question is "which layer does this belong to?"

```
  ┌─────────────────────────────────────────────────────────────┐
  │ 1. THE FLAKE           ~/src/nix-config                      │
  │    Declares the system: packages, services, kernel, users —  │
  │    and now most of the dotfiles too, as Nix expressions.     │
  │    Changing it does nothing until you rebuild.               │
  └───────────────┬─────────────────────────────────────────────┘
                  │  nixos-rebuild switch
                  ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ 2. THE ACTIVATED SYSTEM   /run/current-system, /nix/store    │
  │    Read-only. /etc is generated. Home-manager GENERATES most │
  │    of ~/.config and links the rest in from the store.        │
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
│   ├── default.nix            imports, idle ladder, user units (wlsunset,
│   │                          poweralertd, swaync mask), xdg.mimeApps
│   ├── options.nix            `local.checkout` — the path this repo lives at
│   ├── packages.nix           user packages that no program module installs
│   ├── shell.nix              zsh, aliases, PATH, env, git
│   ├── programs.nix           GENERATED configs: kitty, foot, helix, zed, htop,
│   │                          yazi, ncspot, imv, wlogout. No files in dotfiles/ for these
│   ├── waybar.nix             GENERATED: the four waybar layouts, from one set
│   │                          of module definitions
│   ├── theme.nix              GTK + dconf + Qt theming (owned by Nix, not scripts)
│   └── dotfiles.nix           what is still a hand-written FILE, and how it is linked
├── dotfiles/                  the hand-written dotfiles that remain
│   ├── mango/                 compositor: modes, waybar CSS, walker, fsel, scripts
│   ├── nvim/                  the one large hand-rolled config (~22 files, lazy.nvim)
│   ├── swaync/ glow/ fsel/    apps with no module, or whose module is not adopted
│   ├── elephant/              bitwarden.toml; menus.toml is generated (ADR 0014)
│   ├── zsh/conf.d/            shell options, aliases, PATH, prompt
│   ├── scripts/               → ~/.scripts (extensionless bash)
│   ├── Kvantum/ nwg-look/ gtk-3.0/ gtk-4.0/   file-level entries + theme assets
│   ├── helix/ yazi/ wlogout/  ASSETS ONLY — theme, flavor and icons referenced
│   │                          by programs.nix. No config files here
│   └── corectrl/              the single out-of-store entry
├── pkgs/default.nix           the overlay — package overrides and local packages
├── statix.toml                lint config — `repeated_keys` is off, see the file
├── .envrc                     `use flake`; needs direnv, otherwise `nix develop`
├── verify-claims.sh           re-checks the assertions CLAUDE.md makes about the system
└── docs/                      this file, ADRs, work log, migration archive
```

**`dotfiles/` is shrinking by design.** Most configs are now generated by
`modules/home/programs.nix` and have no file here at all — `dotfiles/kitty/`,
`dotfiles/foot/`, `dotfiles/zed/`, `home/htop/`, `dotfiles/ncspot/`, `dotfiles/imv/` and
`dotfiles/ghostty/` were all deleted on 2026-08-01. If you go looking for a config
file and it is not in `dotfiles/`, it is generated: grep `modules/home/`. See §6.

**Do not move `flake.nix` down a level.** With it at the root, `dotfiles/` is
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
| `waybar-reload` | Restart waybar from the current state | After a `rebuild` that touched the bar |
| `mango-reload` | Re-apply the mode, dispatch `reload_config`, restart elephant | After a `rebuild` that touched keybinds, rules or autostart |

The mango scripts are not on `$PATH` — `~/.scripts` is, `~/.config/mango/scripts`
is not, and putting it there would drop 28 files with names like `mode.sh` into
command completion. The two that get typed by hand are aliased instead.

⚠️ Neither reload alias picks up repo edits on its own. `~/.config/mango` is a
store path, so **`rebuild` first, reload second** — running only the reload
restarts the bar against the config it already had, which looks exactly like the
change having no effect.

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
| Anything under `dotfiles/mango/` | `rebuild`, **then** `mango-reload` |
| Waybar layouts (`modules/home/waybar.nix`) or CSS | `rebuild`, then `waybar-reload` |
| kitty | `rebuild`, then `kill -SIGUSR1 $KITTY_PID` or Ctrl+Shift+F5 |
| foot | `rebuild`, then restart the terminal — no live reload |
| helix, zed, htop, ncspot, imv, yazi | `rebuild`, then restart the app |
| wlogout | `rebuild` only — it is spawned fresh on each invocation |
| zsh config | `source ~/.config/zsh/conf.d/<file>.zsh`, or a new shell |
| Neovim plugins | `:Lazy sync` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |
| Desktop mode | `~/.config/mango/scripts/modes/<mode>.sh` |
| `autostart.conf` | **Log out and back in** — `exec-once` only fires at compositor startup |

⚠️ **Almost nothing is live-editable any more, and this catches everyone once.**
`dotfiles/mango/` became a store path on 2026-07-30, and on 2026-08-01 the nine
programs above stopped having a file in this repo at all — they are generated
from Nix. So "edit the dotfile and reload" no longer works in either case:
there is nothing to edit for the generated ones, and the store copy of the
others does not change until you rebuild. **Reloading without rebuilding first
looks exactly like the change having had no effect.**

`corectrl` is the only entry where an edit is still live without a rebuild.

**Never `sudo` the mango scripts.** Under sudo `~` is `/root`, so they fail with
what looks like a broken install, and leave a root-owned elephant process your
own `pkill` cannot kill. `reload.sh` refuses to run as root.

---

## 5. Where do I change X?

The routing table. Find the row, edit the file, apply as in §4.

### System

| Want to change | Edit |
|---|---|
| Install/remove a package | `modules/home/packages.nix` (user) or `modules/system/*.nix` (`environment.systemPackages`). **Not** for the nine in `programs.nix` — their module installs the package too |
| A systemd service | `modules/system/<concern>.nix` — **never** `/etc/systemd/` |
| Kernel or boot params | `modules/system/boot.nix` |
| Battery charge thresholds | `modules/system/power.nix` (`services.tlp`) — the waybar `full-at` follows automatically, see §9 |
| Hibernation, lid and power key | `modules/system/power.nix` (`services.logind`) — no `systemd.sleep`, there is no suspend phase to configure |
| When the machine dims, locks or idle-sleeps | `modules/home/default.nix` (`services.swayidle.timeouts`) |
| What a dying battery does | `modules/system/power.nix` (`services.upower`) — not logind |
| Timezone, keymap, keyd | `modules/system/locale.nix` |
| Firewall ports | `modules/system/networking.nix` |
| Fonts | `modules/system/fonts.nix` |
| Printer / scanner | `modules/system/printing.nix` |
| VMs, containers, Steam | `modules/system/virtualisation.nix` |

### User environment

| Want to change | Edit |
|---|---|
| Shell aliases | `dotfiles/zsh/conf.d/10-aliases.zsh` |
| Shell options | `dotfiles/zsh/conf.d/00-options.zsh` |
| `$PATH`, `$EDITOR` | `modules/home/shell.nix` |
| Default applications | `modules/home/default.nix` (`xdg.mimeApps`) — there is no `mimeapps.list` in this repo |
| Terminal colours | `modules/home/programs.nix` — one `gruvbox` `let` binding feeds both kitty and foot |
| kitty, foot, helix, zed, htop, yazi, ncspot, imv, wlogout | `modules/home/programs.nix` — generated, no file to edit |
| Helix colour scheme | `dotfiles/helix/themes/gruvbox.toml` — the one helix file that is still data |
| GTK/Qt theme, icons, cursor | `modules/home/theme.nix` |
| Which hand-written dotfiles get linked | `modules/home/dotfiles.nix` |
| Language servers | `modules/home/packages.nix` — shared by nvim **and** helix |

### Desktop

| Want to change | Edit |
|---|---|
| Keybinds | `dotfiles/mango/universal/bind.conf` (all modes) or `bind-tiling-hud.conf` |
| Window rules | `dotfiles/mango/universal/rule.conf` |
| Per-workspace layout | `dotfiles/mango/universal/tag.conf` |
| Startup programs | `dotfiles/mango/universal/autostart.conf`, or the per-mode one |
| Waybar modules | `modules/home/waybar.nix` — **generated.** There are no `config*.jsonc` files in this repo |
| Waybar appearance | `dotfiles/mango/waybar/style*.css` + `colors.css` — still hand-written |
| Session menu | `modules/home/programs.nix` (`programs.wlogout`); `dotfiles/wlogout/` holds only the six PNGs. **Adding an entry means bumping `-b` in the waybar `custom/power` on-click too** |
| When the screen locks | `modules/home/default.nix` (`services.swayidle`) |
| Launcher entries | `dotfiles/mango/walker/configs/`, `dotfiles/mango/fsel/config.toml` |
| Wallpaper | `~/.local/share/mango/wallpaper.png` — **not** in the repo |

---

## 6. How configuration reaches `~/.config`

**There are three tiers, not two.** The 2026-08-01 pass moved most of the repo
into the first one, so a lot of what used to be a "dotfile" is now a Nix
expression with no file behind it. The tiers, best first:

### Tier 1 — GENERATED, by a native home-manager module

`modules/home/programs.nix` and `modules/home/waybar.nix`. Nix produces the
file from typed options; **there is no config file in this repo at all.**

| What | Module |
|---|---|
| kitty, foot | `programs.kitty`, `programs.foot` — both fed by one shared `gruvbox` palette |
| helix | `programs.helix` (the theme stays a file — see below) |
| zed | `programs.zed-editor` |
| htop, ncspot, imv, yazi | `programs.htop`, `programs.ncspot`, `programs.imv`, `programs.yazi` |
| wlogout | `programs.wlogout` |
| swaylock | `programs.swaylock` — **`package = null`**, see §9 |
| The four waybar layouts | `modules/home/waybar.nix` |

This is where a config should end up unless there is a reason it cannot. The
argument is not tidiness:

- **Typos become build failures.** This repo's signature bug is config that is
  wrong in a way *nothing reports* — the dead `mmsg -s -d` flags, empty
  `custom/*` modules, `appid:zen` matching nothing, six silently missing
  language servers. Typed options are the only mechanism here that turns that
  class of mistake into an error you cannot miss. `waybar.nix` goes further and
  asserts on a module name with no definition.
- **One owner for the package and its config.** `programs.kitty.enable`
  installs the package *and* writes the config, so removing it removes both.
  Previously `kitty` was in `packages.nix` while `kitty/` was in
  `dotfiles.nix`, with nothing tying them together.
- **Values can be shared.** The Gruvbox palette is one `let` binding instead of
  sixteen hex codes transcribed into two files with nothing keeping them in
  step. Likewise waybar's `full-at` is *read from* the TLP threshold rather
  than copied.

### Tier 2 — store-based, `source = ../../dotfiles/X`

The file stays hand-written but lands read-only in the store. Reproducible;
`~/.config/X` stops depending on this checkout existing. Changes need a
rebuild.

Currently: `mango` (with `recursive = true`), `nvim`, `swaync`, `glow`, `fsel`,
`zsh/conf.d`, and `~/.scripts` — plus the file-level entries `Kvantum`,
`nwg-look`, `elephant/{menus,bitwarden}.toml` and the `gtk-3.0`/`gtk-4.0`
assets.

> **`elephant/menus.toml` is generated, not linked.** It names an absolute path
> into the mango tree, which must be derived from `config.xdg.configHome`
> rather than carry a hardcoded `/home/henry` — so it uses `.text`. It is the
> only thing connecting elephant to `mango/elephant/menus/`, and until
> 2026-08-09 it was hand-written and in no repo. See ADR 0014.

> **File-level is a variant of this tier, not a separate one.**
> `xdg.configFile."X/config".source` pins the *file* read-only while leaving
> the *directory* writable for sibling runtime files — home-manager links a
> directory-valued source as one symlink, but a file-valued one as a real
> directory containing a file symlink. `htop`, `ncspot` and `zed` used to need
> this; their native modules now do exactly the same thing internally, so it
> became upstream's problem. What is left is `Kvantum`, `nwg-look` and the GTK
> asset directories.

`mango` and `nvim` reached this tier by **moving the writer** rather than
accepting a mutable directory — nvim's `lazy-lock.json` moved to
`stdpath("state")`, and mango's runtime state to `~/.local/state/mango/`. That
is the general technique.

### Tier 3 — out-of-store, `mkOutOfStoreSymlink`

A live symlink into this checkout: edits take effect with no rebuild, but a
fresh clone gets a symlink pointing at nothing.

Currently **`corectrl` only** — it writes its own `.ini` and profiles from its
GUI, and that GUI is the entire point of the tool. This is what an honest
out-of-store entry looks like: not "not converted yet", but "converting it
would remove functionality".

### Assets — a fourth thing that is not a tier

`dotfiles/helix/`, `dotfiles/yazi/` and `dotfiles/wlogout/` still exist but contain **no
config**. They hold data a *generated* config points at: helix's 264-line
`themes/gruvbox.toml`, yazi's `noctalia.yazi` flavor, and wlogout's six PNGs.
`programs.nix` references them by relative path, so they end up in the store as
their own paths. Don't mistake these for unconverted configs.

### What is deliberately NOT generated

Do not "finish the job" without reading these:

| Config | Why it stays a file |
|---|---|
| `nvim` | ~22 files of lazy.nvim config. `programs.neovim` with Nix-managed plugins is a *rewrite*, trading `:Lazy sync` for a rebuild per plugin bump. The store path already gives reproducibility |
| `mango` | No module exists, and the mode scripts genuinely need to `cp` into `config.conf` — hence `recursive = true` |
| `swaync` | `services.swaync` exists and works, but declares the unit that is deliberately **masked**. `autostart.conf` owns swaync's lifecycle so restyles apply on mode switch. Adopting the module flips that ownership and needs its own decision. **Never run both** |
| `helix/themes/gruvbox.toml` | A colour scheme is data, not settings. Transcribing 264 lines buys nothing but a chance of a silent typo |
| waybar CSS | Same reasoning — hand-tuned presentation is data |
| `glow`, `nwg-look` | No module at this pin |
| `corectrl` | Writes its own config from the GUI, and that GUI is the program |

### Four traps

⚠️ **Two owners on one path is an activation failure, not a merge.** This is
the one to internalise, because it is how every conversion goes wrong. A
config must be generated *or* linked, never both — moving an entry into
`programs.nix` means deleting it from `dotfiles.nix` **and** deleting the file
from `dotfiles/` in the same change. `waybar.nix` writes into `~/.config/mango/`,
which the recursive `mango` link also owns, and that only works because the
four `.jsonc` files were deleted from `dotfiles/mango/waybar/`. `walker/config.toml`
broke `rebuild` outright this way: tracked in git *and* written as a symlink by
both autostart files.

⚠️ **"Declarative" and "writable" are not actually in tension.** That was an
artefact of only having symlinks. `programs.zed-editor` runs an activation
script that **merges** the Nix-declared settings into the real, writable
`settings.json` with `jq -n '$dynamic * $static'` — Zed keeps persisting its
own state, and the declared keys win on every rebuild. Before assuming a config
must be read-only to be declarative, check whether its module merges instead of
links.

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
layout, keyboard-driven. Config lives in `dotfiles/mango/`, split into:

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
(`tiling` → `style-solid.css`, `hud` → `style-hud.css`; there is no third).
Layout selects which waybar modules are shown. Position moves the bar between
screen edges.

**`SUPER+/` offers `full`, `focus` and `minimal` only** — the `hud` layout is
chosen automatically whenever the desktop mode is `hud`, so it is not a
separate pick.

Waybar configs are generated as the **full layout × position matrix**:
`config-<layout>-<position>.jsonc`, 4 × 2 = 8 files. `waybar-restart.sh` only
builds a filename from the three state values; nothing is rewritten at runtime.

The first two open a walker picker; position is a **straight toggle**, since
with two options a menu costs more keystrokes than the thing it selects.
`waybar-position.sh` also accepts an explicit `top`/`bottom` argument for
scripting.

All three are read by **`scripts/waybar/waybar-restart.sh`**, which is the only
place that knows how they combine — so login, mode switch, layout switch,
position toggle and `reload_config` all land on the same result.

**The state paths and their defaults live in `scripts/lib.sh`**, sourced by
every script that touches them. Each one used to re-derive
`${XDG_STATE_HOME:-$HOME/.local/state}/mango` and its own fallback value, which
is exactly how the mode switch broke one-way on 2026-07-31 — one reader
disagreed with the writers about the path, silently. `lib.sh` also holds
`apply_mode()`, the body `modes/tiling.sh` and `modes/hud.sh` used to carry as
a byte-identical copy each.

> **How position actually works:** waybar takes only `-c`, `-s` and `-b` on the
> command line — `position` is a config key with no flag. So each position is a
> **separate generated file**, and the script picks between them.
>
> The margin mirroring matters: the hud layout uses
> `"margin-bottom": -28` against a 28px bar to cancel its exclusive zone, and
> that has to move edges with the bar. It is `atBottom` in `waybar.nix` now.
>
> Styling follows automatically — waybar adds its position as a CSS class on the
> window, so `window#waybar.bottom` in `style-solid.css` moves the separator
> line to the top edge.

> All four layouts show the battery relative to the TLP charge limit, so a
> battery parked at the 85% stop threshold reads 100%. The limit is read from
> `services.tlp.settings.STOP_CHARGE_THRESH_BAT0`, not copied. The rescale
> happens before `states` is compared, so `warning = 30` is a real 25.5%.

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
| Power button | Tap hibernates, hold powers off — logind, not a mango bind (§9) |

### Waybar

Status bar. **The layouts are generated by `modules/home/waybar.nix`** — there
are no `config*.jsonc` files in this repo; the eight
`config-<layout>-<position>.jsonc` are written into `~/.config/mango/waybar/`
alongside the hand-written CSS, which stays a file. Each module is defined once
and a layout is a list of names, so a name with no definition is an **eval
error** rather than an empty module. Per-layout divergences live in a `tweaks`
attribute at the call site.

> There are two stylesheets, `style-solid.css` and `style-hud.css`. A third,
> `style.css`, was deleted in 2026-08 as unreachable — `current-mode` only ever
> holds `tiling` or `hud`, so its fallback branch could never be taken. Check
> `waybar-restart.sh` can actually reach a file before adding one.

Notable custom modules — each is a script under `dotfiles/mango/scripts/`, so if one
is missing from the bar, **run its script by hand first**:

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
| **rofi** | Secondary menus. **No config in this repo** — there is no `rofi/` directory and never was on NixOS; it runs on its own defaults. Grepping for `rofi` is misleading, since it substring-matches `power-profile` |
| **swaync** | Notifications. Started from `autostart.conf`, **not** systemd — the nixpkgs unit is masked |
| **awww** | Wallpaper daemon (the swww fork; the binary is `awww`) |
| **wlsunset** | Night light, owned by a systemd user unit |
| **wlogout** | Session menu behind the waybar power icon — lock, logout, suspend, hibernate, reboot, shutdown |
| **swaylock** | Screen lock (`swaylock-effects`). Needs the hand-declared PAM service in `desktop.nix`; configured by `programs.swaylock` (§9) |
| **swayidle** | Lock handler *and* idle daemon — swaylock on `before-sleep`/`lock-session`, plus the dim → lock+blank → suspend ladder (§9) |
| **poweralertd** | Low-battery notifications into swaync. `-S` keeps it to power supplies, so headphones don't alert (§9) |
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
Hack Nerd Font Mono 11 — kitty additionally takes bold and italic from
0xProto Nerd Font Mono (bold-italic stays Hack; 0xProto ships none).
`checks/static.sh` asserts every family named here actually resolves.

⚠️ **kitty and foot are generated** by `programs.kitty` / `programs.foot`, from
a **single `gruvbox` palette** in `modules/home/programs.nix` — kitty takes
`#rrggbb`, foot takes bare hex, both from the same `let` binding. There is no
`dotfiles/kitty/` or `dotfiles/foot/` in this repo. Change the palette there, once.
ghostty has no config at all: `dotfiles/ghostty/config.ghostty` was a zero-byte
file and was deleted rather than converted; the package runs on its defaults,
exactly as it already did.

There is no `active-theme` indirection any more, and it is now *impossible* to
reintroduce as it stood — there is no directory for a mode script to write a
theme into.

**Editors:** Neovim is `$EDITOR`/`$VISUAL`, so it is what git, `sudoedit`,
`systemctl edit`, lazygit and yazi all open. It is a hand-rolled lazy.nvim
config (~18 plugins), and the one large config still hand-written — see
`dotfiles/nvim/README.md`. Helix is a second option, generated by `programs.helix`
down to a single setting (`theme = "gruvbox"`), with the theme itself left as a
file. **Its binary is `hx`, not `helix`** — the desktop entry works while
typing `helix` in a shell does not. Zed is generated too, but by a module that
*merges* into a writable `settings.json` rather than linking it.

⚠️ **Neither ships language servers.** There is no mason; both take servers from
`$PATH`, so every server must be declared in `modules/home/packages.nix`. A
missing server is skipped in **silence**. `hx --health` is the fastest audit —
one line per language, `✘` against anything it cannot find. See
`docs/adr/0007`.

---

## 9. Hardware behaviour

Three things look like faults and are not.

### Power modes

Three TLP profiles. `SUPER+SHIFT+p` and a left-click on the waybar
leaf/bolt/adjust glyph toggle **balanced ↔ performance** — the two everyday
modes. **Fanless is right-click only**, and left-clicking out of it lands in
balanced. It is kept off the left-click path deliberately: a 1.1 GHz cap with
the iGPU pinned to 200 MHz is too large a penalty to reach by clicking one time
too many.

Right-click returns to whatever the current supply implies — performance on
mains, balanced on battery. It names that explicitly because
`TLP_AUTO_SWITCH=2` holds fanless across a charger change by design, so nothing
reverts it on its own.

| Profile | TLP | Governor / EPP | Max freq | Boost | iGPU | ABM |
|---|---|---|---|---|---|---|
| performance | `_ON_AC` | performance / performance | 4.63 GHz | on | auto | 0 |
| balanced | `_ON_BAT` | powersave / power | 4.63 GHz | **off** | auto | 1 |
| fanless | `_ON_SAV` | powersave / power | **1.12 GHz** | off | **low** | 3 |

`fanless` is TLP's `power-saver` (`SAV`). `TLP_AUTO_SWITCH=2` keeps it across a
charger transition, so it holds on mains — that is deliberate, and the tooltip
says so rather than looking like a bug.

⚠️ **"Fanless" is aspirational under sustained all-core load, and measurably
so.** Two `fan-calibrate` runs put the EC trip at ~47–48 °C against an idle
plateau of 40–46 °C depending on ambient; twelve threads cross that even at
418 MHz, the hardware minimum. There is no cap that makes sustained load
silent on this chassis, so the mode targets **bursty** desktop use, where it is
genuinely quiet.

The cap is therefore `lowest_nonlinear` (1115770) — the highest clock still at
minimum core voltage, i.e. the best perf-per-watt point. Efficiency is the
objective only because the thermal one proved unreachable; a lower cap buys
silence it cannot deliver and costs real speed. Details in `docs/adr/0017`.

> The everyday win is **balanced**, not fanless. With boost off and the 2.9 GHz
> base ceiling it idles fan-free at ~40 °C, where the old low-power mode ran at
> 2340 rpm. That is what fixed the original complaint.

> `platform_profile` moves with the profile but is not what does the work — it
> is a firmware hint and is identical across all three for everything the
> scheduler reads. Don't diagnose from it.

ABM 3 visibly shifts panel contrast; that is the mode working, not a display
fault. The iGPU pin costs compositor smoothness — 200 MHz against a 1899 MHz top
state — and is the first thing to relax if fanless feels sluggish.

### Battery stops below 100%

TLP sets EC thresholds **START 75 / STOP 85** (`modules/system/power.nix`,
confirmed against live sysfs). On AC the battery parks wherever it is and only
tops up below 75%. `status` then reads `Not charging`, which waybar renders as
a **plug** icon rather than a lightning bolt. A plug with a static sub-100%
reading is the hysteresis working.

Raising STOP does not trigger a charge — the EC only starts below START. To
force one: `sudo tlp setcharge 84 85 BAT0`.

> `upower -i` reports `charge-start-threshold: 75%` regardless of the real
> value. Trust `/sys/class/power_supply/BAT0/charge_control_*_threshold`.

> The bar shows the **raw** percentage. `full-at`, which rescaled it so the 85%
> stop read as 100%, was removed on 2026-08-09 — it made the bar disagree with
> `upower` and sysfs by a constant factor, and that masked two reports of the
> module freezing. `checks/static.sh` asserts no generated config carries it.
> Consequence: on AC the bar parks at 85% and never reads 100%.

### Suspend and s0i3

The firmware exposes only **s2idle** (`/sys/power/mem_sleep` → `[s2idle]`), not
S3 — so `mem_sleep_default=deep` would achieve nothing. Under s2idle the SoC
only reaches its low-power state (**s0i3**) once every IP block reports idle.

**A lit panel during suspend is a battery bug, not a cosmetic one.** The
DISPLAY block tracks the display *pipe*, so a screen left on holds s0i3 off
entirely and the machine idles at **~4.1 W** through what looks like sleep.
That is how the laptop was found flat after a night closed on the desk.

Fixed with `powerManagement.powerDownCommands`/`resumeCommands` in `power.nix`,
running **`wlopm --off '*'`** / `--on` through the shared `setDisplayPower`
helper. The resume hook is the load-bearing half: an output left in its off
power-mode is not restored by input, so dropping it wakes the machine to a
black screen no keypress fixes. `wlopm` needs the Wayland socket, so it cannot
run as root directly — the helper loops over `/run/user/*/wayland-[0-9]` and
`runuser`s to the owning user.

⚠️ **The backlight cannot do this job.** `brightnessctl` and `bl_power` only
drive PWM; the DISPLAY block tracks the CRTC. Hooks written that way succeed,
exit 0, and leave the panel lit and the battery draining.

**Result: fixed.** A 9h37m lid-closed suspend on battery cost **4 percentage
points** (58% → 54% of a 42.4 Wh cell) — about **0.15 W**, which is s0i3. That
retracts the earlier reading here: blanking the display was measured as taking
suspend from 4.10 W only to ~3.03 W, with `last_hw_sleep` still 0, and this
section concluded s0i3 was unreachable for unknown reasons. It is reachable.
The short instrumented measurements were the unreliable part, not the fix — a
long sleep measured by battery percentage either side is the honest test, and
the only one that matched what the machine actually does overnight.

Hibernation on the lid stays regardless: it is there for the resume hang and the
spurious wake (§below), not for the drain.

> If suspend drain is ever suspected again, read
> `/sys/kernel/debug/amd_pmc/smu_fw_info` **first** — it names the offending IP
> block directly, in one command.

### Idle

Until 2026-08-11 nothing acted on idleness at all: swayidle carried **no
timeouts**, so with the lid open the machine never dimmed, never locked and
never slept — 6.9 W until the 3% hibernate, roughly six hours, with the desktop
unlocked the whole time. That gap dwarfed every other power setting on this
machine.

The ladder now, all in `services.swayidle`:

| Idle | What happens | Undone by |
|---|---|---|
| 4 min | `brightnessctl -s set 10%` — dim, as the warning | `brightnessctl -r` on activity |
| 5 min | `swaylock -f`, then `wlopm --off '*'` | `wlopm --on '*'` on activity |
| 30 min | `idle-suspend` — suspends only on battery, and only if no MPRIS player reports `Playing` | any input, instantly |

Three things make it safe rather than annoying:

- mango advertises `zwp_idle_inhibit_manager_v1`, so mpv and Firefox suppress
  the whole ladder during playback. Check with `wayland-info | grep inhibit`
  before assuming that of any compositor.
- The lock/blank step is joined with `;`, **not `&&`** — see `docs/gotchas.md`.
- `idle-suspend` is a `writeShellApplication`, so it is shellchecked at build
  time rather than being an inline string nothing gates.

On AC the ladder stops after the blank: locked, dark, and still up.

Playback is handled at two different levels, deliberately:

- **Video** needs nothing from us. mpv and Firefox hold a `zwp_idle_inhibit`
  surface while playing, which stops the ladder before the first rung — no dim,
  no lock, no sleep.
- **Audio-only** (ncspot, Spotify, a music tab) usually takes no inhibitor, so
  the ladder runs. That is wanted for the first two rungs — dimming and locking
  over an album is correct — but not for the last, so `idle-suspend` alone
  checks `playerctl --all-players status` and bails on `Playing`. `Paused` and
  `Stopped` sleep.

⚠️ **`systemd-inhibit --what=idle` does not hold any of this off.** swayidle
takes its idle signal from `ext_idle_notifier_v1`, i.e. from the compositor, and
mango does not bridge logind's inhibitors into it. So an unattended long build on
battery still hits the 30-minute suspend — it resumes where it left off, but
network connections will not. Same for anything playing audio without an MPRIS
interface: a game, a call in an app that publishes none.

#### Holding the ladder off — `idle_inhibitor`

The bar carries waybar's **built-in `idle_inhibitor`** (`full` and `focus`
layouts, between night mode and the power profile). Click to toggle: 󰒲 means the
ladder is live, 󰒳 in yellow means nothing dims, locks or sleeps.

It works where `systemd-inhibit` does not because it holds a
`zwp_idle_inhibit_manager_v1` inhibitor on waybar's layer surface — the
mechanism mpv and Firefox use, and the one mango feeds into
`wlr_idle_notifier_v1_set_inhibited`. **No `timeout`**: an inhibitor that
silently expires part-way through is the failure it exists to prevent.

⚠️ **The state does not survive a waybar restart** — it is a process-lifetime
bool, and the inhibitor dies with the surface. `waybar-reload`, a mode switch
and `SUPER+/` all drop it back to "sleep allowed"; `minimal` and `hud` do not
carry the module at all.

`systemctl --user stop swayidle` (and `start` after) is the escape hatch nothing
in the desktop can undo behind your back.

### Locking

`services.swayidle` in `modules/home/default.nix` runs `swaylock -f` on
`before-sleep`, on `lock`, and on the 5-minute idle timeout above. Before it
existed, swaylock was reachable only by hand (`SUPER+Delete`, `SUPER+SHIFT+s`,
the wlogout button) and **every lid-close resumed straight to the unlocked
desktop**.

swayidle rather than another `powerManagement` hook, for two reasons:

- It holds a **logind sleep inhibitor** — `-w` makes it wait for `swaylock -f`
  to fork, and swaylock forks only once the lock surface is up. So the lock is
  guaranteed present before the suspend, not racing it.
- A root sleep hook runs inside `sleep-actions.service`, whose cgroup is
  **killed when the unit stops on resume** — taking the swaylock it just
  started with it. That leaves the compositor locked with no client, which
  `ext-session-lock-v1` makes unrecoverable (§13).

Ordering falls out of this: swayidle's inhibitor puts the lock up first, then
`sleep-actions` powers the panel down.

`lock`/`unlock` mean `loginctl lock-session` works too.

#### What it looks like, and why

`programs.swaylock` generates `~/.config/swaylock/config`, which **every lock
path reads** — all of them run bare `swaylock -f` and pass no `--config`.

`clock` + `indicator` are the point of it: a swaylock screen with nothing drawn
on it is indistinguishable from a machine that is off or hung, so the lock now
shows a **ticking clock inside a permanently visible indicator ring**. The clock
is the proof of life; the ring is where typing lands. `indicator-idle-visible`
keeps the ring up rather than fading it out.

Both options are **swaylock-effects extensions**, which is why the module sets
`package = null` — see the trap in `docs/gotchas.md`.

This replaced three separate copies of the same theme: `mango/tiling/swaylock.conf`,
`mango/hud/swaylock.conf`, and an **untracked** hand-written
`~/.config/swaylock/config` that had been quietly supplying the theme to every
bare `swaylock -f` all along. The per-mode files are deleted and both
`SUPER+Delete` binds now run bare `swaylock -f`; there is one lock screen.

### Hibernation

A closed lid **hibernates**, on both power sources. There is no suspend phase
and no `HibernateDelaySec`, so a short lid-close costs a ~6 GiB write and a
~10–30 s resume rather than returning instantly.

**So does a tap on the power key**, with a long press left as `poweroff`. The
systemd defaults are the other way round — a brushed button ended the session
with no prompt, and holding it did nothing — which is the one power-management
default on this machine that could lose work.

Three routes into hibernation, then: the lid, the power key, and upower at 3%
(below). The 30-minute idle rung used to be a fourth and **suspends** now —
`docs/adr/0016` has why the lid evidence does not transfer to it, and why
upower's 3% action is what makes an unattended idle suspend safe.

That instant resume is what `suspend-then-hibernate` bought, and it was tried
twice — first with AC on a plain `suspend`, then with s-t-h on both sources. Both
lost the same way: a spurious wake ends the s-t-h cycle, and logind's lid
re-check ~30 s later degrades to a plain `suspend` with no hibernate timer
behind it, leaving the machine in the long s2idle its resume hangs from. Removing
the suspend phase removes the wake that starts it. `docs/gotchas.md` → Power has
the journal signature.

The image goes to the 20 GiB swapfile on `@swap` (§1). **zram remains the
working swap** at priority 5 against the file's −1, so ordinary swapping never
touches the disk — the file exists only to hold an image zram cannot, being
itself in the RAM being saved.

**A dying battery hibernates too**, via upower rather than logind:
`criticalPowerAction = "Hibernate"` at `percentageAction = 3`. NixOS defaults to
`HybridSleep`, which writes the image and then *stays in s2idle* — the session
survives, but the machine is still drawing at the one moment it must not. The
~3 W once measured for that state came from the same short-measurement batch as
the retracted s0i3 figure and should not be quoted; the argument does not need
it, since any suspend at 3% is the wrong state to be in.

3% is one point above upower's default, not a safety cushion: 1% is 0.42 Wh
here, worth ~60 s at the ~25 W a hibernate write draws, against a write that
takes ~30 s. The extra point covers the poll interval at this battery's 38 W
recorded peak. **The gauge is accurate this low** — it has logged 1% repeatedly,
so there is no firmware cliff to stay clear of, and a larger margin only costs
runtime.

⚠️ **`percentageLow`/`Critical`/`Action` must stay strictly descending** (20 >
5 > 3). Out of order or otherwise invalid, upower discards all three and uses
its own defaults — the action still fires, just at a charge nobody chose, and
nothing logs. Read back `/etc/UPower/UPower.conf`, not the Nix.

⚠️ **`resume_offset` is the fragile part, and getting it wrong fails silently.**
Both `boot.resumeDevice` and `boot.kernelParams = [ "resume_offset=…" ]` are
required: one names the filesystem, the other locates the image inside it. Get
it wrong and the machine simply boots fresh and discards the session, which
presents as "hibernate didn't work" rather than "resume was misconfigured". The
number is valid only for the exact file that exists now — recreating, resizing,
defragmenting or `balance`-ing it moves the image. Re-derive with:

```
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

⚠️ **A rebuild is not enough — you must REBOOT.** `resume=` is a kernel command
line parameter, so `rebuild` writes the new logind and sleep config while the
*running* kernel has neither. `systemctl hibernate` then snapshots memory,
prepares S4 and returns **without writing an image or powering off** — and
because the screen blanks and comes back, it reads as a fast, successful
hibernate. It is not. This is dangerous while half-applied, because the lid
handler goes live at rebuild time: closing the lid then attempts the failed
hibernate, thaws, and leaves the machine awake with the lid shut, draining
*faster* than plain suspend. **Reboot promptly after the rebuild.**

⚠️ **The kernel log cannot tell you whether a hibernate succeeded.** The memory
image is snapshotted *before* the write and power-off, so a successful and a
refused attempt leave byte-identical traces. Do not conclude from
`Waking up from system sleep state S4` that anything worked, and in particular
do not set `HibernateMode=shutdown` on that misreading — that was tried and
reverted. What actually distinguishes them:

| Check | Meaning |
|---|---|
| Machine physically powers off; firmware screen on the way back | It really hibernated. **This is the primary signal** |
| `journalctl --list-boots` — boot ID unchanged across the cycle | Resume worked, session restored |
| A new boot ID | Image written but resume failed — session discarded |
| No power-off, journal continuous | Aborted. Check `grep -o 'resume[^ ]*' /proc/cmdline` shows **both** parameters |

> **RTC trap:** `rtc0` here is `acpi-tad` and has no `wakealarm`, so `rtcwake`
> fails with `not enabled for wakeup events` and looks like broken firmware.
> The alarm actually comes from **`rtc1` (`rtc_cmos`)**. Don't point anything
> at `rtc0` to "fix" it.

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
| `fprintd` | Fingerprint (Synaptics `06cb:00f9`). Enabling it turns `fprintAuth` on for **every** pam service; `swaylock` and `login` are switched back off — see `docs/gotchas.md` → swaylock |
| `NetworkManager` | Networking (**not** networkd) |
| `systemd-resolved` | DNS |
| `avahi` | mDNS, for CUPS printer discovery |
| `tlp` | Power tuning + battery thresholds |
| `thermald`, `fwupd`, `upower` | Thermals, firmware updates, battery reporting + the critical-battery hibernate (§9) |
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
| `micmute-led` | Syncs the mic-mute LED with PipeWire. **The only place `pactl` exists** — it comes from this unit's `path`, not `systemPackages` |
| `nextcloud-client` | Cloud sync — stores its credentials in gnome-keyring |
| `cliphist` (+ `cliphist-images`) | Clipboard history behind `SUPER+V` |
| `mango-session.target` | A marker other units can hang off; started from `autostart.conf` |
| `swaync.service` | **Masked** — autostart owns swaync instead |

`~/.config/systemd/user/` now contains **only** home-manager symlinks into the
store. Keep it that way: it overrides `/etc/systemd/user/`, so any hand-written
file there silently shadows the unit the flake generates.

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
| Zen browser profile | `~/.config/zen/` | **912 MB** — 13 extensions, logins, history. Growing |
| NetworkManager profiles | `/etc/NetworkManager/system-connections` | the ~29 ordinary APs, root-only, mode 600. The nine credential-bearing ones are declared — ADR 0013 |
| Bluetooth pairings | `/var/lib/bluetooth` | 7 devices |
| Wallpaper | `~/.local/share/mango/wallpaper.png` | 4.6 MB |
| Runtime state | `~/.local/state/mango/` | mode, layout, night-temp, last-vpn |
| **age private key** | `/var/lib/sops-nix/key.txt` | **189 bytes, in no repo — losing it makes `secrets/secrets.yaml` unreadable** |
| CLI credentials | `~/.config/{gh,glab-cli,gpu-screen-recorder,opencode,rclone,rbw,tea}` | gitignored by name |
| corectrl profiles | `~/.config/corectrl/` | written by its GUI |

Snapper covers `/home` against accidental deletion, but snapshots are on the
same disk — they are not a backup.

**Secrets moved into sops-nix on 2026-08-06** (ADR 0012). `secrets/secrets.yaml`
is encrypted and tracked; the PIA credentials, the `homelab` WireGuard key and
the `gh`/`glab`/`tea` tokens all live there. Edit with
`nix develop -c sops secrets/secrets.yaml` **from the repo root**.

⚠️ What replaced that gap is a smaller, sharper one: **the age key at
`/var/lib/sops-nix/key.txt` is a single point of failure in no backup.** Keep a
copy in Bitwarden and on the offline drive.

**The nine credential-bearing NetworkManager profiles moved into the flake on
2026-08-09** (ADR 0013) — `homelab` plus the eight PIA exits, with credentials
substituted from a sops template at activation. The ~29 ordinary access points
stay in NetworkManager's own state, which is a decision rather than a TODO:
`ensureProfiles` deletes nothing, so declaring a subset is supported.

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

Things that are true today and worth knowing. *(Reviewed 2026-08-11.)*

- **Nothing here can hold off the idle ladder except a Wayland idle inhibitor.**
  `systemd-inhibit --what=idle` does not reach swayidle, so unattended work on
  battery meets the 30-minute suspend. The bar's `idle_inhibitor` toggle is the
  in-session answer, but it is released by any waybar restart; the one nothing
  can undo behind you is `systemctl --user stop swayidle`. See §9.
- **The spurious s2idle wake source is still unidentified**, and it is what keeps
  `suspend-then-hibernate` off the lid. Standing suspect: the Synaptics
  fingerprint reader — at `1-3`, the *only* device on USB bus 1, with its own
  `power/wakeup` disabled but its parent XHCI controller `0000:74:00.3`
  `enabled`. Disabling wakeup on that controller costs nothing (there is nothing
  else behind it) and is untried. Since 2026-08-12 the idle rung suspends, so
  the machine finally produces samples to test it against — see
  `docs/adr/0016`.
- **The age key is a single point of failure.** `/var/lib/sops-nix/key.txt` is
  in no repo and no backup; without it `secrets/secrets.yaml` is unreadable.
  See §11.
- **Helix has no Python type checking.** `pyright` is declared and serves nvim,
  but helix's defaults are `ty`, `ruff`, `jedi-language-server` and `pylsp` —
  none of which is pyright. It gets lint and format from `ruff`; `hx --health
  python` still shows ✘ against three of its four. Deliberately not closed yet.
  **Always confirm with `hx --health <lang>` rather than assuming a server
  declared for nvim serves helix too.**
- ~~Nothing gates a rebuild~~ — **closed 2026-08-03.** `nix flake check` now
  builds `system.build.toplevel` and the home-manager activation package, so
  `buildEnv` collisions and failing derivations surface before a `switch`.
  `verify-packages.sh` was retired as a strict subset of it.
- ~~`nix fmt` uses the unmaintained `nixpkgs-fmt`~~ — **closed 2026-08-03**,
  now `nixfmt` (RFC 166).
- **The `.nix` files are comment-heavy** — 1,346 of 3,506 lines. `dotfiles.nix`
  is 54 lines of code under 249 lines of prose. Much of it duplicates
  `docs/adr/`, which is where the narrative belongs.
- **`~/arch-residue-backup-2026-07-30/`** (2.1 MB) is still in the home
  directory and can be deleted.

---

## 14. Further reading

| Document | Read it when |
|---|---|
| `CLAUDE.md` | Before changing anything — the rules that apply to every task |
| `docs/gotchas.md` | Before changing one area — the failure catalogue, by area |
| `docs/adr/0001` … `0012` | Before undoing something that looks redundant |
| `docs/WORK-LOG.md` | To see what the 30–31 July declarative pass covered |
| `docs/archive/MIGRATION.md` | History of the Arch→NixOS install. Not instructions |
| `dotfiles/nvim/README.md` | The Neovim config map |
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
| 0009 | Generate config from Nix where a module exists; link files only where one does not |
| 0010 | `nix flake check` is the gate; lints tuned to fire only on real findings |
