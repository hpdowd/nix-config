# CLAUDE.md

`~/src/nix-config` — the NixOS flake that builds this ThinkPad, plus the dotfiles
it installs. Arch is gone: there is no dual boot and no fallback.

```
flake.nix          at the ROOT — load-bearing (docs/adr/0001)
hosts/thinkpad/    host config + hardware-configuration.nix
modules/system/    boot, locale, networking, audio, desktop, fonts, power, …
modules/home/      home-manager: packages, shell, dotfiles, theme, programs, waybar
dotfiles/          hand-written app config (mango, nvim, zsh, swaync, scripts, …)
pkgs/              overlay for anything not in nixpkgs
checks/            assertions run by `nix flake check`
secrets/           sops-encrypted, tracked in git (docs/adr/0012)
docs/archive/      the Arch→NixOS migration — history, not instructions
```

## Silent failure is this repo's signature bug

Almost everything that has broken here broke *without saying so*: a waybar module
rendering empty rather than erroring, a script exiting 127, a `pkill` matching
nothing, a window rule whose appid never matches, an `mmsg` flag that returns
`{"error":…}` and exits 0, six language servers absent, a GTK `url()` that fails
unlogged. **A thing that is missing and a thing that is broken look identical
here**, so "it ran and exited 0" is not evidence.

Three habits follow, and they matter more than any single fact below:

- **Prefer generated config.** A typed home-manager option turns a typo into an
  eval error. See the tier rule.
- **Verify by output, not by exit status.** When something is missing, run its
  command by hand and check the output is non-empty — `elephant listproviders`,
  `hx --health <lang>`, the module's own `exec`.
- **Assert a floor.** A scan that stops matching passes by finding nothing, so
  `checks/static.sh` fails when a count hits zero, deliberately.

**`docs/gotchas.md` is the catalogue** — read the section for the area you are
about to change (Arch carryover, nixpkgs, desktop, waybar, power, editors,
theming, networking, secrets, scripts). It records what has already bitten us,
including several theories that looked right and were not.

## Changing things

`rebuild` = `sudo nixos-rebuild switch --flake "$HOME/src/nix-config#thinkpad"`.

- **Gate first: `nix flake check`.** It builds the system *and* home closures — so
  a `buildEnv` collision surfaces there rather than halfway through a switch — and
  runs statix, deadnix, shellcheck and `checks/static.sh`. An evaluate-only script
  cannot catch either failure; don't reintroduce one (`docs/adr/0010`).
- **`rebuild-test` for structural changes** — it applies without moving the boot
  default, so a mistake is one reboot from gone.
- **Except for `boot.kernelParams`, where `test` is exactly wrong.** It writes no
  boot entry, so test-then-reboot silently lands back on the *previous*
  generation with the change reverted. Use `switch` or `boot`. The tell:
  `/nix/var/nix/profiles/system` and `/run/current-system` pointing at different
  store paths.
- **Always quote a flake ref in zsh.** `EXTENDED_GLOB` makes `#` a pattern
  operator, so an unquoted `…#thinkpad` fails with `zsh: no matches found:`
  before `nixos-rebuild` ever runs — it reads like a broken path. Use
  `"$HOME/…"`; `~` does not expand inside double quotes.
- **Rebuild before reload.** Anything generated, and everything under
  `dotfiles/mango/` (a store path), needs a rebuild first. Reloading alone
  reloads what the *last* rebuild produced, which looks exactly like the change
  having had no effect.

| Reload | How |
|---|---|
| zsh | new shell, or `source ~/.config/zsh/conf.d/<file>.zsh` |
| Mangowm | `~/.config/mango/scripts/reload.sh` — never under sudo |
| mode / waybar | `mango-reload`, `waybar-reload` |
| GTK theme | `~/.config/mango/scripts/system/gtk-apply.sh` |
| kitty | `kill -SIGUSR1 $KITTY_PID` |
| foot, helix, zed, htop, ncspot, imv, yazi | restart the app |
| nvim plugins | `:Lazy sync` |

Inputs are pinned by `flake.lock`. Re-lock deliberately with `nix flake update`,
never as a side effect of a build.

## Where configuration lives — three tiers

`~/.config/<app>` is produced by home-manager. **Edit under `dotfiles/`.**

| Tier | Mechanism | Use when | Declared in |
|---|---|---|---|
| 1 — generated | `programs.<app>` | a native module exists — **the default** | `modules/home/{programs,waybar,theme}.nix` |
| 2 — store-based | `source = ../../dotfiles/X` | no module, or generating would lose hand-tuned data | `modules/home/dotfiles.nix` |
| 3 — out-of-store | `mkOutOfStoreSymlink` | the app rewrites its own config from its GUI | `corectrl` only |

Tier 1 earns its churn three ways: typos become build failures, one option owns
both the package and its config, and values can be shared (one Gruvbox `let`
binding feeds kitty and foot, instead of sixteen hex codes transcribed twice).
What is deliberately *not* generated — `nvim`, `mango`, `swaync`,
`helix/themes/`, `glow`, `nwg-look` — is listed with its reasons in
`docs/SYSTEM.md` §6. Read that before "finishing the job". See `docs/adr/0009`.

Two traps that destroy work rather than merely failing:

- **`recursive = true` writes *through* an existing out-of-store symlink, into
  the repo.** Converting `mango` this way replaced 65 tracked files with
  self-referential symlinks and broke the live config too. Delete `~/.config/X`
  first, so home-manager builds a fresh directory. (`nixos-rebuild test`
  compounds it: it creates no profile generation, so the new store path has no GC
  root.)
- **Two owners for one path is an activation failure, not a merge.** If anything
  writes a file at runtime — `mango/config.conf`, `mango/walker/config.toml` — git
  must not track it and no `xdg.configFile` may claim it.

Two techniques worth reaching for before accepting a mutable directory: manage a
*file* rather than a directory (`xdg.configFile."Kvantum/kvantum.kvconfig".source`
leaves the parent writable), and check whether the module **merges** instead of
linking — `programs.zed-editor` merges Nix settings into the real writable
`settings.json`, so declarative does not have to mean read-only.

## Writing shell here

Shell is the layer that actually breaks here — **every failure catalogued in this
repo is a shell failure**. shellcheck and `checks/static.sh` run under
`nix flake check`, over
**git-tracked files only** — a new script is ungated until `git add`, and
`dotfiles/zsh/conf.d/*.zsh` is ungated entirely (no shebang, and shellcheck does
not do zsh). See `docs/adr/0011`.

- `#!/usr/bin/env bash` — there is no `/bin/bash`; the symptom is exit 127 and
  silence.
- `pkill -f 'bin/foo$'`, never `pkill -x foo` — nixpkgs wraps binaries, so `comm`
  is `.foo-wrapped`, truncated to 15 chars. Drop the `$` if the process takes
  arguments: `-f` matches the whole command line, so the anchor misses.
- **To *test* for a process, match `comm`: `pgrep '^\.?foo'`.** `-x` misses the
  wrapper exactly as above, and `-f` matches the guard's own shell — the cmdline
  of `pgrep -f 'foo$' || foo` ends in `foo`, so the guard is always true and the
  daemon never starts. Bare-invoked processes (`mango`, `kdeconnectd`) carry no
  path in their cmdline either, so `bin/` anchors do not help.
- `mmsg` takes verbs (`get`, `dispatch`, `watch`). The dwl-era `-s -d` flags
  return an error object and **exit 0**.
- Runtime state is `${XDG_STATE_HOME:-$HOME/.local/state}/mango`. Every reader
  *and* writer must agree, or a mode switch goes one-way with nothing logged.
- Glyphs in Nix must be literal UTF-8 — there is no `\uXXXX` escape. Verify with
  `jq -r` piped to a codepoint dump, never by eye.
- Run shellcheck as `nix shell nixpkgs#shellcheck -c …`. The `nix run … 2>/dev/null`
  form swallowed all 24 findings once and reported zero, which reads exactly like
  a clean bill of health.

## This shell

zsh via `ZDOTDIR` (`dotfiles/zsh/conf.d/*.zsh`), with `EXTENDED_GLOB` on.
`cat`→`bat`, `ls`/`ll`/`la`→eza, `cd`→zoxide, `lf`→yazi, `zed`→`zeditor`.
**No package-manager alias** — packages go in `modules/home/packages.nix`,
followed by a rebuild. `$EDITOR` is `nvim`. Full inventory and keybinds:
`docs/SYSTEM.md` §7–8.

`ls` in `$HOME` with no args is a *function* that hides clutter listed in
`_HOME_HIDE`; `ll`/`la` are the unfiltered escape hatches. That file opens with
`unalias ls l ll` because NixOS predefines those three, and an existing `ls`
alias makes `ls() { … }` a **parse error that aborts the rest of the file** —
silently dropping everything below it. Don't remove the `unalias`.

## Where to look

| When you're… | Read |
|---|---|
| about to change waybar, mango, the shell, editors, theming, secrets, or anything carried over from Arch | `docs/gotchas.md` — the failure catalogue, by area |
| asking how the system is laid out, which keybind does what, or where a change belongs | `docs/SYSTEM.md` (§13 = known rough edges — check before reporting one as new) |
| about to undo something that looks redundant | `docs/adr/` — twenty records, each carrying the failure that motivated it |
| hitting the GPU freeze, suspend drain or hibernation | `docs/gotchas.md` → Power, then `docs/SYSTEM.md` §9 |
| assuming something is unfinished rather than decided | `docs/WORK-LOG.md` |
| planning the next structural change | `docs/PLAN-idiomatic-nix.md` |
| filing or triaging an issue | `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md` |

## Keeping this current

When a change alters what these files describe, update them in the same task,
unasked. Where this file and `docs/SYSTEM.md` disagree, this one wins — it is the
one kept current against failures.

Route new material by kind: a **decision** becomes an ADR, a **failure** goes in
`docs/gotchas.md`, and the layout goes in `docs/SYSTEM.md`. Keep none of it in a
code comment — `docs/PLAN-idiomatic-nix.md` §5d is moving 1,417 lines of narrative
comment out of the Nix, so adding more works against that. A one-line reason plus
a pointer is the target.
