# Work log — the declarative pass

**2026-07-30 → 2026-07-31 · 17 commits, `c12388d` → `a7aefcf`.**

Covers the work after the Arch→NixOS migration was already installed and
booting: retiring the old repo, restructuring it, and moving the configuration
from "symlinks into a checkout" to "carried by the flake".

`docs/archive/WORK-LOG.md` is the earlier, separate log covering the migration
itself. `CLAUDE.md` describes how the system *is*; `docs/adr/` records the
decisions; this file records what changed and what it cost.

---

## State as of this entry (2026-07-31)

> ⚠️ **A snapshot, not the current state.** This is a chronological log; later
> entries below supersede it, and the 2026-08-01 pass in particular moved most
> of these dotfile entries out of `dotfiles.nix` and into generated modules.
> For where things stand now, read `docs/SYSTEM.md` §6.

| | |
|---|---|
| Repo | `~/src/nix-config`, flake at the root, dotfiles under `home/` |
| Remote | `origin` → `git.henrydowd.dev/henry/nix-config` only (GitHub mirrors removed) |
| Working tree | clean, 0 typechanges, 0 unpushed |
| Dotfile entries | **24 store-based, 1 out-of-store** (`corectrl`) — before the 2026-08-01 conversion to generated modules |
| `nix flake check` | passes |
| `/nix/store` | 47 GB (was 60 GB before `gc`) |
| Booted vs current | **reboot pending** — see below |

**The pending reboot is benign.** `nix store diff-closures` shows only the
language servers, the home-manager file/dconf derivations from the GTK work,
and `initrd-linux` shrinking ~31 KiB. No kernel change, no systemd change. The
hostname in the *booted* derivation still reads `arch` because generations 1–7
predate the rename; the runtime hostname has been `thinkpad` throughout.

### Verified working

- All six language servers on `$PATH`: `nil`, `lua-language-server`,
  `bash-language-server`, `marksman`, `taplo`, `yaml-language-server`
- `~/.scripts` → `hm_scripts` in the store; `micmute-led.service` **active**,
  running from its store path
- `/sys/firmware/acpi/platform_profile` writable by `wheel`; the waybar module
  emits a non-empty glyph
- Papirus `folder.svg` byte-identical to `folder-yellow.svg` (stock was
  `folder-blue.svg`)

---

## What was done

### The repo itself

The root *was* `~/.config` — 9.6 GB of browser profiles, Electron data and real
credentials — with the flake in a `nixos/` subdirectory. That put the dotfiles
**outside the flake root**, unreachable by any relative path, which is why every
entry was an out-of-store symlink. Moving the flake up and the dotfiles into
`home/` fixed it and let `.gitignore` become an ordinary denylist instead of a
119-line allowlist. See [ADR-0001](adr/0001-flake-at-repo-root.md).

Then: `~/src/arch-config` and `~/.config/.git` deleted (both verified to hold
nothing unique), the GitHub remotes removed, `dotfiles/fish/` dropped (the shell is
not installed), 20 committed `.zsh_tmp_git_*` junk files removed, and a
`gtk-4.0/assets` symlink into `/usr/share` that resolved to nothing.

### Declarative conversion

1 → 24 store-based entries, by three techniques, chosen per app:

- **Native module** where Nix represents the config faithfully — `gtk.*` now
  generates both `settings.ini` files, both `gtk.css` files and the Thunar
  bookmarks.
- **Move the writer** where something wrote into the config directory —
  nvim's `lazy-lock.json` to `stdpath("state")`, mango's runtime state to
  `~/.local/state/mango`, the wallpaper to `~/.local/share/mango`.
- **Pin the file, not the directory** — `xdg.configFile."htop/htoprc".source`
  leaves `~/.config/htop` a real writable directory, so sibling runtime files
  (`ncspot/userstate.cbor`) still work.

`~/.scripts` moved into the repo. That was the sharpest gap: `audio.nix`
declared a systemd unit with `ExecStart = "%h/.scripts/micmute-led"`, a
*fully declarative unit depending on a file in no repo and no backup*.

### Correctness fixes found along the way

- **Language servers**: none were installed. Both editors take them from
  `$PATH` and skip missing ones silently, so LSP had been dead since the
  migration with `rust-analyzer` the lone survivor. ([ADR-0007](adr/0007-language-servers-declared.md))
- **`mmsg` calls**: five scripts used the dwl-era `-s -d` flags, which return
  `{"error":"unknown command"}` **and exit 0**. `reload.sh` was among them, so
  every "reload" only rewrote `config.conf` while the compositor kept running
  the old configuration.
- **Waybar power-profiles module**: bound a D-Bus API nothing implements
  (power-profiles-daemon is off because it conflicts with TLP). Replaced with
  the ACPI `platform_profile`, which needs no daemon.
- **Papirus folders were blue** because `papirus-folders` recolours the theme
  *in place* and the theme is a read-only store path. Done as a build-time
  `color` override instead.
- **zsh `EXTENDED_GLOB`** made `#` a pattern operator, so the unquoted
  `~/src/nix-config#thinkpad` in the rebuild aliases was globbed and died with
  `no matches found` before `nixos-rebuild` ran.

Documentation: eight ADRs created, README rewritten (it still said *"The system
is still Arch"*), and `docs/archive/` given ARCHIVED banners because its
commands reference paths that no longer exist.

---

## What broke, and why

Worth reading before repeating any of it.

### `recursive = true` overwrote the repo — twice

`recursive = true` does not *replace* a directory; it creates files **inside**
it. When `~/.config/X` is still an out-of-store symlink into the checkout, those
writes follow it into the repo.

- **First time**: converting `mango` replaced **65 tracked files** with symlinks
  into the store. `git status` showed typechanges (` T `); the targets resolved
  in a loop, so the live config broke too.
- **Second time**: after adding a guard for `mango` and `nvim` by name, the next
  day's conversion of htop/ncspot/zed/Kvantum/nwg-look/gtk-3.0/gtk-4.0 was **not
  covered by it**, and clobbered ten more files. Those were then committed and
  pushed, because `nix flake check` was run and its failure not acted on.

Recovered both times with `git checkout` — nothing was lost, purely because the
content had been committed and pushed first.

The fix is now structural: `unlinkStaleConfigDirs` is **derived from
`xdg.configFile`**, so every managed path is covered automatically. A
hand-maintained list of "things not to forget" failed within a day of being
written.

`nixos-rebuild test` compounds this: it activates **without creating a profile
generation**, so the new store path has no GC root and a later
`nix-collect-garbage` can delete what the repo now points at.

### Two silent-empty failures

Both presented as "the thing is missing" rather than "the thing is broken":

- `cp` from a read-only store file gives the **destination** mode 0444, so the
  first mode switch wrote a read-only `config.conf` and every switch after it
  failed with `Permission denied`. Now `install -m 644`.
- The power-profile script's icons were written as literal glyphs and lost in
  transit, so every branch assigned `""` and waybar drew nothing. The script ran
  fine and exited 0. Now `$'\uXXXX'` escapes, keeping the source pure ASCII.

**For any `custom/*` module: check that `text` is non-empty, not just that the
exec succeeds.** An empty module and an absent one are indistinguishable.

---

## Deliberately not declarative

Not a backlog — these are decisions:

- **`corectrl`** writes its ini and `profiles/*.ccpro` from its GUI, and that
  GUI is the program. Pinning them would remove the only way it is used.
- **`users.mutableUsers = true`** — passwords stay imperative.
- **NetworkManager profiles** (35, root-only) and the OpenVPN certs are
  hand-restored. VPN `autoconnect` is off on all 9 profiles on purpose:
  `homelab` claiming `+DefaultRoute` pushed an unreachable DNS server onto every
  link and killed *all* name resolution.

### Open

- **No secrets management.** `pia-auth` is plaintext (mode 600); the WireGuard
  key and forge tokens sit outside the repo. `sops-nix`/`agenix` is the
  standard answer and is a task of its own.
- **`local.checkout` cannot be eliminated**, only centralised — a flake
  evaluates from a store copy of itself, so nothing can derive where the repo
  was cloned. It dies with the last out-of-store entry.
- Seven configs could still become native modules (`programs.htop`, `qt.*`);
  they are pinned files today, which is reproducible but not expressed in Nix.

---

## Checking it still holds

```bash
git -C ~/src/nix-config status --porcelain   # expect empty; ` T ` means clobbered
nix flake check                              # and ACT on failure
hx --health | grep -E '^(nix|lua|bash) '     # LSP coverage, both editors
~/.config/mango/scripts/system/power-profile.sh   # `text` must be non-empty
mmsg dispatch reload_config                  # {"success":true}, not "unknown command"
```

After any `dotfiles.nix` change, build `home-files` and look at the result
rather than trusting evaluation — directory-valued sources become one symlink,
file-valued ones a real directory of links, and the difference is the whole
game:

```bash
nix build --no-link --print-out-paths \
  '.#nixosConfigurations.thinkpad.config.home-manager.users.henry.home-files'
```

---

# Work log — suspend drain and the mango flattening

**2026-07-31 → 2026-08-01.** Started as "was the lid-close toggle script
migrated?" and became a power investigation plus a structural change.

## The battery problem

The laptop was found flat after a night closed on the desk. Suspend was working
throughout; it just cost **~4.1 W**, because the SoC never reached s0i3.

Under s2idle the SMU only enters its deep state once every IP block reports
idle. `/sys/kernel/debug/amd_pmc/smu_fw_info` named the culprit outright —
every block at `0` except **`DISPLAY 9440595`** — with `Last S0i3 Status:
Unknown/Fail` and `amd_pmc: Last suspend didn't reach deepest state` each cycle.

The existing backlight hooks could never have fixed this. `brightnessctl`
drives the PWM level, the amdgpu backlight is `type: raw`, and the DISPLAY block
tracks the CRTC rather than the PWM — so `bl_power=4` collapsed to "brightness
0" and even a genuinely dark panel would have left the block active. The hook
ran, exited 0, and did nothing. It had been built that way because `CLAUDE.md`
recorded that mango exposed no `wl_output`, which had **silently stopped being
true** (probably at the mango 0.15.5 upgrade). One stale sentence cost a battery.

Replaced with `wlopm --off/--on` via a `setDisplayPower` helper, run as the
session user because it needs the Wayland socket.

| | draw | s0i3 residency |
|---|---|---|
| before | 4.10 W | 0% |
| after `wlopm` | 3.03 / 3.04 W (two runs) | 0% |
| with `ath11k_pci` unloaded | 3.16 W | 0% |

**s0i3 is still unreached with every block idle**, so a second blocker remains.
`ath11k_pci` and USB were excluded by bisect; `r8169` and the S0-armed PCIe
bridges (`GP11`, `NHI0`) are untested. Rather than keep hunting an unbounded
search space, worked around it with **hibernation**: a 20 GiB swapfile on a
dedicated `@swap` btrfs subvolume, `suspend-then-hibernate` on battery after
30 min, plain `suspend` on AC.

### Two false conclusions, both from reading logs

1. **"ACPI S4 is being refused"** → set `HibernateMode=shutdown`. Wrong, and
   reverted. The kernel log **cannot** distinguish a successful hibernate from a
   refused one: the memory image is snapshotted *before* the write and
   power-off, so on resume everything logged after that point never existed.
   `PM: Wrote … kbytes` is never visible. Three attempts were byte-identical in
   the journal; the discriminators are a physical power-off and an unchanged
   boot ID.
2. **"hibernation is unverified"** → it was working. Committed as unverified,
   corrected the next commit.

Both were reported to the user as findings before being disproven. The lesson is
the same one as the `wl_output` note: verify the claim, don't reason from the
artifact that merely accompanies it.

## Structural change — flattening `dotfiles/mango/`

The nesting existed because the config tree doubled as the **backup** unit: only
directories worth keeping lived under `mango/`. Once everything became
declarative and tracked, that rationale expired, and what remained was a cost —
neither app sat at the XDG path it looks in by default, so **eight** call sites
had to name the config explicitly.

```
dotfiles/mango/wlogout/  →  dotfiles/wlogout/     (7 files)
dotfiles/mango/swaync/   →  dotfiles/swaync/      (1 file)
```

Both are now plain store paths **without `recursive = true`**; under `mango/`
they inherited that flag, which exists only so the mode scripts can write
`config.conf`. All eight `-s`/`-C`/`-l` flags deleted.

`mango/rofi/` was listed in `CLAUDE.md` as a themed directory. **It does not
exist and never did.** Grepping for `rofi` is misleading because it
substring-matches `power-profile`.

## Three stale-path bugs, all from the 2026-07-30 state move

`CLAUDE.md` asserted "every script resolves it as
`${XDG_STATE_HOME:-$HOME/.local/state}/mango`". That assertion is part of why
these survived — it read as verified.

- **`scripts/desktop-mode.sh`** still read `$MANGO_DIR/state/current-mode`.
  `current_mode()` never found it, fell back to `"tiling"`, so the menu always
  bulleted tiling and the `[[ "$CHOICE" == *"  •" ]] && exit 0` guard treated
  picking tiling as "already there". **Switching to hud worked; switching back
  was impossible**, silently. Reported as "I can switch to hud mode but I can't
  switch back".
- **`pkill -x swaync`** in both `autostart.conf` files had never worked on
  NixOS — `comm` is `.swaync-wrapped`, the same wrapper trap as elephant. The
  pkill hit nothing, the old instance survived, the replacement exited with
  "already running", so a restyle on mode switch never took effect. Invisible
  because both modes share one stylesheet. Now `pkill -f '^swaync( |$)'`, which
  excludes `swaync-client`.
- **`mango/walker/config.toml` was a tracked symlink** containing an absolute
  path into `$HOME`, while both `autostart.conf` files rewrite that same path
  with `ln -sf` on every mode switch. Two owners; home-manager activation failed
  outright with `would be clobbered`, and `backupFileExtension` does not rescue
  it. The timing hid the cause: the symlink only exists once a mode script has
  run, so it broke a rebuild that had nothing to do with it. Untracked and
  gitignored, matching `mango/config.conf`.

## `verify-claims.sh`

Added 2026-08-01 at the repo root, alongside `verify-packages.sh`. Every check
in it exists because a documented claim silently stopped being true and cost
debugging time — prose cannot be trusted to stay correct, so these are run
instead. Exit 0 if all pass; Wayland-dependent checks skip rather than fail
when headless.

It covers: tracked symlinks; generated files being gitignored rather than
tracked; scripts still reading the pre-2026-07-30 state path; `pkill -x` against
a nixpkgs wrapper; `STOP_CHARGE_THRESH_BAT0` vs waybar `full-at`; and `wlopm` /
`mmsg` actually enumerating an output.

The `pkill` check resolves each target and only fails on genuinely wrapped
binaries — flagging every `pkill -x` produced a false positive on `dsearch`,
which is unwrapped and fine. A checker that cries wolf gets ignored, which
defeats the point.

Verified non-vacuous by reintroducing the swaync bug: the run failed, named
`.swaync-wrapped`, and pointed at the file.

Current: **8 passed, 0 failed.**

## Migration discrepancy audit — 2026-08-01

Checked against the live system, not against `CLAUDE.md`, which had been wrong
three times that week (`wl_output`, state-path uniformity, `mango/rofi/`).

**Genuinely finished.** No `*.hm-bak`, no `~/arch-residue-backup-*`, no
`~/src/arch-config`, no tracked symlinks, and exactly one out-of-store dotfile
entry — `corectrl`, which is deliberate and is the last thing keeping
`local.checkout` alive.

**Still open, in the order worth fixing:**

1. **6 of 12 nvim language servers missing.** `lsp.lua` enables `lua_ls`,
   `rust_analyzer`, `pyright`, `ruff`, `clangd`, `ts_ls`, `bashls`, `texlab`,
   `tinymist`, `marksman`, `taplo`, `yamlls`; absent are **`pyright`, `ruff`,
   `clangd`, `ts_ls`, `texlab`, `tinymist`**. Python, C/C++, TypeScript, LaTeX
   and Typst therefore have no LSP at all. Formatters are worse — `stylua` and
   `shfmt` are referenced and absent, only `rustfmt` is present. The config
   states plainly that "a server whose binary is missing is simply skipped (no
   error)", which is exactly what hid the original gap for a day after the
   migration and is hiding these now. `texlab`/`tinymist` also underpin the
   writing stack (`vimtex`, `typst-preview`, knap).

2. **`~/.config/zen` is 929 MB and in no repo** — 13 extensions, saved logins,
   history — surviving only via the `@home` subvolume. Up ~70 MB since the
   migration notes. Needs its own backup; a clone does not reproduce it. Same
   class: `~/.local/share/mango/wallpaper.png` (4.6 MB) and `~/.config/{gh,glab-cli}`.

3. **Secrets unmanaged** — `pia-auth` plaintext mode 600, WireGuard key, forge
   tokens. `sops-nix`/`agenix`. Biggest genuine gap; a task of its own.

4. **NetworkManager profiles and Bluetooth pairings** are root-owned and
   restored by hand. A decision rather than a TODO — but re-restoring
   reintroduces `autoconnect=yes` on the 9 VPN profiles, which killed all DNS
   once already. (Counts not re-verified here: both need root and the check
   returned nothing usable.)

5. **Suspend still costs ~3 W** — the thing that started this week. See above.

Deliberate removals, not discrepancies: fish, LibreWolf, Proton Drive, KDE
Plasma, DankMaterialShell/Quickshell, `papirus-folders`, the pacman aliases.

## Open

- **s0i3 never reached.** Hibernation works around it; the cause is unknown.
  Untested: `r8169`, and `GP11`/`NHI0` armed for wake at S0 via `/proc/acpi/wakeup`.
  Method is one suspend per suspect: unload, suspend 10+ min on battery, check
  `last_hw_sleep`.
- **`walker/`, `fsel/`, `elephant/` not moved.** Same argument as wlogout/swaync,
  but each needs its config-resolution path confirmed first.
- **`walker/themes/` unaudited** for the same tracked-symlink pattern that
  `config.toml` had. A `walker/themes/noctalia` symlink was already deleted on
  2026-07-30 for resolving into its own parent.

---

# Work log — zsh startup time

**2026-08-01.** Interactive shells felt slow to open. Profiled with `zmodload
zsh/zprof` and per-line `$EPOCHREALTIME` deltas; the cost was all completion
setup, none of it in the hand-written `conf.d/*.zsh`.

## What was costing what

| Cause | Cost |
|---|---|
| `compinit` run **twice** — NixOS's `programs.zsh` and home-manager's | 219 ms |
| `compaudit` inside the surviving `compinit` | 87 ms of 120 ms |
| `zoxide init` run twice — `conf.d/10-aliases.zsh` on top of `programs.zoxide` | 8 ms |

~315 ms removed. An interactive shell now measures ~110 ms.

## The three changes

1. **`programs.zsh.enableCompletion = false`** (`hosts/thinkpad/default.nix`).
   Drops the system-level `compinit`; home-manager's is the one kept.
   `programs.zsh.enable = true` stays — that is what makes zsh a valid login
   shell and has nothing to do with completion.
2. **`completionInit = "autoload -U compinit && compinit -C"`**
   (`modules/home/shell.nix`). `-C` skips `compaudit`, which was auditing
   store paths that are read-only by construction.
3. **`home.activation.invalidateZcompdump`** — `rm -f ~/.config/zsh/.zcompdump*`
   on every rebuild.

**2 and 3 are one change and must not be separated.** `-C` also skips the
staleness check, so on its own it pins completions to whatever the dump held
when it was written: a newly installed package's completions never appear, and
nothing reports it. A rebuild is the only moment completions can change on this
system, so invalidating the dump exactly then is equivalent to checking on every
shell, at zero per-shell cost. The glob also clears the
`.zcompdump.<host>.<pid>` temps a killed `compdump` leaves behind.

## zoxide

The init moved to `programs.zoxide` with `options = [ "--cmd" "cd" ]` and was
deleted from `conf.d/10-aliases.zsh`. **`--cmd cd` had to move with it** — it is
what makes `cd` zoxide rather than the builtin, so deleting the duplicate
without carrying the flag across silently reverts `cd` to builtin `cd`. Same
shape as the `y`/`yy` yazi wrapper noted in that file: two owners for one name,
surviving only on source order.

## Checking it still holds

```
zsh -i -c exit            # time it; ~0.11 s
grep compinit ~/.config/zsh/.zshrc   # exactly one, with -C
grep -c compinit /etc/zshrc          # 0
zsh -ic 'whence -w cd'               # "cd: function", not builtin
```

---

# Work log — a gate that runs before the rebuild does

**2026-08-03.** Phase 0 of the idiomatic-Nix plan. Nothing verified a change
before `nixos-rebuild switch` applied it; now `nix flake check` does. Full
reasoning in [`docs/adr/0010`](adr/0010-flake-check-is-the-gate.md).

## What was wrong

`verify-packages.sh` **evaluated** the closure and said so itself — it "cannot
catch profile collisions or a derivation that fails to build". `CLAUDE.md` names
`buildEnv` collisions as *the* expected failure mode when adding packages, so
the most likely break was the one thing structurally uncheckable. `nix fmt`
pointed at `nixpkgs-fmt`, archived upstream.

## What landed

`checks.x86_64-linux` = `system` (`system.build.toplevel`), `home` (the
home-manager activation package), `statix`, `deadnix`. The first two are real
build products, so checking them builds the whole closure.
`verify-packages.sh` deleted as a strict subset; `verify-claims.sh` kept, since
it checks the **live** system, which no build can see.

Formatter is `nixfmt` (RFC 166). devShell + `.envrc` pin the tooling.

## Four things that did not go to plan

| Expected | Actual |
|---|---|
| `formatter = pkgs.nixfmt`, one line | Doesn't work at all — nixfmt takes FILES. No args → reads stdin, dies on empty input with `unexpected end of input`. A directory → Haskell backtrace. Needs a `writeShellApplication` wrapper |
| `nixfmt-rfc-style` is the attribute | Deprecated alias at this pin; same derivation, warns on every eval. Use `nixfmt` |
| statix finds a handful of things | 69 findings, **all one lint** (`repeated_keys`), all wanting NixOS config nested against the standard flat style. Disabled in `statix.toml` |
| deadnix finds a handful | 39 findings, **37 of them `{ config, lib, pkgs, ... }` module headers**. `--no-lambda-pattern-names` leaves the 2 real ones |

The rule behind the last two: **a check that always fails is one you learn to
ignore** — worse than no check. Tune until every finding is real.

## The reformat, and how it was verified

`nix fmt` touched all 21 `.nix` files, 618 lines, committed separately from the
change that introduced the formatter.

Treated as risky rather than routine: `waybar.nix` carries literal UTF-8 Nerd
Font glyphs, and this repo has already lost four network icons to transcription
once — invisible until you look at the bar. So instead of trusting the
formatter, both build products were evaluated before and after:

```
system.build.toplevel   rwzmsmi770bchf6hwv5sybn77hb6d9m6   identical
home activationPackage  szpavcxrkp673vaifwps2ivspf7pkf59   identical
```

Byte-identical derivations prove the diff is semantically a no-op, glyphs
included — **and that no rebuild was needed**, since there is nothing new to
switch to. The technique generalises to any change that should not alter the
built system.

## Checking it still holds

```
nix flake check       # builds system + home, runs both linters
nix fmt               # idempotent — a second run must produce no diff
./verify-claims.sh    # 8/8 against the live system
```

---

# Work log — gating the layer that was actually breaking

**2026-08-03.** Phase 0.5 of the idiomatic-Nix plan, which now lives at
[`docs/PLAN-idiomatic-nix.md`](PLAN-idiomatic-nix.md) rather than in a session
scratchpad under `/tmp`. Full reasoning in
[`docs/adr/0011`](adr/0011-shell-is-gated-too.md).

## What was wrong

Phase 0 built a careful gate and pointed it at the wrong layer.

| | Lines | Files | Gated by |
|---|---|---|---|
| Nix | 3,930 | 22 | full closure build + statix + deadnix |
| **Shell** | **2,100** | **39** | **nothing** |

Every failure this log and `CLAUDE.md` record is a shell failure — the
`#!/bin/bash` exit-127s, the `mmsg -s -d` flags that return 0, `pkill -x`
against a wrapper, the state path one reader disagreed about. Not one was a Nix
error.

`verify-claims.sh` had the same shape of problem from the other side: six of
its eight checks needed no live system, so they were a manual step nobody was
obliged to run — and the battery/`full-at` coupling check had already rotted to
"could not read" after the config it read was renamed.

## What landed

`checks.shellcheck` (default severity, `SC1091` excluded) and `checks.static`
(`checks/static.sh`, 11 assertions). `nix flake check` now runs 10 checks.
`verify-claims.sh` keeps the two that need a compositor.

The 24 shellcheck findings were fixed rather than staged behind a raised
threshold. 16 were SC2015 — `A && B || C` is not if-then-else, and every one
was `<action> && notify success || notify failure`, so a working action with a
failed notification reported failure. `bluetooth-menu.sh`'s power toggle turned
the radio back **on** if the off command failed.

## Four things that did not go to plan

| Expected | Actual |
|---|---|
| `cd ${self}` then write a file list | `${self}` is a read-only store path — `Permission denied` plus `find: write error`, which reads as a broken find. Use `$TMPDIR` |
| `head -1` to read shebangs | bash warns about null bytes on the repo's PNGs, three times per build. `head -c 64 \| tr -d '\0'` |
| The git checks move verbatim | No git inside a derivation. `git ls-files` → `find -type l`; the tracked check consults git only when `.git` exists |
| Inline the static checks in `flake.nix` | That shell would be the only unchecked shell left. It goes in a file so the new gate lints it |

## The rule this phase adds

**A scan that stops matching passes by finding nothing** — the shape of every
bug above. So every scan asserts a floor: script count ≥30, waybar configs =8,
waybar script references >0. The motivating incident is concrete:
`nix run nixpkgs#shellcheck -- … 2>/dev/null` swallowed all 24 findings and
reported zero during the audit, which reads exactly like a clean bill of health.
Use `nix shell nixpkgs#shellcheck -c …`.

Corollary: **verify a gate by breaking something.** Both were confirmed to fail
on a planted defect — an unquoted `rm -rf $var`, and an `mmsg -s -d` call.

## Checking it still holds

```
nix flake check       # 10 checks
./verify-claims.sh    # 2/2 against the live session
checks/static.sh . "$(nix eval --raw \
  '.#nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage')"
```

Not covered: `dotfiles/zsh/conf.d/*.zsh` (no shebang, and shellcheck does not do
zsh), and any script not yet `git add`ed — the flake source is the tracked tree.

---

# Work log — secrets into sops (2026-08-06)

Phase 1 of `docs/PLAN-idiomatic-nix.md`. Recorded as **ADR 0012**. The flake
input landed earlier in `c6df2e9`; this entry is the key, the file and the
wiring.

## What was unmanaged

| Secret | Lived in | Survived via |
|---|---|---|
| PIA username + password | `~/.local/state/mango/pia-auth`, plaintext mode 600 | `@home` |
| `homelab` WireGuard key | `/etc/NetworkManager/system-connections/` | hand restore |
| `gh` / `glab` / `tea` tokens | `~/.config/{gh,glab-cli,tea}/` | `@home` |

All three now in `secrets/secrets.yaml`, sops-encrypted and tracked.

## What the plan got wrong

- **`ssh-to-age` was impossible.** `services.openssh` is off, so `/etc/ssh` has
  no host keys. Standalone `age-keygen` instead.
- **Only the NixOS module was needed.** The plan assumed the home-manager
  surface too, because a *user* script reads `pia-auth` — but
  `owner = "henry"` handles that, and the HM module would have wanted a second
  age key readable by the user.
- **`pia-auth` was written, not just read.** `vpn-menu.sh` had a "Set PIA
  credentials" entry that prompted through walker and wrote the file. A sops
  secret is mode 0400, so it had to go. Deleted rather than kept as a fallback:
  a fallback leaves "no plaintext secret outside sops" unenforceable, and this
  repo's failures are all unenforceable invariants that had already drifted.

## What cost time

**`sops <path>` on a nonexistent file opens its `hello: Welcome to SOPS!`
template for a new file rather than erroring.** Run from inside `secrets/`,
`sops secrets/secrets.yaml` resolves to `secrets/secrets/secrets.yaml`, opens
the sample, and on exit reports `File has not changed, exiting`. Two round
trips before the tell was spotted. Same genre as everything else here: the
failure output is indistinguishable from a success.

**The key must be readable by whoever edits.** `age-keygen` writes it
root-owned mode 600, so `sops` as henry cannot decrypt. The alternatives were a
second admin key, or `sudo sops` — which writes the file back root-owned inside
a git repo. Chose chown to henry plus `SOPS_AGE_KEY_FILE` in the devShell.

## Stored vs declared

`sops.secrets.<name>` decrypts to `/run/secrets/<name>` on every boot, so a
declared secret with no consumer is plaintext on a running system for nothing.

- **Declared:** `pia/username`, `pia/password` — `vpn-menu.sh` reads them.
- **Stored only:** the WireGuard key (declared in Phase 2, when
  `ensureProfiles` consumes it) and the three forge tokens (permanent — all
  three CLIs rewrite their own config, the `corectrl` fight from ADR 0002).

## Checking it still holds

```
nix flake check       # 13 checks
nix develop -c sops -d secrets/secrets.yaml | grep -c REPLACE_ME   # must be 0
sudo ls -l /run/secrets/pia/                                       # henry, 0400
```

The static check asserts every `secrets/*.yaml` carries the `sops:` metadata
block — confirmed against a planted plaintext file. It does **not** check the
values are real: a file full of `REPLACE_ME` encrypts and passes, which is
exactly what happened twice before the edit took.

---

# 2026-08-09 · Phase 2 — the NetworkManager profiles are declared

Recorded in **ADR 0013**. The nine that carry a credential or can hijack the
default route — `homelab` plus eight PIA exits — are generated from
`modules/system/networking.nix`. The ~29 ordinary access points stay in
NetworkManager's own state. `nix flake check` now runs 16 static assertions.

## What the plan did not anticipate

**`ensureProfiles` writes to `/run/NetworkManager/system-connections/`, not
`/etc`** — and NetworkManager reads `/etc`, `/run` and `/usr/lib` alike. The
hand-restored `/etc` copies carry the same UUIDs, so leaving them in place makes
the entire declaration a **silent no-op**: the system looks converted, `nmcli`
lists nine profiles with `autoconnect no`, and not one of them is the generated
file. That is this repo's signature failure appearing inside the change meant to
end it. `nmcli -f NAME,FILENAME con show` is the only thing that distinguishes
the two states.

The same property is what makes declaring a *subset* safe rather than a
compromise: the unit writes what it is given and deletes nothing.

**The PIA CA lived in `$HOME`.** Every profile pointed at
`~/.local/share/networkmanagement/certificates/nm-openvpn/<name>-ca.pem`, left
behind by `nmcli connection import` — a root daemon reading a user's home
directory. All eight files are byte-identical. Vendored as one
`modules/system/pia-ca.pem`; it is PIA's public self-signed CA, valid to 2034,
so plaintext in git is correct.

**`pkgs.formats.ini` handles the WireGuard peer section unchanged.** The section
name is `[wireguard-peer.<base64 pubkey>]` and contains `.`, `/` and `=`; it
round-trips verbatim. Verified by reading the generated keyfile out of the
store, not by assuming.

## Two dead things found on the way

**`vpn-menu.sh`'s `.ovpn` importer is unreachable.** Its second path enumerates
`~/Downloads/openvpn/*.ovpn` to build a PIA server list and injects credentials
from sops on import. That directory does not exist, so the list is always empty
and the branch never runs — the nine NM profiles are the entire menu. Phase 4
material; not removed here.

**Three checks in `checks/static.sh` had been scanning `$SRC/home`** since
`859895a` renamed `home/` to `dotfiles/`, and had therefore been passing by
finding nothing for six days: the `mmsg` dash-flag check, the `pkill -x` check
and the `pia-auth` check. Fixed in the same commit. The `pkill -x` check went
from silently examining 0 targets to 2 — its own floor assertion did not cover
zero, which is now the fourth instance of a scan that stopped matching and
reported success.

## The two new assertions

Both read the keyfiles the unit will actually write, parsed out of the built
unit script, rather than the option that produced them — the question is what
lands in `/run`.

- **No declared profile may omit `autoconnect=false`.** The failure this whole
  phase exists to prevent.
- **Every `password` / `private-key` / `psk` must be a `$`-placeholder.**
  `/nix/store` is world-readable, and an inlined credential produces a profile
  that works perfectly while leaking.

Confirmed by planting both defects at once and watching the build fail with
`14 passed, 2 failed`. A gate only ever observed passing has not been observed.

## Checking it still holds

```
nix flake check                                 # 16 static assertions
nmcli -f NAME,FILENAME,AUTOCONNECT con show     # the nine: /run/... and `no`
resolvectl status                               # no tunnel holds Default Route: yes
sudo ls -l /run/secrets/rendered/               # networkmanager.env, root, 0400
```

`FILENAME` is the load-bearing column. A `/etc/...` path against any of the nine
means something wrote through the declaration — most likely an `nmcli con
modify`, which is now the two-owners trap from ADR 0002 in a different medium.

---

# 2026-08-09 · Phase 4 — the dead-code sweep, which found the opposite

Recorded in **ADR 0014**. `nix flake check` now runs 19 static assertions.

## The sweep found one dead thing and three inert ones

Only one directory entry was genuinely unreachable: `vpn-menu.sh`'s `.ovpn`
importer, which built a PIA server list from `~/Downloads/openvpn` — a directory
that does not exist, so the list was always empty and the whole
import-and-inject-credentials branch never ran. After ADR 0013 it was worse than
dead: its `nmcli con modify` would have written a shadowing `/etc` copy over a
declared profile, silently un-declaring it. 156 → 78 lines.

The bigger finding was the inverse. **Three declared files were reachable only
through a namer that was itself in no repo:**

| Declared | Bridged by | On a fresh clone |
|---|---|---|
| `elephant/menus/connectivity/connectivity.lua` | `~/.config/elephant/menus.toml` | provider does not exist |
| `mango/fsel/config.toml` | `~/.config/fsel`, a hand-made symlink | stock colours |
| elephant's bitwarden provider | `~/.config/elephant/bitwarden.toml` | upstream defaults |

All three worked here because `@home` carried the bridges across the migration,
and all three were invisible from inside the repo — the file was tracked, in the
store, and linked into `~/.config`. The only thing that distinguished "declared
and working" from "declared and inert" was asking the program:
`elephant listproviders` naming `menus:connectivity`.

`fsel` moved out of `dotfiles/mango/` to `dotfiles/fsel/`, since it is not a
mango program and was only there because the symlink made it work.

Also gone: the `archlinuxpkgs` action blocks in both walker configs — a pacman
install/remove UI, still offered by the launcher on a machine with no pacman.

## The check that could not be written generically

The obvious implementation — concatenate every other tracked file and grep for
each basename — **flagged both live walker themes on its first run**. The
strings that name them (`theme = "mango-tiling"`) live in `walker/configs/`,
which the scan excluded to stop files matching themselves. Loosening the
exclusion would have made `tiling` match `current_mode()`'s fallback and pass on
nothing at all, which is the failure mode the check exists to catch.

Rewritten per-selector and bidirectional, enumerating values from the writers:
`MODES` out of `desktop-mode.sh`, `theme =` out of the walker configs. Every
value must have a file **and** every file must be a value — one direction alone
misses half the class, because a missing file is a runtime fallback that mostly
looks fine while a surplus file is dead weight that still looks maintained.
`walker/themes/mango/` was the second kind: 765 lines, documented in two places
as the default, reachable from nothing.

All three new assertions confirmed against planted defects — a surplus theme
directory, a walker config naming no mode, and a declared menu path with no
`.lua` behind it — producing `16 passed, 3 failed`.

## A tightening that fell out of it

With the importer gone, nothing in user space reads the PIA credentials; the
only consumer is the sops template rendered by root at activation. Both secrets
dropped `owner = "henry"` and are root-only again.

## Checking it still holds

```
nix flake check                      # 19 static assertions
elephant listproviders               # must name menus:connectivity
ls ~/.config/fsel/config.toml        # a store symlink, not a hand-made one
```

The middle one is the only real test. The other two prove the files are
declared, which is what this entry is about not being sufficient.

---

## Fingerprint reader (2026-08-11)

Synaptics `06cb:00f9`, on USB bus 1. Confirmed supported by checking libfprint's
own modalias list rather than the web — it sits with the other `06cb` IDs.
`services.fprintd.enable` plus `fprintd-enroll`; nothing needed in `pkgs/`.

**Enabling it is not scoped.** `security.pam.services.<x>.fprintAuth` defaults to
`config.services.fprintd.enable`, so one `enable = true` put `pam_fprintd` into
all 23 pam stacks. Naming `sudo` explicitly reads like scoping and is a no-op;
only `fprintAuth = false` removes it. `swaylock` and `login` are switched back
off — a password-first UI cannot render the sensor's prompt, so the first
`timeout` seconds of every unlock silently swallow typing. `greetd` needed no
rule of its own: it substacks `login`. Shipped wrong for one rebuild and caught
by reading `/etc/pam.d/`, which is the only place this is visible.

Left on for the terminal services, where the ordering reads correctly: the
prompt appears, and **Ctrl-C falls through to the password** — `pam_fprintd`
returns `PAM_AUTHINFO_UNAVAIL` on SIGINT, which a `sufficient` control passes to
`pam_unix`. Not guaranteed by the module (it never blocks SIGINT, and `signalfd`
only receives blocked signals); it works because `sudo` blocks it. `timeout` cut
30 s → 10 s on `sudo`; it fires once, and `max-tries` counts only real
mismatches, so an ignored sensor costs 10 s flat rather than 3 × 30.

Auth reaches `sudo` as *your* password, not root's — root's is for bare `su` and
for `emergency.service`'s sulogin prompt, which is the recovery path if the
system ever fails to reach greetd.

Still open: the reader is the standing suspect for the spurious s2idle wake that
made lid-close freeze the machine (its controller `0000:74:00.3` has wakeup
enabled, though the device itself does not). The lid hibernates outright for now;
confirming the wake source is what would let `suspend-then-hibernate` return.

```
grep -l pam_fprintd /etc/pam.d/*      # the only honest scope check
grep ^auth /etc/pam.d/sudo            # must show timeout=10
fprintd-verify                        # must match, not just exit 0
```


---

## The lid setting that was never live (2026-08-11)

A lid-close at 03:52 suspended for 9h37m instead of hibernating, and so did the
retry at 13:30 — with `HandleLidSwitch=hibernate` sitting correctly in
`/etc/systemd/logind.conf` the whole time. The file was right; the daemon was
running the config it read at boot.

**nixpkgs never wires the reload.** `nixos/modules/system/boot/systemd/logind.nix`
sets `reloadIfChanged = true` but leaves the matching `restartTriggers` line
**commented out** (restarting logind used to break X11 sessions). So a
`logind.conf`-only change alters no unit, `switch-to-configuration` sees nothing
to act on, and the running logind keeps the old handler with nothing logged
either way. `power.nix` now declares `reloadTriggers` against that file;
`nix flake check` builds an `X-Reload-Triggers-systemd-logind` derivation, which
is the evidence it took.

The tell is that `/etc/` and the daemon disagree, so only the daemon can be
asked:

```
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager HandleLidSwitch     # not the .conf
systemctl reload systemd-logind                       # Type=notify-reload
```

Reload, never restart — `Type=notify-reload` re-reads config in place; a restart
takes the session with it.

Two things fall out of the 9h37m the machine spent asleep instead:

- **s0i3 is reached.** 58% → 54% of a 42.4 Wh cell is ~0.15 W, not the ~3 W this
  repo had recorded as an unsolved floor. That figure came from short
  instrumented measurements which are now retracted; a long sleep measured by
  battery percentage either side is the test that matches reality. `docs/SYSTEM.md`
  §9 and the Power section of `docs/gotchas.md` are corrected.
- **`suspend-then-hibernate` has a second failure mode**, distinct from the
  documented degrade-to-plain-suspend: this run logged `Suspending, then
  hibernating...` cleanly and the 30-minute wake never fired at all. Unproven
  but suspicious: `rtc0` is `acpi-tad` with no `wakealarm` attribute, and only
  `rtc1` (`rtc_cmos`) reports "RTC can wake from S4". Not investigated further —
  s-t-h is off the table for the wake-source reason anyway.

