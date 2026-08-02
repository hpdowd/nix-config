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
home/              the hand-written dotfiles that remain (mango, nvim, zsh, …)
pkgs/              overlay for anything not in nixpkgs
docs/SYSTEM.md     the operator's manual — start here to use the machine
docs/adr/          numbered decision records
docs/agents/       config for the engineering agent skills
docs/archive/      the Arch→NixOS migration — history, not live instructions
verify-packages.sh checks that package names still resolve in nixpkgs
verify-claims.sh   re-checks the assertions CLAUDE.md makes about the system
```

**`home/` is shrinking by design.** kitty, foot, helix, zed, htop, ncspot, imv,
yazi, wlogout and the four waybar layouts are now *generated* from
`modules/home/` and have no file in this repo. If a config file is not under
`home/`, that is why — grep `modules/home/` for it.

`docs/adr/` holds numbered architecture decision records — the decisions that
were expensive to learn, written down so they don't get quietly undone. Start
at [`docs/adr/README.md`](docs/adr/README.md). `CONTEXT.md` still does not
exist; per `docs/agents/domain.md` it gets created lazily, once there is
vocabulary worth pinning down.

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
| Work on the configs themselves | [`CLAUDE.md`](CLAUDE.md) — the standing description of how this machine is put together |
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
| **Store-based** | the file stays hand-written but lands read-only in the store | `modules/home/dotfiles.nix` → `home/` |
| **Out-of-store** | a live symlink into this checkout | `corectrl` **only** |

Generated is the default. Typed options are the only mechanism here that turns
a config typo into an error you cannot miss — this repo's signature bug is
config that is wrong in a way *nothing reports*.

The flake sits at the repo root specifically so it can reference `home/` — when
it lived in a `nixos/` subdirectory the dotfiles were outside the flake root and
unreachable by any relative path.

⚠️ **Almost nothing is live-editable.** Out-of-store symlinks used to make edits
take effect immediately; that is now true for `corectrl` alone. Everything else
needs a `rebuild` before a reload, and the generated configs have no file to
edit at all.

`nixos-rebuild` reads this checkout directly. The repo is expected at
**`~/src/nix-config`** — declared once as `local.checkout` in
`modules/home/options.nix`, not hardcoded in `dotfiles.nix`. It cannot be
`~/.config` itself, since that is where the links are written *to*.

---

## The `.gitignore` is an ordinary denylist

It was an **allowlist** until 2026-07-30, and it had to be: the repo root was
literally `~/.config`, ~9.6 GB of browser profiles, Electron app data, caches
and real credentials. Ignoring everything with `/*` and un-ignoring 38 known
paths was the only safe rule — and the cost was that any new directory stayed
invisible to git until someone added a `!/name/` line. That is how
`rclone.conf`, `gh/hosts.yml` and the user systemd units all fell through both
git *and* the backups at once.

The restructure moved the dotfiles under `home/`, so the root is now an ordinary
project root. Add a new config directory by just adding it.

What is still ignored is specific and intentional: generated files
(`home/mango/config.conf`, `home/mango/walker/config.toml`), runtime state,
zsh's compdump/cache, and the credential directories (`gh`, `glab-cli`,
`opencode`, `gpu-screen-recorder`, `rclone`, `rbw`, `tea`). Those credential
dirs are **not** linked by the flake either — see `docs/archive/WORK-LOG.md` §1
for why linking them would have been worse than not having them.

One consequence worth knowing: **flakes copy only git-tracked files**. A file
that is ignored, or merely untracked, does not exist as far as the build is
concerned. That is what forced the wallpaper out of the config tree — a 4.6 MB
ignored PNG simply would not exist under a read-only `~/.config/mango`, so it
now lives at `~/.local/share/mango/wallpaper.png` and is in no repo at all.

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

⚠️ **Edits under `home/` need a rebuild too.** They used to be live, when every
entry was an out-of-store symlink; they are store paths now. Reloading without
rebuilding first restarts against the config that was already there, which is
indistinguishable from the change having had no effect.
