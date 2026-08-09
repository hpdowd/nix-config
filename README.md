# nix-config

Henry's NixOS system for a ThinkPad L14 Gen 5 — the flake that builds the
machine, and the dotfiles it installs.

**This is the booted system.** NixOS was installed 2026-07-29; Arch was removed
2026-07-30. There is no dual boot and no fallback.

## Layout

```
flake.nix          the system, at the ROOT so it can reference everything below
flake.lock         pinned inputs — re-lock deliberately with `update`
hosts/thinkpad/    host config + hardware-configuration.nix
modules/system/    boot, locale, networking, audio, desktop, fonts, power, …
modules/home/      home-manager: packages, shell, theme, dotfiles, and —
                   programs.nix + waybar.nix — the configs GENERATED from Nix
dotfiles/          the hand-written dotfiles that remain (mango, nvim, zsh, …)
pkgs/              overlay for anything not in nixpkgs
docs/SYSTEM.md     the operator's manual — start here to use the machine
docs/adr/          numbered decision records
docs/agents/       config for the engineering agent skills
docs/archive/      the Arch→NixOS migration — history, not live instructions
statix.toml        lint config (see the file for why `repeated_keys` is off)
verify-claims.sh   re-checks the assertions CLAUDE.md makes about the system
```

## Checking a change

```
nix flake check     # builds the system AND the home generation, + statix/deadnix
nix fmt             # nixfmt (RFC 166)
./verify-claims.sh  # assertions about the LIVE system that no build can see
```

**Run `nix flake check` before `rebuild`.** It builds `system.build.toplevel`
and the home-manager activation package, so `buildEnv` collisions and failing
derivations surface there rather than halfway through a `switch`.

**`dotfiles/` is shrinking by design.** kitty, foot, helix, zed, htop, ncspot,
imv, yazi, wlogout and the waybar layouts are *generated* from `modules/home/`
and have no file in this repo. If a config is not under `dotfiles/`, that is
why — grep `modules/home/` for it.

## Rebuilding

| Alias | Runs |
|---|---|
| `rebuild` | `nixos-rebuild switch --flake "$HOME/src/nix-config#thinkpad"` |
| `rebuild-test` | `nixos-rebuild test` — applies **without** changing the boot default |
| `rebuild-boot` | `nixos-rebuild boot` — next boot only |
| `update` | `nix flake update` |
| `generations` | `nixos-rebuild list-generations` |
| `gc` | `nix-collect-garbage --delete-older-than 30d` |

Use **`rebuild-test`** for anything structural: it applies without touching the
boot default, so a mistake is one reboot from gone. Defined in
`modules/home/shell.nix`.

**Quote flake refs in zsh.** `EXTENDED_GLOB` is on (`zsh/conf.d/00-options.zsh`),
which makes `#` a pattern operator — so an unquoted `~/src/nix-config#thinkpad`
is globbed, matches nothing, and fails with `zsh: no matches found:` before
`nixos-rebuild` runs at all.

---

## Start here

| I want to… | Read |
|---|---|
| Work on the configs themselves | [`CLAUDE.md`](CLAUDE.md) — the rules that apply to every change here |
| Change one area without stepping on a known trap | [`docs/gotchas.md`](docs/gotchas.md) — the failure catalogue, by area |
| Learn how the system is laid out | [`docs/SYSTEM.md`](docs/SYSTEM.md) — the operator's manual |
| Understand why something is the way it is | [`docs/adr/`](docs/adr/) — numbered decision records, each with the failure that motivated it |
| See what changed recently, and what broke | [`docs/WORK-LOG.md`](docs/WORK-LOG.md) — the declarative pass (2026-07-30/31), plus a current-state snapshot |
| Know how agents should use this repo | [`docs/agents/`](docs/agents/) — domain docs, issue tracker, triage labels |
| Read the migration history | [`docs/archive/`](docs/archive/) — `MIGRATION.md`, `MIGRATION-GUIDE.md`, `INSTALL.md`, `WORK-LOG.md`. Kept for their post-mortems, **not** as live instructions |

---

## Where the configuration lives

Three tiers, best first. `docs/SYSTEM.md` §6 has the full rule and the
reasoning; the short version:

| Tier | Mechanism | Where |
|---|---|---|
| **Generated** | a native home-manager module writes the file from typed options | `modules/home/programs.nix`, `modules/home/waybar.nix` |
| **Store-based** | the file stays hand-written but lands read-only in the store | `modules/home/dotfiles.nix` → `dotfiles/` |
| **Out-of-store** | a live symlink into this checkout | `corectrl` **only** |

Generated is the default. Typed options are the only mechanism here that turns
a config typo into an error you cannot miss — this repo's signature bug is
config that is wrong in a way *nothing reports*.

⚠️ **Almost nothing is live-editable.** That is `corectrl` alone. Everything
else needs a `rebuild` before a reload, and the generated configs have no file
to edit at all.

`nixos-rebuild` reads this checkout directly. The repo is expected at
**`~/src/nix-config`**, declared once as `local.checkout` in
`modules/home/options.nix`. It cannot be `~/.config` itself, since that is where
the links are written *to*.

---

## The `.gitignore` is an ordinary denylist

It was an allowlist until 2026-07-30, when the repo root was `~/.config` itself
and a new directory stayed invisible to git until someone un-ignored it by name.
The root is an ordinary project root now — add a config directory by adding it.

What is still ignored is specific: generated files (`dotfiles/mango/config.conf`,
`dotfiles/mango/walker/config.toml`), runtime state, zsh's compdump, and the
credential directories (`gh`, `glab-cli`, `opencode`, `gpu-screen-recorder`,
`rclone`, `rbw`, `tea`). Those are not linked by the flake either.

⚠️ **Flakes copy only git-tracked files.** An ignored or merely untracked file
does not exist as far as the build is concerned — which is why the wallpaper
lives at `~/.local/share/mango/wallpaper.png` and is in no repo at all.

---

## Applying changes

Everything below assumes you have already run `rebuild`.

| Component | Reload |
|---|---|
| NixOS / home-manager | `rebuild` (or `rebuild-test`) |
| Mangowm | `mango-reload` |
| Waybar | `waybar-reload` |
| Switch mode | `~/.config/mango/scripts/modes/<mode>.sh` |
| zsh | open a new shell, or `source ~/.config/zsh/conf.d/<file>.zsh` |
| kitty | `kill -SIGUSR1 $KITTY_PID` |
| foot, helix, zed, htop, ncspot, imv, yazi | restart the app |
| wlogout | nothing — it is spawned fresh each time |
| Neovim plugins | `:Lazy sync` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |
| `autostart.conf` | log out and back in — `exec-once` fires only at startup |

⚠️ **Edits under `dotfiles/` need a rebuild too** — they are store paths, not
live symlinks. Reloading without rebuilding restarts against the config that was
already there, which is indistinguishable from the change having had no effect.
