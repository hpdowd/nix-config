# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

`~/.config` is Henry's personal dotfiles and application configuration directory on Arch Linux. There is no build system or test suite — changes are applied by restarting or reloading the relevant application.

## Shell environment

Fish shell (`~/.config/fish/config.fish`) with key aliases that affect all terminal work:

- `cat` → `bat` (syntax-highlighted pager — use Read tool instead of Bash cat)
- `ls` / `ll` / `la` → `eza` variants
- `lf` → `yazi` (file manager)
- `zed` → `zeditor`
- `pacman` → `sudo pacman`; typo alias `pamcan` also works
- PATH additions: `~/.config/emacs/bin`, `~/.cargo/bin`, `~/Applications/*/bin`, `~/.local/bin`, `~/.bun/bin`
- `zoxide` is active for `z` directory jumping

**Home-directory clutter hiding** (added to reduce `ls ~` / file-manager noise, not to move anything):
- `~/.hidden` lists top-level dirs that GTK file managers (Thunar) omit from the `~` view. Toggle back with **Ctrl+H**.
- In zsh (`~/.config/zsh/conf.d/10-aliases.zsh`), `ls`/`l` are a function that applies eza `--ignore-glob="$_HOME_HIDE"` **only when `$PWD == $HOME` and no args are given** — so common names (`share`, `temp`, `log`, `R`) are never hidden inside projects. `ll`/`la`/`lla`/`lls` are unfiltered escape hatches.
- Both surfaces share the same list: `Android Applications blender colors go log R share temp vaults winboat Zomboid`. To un-hide a dir, remove it from **both** `~/.hidden` and `_HOME_HIDE`. Nothing is moved; `cd`/`z`/paths are unaffected.

## Theming architecture

Theming is driven by **Mangowm mode scripts** (`~/.config/mango/scripts/modes/`). Switching modes symlinks the correct theme into `active-theme.*` files:
- `~/.config/kitty/active-theme.conf` — symlinked by mode script, included by `kitty.conf`
- `~/.config/foot/active-theme.ini` — symlinked by mode script, included by `foot.ini`
- Equibop (Discord) CSS theme is also swapped via `jq` on `settings.json`

Current modes: **tiling** (Gruvbox Orange) and **hud**. Active mode is stored in `~/.config/mango/state/current-mode`. (A third `dms` mode was removed in July 2026 along with DankMaterialShell.)

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
- **swaync** — notification daemon, styled in `mango/swaync/`
- **lxpolkit** (from `lxsession` package) — polkit authentication agent, started from `mango/universal/autostart.conf`. Note: `exec-once` only fires on initial compositor startup, not on reload — log out/in after changing autostart.
DankMaterialShell and Quickshell were **removed in July 2026**, along with the `dms` mode and all its theme files. Two things kept their names deliberately: `kitty/tabs.conf` (renamed from `dank-tabs.conf`; included by `kitty.conf` in every mode) and `yazi/flavors/noctalia.yazi` (still the active yazi theme per `yazi/theme.toml`).

Mangowm is the sole desktop environment. KDE Plasma has been removed from this system.

## Networking

**WiFi card**: Qualcomm QCNFA765 (`wlp1s0`), driver `ath11k_pci`. Connected to `Minerva_2` (enterprise router).

**Known issue — WiFi fails to recover after system suspend**: The ath11k_pci driver does not cleanly reinitialize on resume, and the enterprise router drops the association. NM retries but DHCP times out and the connection never recovers. Manually restarting NetworkManager fixes it.

**Fix in place (two separate layers, both necessary)**:
- TLP config (`/etc/tlp.conf`) — sets `WIFI_PWR_ON_AC=off` and `WIFI_PWR_ON_BAT=off`. Prevents the radio from power-saving during normal runtime. Does *not* affect suspend/resume behaviour.
- `/etc/systemd/system-sleep/wifi-resume.sh` — cycles the WiFi radio off/on 3 seconds after system wake, forcing a clean re-association. This is what actually fixes the resume failure.

These can't be merged: TLP is applied by its service; the sleep hook is executed by systemd. Each covers a different failure mode.

If the issue recurs, check `journalctl -u NetworkManager` for DHCP timeout after wake. Disabling Fast Transition (`nmcli connection modify Minerva_2 wifi-sec.key-mgmt wpa-psk`) is an additional option if the sleep hook alone doesn't resolve it.

## NixOS migration (in progress)

`~/.config/nixos/` holds a NixOS flake that reproduces this machine. It is **not yet in use** — the system is still Arch. See `nixos/MIGRATION.md` for the plan, the benefit/cost assessment, and the outstanding work queue.

**Status:** the full system closure evaluates cleanly against nixpkgs-unstable with zero errors and zero warnings (verified 2026-07-27); `nix build --dry-run` reports 13.9 GiB download / 37.4 GiB unpacked. Re-verify at any time with `nixos/verify-packages.sh` (parses every file, evaluates the closure, then sizes the build). Nix is installed on the Arch host via the `nix` package, with flakes enabled in `~/.config/nix/nix.conf`.

- `flake.nix` — inputs: nixpkgs unstable, home-manager, nixos-hardware, plus only two third-party flakes (`zen-browser`, `claude-desktop`). Most AUR software turned out to be in nixpkgs already — `mango`, `fsel`, `walker`, `elephant`, `dsearch`, `weathr`, `sidequest`, `winboat`, `valent`. (`dms-shell`, `quickshell` and `dgop` are packaged too, but are excluded on purpose — DankMaterialShell is being dropped.) Note `claude-desktop` must NOT use `inputs.nixpkgs.follows`; it references the removed `pkgs.nodePackages` and only builds against its own pin.
- `hosts/thinkpad/` — host config and `hardware-configuration.nix` (real UUIDs from the live fstab)
- `modules/system/` — one file per concern: boot, locale, networking, audio, desktop, fonts, power, printing, virtualisation, nix-settings
- `modules/home/` — home-manager: packages, shell, dotfiles, theme
- `pkgs/default.nix` — overlay + templates for packaging AUR software
- `verify-packages.sh` — checks which package names resolve in nixpkgs; run before any rebuild

Design decision worth knowing: `modules/home/dotfiles.nix` uses `mkOutOfStoreSymlink`, so `~/.config/{mango,nvim,kitty,foot,…}` stay writable rather than becoming read-only store paths. This is deliberate — the Mangowm mode scripts symlink `active-theme.*` and `jq`-patch Equibop's `settings.json` at runtime, which requires writable config directories.

Planned installation is **side-by-side**: new `@nixos` and `@nix` btrfs subvolumes on the existing `nvme0n1p2`, reusing `@home` and the shared ESP, leaving the Arch install bootable.

## Scripts

Custom scripts live in `~/.scripts/`. **None of them have a file extension** — they are bash scripts named without `.sh`:
- `toggle_lid_action` — toggle lid close behaviour in `/etc/systemd/logind.conf` (run via `lidaction` alias)
- `clean_tmp` — clean tmp files (run via `cleantmp` alias)
- `keyd-application-mapper` — per-application keyd layer switching
- `micmute-led` — daemon that syncs the ThinkPad mic-mute LED with PipeWire's default source mute state; subscribes to PipeWire events via `pactl subscribe`
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
