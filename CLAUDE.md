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
  command by hand and check the output is non-empty — `rofi -no-config -h`,
  `nvim --headless '+checkhealth lsp' +qa`, the module's own `exec`.
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
| foot, zed, htop, imv, yazi | restart the app |
| ncspot | mode switch re-points `config.toml`, then restart the app |
| nvim plugins | `:Lazy sync` |
| Equibop theme | mode switch — `apply_theme` writes `enabledThemes`; a rebuild alone does not |

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
both the package and its config, and values can be shared —
`modules/home/palette.nix` is the one palette — whichever of
`modules/home/themes/*.nix` that `modules/home/scheme.nix` names (`docs/adr/0030`;
switching is that one string plus a rebuild, and four ship: `mocha`,
`mocha-high-contrast`, `gruvbox`, `nord`) — feeding
swaylock, imv, nvim, swaync, fsel, the lock-background ramp and the bar's
`colors.css` — and, *per mode*, kitty, foot, rofi, ncspot, Equibop and mango, instead
of the same hex codes transcribed into four files with nothing keeping them in
step. A **drifted palette looks deliberate**, which is why it gets a check
rather than a convention: `checks/static.sh` asserts every generated colour is
used and every reference resolves.

A theme file also declares what the palette **cannot** colour — the GTK, Kvantum,
icon, cursor and yazi artefacts, and the scheme *names* noctalia, nvim and Zed
resolve internally (`docs/adr/0032`). These are the half that fails silently:
every one falls back to its own default and looks merely unstyled. The check
asserts each name resolves to a real directory. **All four shipped schemes are
fully native** — `native = false` marks a stand-in and nothing currently uses
one, which is why the scheme set is what it is: noctalia ships ten colour
schemes and nixpkgs fully serves only Catppuccin, Gruvbox and Nord.

Each theme declares its own `contrastFloor` and `ansiFloor`, **measured, not
chosen**, and there is no global minimum under them: the assertion is only "this
theme is as legible as it claims". Nord's comment colour is 1.69:1 and that is
Nord. Every scheme **in service** is audited, not just the selected one — see
below.

**`scheme.nix` is the artefact scheme; `modules/home/modes.nix` is the colour
one, per desktop mode** (`docs/adr/0034`). The split follows the paragraph
above: artefacts are built, so they cannot follow a runtime mode switch and
there is one set for the machine; colour can, where colour is the *whole* of a
consumer's theme. Following the mode: mango's `colors-<mode>.conf`, noctalia's
`predefinedScheme`, Equibop's theme *filename*, and **kitty, foot, rofi and
ncspot through a runtime symlink** that `apply_theme()` in `lib.sh` re-points —
the per-mode halves are generated by `modules/home/mode-theme.nix` (Equibop's by
`dotfiles.nix`, with its other generated config), keyed by *mode* so no scheme
name ever crosses the Nix→shell boundary. waybar and swaync do not run in noctalia mode and stay
on `scheme.nix`, so the divergence has a ceiling and the ceiling is checked:
every mode that runs them must wear `scheme.nix`'s scheme, and only `noctalia`
— which runs neither — may differ. Build-time modes were rejected — they buy only the half
that is already one line.

**Four link paths are owned by `apply_theme` and by nothing else** —
`kitty/current-theme.conf`, `foot/themes/noctalia`, `rofi/colors.rasi`,
`ncspot/config.toml`. None may become an `xdg.configFile`; that is the
two-owners activation failure, and `checks/static.sh` asserts they are absent
from the generation. For ncspot that means **`programs.ncspot.settings` must
stay `{ }`** — the module claims the path the moment it holds one value. A
missing link is silent in kitty, rofi and ncspot and **fatal in foot**, which is
why `mode-theme.nix` seeds them at activation — see `docs/gotchas.md` → Theming.

Equibop is per-mode too and needs no link: it enables a theme by *filename* from
its own `settings.json`, which `apply_theme` rewrites — so the generated file is
`equibop/themes/<mode>.theme.css`.

What is deliberately *not* generated — `nvim`, `mango`, `swaync`, `glow`,
`nwg-look` (all of which now take their *colours* from the palette even where
the rules stay hand-written) — is listed with its reasons in
`docs/SYSTEM.md` §6. Read that before "finishing the job". See `docs/adr/0009`.

Two traps that destroy work rather than merely failing:

- **`recursive = true` writes *through* an existing out-of-store symlink, into
  the repo.** Converting `mango` this way replaced 65 tracked files with
  self-referential symlinks and broke the live config too. Delete `~/.config/X`
  first, so home-manager builds a fresh directory. (`nixos-rebuild test`
  compounds it: it creates no profile generation, so the new store path has no GC
  root.)
- **Two owners for one path is an activation failure, not a merge.** If anything
  writes a file at runtime — `mango/config.conf`, and `mango/walker/config.toml`
  before walker left — git must not track it and no `xdg.configFile` may claim it.

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
- **Never run `dbus-update-activation-environment` or `systemctl --user
  import-environment` from a task shell.** Both overwrite the *session's*
  environment with the calling shell's — from inside this repo's devShell that
  injects `stdenv`, `IN_NIX_SHELL` and a scratchpad `XDG_CONFIG_HOME` into every
  user unit started afterwards, which had three applications silently reading and
  writing their config under `/tmp`. `docs/gotchas.md` → Session environment.

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
| chasing an app that lost its config, its login or its profile | `docs/gotchas.md` → Session environment, then Credentials and keyrings |
| asking how the system is laid out, which keybind does what, or where a change belongs | `docs/SYSTEM.md` (§13 = known rough edges — check before reporting one as new) |
| about to undo something that looks redundant | `docs/adr/` — thirty-eight records, each carrying the failure that motivated it |
| changing the colour scheme, or any part of how the machine looks | `docs/THEME-MIGRATION.md` — the runbook; `docs/adr/0028` for why it splits in two, `docs/adr/0032` for what a theme file owns, `docs/adr/0034` for what follows the mode |
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

### Write it short

Documentation, comments and commit messages here are **direct and concise**. The
argument lives in one place — the ADR or the gotchas entry — and everything else
points at it. Writing it twice is not thoroughness; it is two copies that drift.

- **Comments: a one-line reason plus a pointer.** `# <what and why>. docs/adr/00NN`
  A file past ~30% comment is a signal to move text out, not a well-documented
  file. Never restate in a comment what the ADR beside it already argues.
- **ADRs run ~100 lines.** Context, Decision, Consequences, and the failure that
  motivated it. Past 200 is an outlier worth trimming.
- **Prefer the assertion to the paragraph.** A check in `checks/static.sh` that
  fails when a fact stops being true is worth more than three sentences asking
  the reader to remember it — and it is shorter.
