# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

`~/src/nix-config` — the NixOS flake that builds this ThinkPad, plus the dotfiles it installs. **Arch is gone**: subvolumes, boot entry and EFI residue all deleted 2026-07-30. There is no dual boot and no fallback.

```
flake.nix          at the ROOT — load-bearing, see below
hosts/thinkpad/    host config + hardware-configuration.nix
modules/system/    boot, locale, networking, audio, desktop, fonts, power, …
modules/home/      home-manager: packages, shell, dotfiles, theme
home/              the dotfiles (mango, nvim, kitty, foot, zsh, …)
pkgs/              overlay for anything not in nixpkgs
docs/archive/      the Arch→NixOS migration — history, not live instructions
```

`~/.config/<app>` is a symlink into `~/src/nix-config/home/<app>`, created by home-manager. **Edit under `home/`**; going through the `~/.config` symlink reaches the same file.

Rebuild with `rebuild` (= `sudo nixos-rebuild switch --flake "$HOME/src/nix-config#thinkpad"`). Use **`rebuild-test`** for anything structural — it applies without changing the boot default, so a mistake is one reboot from gone.

**Always quote a flake ref in zsh.** This shell runs with `EXTENDED_GLOB` (`zsh/conf.d/00-options.zsh`), which makes `#` a pattern operator meaning "zero or more of the preceding", so an unquoted `~/src/nix-config#thinkpad` is treated as a glob, matches nothing, and fails with `zsh: no matches found:` before `nixos-rebuild` is ever invoked. It reads like a broken path. Double quotes fix it; use `"$HOME/…"` rather than `~`, which does not expand inside them.

**Why the flake is at the root, and why that matters.** Until 2026-07-30 this repo was `arch-config`, its root *was* `~/.config`, and the flake sat in a `nixos/` subdirectory — which put the dotfiles **outside the flake root**, unreachable by any relative path. That, not just writability, is why `dotfiles.nix` uses `mkOutOfStoreSymlink` for everything. With the flake at the root, `.source = ../../home/kitty` resolves; paired with `recursive = true` (links individual files, leaves the directory writable) configs can move into the store one at a time. **Don't move the flake back down a level.**

Only directories tracked in git are linked. `~/.scripts` moved into the repo on 2026-07-30 (`home/scripts/`) and is now a store path; the credential dirs `.gitignore` excludes (`gh`, `glab-cli`, `gpu-screen-recorder`, `opencode`) are still plain directories surviving via `@home`.

## Shell environment

**The login shell is zsh** (`/etc/passwd`), configured from `~/.config/zsh/conf.d/*.zsh` via `ZDOTDIR`. **Fish is gone** — dropped from the flake on 2026-07-28 and its config deleted from the repo on 2026-07-30, once `command -v fish` confirmed the shell was not installed here at all. It was only ever a secondary interactive shell; zsh is what terminals start and always was.

`programs.zsh` in `modules/home/shell.nix` owns `~/.zshrc`, the plugins, and the history settings, and it sources `conf.d/*.zsh` at the end. **`conf.d/00-options.zsh` is where the shell options live** — recovered on 2026-07-30 from the Arch-era `.zshrc` that home-manager displaced at the migration, which had carried settings Nix never reproduced. It is sourced *after* home-manager's own `set_opts` loop, so it deliberately wins: `EXTENDED_HISTORY` and `INC_APPEND_HISTORY` are re-enabled there against home-manager's `NO_*` defaults. It also does `zmodload zsh/datetime` — `40-prompt.zsh` times commands with `$EPOCHSECONDS`, and without the module that parameter is simply unset, so the timer silently computed `0 - 0` on every prompt.

Aliases that affect terminal work:

- `cat` → `bat` (syntax-highlighted pager — use Read tool instead of Bash cat)
- `ls` / `ll` / `la` → `eza` variants
- `lf` → `yazi` (file manager)
- `zed` → `zeditor`
- No package-manager alias. The old `pacman`/`pamcan` wrappers are commented out in `10-aliases.zsh` and there is no pacman on this system. Package changes go in `modules/home/packages.nix`, followed by a rebuild
- PATH additions: `~/.config/emacs/bin`, `~/.cargo/bin`, `~/Applications/*/bin`, `~/.local/bin`, `~/.bun/bin`
- `zoxide` is active for `z` directory jumping
- **`waybar-reload`** and **`mango-reload`** (added 2026-07-31, `modules/home/shell.nix`) run `mango/scripts/waybar/waybar-restart.sh` and `mango/scripts/reload.sh`. The mango scripts are deliberately **not** on PATH — `~/.scripts` is, `~/.config/mango/scripts` is not, and adding it would put 28 files with names like `mode.sh` into command completion. Note neither alias picks up a repo edit by itself: `~/.config/mango` is a store path, so it is **`rebuild` first, reload second**, and reloading alone restarts against the config that was already there — indistinguishable from the change having had no effect

The zsh `lidaction` and `cleantmp` aliases point at the real extensionless scripts in `~/.scripts/` and work. (Fish had its own `lidt`/`cleantmp` aliases that appended a `.sh` the scripts do not have, so they were always broken — moot now that fish is gone.)

**Home-directory clutter hiding** (added to reduce `ls ~` / file-manager noise, not to move anything):
- `~/.hidden` lists top-level dirs that GTK file managers (Thunar) omit from the `~` view. Toggle back with **Ctrl+H**.
- In zsh (`~/.config/zsh/conf.d/10-aliases.zsh`), `ls`/`l` are a function that applies eza `--ignore-glob="$_HOME_HIDE"` **only when `$PWD == $HOME` and no args are given** — so common names (`share`, `temp`, `log`, `R`) are never hidden inside projects. `ll`/`la`/`lla`/`lls` are unfiltered escape hatches. The file starts with `unalias ls l ll` — NixOS's `/etc/zshrc` (from `programs.zsh.enable`) predefines those three from the `environment.shellAliases` defaults, and an existing `ls` alias makes `ls() { … }` a **parse error that aborts the rest of the file**, silently dropping the `y` yazi function and the zoxide init below it. Don't remove the `unalias`.
- Both surfaces share the same list: `Android Applications blender colors go log R share temp vaults winboat Zomboid`. To un-hide a dir, remove it from **both** `~/.hidden` and `_HOME_HIDE`. Nothing is moved; `cd`/`z`/paths are unaffected.

## Theming architecture

Theming is driven by **Mangowm mode scripts** (`~/.config/mango/scripts/modes/`). Terminals name their theme directly — `kitty.conf` includes `gruvbox-orange.conf`, `foot.ini` includes `gruvbox-colors.ini`. Equibop (Discord)'s CSS theme is swapped via `jq` on `settings.json`.

**The `active-theme.*` indirection was removed on 2026-07-30.** `kitty/active-theme.conf` and `foot/active-theme.ini` were symlinks that the mode scripts rewrote on every switch — but both `tiling.sh` and `hud.sh` pointed them at the *same* gruvbox files, so the indirection selected nothing, and `kitty.conf` was including its theme twice. It was only ever load-bearing when the removed `dms` mode had its own palette. Don't reintroduce it: naming the theme directly is what lets `kitty/` and `foot/` become read-only store paths.

Current modes: **tiling** (Gruvbox Orange) and **hud**. Active mode is stored in **`~/.local/state/mango/current-mode`**.

**Runtime state lives at `~/.local/state/mango/`, not in the config tree** — moved 2026-07-30. It holds `current-mode`, `waybar-layout`, `night-temp`, `last-vpn` and `pia-auth` (PIA credentials, mode 600). Every script resolves it as `${XDG_STATE_HOME:-$HOME/.local/state}/mango`, so there is one place to change it. The old `mango/state/` is still in `.gitignore` so a stray script cannot quietly recreate it. **This is what let `~/.config/mango` move into the Nix store on 2026-07-30** — state written into a config directory is what forces that directory to stay writable. The wallpaper moved out for the same reason, to `~/.local/share/mango/wallpaper.png`.

**`mango/config.conf` is generated, and that is why it is not in the repo — but the config it contains *is*.** The mode script does a verbatim `cp mango/tiling/tiling.conf mango/config.conf` (or `hud/hud.conf`). So `config.conf` is a *copy of whichever mode is active*, not a source file: tracking it would mean committing a duplicate that changes on every mode switch. The real config lives in `tiling/tiling.conf` and `hud/hud.conf`, both tracked. `config.conf` is what mango actually reads, and it `source=`s every keybind, rule and autostart line.

Consequence for a fresh clone: there is no `config.conf`, so mango starts on built-in defaults — no waybar, no keybinds — until a mode script has been run once. `~/.config/mango` is a store path with `recursive = true` precisely so that `cp` still works. Note `mango -c <file>` accepts a custom config path, so this could move to `~/.local/state/mango/` and stop touching the config tree at all.

To reload Mangowm config: `~/.config/mango/scripts/reload.sh` (re-runs the mode script, dispatches `reload_config`, restarts elephant).

**`mmsg` takes verbs, not flags — the old `-s -d` style is dead.** `mmsg --help` lists exactly three: `get`, `dispatch`, `watch`. Anything else returns `{"error":"unknown command"}` **and exits 0**, so a script using the old form reports success while doing nothing. Five scripts were on the dwl-era flags and all were silently broken until 2026-07-31 — including `reload.sh` itself, which meant every "reload" was really just the mode script rewriting `config.conf`, with the compositor still running the old configuration until the next logout. The translations: `mmsg -s -d <func>` → `mmsg dispatch <func>`, `mmsg -d quit` → `mmsg dispatch quit`, `mmsg -w -c` → `mmsg watch all-clients`. Check the return value, since it is the only signal you get.

**Editing anything under `home/mango/` now needs a rebuild.** `~/.config/mango` became a store path on 2026-07-30, so the files there are read-only copies — editing the repo no longer takes effect immediately the way it did with the out-of-store symlink. Rebuild, *then* reload.

**Don't `sudo` the mango scripts.** Under sudo `~` is `/root`, so `reload.sh` fails with `/root/.config/mango/scripts/mode.sh: No such file or directory` followed by `MANGO_INSTANCE_SIGNATURE is not set` — which reads like a broken install rather than a wrong user. It also leaves a **root-owned elephant** running that your own `pkill -f 'bin/elephant$'` then cannot kill (`Operation not permitted`). `reload.sh` refuses to run as root as of 2026-07-31.

**`pkill -x elephant` does not work on NixOS** — fixed in `reload.sh` on 2026-07-30, and worth knowing because the same trap applies to any nixpkgs-wrapped binary. nixpkgs ships elephant as a wrapper, so the process `comm` is `.elephant-wrapped`, which the kernel truncates to 15 chars → **`.elephant-wrapp`**. `pkill -x` matches `comm` exactly, so it silently matched nothing and *every reload leaked another elephant process*. On Arch the binary was plain `elephant`, so this only broke after the migration. Match the command line instead: `pkill -f 'bin/elephant$'`. The script also `setsid`s the new elephant with stdout redirected — without that it inherits the caller's stdout, so `reload.sh | anything` hangs forever waiting for EOF on a pipe the daemon holds open.

**Papirus folder icons are recoloured at build time, not at runtime.** Stock Papirus folders are **blue**, which reads as badly broken against Gruvbox — the symptom is Thunar looking correctly themed *except* every folder icon. The usual fix, the `papirus-folders` CLI, recolours the theme **in place** and therefore cannot work on NixOS: the icon theme is a read-only store path, so the tool silently achieves nothing. nixpkgs exposes the same thing as a derivation argument, so `pkgs/default.nix` overrides `papirus-icon-theme` with `color = "yellow"` (matching `Gruvbox-Yellow-Dark`; `orange` would match the terminals). It is done in the **overlay** rather than at the call sites because both `gtk.iconTheme.package` and `systemPackages` reference the theme — overriding one would put two different Papirus derivations on `XDG_DATA_DIRS` and let lookup order pick the folder colour. `papirus-folders` was dropped from `systemPackages` on 2026-07-30.

Static theme baseline: **Gruvbox Dark** across terminals, editors, and shell. Fonts: **Hack Nerd Font Mono** at size 11 in kitty/foot, 0xProto Nerd Font for bold/italic variants.

**GTK theming is owned by Nix as of 2026-07-30, not by the mode scripts.** `modules/home/theme.nix` declares `gtk.*`, which writes both `settings.ini` files, both `gtk.css` files, the Thunar bookmarks and the `org.gnome.desktop.interface` dconf keys. This reverses the earlier decision, because its premise was false: `gtk-apply.sh` took a `$MODE` argument and ignored it, **both** modes called it as `gtk-apply.sh tiling`, and the `-tiling` variants were byte-identical to their targets — the same empty indirection as `active-theme.*`. `gtk-apply.sh` now only exports `GTK_THEME` to the systemd user environment and restarts `xdg-desktop-portal-gtk` (which caches the theme at startup). **Never have both setting the theme** — one owner, in either direction. See `docs/adr/0004`.

Default applications are set in `~/.config/mimeapps.list`. Current defaults:

| Type | Application | Desktop file |
|---|---|---|
| Browser (HTTP/HTTPS/HTML) | Zen Browser | `zen-beta.desktop` |
| PDF | Zathura | `org.pwmt.zathura.desktop` |
| Images | imv | `imv.desktop` |
| Video / Audio | mpv | `mpv.desktop` |
| Directories / ZIP | Thunar | `thunar.desktop` |
| Email / calendar | Betterbird | `eu.betterbird.Betterbird.desktop` |
| Shell scripts / Markdown | Neovim | `nvim.desktop` |
| Torrents / magnets | Free Download Manager | `freedownloadmanager_*.desktop` |
| `discord:` scheme | Equibop | `equibop.desktop` |
| `obsidian:` scheme | Obsidian | `obsidian.desktop` |

**LibreWolf is no longer installed** (verified 2026-07-27 — no package, no profile directory). The default browser is **Zen**.

### Zen on NixOS — everything is called `zen-beta`

The `zen-browser` flake installs the **beta** channel, so the binary, the desktop file and the Wayland `app_id` are all **`zen-beta`**. Arch's `zen-browser-bin` used `zen` for all three. Every one of those references had to be corrected on 2026-07-30, and each failed *silently*:

- `xdg.mimeApps` pointed at `zen.desktop`, which does not exist — so xdg fell back and `xdg-mime query default x-scheme-handler/https` reported **chromium**. Fixed in `modules/home/default.nix`.
- The zsh alias was `zen='zen-browser'`, a binary that exists on neither system.
- Two `mango/universal/rule.conf` window rules matched `appid:zen` / `appid:^zen$` (Picture-in-Picture float, and the opacity exemption) and so never fired. Confirm the real value with `mmsg watch focusing-client`, which reports `"appid":"zen-beta"`.

Note `nvim/scripts/zen-wrapper` is **unrelated** to this browser — it is a knap live-preview wrapper that launches chromium in app mode. Don't "fix" it to use Zen.

**The profile is at `~/.config/zen/`, and there are two of them — only one is real:**

| Profile | Size | State |
|---|---|---|
| `kxsz4wom.Default (release)` | **839 MB** | the real one — 13 extensions, saved logins, 39 KB `prefs.js` |
| `inemk327.Default Profile` | 64 MB | near-empty, no extensions, no logins |

Gecko resolves the profile root from `Profile=zen` in `application.ini`, i.e. `$XDG_CONFIG_HOME/zen` — so the directory carries across from Arch untouched. What does *not* carry is which profile is default: `profiles.ini` selects it per-installation via an `[Install<hash>]` section keyed on the **executable path**, and `/opt/zen-browser-bin/` became a `/nix/store/` path. With no matching install, Zen fell back to the legacy `Default=1` flag — which sat on the empty profile, so the first launch on NixOS came up with no extensions, no logins and no history.

Fixed by moving `Default=1` onto `[Profile0]` (the real profile) in `~/.config/zen/profiles.ini`; the pre-edit file is kept as `profiles.ini.bak-2026-07-30`. **Do not "fix" this by adding an `[Install<hash>]` entry for the current store path** — that path changes on every Zen update, which would orphan the setting again. A stale lock from the last Arch session (`lock -> 192.168.1.144:+53362`) was also cleared.

`~/.config/zen/` is 859 MB and in no repo; it survives purely via the shared `@home` subvolume, so it is **not** covered by a git clone or by the flake. Back it up separately.

Stale `librewolf.desktop` entries remain in `mimeapps.list` and can be removed. The `userChrome.css` / Sidebery notes below applied to the LibreWolf profile and are kept only for reference if you set up a Firefox-family browser again: chrome customisation requires `toolkit.legacyUserProfileCustomizations.stylesheets=true` in about:config, and Sidebery's custom CSS must be pasted into the extension's settings (Sidebery → Styles → Custom CSS) since it doesn't read from disk.

The `pdf` shell alias opens files via `xdg-open`, deferring to the system default.

## Editor setup

**Neovim** (`~/.config/nvim/`) — minimal hand-rolled config on `lazy.nvim` (~18 plugins; replaced a LazyVim install in June 2026). See `nvim/README.md` for the full map.
- `lua/config/` holds `options.lua`, `keymaps.lua`, `autocmds.lua`, `lazy.lua`; `lua/plugins/` holds one spec file per concern (colorscheme, treesitter, lsp, completion, coding, editor, ui, writing, ai)
- **No mason** — language servers are taken from `$PATH`, so they must be declared in `modules/home/packages.nix`. **This is shared with helix**, which also only *configures* servers rather than shipping them. The Arch-installed set did not survive the migration and nobody noticed for a day, because a missing server is skipped in silence: `rust-analyzer` was the only one working. `nil`, `lua-language-server`, `bash-language-server`, `marksman`, `taplo` and `yaml-language-server` were declared on 2026-07-30; `pyright`, `ruff`, `texlab`, `tinymist`, `stylua`, `shfmt` and `clangd` are still absent. **`hx --health` is the fastest audit** — one line per language, `✘` against any server it cannot find. LSP uses Neovim 0.11+ native `vim.lsp.enable`; completion is `blink.cmp`
- Tree-sitter is the classic `master` branch; parsers compile with system `cc`. `latex`/`bibtex` parsers are intentionally omitted (vimtex owns `.tex`/`.bib`)
- Writing stack: `render-markdown` (in-buffer), `knap` (live preview: `<leader>ks` once, `<leader>ka` toggle, `<leader>kc` close), `vimtex` (LaTeX, zathura viewer), `typst-preview` (`<leader>tp`). knap converter/wrapper live in `nvim/scripts/`
- `<C-d>` / `<C-u>` centre the cursor after scroll; Copilot ghost-text accept is `<M-l>`
- Old config + plugin data backed up to `~/.config/nvim.bak.*` and `~/.local/share/nvim.bak.*` (delete once settled)

**Helix** (`~/.config/helix/`) — installed and working, config is one line (`theme = "gruvbox"`) plus a `themes/` dir. **The binary is `hx`, not `helix`** — that is upstream's name for it, and there is no `helix` command. The desktop entry ships `Exec=hx %F` with `Terminal=true`, so the launcher entry works while typing `helix` in a shell does not; reported as "it's listed in Applications but the command doesn't work". Nothing is broken. Helix needs no plugins for highlighting, textobjects or indent — those are built in — but it does **not** ship language servers either, so it shares the `$PATH` dependency described under Neovim above. `hx --health` is the audit.

`$EDITOR`/`$VISUAL` are **`nvim`** (`modules/home/shell.nix`), which is what git, `sudoedit`, `systemctl edit`, lazygit and yazi all invoke. Changing editors means changing those, not adding an alias. Separately, `mimeapps.list` points `text/markdown` and `application/x-shellscript` at `nvim.desktop`, which governs GUI double-clicks and is independent of `$EDITOR`.

**Zed** (`~/.config/zed/settings.json`) — vim mode on, VSCode base keymap, Gruvbox Dark theme, MCP agent servers configured (opencode, claude-acp, github-copilot-cli).

## Desktop environment

**Mangowm** (`~/.config/mango/`) — Wayland compositor/WM. Config is split into universal settings (shared across modes) and per-mode overrides (`tiling/`, `hud/`). Each mode has its own `autostart.conf` and compositor config that gets copied to `config.conf` on mode switch.

Window rule positioning: `offsetx`/`offsety` are **percentages from the usable-area centre** (range −999 to 999). `±100` = the usable screen edge (i.e. respects the Waybar reserved area). Example: `offsetx:100,offsety:-100` = top-right corner just below the Waybar.

Key components running under Mangowm:
- **Waybar** — status bar, config and styles in `mango/waybar/` (per-mode layouts, switched with `SUPER+/`). The **full** layout (`config.jsonc`) was rearranged on 2026-07-31 to match `config-focus.jsonc`: **clock first on the left, `custom/window` in the centre**. It previously had the clock centred and the window title crammed on the left after `wlr/taskbar`. The **minimal** layout (`config-minimal.jsonc`) joined them the same day — its clock had been the first entry in `modules-right`. All three now differ only in which modules they carry (full keeps `wlr/taskbar`, `cpu`, `memory`, `custom/phone`; minimal drops everything but battery, tray and power), not in where the clock and title sit. **Keep them consistent** — the clock leads the left block in every layout, so switching layout with `SUPER+/` no longer moves it. The focused-window title comes from **`custom/window`**, backed by `scripts/waybar/window-title.sh` (streams `mmsg watch focusing-client` as waybar JSON). Do **not** reintroduce waybar's built-in `dwl/window` module: mango 0.15.5 (upgraded 2026-07-27) dropped the dwl IPC protocol `zdwl_ipc_manager_v2` that module binds to, and its absence makes waybar SIGSEGV on startup. CSS selector is `#custom-window`, not `#window`

  **The bar toggles between the top and bottom edge with `SUPER+SHIFT+/`** (added 2026-07-31, `scripts/waybar/waybar-position.sh`, state in `~/.local/state/mango/waybar-position`). It is a **toggle, not a picker** — the other two `/` binds open walker because they select between three or more options; two options do not earn a menu. Position cannot be passed on the command line: `waybar --help` offers only `-c`, `-s` and `-b`, and `position` is a config key — so `waybar-restart.sh` rewrites it into a generated copy at **`~/.local/state/mango/waybar-config.jsonc`** (a fixed path, replacing the `mktemp` that leaked a new `/tmp/waybar-XXXXXX.jsonc` on every switch). It **mirrors the vertical margins** at the same time, which is load-bearing rather than tidy: `config-hud.jsonc` sets `"margin-bottom": -28` against a 28px bar to cancel its exclusive zone, and that has to change edges with the bar. The margin swap runs through a `margin-swap` placeholder because sed applies every `-e` to the same line in order, so a plain top→bottom + bottom→top pair renames the key and immediately renames it back. Styling needs no per-position plumbing — waybar adds the position as a class on the window (`bar.cpp`: `add_class(to_string(position))`), so `window#waybar.bottom` in `style-solid.css` moves the separator to the top edge.

  **`bind=` matches on KEYCODE, `bindsym=` matches on keysym — which is why `SUPER+SHIFT,slash` is correct and not dead.** Shift turns `/` into the `question` keysym, and mango reads keysyms from the live xkb state (`mango.c`: `xkb_state_key_get_syms`), so a keysym comparison would never match a bind written as `slash`. It matches anyway because `bind=` entries are resolved to keycodes at parse time (`parse_config.h`: `parse_key(str, false)` → `find_keycodes_for_keysym`, `type = KEY_TYPE_CODE`) and compared by keycode, which does not consult the shift level. The same applies to `SUPER+SHIFT,1..9` (`exclam`, …), which is why those work. **If you ever switch a shifted bind to `bindsym=`, spell out the shifted keysym** — otherwise it silently never fires, with nothing in any log.

  **`#taskbar button` must keep `min-width` ≤ `icon-size`, or the window icons sit left of centre.** waybar builds each taskbar button as a `Gtk::Box` and adds the icon with `content_.add()` — i.e. `pack_start`, so the image is pinned to the **start** of the content box. Any width `min-width` claims beyond the icon therefore becomes empty space on the **right only**; at `min-width: 20px` against `"icon-size": 14` that was 6px of one-sided slack, and no symmetric padding could correct it. Both stylesheets now set `min-width: 14px` and widen the horizontal padding to hold the button's overall width, so the box hugs the icon and the padding centres it (2026-07-31). **The two numbers are coupled** — if `icon-size` changes in the layout JSON, change `min-width` to match. Same underlying shape as the power-profile glyph below: a container wider than its content, filled from one end.
- **fsel** — primary application launcher (`SUPER+Space`), runs in a floating foot terminal pinned to the right side via the `fsel-launcher` window rule. Config at `~/.config/mango/fsel/config.toml` — loaded by passing `XDG_CONFIG_HOME=/home/henry/.config/mango` in the keybind, matching Walker's pattern
- **Walker** — structured menus (bluetooth, clipboard, bitwarden, etc.); provider list bound to `SUPER+W`, configs in `mango/walker/configs/`. The wrapper at `mango/scripts/walker/walker.sh` injects a default `--maxheight 500` for non-HUD modes (so windows shrink to fit short lists) unless the caller passes its own
- **Network menu** (`mango/scripts/menus/network-menu.sh`) — bash dmenu script for WiFi/ethernet/VPN. Bound to `SUPER+CTRL+N` and Waybar network right-click. Supports `--warm` (build cache at startup, in autostart) and `--reload` (rescan + relaunch). Replaces an earlier elephant Lua provider that couldn't preserve section order
- **Rofi** — secondary launcher/menus, themed in `mango/rofi/`
- **Elephant** — shell widget layer, menus in `mango/elephant/`
- **swaync** — notification daemon, styled in `mango/swaync/`. **Autostart owns the process, not systemd**: the `exec=` line in each mode's `autostart.conf` pkills and respawns it with `-s ~/.config/mango/swaync/style.css`, so a restyle takes effect on mode switch. The unit nixpkgs ships is masked in the flake — see NixOS point 7 below. Don't enable both.
- **Wallpaper (awww)** — `mango/scripts/system/wallpaper-restore.sh`, run from `mango/universal/autostart.conf`, starts `awww-daemon` and re-applies `mango/wallpaper/wallpaper.png`. Added 2026-07-30: nothing had started the daemon before, so the wallpaper had to be re-set by hand after every boot (true on Arch too). The binary is **`awww`, not `swww`** — nixpkgs renamed the package to the fork already in use. `mango/scripts/system/set-wallpaper.sh <image>` changes it. **The image lives at `~/.local/share/mango/wallpaper.png`** — moved out of the config tree on 2026-07-30, because a 4.6 MB PNG cannot live in a read-only store path, and because it is user data rather than configuration. It is in no repo; the restore script exits 0 when it is absent, so a fresh clone is not an error, it just has no wallpaper.
- **Power profile** — `custom/power-profile`, backed by `mango/scripts/system/power-profile.sh`, reading **`/sys/firmware/acpi/platform_profile`** (choices: `low-power balanced performance`). Click cycles, right-click forces `low-power`, and **`SUPER+SHIFT+P` cycles from the keyboard** (that key previously held the dead `wlopm` bind). Refresh signal is `RTMIN+11`. The profile is the **firmware/EC** setting and is independent of TLP, which does its own AC-vs-battery tuning — they stack, which is why power-profiles-daemon had to be disabled while this does not. This **replaced waybar's built-in `power-profiles-daemon` module on 2026-07-30**, which had never worked here: that module binds the `net.hadess.PowerProfiles` D-Bus API, and power-profiles-daemon is disabled in `power.nix` because it conflicts with TLP — so `busctl --system list` shows nothing implementing it and the module rendered empty, reading as *missing from the bar* rather than broken. `power.nix` also claimed NixOS's TLP module bridges TLP to that API the way Arch's `tlp-pd` does; **it does not**, and that wrong comment is why it went unexamined. The ACPI attribute needs no daemon; writing it needs group permission, granted by a `systemd.tmpfiles` rule handing it to `wheel` (a udev rule cannot — it is not a device attribute). Note ACPI says `low-power`, where power-profiles-daemon said `power-saver`; the CSS classes changed to match.

  **Its icons are `$'\uXXXX'` escapes, deliberately.** Written as literal glyphs they were lost in transit and every branch assigned the empty string, so the module emitted `{"text":""}` and waybar drew nothing — reported as *"I still don't see a power mode module"*, because **an empty custom module is indistinguishable from an absent one**. Same failure shape as the exit-127 scripts, and it survived a rebuild because the script ran fine and exited 0. When a `custom/*` module is missing from the bar, run its exec by hand and check the `text` field is non-empty, not just that the script succeeds.

  **It renders in `Symbols Nerd Font Mono`, not the bar's `3270 Nerd Font`, and that is what centres it.** 3270 patches the Font Awesome icons in at their natural width but keeps its own narrow **0.54em advance** — `fa-circle_half_stroke` (U+F042) advances 1080/2000 units while its ink spans 0..1846 — so the glyph overflows its cell to the right and sits jammed against the next module's border, with all the slack on the left. Reported as *"the icon is off centre"*, and **padding cannot fix it**: symmetric padding centres the advance box, not the ink. Symbols Nerd Font Mono gives all four glyphs a full 1em advance with the ink centred inside, so ordinary padding works. Fixed 2026-07-31 in `style.css` and `style-solid.css`. To check any other icon-only module for the same thing, compare `adv` against the glyph bounds with fontTools — the module gets *wider* when this is fixed, since the real advance was always understated.
- **Night light (wlsunset)** — the **systemd user service owns the process**; `mango/scripts/menus/night-mode.sh` only drives that unit (`systemctl --user start/stop/restart`). Never go back to `pgrep`/`pkill` + spawning a second wlsunset: only one Wayland client can hold a gamma control, so the loser prints `gamma control of output eDP-1 failed` and silently does nothing. The unit is hand-written in `modules/home/default.nix` rather than using `services.wlsunset`, because that module bakes temperatures into a static `ExecStart` and wlsunset has no runtime IPC — so the waybar temperature picker could not change them. Instead `ExecStart` is `mango/scripts/system/night-light-run.sh`, which reads the chosen night temperature from `~/.local/state/mango/night-temp` at start; the picker writes that file and restarts the unit. Location and day temperature stay declared in Nix via `Environment=`. Waybar module: `custom/night-mode`, refreshed by `pkill -RTMIN+9 waybar`.
- **wlogout** — the session menu (lock/suspend/reboot/shutdown/logout) behind the waybar power icon (`custom/power`). **Its glyph is the NixOS logo, `` (nf-linux-nixos), as of 2026-07-31** — set identically in all four layouts. That codepoint is **not** in every Nerd Font: the bar renders in `3270 Nerd Font` (`style.css`), which does have it. Check before swapping in another glyph — `fc-list ':charset=f313' family` lists the fonts that carry it, and a glyph the font lacks renders as an empty box with nothing in any log. It is **coloured at rest** (`@blue`) rather than only on hover, and still turns `@red` on hover to flag that the menu is destructive. Note each stylesheet declares `#custom-power` **twice** — once in a grouped rule that sets `color: @text`, then again later — so the second declaration is the one that wins; edit that one. `@blue` (#83a598, Gruvbox bright blue) was added to `waybar/colors.css` for this; the palette had no blue at all. Not to be confused with `custom/power-profile`, a different module. Layout and CSS in `mango/wlogout/`; its five PNGs are **vendored into `mango/wlogout/icons/`** and referenced relatively. See NixOS point 3 below for why.
- **Proton Drive — removed 2026-07-30, do not re-add.** Proton actively blocks rclone's standard access method, so the mount cannot be made reliable however the unit is written; and it was inherited config, not something in use. Cloud sync here is **Nextcloud**, via `services.nextcloud-client`. Both the `rclone-protondrive` unit and the Arch-era `rclone@ProtonDrive.service` template are gone, along with `~/ProtonDrive` and the dangling `~/mnt` → `/run/media/henry` symlink. `rclone` stays in `packages.nix` for interactive use. See NixOS point 8 for what leaving it in place cost.
- **Polkit agent** — **on NixOS this is `polkit_gnome`**, run as the systemd user service `polkit-gnome-authentication-agent-1` (`modules/system/desktop.nix`), *not* from autostart. The `exec-once=... command -v lxpolkit && lxpolkit` line in `mango/universal/autostart.conf` is an Arch leftover. It is guarded by `command -v`, so it is a permanent no-op — `lxsession`/`lxpolkit` are not installed and, with Arch gone, never will be. Safe to delete whenever that file is next edited. Note: `exec-once` only fires on initial compositor startup, not on reload — log out/in after changing autostart.
- **KDE Connect** — `kdePackages.kdeconnect-kde`. Both `autostart.conf` files start `kdeconnectd`, and the Waybar phone module (`mango/scripts/kdeconnect/phone-status.sh`) queries the `org.kde.kdeconnect` D-Bus name and shells out to `kdeconnect-cli`. **Do not swap in `valent`** — it is a different implementation under `ca.andyholmes.Valent` and satisfies none of those call sites. Firewall ports 1714-1764 are opened in `modules/system/networking.nix`.
DankMaterialShell and Quickshell were **removed in July 2026**, along with the `dms` mode and all its theme files. Two things kept their names deliberately: `kitty/tabs.conf` (renamed from `dank-tabs.conf`; included by `kitty.conf` in every mode) and `yazi/flavors/noctalia.yazi` (still the active yazi theme per `yazi/theme.toml`).

Mangowm is the sole desktop environment. KDE Plasma has been removed from this system.

## Battery charge thresholds

ThinkPad EC thresholds are set by TLP in `modules/system/power.nix`: **START 40 / STOP 85**. Live values are `/sys/class/power_supply/BAT0/charge_control_{start,end}_threshold` (the older `charge_{start,stop}_threshold` aliases mirror them).

**Two coupled settings, and the coupling is not obvious:**
- `STOP_CHARGE_THRESH_BAT0` must match **`"full-at"` in `mango/waybar/config-focus.jsonc`** (currently **85**). Waybar rescales the reading as `shown = real / full-at × 100`, so with STOP at 80 against a `full-at` of 85 the bar peaked at 94% and displayed 88% at a real 75% — reported as "stuck at 88%". Change one, change the other.
- Only `config-focus.jsonc` carries `full-at`; `config.jsonc`, `config-minimal.jsonc` and `config-hud.jsonc` have none and therefore show the **raw** percentage. Switching layout with `SUPER+/` changes the number you see.

**Expected behaviour that looks like a fault:** with START at 40, a battery on AC parks at whatever charge it had and only tops back up below 40%. `status` then reads `Not charging`, and waybar maps that to `format-plugged` (plug glyph) — the lightning bolt is `format-charging` and appears only for `status = Charging`. So a plug icon with a sub-100% reading that never moves is the hysteresis working. Raising STOP does **not** trigger a charge; the EC only starts below START. To force a top-up: `sudo tlp setcharge 84 85 BAT0`.

Note `upower -i` reports `charge-start-threshold: 75%` regardless of the real value — trust sysfs, not upower, for thresholds.

## Suspend — s2idle only, and the panel is software's problem

`cat /sys/power/mem_sleep` reports **`[s2idle]`** with no `deep` alternative: the firmware exposes Modern Standby (s0ix), not S3. Putting `mem_sleep_default=deep` on the kernel command line would therefore achieve nothing. Journal confirms it every time — `PM: suspend entry (s2idle)`.

**The consequence that looks like a fault:** s2idle does not cut power to the display. S3 blanked the panel in hardware; under s2idle the software owns it, and nothing did — so suspending left the last frame lit on screen. Reported as "suspending doesn't turn off the screen, just freezes it". The machine was suspending and resuming correctly the whole time (`suspend entry` → `suspend exit`, WiFi reassociating via the hook in `networking.nix`).

Fixed 2026-07-30 with `powerManagement.powerDownCommands` / `resumeCommands` in `modules/system/power.nix`, driving the **backlight** via `brightnessctl` (`--save` + `set 0`, then `--restore` with a `set 50%` fallback so a failed restore can't wake to a permanently black screen). Both land in the generated `sleep-actions.service` — `ExecStart` before sleep, `ExecStop` on resume.

**`brightnessctl set 0` is not sufficient on its own, and the shortfall reads as a partial fix.** On amdgpu, brightness 0 is the panel's *minimum*, not off, so the first version of this hook left the screen lit at low brightness — reported as "suspend works, but screen stays on with brightness low". The panel's real power switch is `/sys/class/backlight/amdgpu_bl1/bl_power`, which takes the kernel fb blanking levels: **0 = FB_BLANK_UNBLANK, 4 = FB_BLANK_POWERDOWN**. The hooks now write `4` on the way down and `0` on resume, **before** `--restore` — clearing `bl_power` first is required, or the panel stays dark no matter what brightness is written. Added 2026-07-30, needs one suspend to confirm.

### Why not wlopm / Wayland DPMS

**mango advertises no `wl_output` global at all.** It offers `zwlr_output_power_manager_v1` (and `zwlr_output_manager_v1` v4, `zxdg_output_manager_v1` v3), but of the 51 globals on the wayland socket, none is `wl_output`. So every output-enumerating client sees nothing:

- `wlopm --json` → `[]`, and `wlopm --off '*'` matches zero outputs — a silent no-op
- `wlr-randr` prints nothing
- `mmsg get all-monitors` → `{"monitors":[]}`

…while `mmsg watch focusing-client` happily reports `"monitor":"eDP-1"` and `awww` sets the wallpaper on `eDP-1: 1920x1200`. Identical on both `wayland-0` and `wayland-1`, so it is not a socket mix-up. This is why the backlight is the mechanism: `brightnessctl` writes `/sys/class/backlight/amdgpu_bl1` and needs no compositor connection, which also makes it correct when the lid closes on a locked session.

**`wlopm` is deliberately not installed** — see the comment in `modules/home/packages.nix`. `bind=SUPER+SHIFT,p` used to be `wlopm --off '*'` ("power off monitors") and was dead for the reason above — not a missing package, but a missing protocol. **That key was reclaimed on 2026-07-31 to cycle the ACPI power profile**; there is still no way to blank the outputs from a keybind, and no idle daemon (no swayidle/hypridle), so the screen never blanks on idle either.

## Networking

**WiFi card**: Qualcomm QCNFA765 (`wlp1s0`), driver `ath11k_pci`. `Minerva_2` (enterprise router) is the network the resume bug below was diagnosed on, but it is not the only one in use — as of 2026-07-30 the machine was on `Vodafone-3A90`, also on `192.168.1.0/24`, which is the subnet the Gitea host lives on. 37 NetworkManager connections are defined in total.

**Known issue — WiFi fails to recover after system suspend**: The ath11k_pci driver does not cleanly reinitialize on resume, and the enterprise router drops the association. NM retries but DHCP times out and the connection never recovers. Manually restarting NetworkManager fixes it.

**Fix in place (two separate layers, both necessary)**:
- TLP config (`/etc/tlp.conf`) — sets `WIFI_PWR_ON_AC=off` and `WIFI_PWR_ON_BAT=off`. Prevents the radio from power-saving during normal runtime. Does *not* affect suspend/resume behaviour.
- `/etc/systemd/system-sleep/wifi-resume.sh` — cycles the WiFi radio off/on 3 seconds after system wake, forcing a clean re-association. This is what actually fixes the resume failure.

These can't be merged: TLP is applied by its service; the sleep hook is executed by systemd. Each covers a different failure mode.

**On NixOS both are declarative — do not edit `/etc` directly**, it is generated and read-only. `networking.wifi.powersave = false` and `systemd.services.wifi-resume` live in `modules/system/networking.nix`; the TLP settings are in `power.nix`. Change those and `nixos-rebuild switch`.

If the issue recurs, check `journalctl -u NetworkManager` for DHCP timeout after wake. Disabling Fast Transition (`nmcli connection modify Minerva_2 wifi-sec.key-mgmt wpa-psk`) is an additional option if the sleep hook alone doesn't resolve it.

### VPN profiles: autoconnect is off, deliberately

The 9 VPN profiles (`homelab` WireGuard + 8 PIA OpenVPN exits) all came off the backup with `connection.autoconnect=yes` and `ipv4.dns-priority=0`. **All 9 were set to `autoconnect=no` on 2026-07-30.** Don't turn it back on.

The failure mode, seen the moment the profiles were restored: `homelab` auto-activated, claimed `+DefaultRoute`, and pushed its DNS server `192.168.1.5` onto *every* link. Away from `Minerva_2` that server is unreachable, so **all** name resolution failed — `resolvectl query` returned "All attempts to contact name servers or networks failed" for everything. Nothing identifies itself as a VPN problem at that point; it presents as total DNS death, and the visible symptom was rclone reporting `lookup drive-api.proton.me: no such host`. Check `resolvectl status` for a tunnel holding `Default Route: yes` before suspecting anything else.

Bring the tunnel up by hand when you are **away from the home LAN** and need Gitea: `nmcli connection up homelab`. `git.henrydowd.dev` is `192.168.1.200`, a LAN address — so on `192.168.1.0/24` it is reachable directly and the tunnel is not involved at all. Verified 2026-07-30: `git push` and `tea` both work with no VPN active. (This file previously said the tunnel was the *only* route, which is wrong and would have you chasing a VPN when nothing is broken.)

**These profiles are not in git and not declarative.** They live in `/etc/NetworkManager/system-connections` (root-only, mode 600) and were restored by hand from the backup drive. If you ever re-restore them, the `autoconnect=yes` comes back with them and so does the DNS failure.

## NixOS migration — INSTALLED 2026-07-29, now the booted system

the flake at the repo root that reproduces this machine. **It is live and it is the only system.** `nixos-install` completed on 2026-07-29 and the machine boots NixOS; Arch stayed selectable from the boot menu through the transition and was removed on 2026-07-30. `docs/archive/MIGRATION.md` §8c records the install, `docs/archive/MIGRATION-GUIDE.md` Part 10 the restore steps — both are history now, not instructions.

**What is done:** install, bootloader, both EFI entries, root and `henry` passwords, home-manager activation, mango starting. Then, verified on 2026-07-30: CLI credentials (`rclone`, `gh`, `glab-cli`, `rbw`), the printer (`Brother_MFC_L3740CDW_series` — driverless IPP discovery found it, `/etc/cups` never touched), the GTK theme resolving to `Gruvbox-Yellow-Dark`, 3270 Nerd Font, magnet links reaching qBittorrent, and the 8 OpenVPN `.pem` certs which survived via `@home`. `mango/wallpaper/` is restored — it is a single 4.6 MB `wallpaper.png`, not a collection.

**What remains** (nothing blocking; see `MIGRATION-GUIDE.md` Part 10):
- ~~Restore NetworkManager profiles and Bluetooth pairings~~ — **done 2026-07-30**: 35 profiles into `/etc/NetworkManager/system-connections` (37 connections, 8 VPN) and 7 Bluetooth devices into `/var/lib/bluetooth`. See the VPN autoconnect note under Networking — restoring the profiles broke DNS until autoconnect was turned off.
- ~~Clean up `~/.config/*.hm-bak` and the `.arch-bak` units~~ — **done 2026-07-30**: all 21 `*.hm-bak` entries removed, plus `micmute-led.service.arch-bak` and `mango-session.target.hm-bak`. Each was diffed against its repo counterpart first; the only content that existed *nowhere else* was `mango/state/pia-auth` (PIA credentials, mode 600) and `mango/state/last-vpn`, both restored into `mango/state/` before deleting. `micmute-led.service` now resolves to `/etc/systemd/user/` and runs (verified `enabled` + `active`, with `platform::micmute` present).

  **Finished 2026-07-30**: five hand-written units the `*.hm-bak` sweep did not cover were still present — `claude-message.service`, `claude-message.timer`, `elephant.service`, `rclone-nextcloud.service`, `rclone@.service` — plus two dangling `default.target.wants` links (`gpu-screen-recorder-ui.service` → `/usr/lib/systemd/user/`, which does not exist on NixOS, and `micmute-led.service` → the file already deleted). All removed, backed up to `~/arch-residue-backup-2026-07-30/`. **`~/.config/systemd/user/` now contains only home-manager symlinks into the store** — no hand-written content remains, so the shadowing hazard in point 1 is closed rather than merely audited.
- Verify the suspend screen-blank fix — suspend/resume itself is confirmed working (WiFi reassociates), but the `brightnessctl` sleep hooks added 2026-07-30 need one rebuild plus one suspend to confirm. See Suspend above.
- ~~Don't delete the Arch subvolumes (`@`, `@pkg`, `swap`) until a month has passed without booting it.~~ — **superseded 2026-07-30**: Arch was removed outright, see the top of this file. `/etc/fstab` now mounts only `@nixos`, `@home`, `@nix` and `@log`, and nothing Arch-era is mounted. There is no fallback to preserve.

**Dead weight removed 2026-07-30, once Arch was gone.** `~/src/arch-config` (the old repo — verified to hold nothing that was not already in this one) and `~/.config/.git` (a third clone, at an ancestor commit, left over from when the repo root *was* `~/.config`). From the repo itself: `home/fish/` (the shell is not installed — `command -v fish` finds nothing), `home/zsh/.zshrc` (Arch-era, superseded by the one `programs.zsh` generates), 20 tracked `home/zsh/.zsh_tmp_git_*` junk files, `home/gtk-4.0/assets` (a symlink into `/usr/share/themes/…`, which does not exist here, and which nothing referenced), and `home/mango/walker/themes/noctalia` (a symlink that resolved into its own parent via `~/.config/walker`, so it was an unresolvable loop). Anything not recoverable from git history was tarred into `~/arch-residue-backup-2026-07-30/` first.

**Ten things that will surprise you if you don't know them:**
1. **`~/.config/systemd/user/` overrides `/etc/systemd/user/`**, and that directory survived the migration via `@home`, so Arch-era units silently shadow the ones the flake generates. `micmute-led.service` was shadowed this way: the leftover copy had no `PATH=`, so `pactl` was not found and the daemon exited instantly — 6464 restarts deep. Moved aside on 2026-07-30 and deleted the same day, so `micmute-led.service` now resolves to `/etc/systemd/user/` and runs. To audit: compare `ls ~/.config/systemd/user/` against `/etc/systemd/user/`; that was the only collision. Note a unit's `path`/`Environment=PATH` is its **entire** PATH, so anything a script shells out to must be listed — including **`bash` itself**, since every script here is `#!/usr/bin/env bash`.
2. **There is no `/bin/bash`** — `/bin` holds exactly one entry, `sh`. Every script must use `#!/usr/bin/env bash`; a `#!/bin/bash` shebang fails with `bad interpreter` and exit 127. This bit 13 scripts after the migration (fixed 2026-07-30), and the symptom is *silence*, not an error: a waybar `custom/*` module whose `exec` script exits 127 simply renders as an empty module, which reads as "the module is missing from the bar". `custom/night-mode` disappeared this way. When something in mango is inexplicably absent, run its script by hand first.
3. **`share/<pkgname>` is not in `environment.pathsToLink`**, so a package's data files exist *only* at its versioned `/nix/store` path — `/run/current-system/sw/share/wlogout/` does not exist even though wlogout is in `systemPackages`. Never hardcode `/usr/share/...` or a store path in a config. `mango/wlogout/` vendors its five PNGs into `wlogout/icons/` and references them **relatively** (`url("icons/lock.png")`), which works because GTK resolves CSS `url()` against the stylesheet's own path. GTK draws its missing-image box for a failed `url()` **without logging a warning**, so this class of bug is invisible in logs — it was reported as "the icons are just square boxes".
4. **Generated files are gitignored**, so a fresh clone lacks them. `mango/config.conf` is the big one — it `source=`s every keybind and autostart line, and without it mango runs on built-in defaults (no waybar, no shortcuts). Run `~/.config/mango/scripts/modes/tiling.sh`, then log out and back in. That one script is now the whole list: `mango/state/` moved to `~/.local/state/mango/` and `kitty/active-theme.conf` / `foot/active-theme.ini` were removed, both on 2026-07-30, so neither is a fresh-clone concern any more.
5. **`cc` and `c++` are clang, not gcc** — the reverse of Arch. `packages.nix` carries `(lib.hiPrio clang)` to break a `buildEnv` collision with `gfortran`, which ships its own `cc`/`c++`. `gcc`, `g++` and `gfortran` are all still on PATH.
6. **`buildEnv` collisions are the failure mode to expect** when adding packages. Two packages owning the same file path abort the whole generation. If one supersedes the other, drop it; if they merely contend over a few names, use `lib.hiPrio` on the winner — **not** `lib.lowPrio` on the loser, which silently does nothing when the two priorities are already equal.
7. **nixpkgs packages ship user units that Arch's packages did not**, and they auto-start. `swaync` is the case in point: nixpkgs' SwayNotificationCenter ships `swaync.service` with `WantedBy=graphical-session.target`, so it raced the `exec=` line in `mango/{tiling,hud}/autostart.conf` — which is the copy that matters, because it passes `-s ~/.config/mango/swaync/style.css`. Autostart won the `org.freedesktop.Notifications` bus name and the unit died with `An instance of SwayNotificationCenter is already running!`, five times, then sat in `start-limit-hit`. **Notifications worked the whole time**, which is why it went unnoticed until 2026-07-30. It is now masked in `modules/home/default.nix` via `xdg.configFile."systemd/user/swaync.service".text = ""` — an empty unit file loads as `masked` per systemd.unit(5), and the usual `source = "/dev/null"` is rejected by pure evaluation as an absolute path. When adding a package that has a daemon, check `ls $(nix eval --raw nixpkgs#foo)/share/systemd/user/` before trusting autostart to be the only owner.
8. **A ported unit can carry a path that only worked by accident.** `rclone-protondrive` faithfully reproduced the Arch template's `%h/mnt/%i`, but `~/mnt` is a symlink to `/run/media/henry` — the udisks removable-media directory, which does not exist unless a drive is mounted. `mkdir -p` reports `File exists` for a dangling symlink rather than creating anything, so rclone could not make its mount point, and `Restart=on-failure` retried every 5s until Proton answered **HTTP 429 with a one-hour backoff** — 230 restarts deep when caught on 2026-07-30. Now mounted at `~/ProtonDrive` (matching the `~/Nextcloud` convention), with `RestartSec=30` and `StartLimitBurst=5`/`StartLimitIntervalSec=600`. **Any unit that talks to a remote API needs a start limit**, or a local misconfiguration becomes an unattended request flood against someone else's service.

   **Two follow-ups found 2026-07-30, after the above was written.** First, the *old* Arch template was never disabled — `default.target.wants/rclone@ProtonDrive.service` → `~/.config/systemd/user/rclone@.service` was still enabled and restart-looping on `/usr/bin/rclone` (203/EXEC, a path that does not exist on NixOS). Two enabled units for one mount. Disabled and removed. Second, and more seriously: the 230-restart flood escalated past rate-limiting. Proton now returns **422 Code=2028, "unusual activity targeting your account … we have temporarily limited access"** — an account-level abuse restriction, not a backoff. The unit is stopped; **do not restart it to test**, each attempt reinforces the flag. It needs either time or an appeal at `proton.me/support/appeal-abuse`. This is the real cost of the missing start limit, and it landed on the account rather than the machine.

   **Resolved by deletion, 2026-07-30.** Proton Drive is not used here and Proton blocks rclone's standard method anyway, so the whole mount was removed from the flake rather than repaired. The transferable lesson is the one above and it still stands for every future service: **a `Restart=` without a `StartLimitBurst=` is a loaded gun**, and when the target is someone else's API the damage is not confined to your machine.
9. **The compositor exposes no `wl_output`, and the machine only has s2idle.** Two independent facts that combine into one confusing symptom — suspend leaving a lit, frozen screen. Neither is fixable by a package or a kernel parameter, and the tool you would reach for first (`wlopm`) fails silently rather than erroring. Full detail in the **Suspend** section above; read it before touching anything to do with displays, DPMS or idle behaviour.
10. **swaylock needs a PAM service declared by hand on mango, or it can never unlock.** swaylock is not setuid and does not read `/etc/shadow` itself — it authenticates through PAM as the service name `swaylock` (true for `swaylock-effects` too). With no `/etc/pam.d/swaylock`, PAM falls back to `/etc/pam.d/other`, which on NixOS is `pam_warn` + `pam_deny`: **every password is rejected, correct or not.** sway and river get this free because their nixpkgs modules import `modules/programs/wayland/wayland-session.nix`, which sets `security.pam.services.swaylock = { }`; `programs.mango.enable` does **not** import it — it only wires portals and `displayManager.sessionPackages`. There is no `programs.swaylock` NixOS module to enable, and installing `pkgs.swaylock` alongside `swaylock-effects` would only be a `buildEnv` collision over `bin/swaylock`. Declared in `modules/system/desktop.nix`; locked out this way on 2026-07-30. The only diagnostic is `pam_warn(swaylock:auth)` in the journal — the lock screen just says the password is wrong. **Do not try to escape it with `pkill swaylock`.** swaylock locks via `ext-session-lock-v1`, and that protocol requires the compositor to **stay locked** if the lock client dies without sending `unlock_and_destroy` — that is the protocol's security guarantee, not a bug. Killing swaylock therefore leaves mango showing a permanently blank surface with the session still locked, which reads as "my mango session is blank". `mmsg` has no unlock command (nothing lock-related in its API), so the only ways out are relaunching swaylock on that same `WAYLAND_DISPLAY` to take over the abandoned lock and authenticating, or restarting the session and losing what was open. Both happened on 2026-07-30; the reboot was the fix.

Inputs are pinned by `flake.lock` (nixpkgs `624af665`) — re-lock deliberately with `nix flake update`, not as a side effect of a build. `verify-packages.sh` re-checks that the closure evaluates, but note it only evaluates: it cannot catch profile collisions or a derivation that fails to build.

**Installer media is ready (2026-07-29):** the SK Hynix 256 GB in the AMicro AM8180 USB enclosure carries `nixos-minimal-26.05` as a whole-device `dd` (iso9660, label `nixos-minimal-26.05-x86_64`, plus a `vfat` `EFIBOOT` partition). It previously held a dead `archinstall` system, verified empty before wiping. The Samsung 128 GB backup drive is separate and untouched by that work — one 100 GiB ext4 partition plus a spare ~19.5 GiB unallocated tail. See `docs/archive/MIGRATION.md` §8b, including why the ISO cannot live on a spare partition and the `parted`-`G`-means-GB trap that briefly truncated the backup drive's filesystem.

- `flake.nix` — inputs: nixpkgs unstable, home-manager, nixos-hardware, plus only two third-party flakes (`zen-browser`, `claude-desktop`). Most AUR software turned out to be in nixpkgs already — `mango`, `fsel`, `walker`, `elephant`, `dsearch`, `weathr`, `sidequest`, `winboat`. (`dms-shell`, `quickshell`, `dgop` and `valent` are packaged too, but are excluded on purpose — DankMaterialShell is being dropped, and `valent` is the wrong KDE Connect implementation for these configs; see below.) Note `claude-desktop` must NOT use `inputs.nixpkgs.follows`; it references the removed `pkgs.nodePackages` and only builds against its own pin.
- `hosts/thinkpad/` — host config and `hardware-configuration.nix` (real UUIDs from the live fstab)
- `modules/system/` — one file per concern: boot, locale, networking, audio, desktop, fonts, power, printing, virtualisation, nix-settings
- `modules/home/` — home-manager: packages, shell, dotfiles, theme
- `pkgs/default.nix` — overlay + templates for packaging AUR software
- `verify-packages.sh` — checks which package names resolve in nixpkgs; run before any rebuild

### Store-based vs out-of-store — the rule

`modules/home/dotfiles.nix` is **mixed**, and which side an entry falls on is decided by one question: *does a running program rewrite a file that is tracked in this repo?*

- **Store-based** (`source = ../../home/X`) — reproducible. A fresh clone plus a rebuild reproduces it exactly, and `~/.config/X` no longer depends on `~/src/nix-config` existing at all. As of 2026-07-30: `mango`, `nvim`, `helix`, `kitty`, `foot`, `ghostty`, `zsh/conf.d`, `yazi`, `bottom`, `lazygit`, `glow`, `imv`, and `~/.scripts`.

  `mango` and `nvim` converted by **moving the writer**, which is the general lesson: `nvim`'s `lazy-lock.json` now lives in `stdpath("state")` (seeded from the tracked copy on first run), and `mango` uses `recursive = true` so the mode scripts can still create the gitignored `config.conf`. Relocating what writes beats accepting a mutable directory.
- **Out-of-store** (`link "X"` → `mkOutOfStoreSymlink`) — a live symlink into the checkout, so edits take effect with no rebuild, but a fresh clone gets a *symlink and no content*. Still required for **`corectrl` only** — it writes `corectrl.ini` and `profiles/*.ccpro` from its GUI, and that GUI is the program. Pinning them would remove the only way the tool is used.

**Third technique, and the one to reach for first: manage a *file*, not a directory.** `xdg.configFile."htop/htoprc".source` puts the config read-only in the store while leaving `~/.config/htop` a real, writable directory — home-manager links a directory-valued `source` as one symlink, but a file-valued one as a real directory containing a file symlink. Sibling runtime files keep working; `ncspot/userstate.cbor` is the case that proves it. Applied to `htop`, `ncspot`, `zed`, `Kvantum`, `nwg-look`. The cost is that these configs can no longer be changed from inside the app — edit the repo and rebuild.

**`gtk-3.0`/`gtk-4.0` are now generated outright** by the `gtk` block in `modules/home/theme.nix` — `settings.ini`, `gtk.css` and the Thunar bookmarks all come from Nix, along with the dconf keys. See the GTK note under Theming.

**`recursive = true` has a trap that destroys the repo — read this before using it.** A plain `source` makes `~/.config/X` *one* symlink to a read-only store directory. `recursive = true` instead creates files *inside* `~/.config/X`, leaving the directory writable. If `~/.config/X` is **already an out-of-store symlink into the checkout**, those writes follow it into the repo: converting `mango` this way on 2026-07-30 replaced **65 tracked files in `home/mango/` with symlinks**, which `git status` reports as typechanges (` T `), and whose targets resolved in a loop — so the live config broke too. Recovered with `git checkout -- home/mango`; reverted to out-of-store.

`nixos-rebuild test` compounds it: it activates **without creating a profile generation**, so the new store path has no GC root and a later `nix-collect-garbage` can delete exactly what the repo now points at.

Converting an already-linked directory therefore requires **deleting `~/.config/X` first**, so home-manager builds a fresh directory rather than writing through the old link. That is a manual step; no rebuild does it for you.

**Symlinking harder does not make the remaining seven declarative.** The real fix for each is a native home-manager module — `programs.htop`, `gtk.*`, `qt.*` — which *generates* the file from Nix so nothing needs to write to it at runtime. That is a per-app conversion, not a mechanical one.

Consequence to keep in mind when editing `dotfiles.nix`: the link **source** must be a path outside `~/.config`, because `xdg.configFile.<name>` writes *to* `~/.config/<name>`. The flake therefore expects this repo cloned at **`~/src/nix-config`**, not used in place at `~/.config`. Pointing a link at its own destination produces a symlink to itself, and with `backupFileExtension = "hm-bak"` that fails silently rather than loudly. Two rules follow: only link directories that are actually tracked in git (`gh`, `glab-cli`, `gpu-screen-recorder`, `opencode` are credential dirs `.gitignore` excludes by name, so none of them are linked), and the flake now sits at the repo root, so `nixos-rebuild` runs against `~/src/nix-config` itself. Note this caveat applies only to the `link`/out-of-store entries — a store-based `source = ../../home/X` has no such hazard, since it never points back at its own destination.

Installation was **side-by-side** and is now the only system: `@nixos` and `@nix` btrfs subvolumes on `nvme0n1p2`, reusing `@home` and the shared ESP. Arch stayed bootable through the transition and was removed on 2026-07-30.

## Scripts

Scripts live in **`home/scripts/`** in this repo and are linked to `~/.scripts` as a **store path** (`dotfiles.nix`). They moved in on 2026-07-30; before that they existed only on this disk, in no repo and no backup, while `modules/system/audio.nix` declared a systemd unit whose `ExecStart` pointed at one of them — so a fresh install produced a unit that could not start. That unit now references the store directly.

**None of them have a file extension** — they are bash scripts named without `.sh`:
- `toggle_lid_action` — toggle lid close behaviour in `/etc/systemd/logind.conf` (run via `lidaction` alias)
- `clean_tmp` — clean tmp files (run via `cleantmp` alias)
- `keyd-application-mapper` — per-application keyd layer switching
- `micmute-led` — daemon that syncs the ThinkPad mic-mute LED with PipeWire's default source mute state; subscribes to PipeWire events via `pactl subscribe`. On NixOS it runs as the user service declared in `modules/system/audio.nix`, which is also the **only** place `pactl` exists: it comes from `pkgs.pulseaudio` on that unit's `path`, and is deliberately *not* in `systemPackages`, so running this script from an interactive shell fails with `pactl: command not found`. Write access to the LED comes from the udev rule in the same file. Don't add a `.sh` extension — the real filename has none.
- `pdf_to_a4` — converts a PDF to A4 page size using Ghostscript, preserving aspect ratio; usage: `pdf_to_a4 input.pdf [output.pdf]`
- `texpdf` — compiles a LaTeX file to PDF with pdflatex and cleans up the aux/log files; usage: `texpdf input.tex [output.pdf]`

## Keeping this file up to date

When you make any change that affects the system layout described in this file — adding/removing components, changing keybinds, renaming scripts, updating reload procedures, changing themes or fonts, adding new modes — update the relevant section of this file in the same task. Do not wait to be asked. Treat CLAUDE.md as live documentation: it should always reflect the current state of `~/.config`.

## Applying changes

| Component | How to reload |
|---|---|
| zsh config | `source ~/.config/zsh/conf.d/<file>.zsh`, or open a new shell |
| kitty | `kill -SIGUSR1 $KITTY_PID` or Ctrl+Shift+F5 |
| foot | Restart terminal (no live reload) |
| Neovim plugins | `:Lazy sync` inside nvim |
| Mangowm | `~/.config/mango/scripts/reload.sh` |
| Switch mode | `~/.config/mango/scripts/modes/<mode>.sh` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |

## Agent skills

### Issue tracker

Gitea issues on the self-hosted instance at `git.henrydowd.dev` (repo `henry/nix-config`), driven by the `tea` CLI, which is already authenticated. It is a LAN host (`192.168.1.200`): reachable directly from the home network, and via the `homelab` WireGuard tunnel from anywhere else. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. They do not exist on the Gitea repo yet; `docs/agents/triage-labels.md` has the `tea labels create` commands.

### Domain docs

**`docs/SYSTEM.md`** is the human-facing operator's manual, added 2026-07-31: hardware and filesystem layout, the three-layer mental model, a repo map, the change/reload loop, a "where do I change X?" routing table, the full keybind reference, hardware behaviour, a services inventory, what is *not* in the repo, and a symptom→cause troubleshooting catalogue. It covers the same system as this file but answers *how do I use it* rather than *what has already broken*; where the two disagree, this file is the one kept current against failures. Its §13 lists known rough edges — check there before reporting one as new.

**`docs/WORK-LOG.md`** records the 2026-07-30/31 declarative pass — what changed, what broke and why, what is deliberately *not* declarative, and a current-state snapshot with the commands to re-verify it. Read it before assuming something is unfinished rather than decided. (`docs/archive/WORK-LOG.md` is the separate, earlier log for the migration itself.)

Single-context. **`docs/adr/` exists as of 2026-07-30** — eight numbered records covering the flake layout, the out-of-store rule, state placement, theming ownership, daemon ownership, start limits, language servers and the Arch removal. Each carries the failure that motivated it, so read the relevant one before undoing something that looks redundant. `CONTEXT.md` still does not exist and is created lazily. For this repo `CLAUDE.md` itself is the standing system description, so read it first. See `docs/agents/domain.md`.

Note for anything adding files under `docs/`: `.gitignore` **stopped being an allowlist on 2026-07-30**. While the repo root was `~/.config` it had to ignore `/*` and un-ignore 38 known-good paths, so a new top-level directory stayed invisible to git until someone added a `!/dirname/` line. Now that the dotfiles live under `home/` and the flake is at the root, it is an ordinary denylist — a new directory is tracked by default, and the rules that remain are specific: generated files (`home/mango/config.conf`), runtime state, wallpaper, and the credential dirs.
