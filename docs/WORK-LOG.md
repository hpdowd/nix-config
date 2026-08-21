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
for s in nil lua-language-server bash-language-server pyright gopls; do \
  command -v $s >/dev/null || echo "$s MISSING"; done   # expect no output
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

> **Reverted 2026-08-11 — 2 and 3 were both removed; 1 stands.** Two of the
> premises above did not hold. The `87 ms` for `compaudit` was measured while
> `compinit` still ran twice; re-measured alone it is **~10 ms** — so `-C` was
> buying a tenth of what the table claims. And "zero per-shell cost" ignored
> where the work went: the activation `rm` runs at every **boot** too, not only
> at rebuilds (`home-manager-henry.service` is `WantedBy=multi-user.target`), so
> the first shell of every session paid ~290 ms to rebuild the dump — 330 ms to
> a prompt against 40 ms for every shell after it.
>
> Plain `compinit` does natively what the pair was hand-rolling: it leaves the
> dump alone when `fpath` is unchanged and regenerates it when a new generation
> changes those store paths. Verified both directions before removing them.
> The trade is +10 ms on every shell against −290 ms once per boot, and one
> option plus one activation block deleted. Simplicity, at this size, wins.

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

---

## Idle behaviour, and the power key (2026-08-11)

Measured first: 6.9 W idle with the lid open against 0.15 W suspended. swayidle
carried **no timeouts** — a lock handler only — so walking away from an open lid
cost 6.9 W until the 3% hibernate about six hours later, with the desktop
unlocked throughout. Nothing else on this machine is worth that much: TLP's
runtime PM, USB autosuspend, `nmi_watchdog=0`, `power_save=1` and amd-pstate-epp
were all already correct, and there was nothing left in TLP to turn.

Ladder added: dim at 4 min, lock + `wlopm --off` at 5, hibernate at 30 **on
battery only** via a `writeShellApplication` that reads `AC/online` (so it is
shellchecked at build time rather than being an inline string nothing gates).
Safe because mango advertises `zwp_idle_inhibit_manager_v1` — checked with
`wayland-info`, not assumed — so playback suppresses it.

The lock and the blank are joined with `;`. `&&` was written first and is wrong:
a second swaylock over a manual lock exits non-zero, and the panel would then
stay lit for the rest of the idle period, logging nothing.

Also: `HandlePowerKey` was systemd's default `poweroff` with
`HandlePowerKeyLongPress=ignore` — a brushed button ended the session with no
prompt, and holding it did nothing. Now hibernate on tap (matching the lid),
poweroff on long press. And `services.poweralertd` (`-s -S`), because nothing
warned about a low battery at all: upower's percentages are policy inputs and
waybar only recolours, so the first unmissable signal was the machine
hibernating. waybar's thresholds moved 30/15 → 20/5 to match upower.

Two measurement notes worth keeping:

- **`nix flake check` did not surface an eval warning that plain `nix eval`
  did** — `reloadTriggers` on a unit that already sets `reloadIfChanged` makes
  the two equivalent. Switched to `restartTriggers`, which is what the
  commented-out nixpkgs line uses. Green checks are not silence.
- **Short instrumented power measurements on this machine are worthless.** A
  six-sample median at 100% backlight read 6.88 W and at 10% read 7.43 W —
  ordinary background work swamps the signal. Only long sleeps measured by
  battery percentage either side are trustworthy, which is exactly what the
  retracted ~3 W s0i3 figure got wrong.

---

## Gating the idle ladder, and two new floors (2026-08-11)

**Media.** The 30-minute hibernate now bails if any MPRIS player reports
`Playing`. Only that rung checks: dimming and locking over an album is correct,
so gating the whole ladder would be wrong. Video needed nothing — mpv and
Firefox hold a `zwp_idle_inhibit` surface, which stops the ladder before the
first rung, which is why this is three lines rather than a caffeine daemon.

`playerctl` rather than a PipeWire stream check: `pactl` is not installed here,
`playerctl` already is (the media keys use it), and "is a media player playing"
is the actual question. The cost is that it sees MPRIS only — a game or a
non-MPRIS call still gets hibernated under. Recorded in gotchas rather than
worked around.

Exercised every branch against the *built* script with `systemctl hibernate`
stubbed and `playerctl`/`AC/online` faked, because the live state at the time
(on AC, player paused) would have exercised exactly one:

```
AC=0 Playing        -> stays awake      AC=1 Paused              -> stays awake
AC=0 Paused         -> HIBERNATE        AC=0 two, one Playing    -> stays awake
AC=0 Stopped        -> HIBERNATE        AC=0 playerctl fails     -> HIBERNATE
```

That last one is the deliberate direction to fail in: a broken `playerctl` lets
the machine sleep rather than keeping it awake forever.

**Two floors in `checks/static.sh`.** The failure this week was documentation
describing an idle ladder that did not exist, so: swayidle must carry at least
one `timeout`, and it must not chain swaylock to wlopm with `&&`. Plus waybar's
battery `states` must equal upower's `PercentageLow`/`Critical`, read from the
built `/etc`, since those two silently drifted to 30/15 against 20/5.

Both were mutation-tested — strip the timeouts, bump one config's threshold, and
confirm the run fails naming the file. A check nobody has watched fail is a
check nobody has tested.

⚠️ `grep -c -o` counts *lines*, not occurrences. The whole swayidle `ExecStart`
is one line, so the first version reported "1 timeout" for three and would have
passed a ladder cut to a single rung. It is `grep -o … | wc -l` now.

**ADR 0015** records hibernate-on-the-lid, because the 0.15 W measurement
removes the battery argument for it while leaving the real ones — the resume
hang and the unidentified wake source — intact. Without that written down, the
next reader finds "s2idle is cheap" and reasonably undoes it.

---

## A "do not sleep" toggle on the bar (2026-08-12)

The idle ladder had no in-session escape: `systemd-inhibit --what=idle` does not
reach swayidle, which takes its signal from the compositor, so the documented
workaround was `systemctl --user stop swayidle`.

waybar's **built-in `idle_inhibitor`**, not a `custom/*` script, because the
built-in takes a real `zwp_idle_inhibit_manager_v1` inhibitor on the bar's layer
surface — the mechanism mpv and Firefox already use. A script could only have
stopped the unit.

Three things checked rather than assumed, since each fails as "the module just
isn't there":

- **mango honours an inhibitor on a layer surface.** `checkidleinhibitor` gets
  `c = NULL` for one, and with `idleinhibit_ignore_visible=0` the `!c` arm sets
  `inhibited = 1`. `wayland-info` confirms the manager is advertised.
- **The module is compiled in** — unconditional in waybar's `src_files`, behind
  no meson feature. Its constructor throws and the module vanishes when the
  manager is absent, so this was worth confirming against the 0.15.0 source.
- **Both glyphs exist at the right advance.** 󰒳/󰒲 are `md-sleep_off`/`md-sleep`;
  3270 gives them ink spanning exactly their 1080/2000 advance, so unlike
  `#custom-power-profile` they need no `Symbols Nerd Font Mono` override.

No `timeout` — waybar can auto-release after N minutes, which is the silent
expiry the toggle exists to prevent.

**The state does not survive a waybar restart.** It is a process-lifetime bool
on a surface that dies with the bar, so `waybar-reload`, a mode switch and
`SUPER+/` all release it; `minimal`/`hud` do not carry it at all. Persisting it
would mean state a crash could strand in the "on" position, which is worse.

**A fourth floor in `checks/static.sh`**: at least one layout must list
`idle_inhibitor`. Dropping it from all eight is otherwise invisible.

---

## The idle rung suspends again (2026-08-12)

ADR 0015 carried two decisions and had evidence for one. All of it is about a
**closed lid** — logind re-handling a lid that is still shut is the mechanism,
and there is none when the rung fires with the lid open. Folded in by symmetry,
it paid a multi-GiB write and a 10–30 s resume every 30 idle minutes for the gap
between 0.15 W and 0 W.

It calls `systemctl suspend` now (`idle-hibernate` → `idle-suspend`), both gates
unchanged. **ADR 0016** records it and amends 0015 in place; the lid half stands.

**Endurance was not the reason.** Samsung MZVL2512HCJQ, ~300 TBW; four
hibernates a day at ~6 GiB is ~8.8 TB/year, ~34 years of headroom. The cost is
latency. Recording the wrong reason would have left the decision resting on a
number that does not support it.

**upower's 3% `Hibernate` is what makes it safe**, and why it does not extend to
the lid: an idle suspend nobody returns to hibernates on the way down, so the
worst case is a slow resume. The lid's failure is not resuming to *reach* 3%.

**The rung is now the instrument for closing 0015** — nothing suspended
automatically before, so neither failure could be observed at all. Both of
0015's observations also predate the `wlopm` hooks and describe a machine that
never reached s0i3; the one long s2idle since was clean.

**A lead on the wake source.** The Synaptics reader is the only device on USB
bus 1. Its own `power/wakeup` reads `disabled` — which is why checking the
device looked like a dead end — but its parent XHCI controller `0000:74:00.3` is
`enabled`, and that is how a device leaving the bus raises a PME. Untried on
purpose: 0015 wants the source confirmed, and the fix removes the symptom.

---

## Comment surgery — Phase 5d (2026-08-12)

`dotfiles.nix`, `power.nix`, `desktop.nix`, `shell.nix`, `pkgs/default.nix` and
`home/default.nix`: narrative comments cut to a one-line reason plus a pointer,
261 lines removed against 127 added. The content was good and is not lost — it
already existed in the ADRs, `gotchas.md` and `SYSTEM.md` §9, which is what made
it duplication.

`desktop.nix` also lost a class of comment worth naming: **stale Arch narration
in the present tense** ("on Arch you have greetd installed but the service is
DISABLED"). Arch has been gone since ADR 0008, so those read as instructions
about the current machine. One was wrong on its own terms too — `fsel` was
annotated as pinned to 3.5.2 by the overlay, which pins 3.6.0.

Proved a no-op by derivation path, per the technique in the plan. Both
`toplevel.drvPath` and the home activation package came back byte-identical —
**except** for one line: a comment inside `programs.zsh.initContent`, which is a
string literal and therefore generated output, not a Nix comment. Bisected to
confirm it was the only leak, then removed deliberately (it said "exactly as on
Arch"). The built home tree now differs from the baseline by that single line
and nothing else.

⚠️ A comment inside `''...''` is data. The ratio scan below counts it as a
comment and the no-op check counts it as output; only the second is right.

---

## Power modes were a placebo (2026-08-12)

The waybar toggle and `SUPER+SHIFT+p` cycled
`/sys/firmware/acpi/platform_profile`. Diffed across all three settings, every
value the scheduler reads — governor, EPP, `scaling_min_freq`,
`scaling_max_freq`, `boost` — is byte-identical. It is a `thinkpad_acpi` DYTC
hint to the firmware, TLP owned the real settings keyed on AC-vs-battery alone,
and TLP rewrote the attribute on every charger transition. A year of a toggle
that moved a glyph.

Found while chasing why the fan runs at ~2340 RPM idle at 45–52 °C on battery in
"low-power": nothing in that mode caps anything. `EPP=power` biases the ramp and
sets no ceiling, so with `boost=1` every keystroke-sized task reaches 4.63 GHz.
The fan here tracks bursts, not averages.

Rebuilt on TLP's third profile (`SAV`, `tlp power-saver`), which 1.9 supports for
every setting and `TLP_AUTO_SWITCH=2` holds across a charger transition.
`docs/adr/0017`.

**Two things that only looked like they worked.** `RADEON_DPM_PERF_LEVEL_ON_SAV`
does not exist in 1.9.1 — the amdgpu branch folds `PP_BAL`/`PP_SAV` and reads
`_ON_BAT` — so it would have been written into `tlp.conf` and never read; the
iGPU pin moved into the `power-mode` wrapper. And `tlpctl`, whose manpage 1.9.1
ships in full, has no binary in the package.

**The calibration sweep is unrun.** It needs root, and the first attempt wrote
`scaling_max_freq` as a normal user with `2>/dev/null` on the writes — so it
completed, reported, and had measured the unmodified machine the whole time.
Exactly the failure this repo is named for. `dotfiles/scripts/fan-calibrate` is
the corrected version; it refuses to start as non-root. The shipped
`CPU_SCALING_MAX_FREQ_ON_SAV = 1115770` is `lowest_nonlinear` reasoned from the
V/f curve, not a measurement.

---

## rofi replaces walker and elephant (2026-08-14)

`docs/adr/0021`. Two menu programs and a 546 MB daemon out, one 256 KB binary
and two plugins in. **427 MB resident** goes with them.

**The finding that forced it.** walker 2.x cannot draw a window without
elephant, and does not say so. With the walker daemon up and only elephant
killed, `walker -d` **exits 0, prints nothing and opens no window** — from the
keyboard indistinguishable from pressing Escape, and from a script
indistinguishable from a cancel, since every caller here reads a cancel as
`|| exit 0`. The control run with elephant up exits 124, the window still open
when the timeout fires. Two exit codes differing only by a timeout was the whole
diagnostic. That put nine scripts and four keybinds behind a daemon whose
absence looked like a working system.

**ADR 0019's prediction did not hold, and that is what decided it.** It recorded
295 MB RSS at 25 providers and reasoned resident memory would fall with the
number of plugins `dlopen`ed. Measured after the trim: **305 MB at 15**. The
store path did fall 807 → 546 MB, exactly as recorded. RSS did not move. So the
remaining 546 MB could not be cut further by the technique already applied.
0019 is superseded rather than deleted — the measurement is the reason 0021
exists, and the "should fall" line was flagged there as a prediction.

**What was actually being used**: two of walker's nine prefixes, `=` calc and
`.` symbols. Both were reachable only by typing into walker's main window,
**which no bind opened** — one `walker` invocation from being unreachable
already. They are real keys now (`SUPER+=`, `SUPER+;`). `websearch`, `files`,
`todo`, `bookmarks`, `windows`, `runner` and `providerlist` are gone, not
stubbed.

**Two things that were already here and unused.** `rofi` was in
`desktop.nix` and invoked by nothing, and `universal/rule.conf` carried two
`layer_name:rofi` animation rules that had never matched — Arch carryover, and
the right name after all (rofi passes the literal `"rofi"` as its
`zwlr_layer_surface` namespace, `source/wayland/display.c:1616`). So was
`menus/bluetooth-menu.sh`: hand-written, 155 lines, bound to nothing, quietly
displaced by elephant's provider. It takes `SUPER+CTRL+B` and the waybar
bluetooth click now; `menus/volume-menu.sh` takes the pulseaudio right-click.

**The check that replaced 0019's is narrower and stronger.** It reads
`rofi -no-config -h`'s `Detected modes` — what `dlopen` actually succeeded on —
rather than the Nix that asked for the plugins, so a plugin that builds and
fails to load is caught, which the old provider scan could not do. Both
directions were negative-tested before being committed: a bogus mode in
`config.rasi`, and a built plugin nothing names, each take the run to
25 passed / 1 failed.

**The check found its own hole first.** The first version hid rofi's stderr with
`2>/dev/null` and reported "rofi reports only 0 modes — the scan is broken".
With stderr kept, the real reason: under the build sandbox `$HOME` is
`/homeless-shelter`, rofi cannot create its runtime directory, warns, and prints
no help at all. Fixed by giving that one invocation `HOME="$TMPDIR"`. A check
that swallows the diagnostic is the thing this repo exists to avoid.

**Not carried over:** hud mode's narrower launcher window (walker's wrapper
injected per-mode sizing; one theme now serves all three modes), and 337 lines
of tuned Gruvbox GTK CSS, which do not port — rasi is a different language.
`config.rasi` starts from rofi's shipped `gruvbox-dark` and overrides four
things. Deliberately plain, to be tuned once against a running system.

---

## One palette for the machine (2026-08-14)

Follows the rofi migration above. The first rofi theme imported rofi's shipped
`gruvbox-dark` on the assumption that a gruvbox is a gruvbox. Seen against the
running desktop it disagreed with every convention here: **2px** borders
against `tiling.conf`'s `borderpx=1`, an `#a89984` border matching nothing,
`#665c54` selection where the terminals use `#504945`, and alternate rows
striped `#32302f` where nothing else on this system stripes at all.

The shape is now read off what exists rather than invented — `tiling.conf`
(`borderpx=1`, `border_radius=0`, `focuscolor=0xd79921`) and `style-solid.css`
(radius 0, 1px `@overlay` hairlines, flat modules, selection drawn as
`background: @accent; color: @base`). Square, 1px, flat, one accent.

**The colours forced a bigger change.** Adding rofi would have made a *fourth*
copy of the same sixteen hex codes — the `let` binding in `programs.nix` for
kitty and foot, `waybar/colors.css` for the bar, `helix/themes/gruvbox.toml`,
and now a rasi. Nothing kept them in step, and a drifted palette is invisible:
there is no way to tell a considered accent from a typo by looking at it. So
`modules/home/palette.nix` is the one definition, and `waybar/colors.css` and
`rofi/colors.rasi` are generated from it. The hand-written `style-*.css` and
`config.rasi` stay hand-written — the line is that stylesheets are *rules* and
a palette is *data*.

**The unification is provably a no-op for what was already there.** The
generated `colors.css` diffs byte-identical against the tracked file it
replaced, and kitty's generated palette is unchanged. Worth doing that
comparison rather than eyeballing the bar: ten colours that are almost right
look exactly like ten colours that are right.

**The rofi-specific trap.** Overriding widgets is not enough — a widget with no
rule of its own resolves through rofi's built-in *role* variables, and those are
Solarized light (`urgent-background` is `#fdf6e3`). The first pass styled
`element selected` and left cream-on-teal waiting in every state nothing had
exercised yet. Fixed by overriding the roles instead, which also covers widgets
nobody thought of. `rofi -dump-theme` is the diagnostic: nothing in the output
should still read `var(lightbg)`, `var(blue)` or `var(red)`. Four Solarized
values remain *defined* in the dump and are read by nothing.

**Two new floors** (`checks/static.sh`, 26 → 28): every generated colour is
referenced by a stylesheet, and every `@name` a stylesheet references is
defined — for waybar and rofi both. Both halves fail silently otherwise: GTK
drops a rule naming an undefined colour and renders the module in whatever it
inherited, and rofi falls back to the built-in role. Negative-tested in both
directions before committing.

---

## noctalia mode looks like noctalia (2026-08-15)

`docs/adr/0020` installed noctalia as a third desktop mode and answered only how
to run it without breaking the other two. What it left behind looked finished
and was not: `noctalia/noctalia.conf` was a **byte-for-byte copy of
`tiling.conf`** — `animations=0`, `border_radius=0`, every gap `0` — so a
rounded, floating, animated shell sat on hard square windows that snapped
between positions with no motion. The mode now overrides the shared flat look
after its `source=` lines: 12px corners matching noctalia's own
`bar.frameRadius`, 8/12px gaps, a 2px border in palette `overlay`, zoom open and
close, shadows on floating windows.

**The divergence rests on a parser fact, so it was measured rather than
assumed.** mango is last-wins and processes `source=` inline at its position —
probed with a nested instance under a scratch `HOME`, using `xkb_rules_layout`
because `mmsg get keyboardlayout` reads the effective value back. Two findings
came out of that: **mango ignores `XDG_CONFIG_HOME`** (the first nested instance
read the *live* config and ran the live autostart against the running session),
and **a misspelled option is reported** — `[ERROR]: Unknown keyword:` with file
and line, which is rare enough here to be worth using. The candidate conf was
started nested with one deliberate typo appended; one error out means every
other line was accepted.

**The seed was inert, which is worse than absent.** `modes/noctalia.sh` wrote
`settings.json` only when the destination did not exist, so on this machine —
which had run the mode — adding a key to it would have changed the repo and not
the desktop. The visible symptom was noctalia rendering in its own purple while
everything else on the machine is Gruvbox by construction. Settings are now
written in two halves: `settings.json` seeds preferences once, and
`settings-pinned.json` is merged over the live file on every entry into the mode
with `jq -s '.[0] * .[1]'`. Against the live file that merge changed exactly one
value (`predefinedScheme`), added nothing and lost nothing — checked before
shipping, because a recursive merge that silently drops a subtree looks like a
program forgetting its settings.

**Three things stay off, deliberately.** Compositor `blur` (this machine hangs
outright on an amdgpu TTM fault; a permanent shader pass is not what to spend
that risk on), `layer_shadows`, and layer animations for anything `^noctalia-` —
the shell draws and animates its own panels, and doubling either is worse than
neither.

**Four new gated assertions** (`checks/static.sh`, 28 → 31 reported checks —
the fourth only ever speaks up to fail; all skipped if
`dotfiles/mango/noctalia/` is gone, so removal still takes nine files): every
key path in both settings files exists in the package's
`Assets/settings-default.json` (noctalia ignores unknown keys in silence — 25
paths today, floor at zero); the pinned colour scheme resolves to a file that
ships, the way `ColorSchemeService.resolveSchemePath()` resolves it; every
`layer_name:^noctalia-` matches a `namespace:` the shipped QML declares; and the
package is in the system profile at all. The assets are reached through the
binary's store path — `environment.pathsToLink` does not link
`share/noctalia-shell`, so looking under `$SYS/sw/share` finds nothing and would
have passed by finding nothing.

**The mode switch could wedge, silently.** Reported the same evening: tiling →
noctalia → tiling → noctalia, and the second entry produced no bar. Two failures
stacked. The shell was aborting on `Failed to create wl_display` because the
systemd user manager's `WAYLAND_DISPLAY` pointed at a socket that was gone —
self-inflicted, by the nested-mango probe above: a nested instance runs the live
`universal/autostart.conf`, whose first line republishes *its* display into the
user manager, and killing it leaves that pointing at nothing. The gotchas entry
now carries that warning next to the nested-instance technique that earned it.

The second failure is the one worth keeping. Five crashes inside
`StartLimitIntervalSec` leave the unit `failed` with `start-limit-hit`, after
which `systemctl --user start` refuses — it does exit 1, but an `exec=` line has
no reader for that, so the switch reported success and produced nothing, and
repairing the environment did not help because the wedge outlives its cause. The
three `exec=` lines are now `scripts/modes/noctalia-start.sh`: `reset-failed`
before start, wait for the unit to be active *and still active 1.5 s later*, and
on failure restart swaync and `notify-send` the reason — a mode with no bar AND
no notification daemon has nothing left to report with. Both paths tested
against a purpose-built crash-looping unit rather than by reasoning about them:
a plain `start` on the wedged unit exits 1 and stays down; through the script it
comes back.


---

## noctalia's keys do noctalia's things (2026-08-16)

The decision `docs/adr/0020` deferred. In `noctalia` mode the shell's launcher,
lock screen, control centre, calendar, session menu, settings panel and dock sat
behind no key at all, while the keys that were bound reached past it to rofi,
swaync and swaylock — the mode looked like noctalia and behaved like tiling.

**Which mechanism to use was measured, not chosen.** mango's binds append and
the dispatcher stops at the first match (`src/mango.c`, `only match the first
keybind`), so a per-mode conf sourced ahead of `universal/bind.conf` really does
override it — the opposite of the last-wins rule for scalar settings found the
day before. But mango also runs `check_key_binding_conflicts()` and prints
`[WARNING] Key binding conflict` with both files and both line numbers for every
duplicate; a nested instance confirmed it fires. Nine overrides would mean nine
warnings on every start, on the stderr where a real one would appear. So the
nine shared keys go through one script — `scripts/menus/shell.sh`, which is
`notify.sh` generalised from one row to thirteen — and only the four keys with
no counterpart elsewhere are bound per-mode, in `noctalia/bind.conf`.

**`noctalia-shell ipc call` prints `Target not found.` and exits 0**, while a
successful void call prints nothing: `mmsg -s -d` all over again. Output is the
signal; the status is worthless. Hence a check pairing all 13 calls against the
`IpcHandler` blocks in the shipped QML, matching the function *inside* its own
target — negative-tested with `dock clear`, which passes a two-greps version
because `notifications` declares `clear`.

**Reading the shell's own code turned up a dead action.** noctalia's
`MangoService.logout()` runs `mmsg -s -q`, which this machine answers with
`{"error":"unknown command"}` and exit 0. Its session-menu logout button is
disabled in the pin rather than left to do nothing.

**The lock is split on purpose.** The manual keys use noctalia's lock screen in
its own mode; swayidle's `before-sleep`, `lock` and 300 s timeout stay on
`lockscreen -f` in every mode, because that path has to be synchronous (`-f`
forks only once the lock is up) and has to work when the shell is not running.
The unit now pins `NOCTALIA_PAM_SERVICE=swaylock` — left alone noctalia probes
and takes `/etc/pam.d/login`, and the swaylock service is the one this repo
declares with `fprintAuth = false` for the reason every Wayland locker needs it.

That warning is now a check instead: no key may be bound twice in any mode,
built per mode from the `source=` lines of its own conf and lowercased first,
since the dispatcher compares with `xkb_keysym_to_lower()`. Adding a per-mode
bind file is exactly the change that can collide, so the assertion arrived with
it.

**Two keys that refused now do something, and four gaps closed.** `SUPER+/` and
`SUPER+SHIFT+/` were guarded by `mode_has_waybar()` and answered a `notify-send`
in noctalia mode — correct, and still two dead keys out of a set that small.
They mean "configure the bar", and each mode's bar is a different program, so
they joined the table: waybar's layout picker and position toggle, or noctalia's
settings panel and `bar toggle`. Then the shipped IPC surface was read against
the existing binds rather than guessed at, which turned up a window switcher
(`SUPER+W`, `rofi -show window` as the fallback — it works because mango does
create `wlr_foreign_toplevel_manager_v1`), do-not-disturb (`SUPER+SHIFT+N`,
`swaync-client -d`) and keep-awake (`SUPER+SHIFT+A`). The last is noctalia-only:
its inhibitor is quickshell's native one over `zwp_idle_inhibit_manager_v1`, so
it holds off **swayidle**, not merely noctalia's own pinned-off idle service —
tiling and hud have no CLI for that and hold one only through waybar's module.
Seventeen actions, seventeen ipc pairs, no key bound twice.

**A check had quietly narrowed.** `network-menu.sh` and `bluetooth-menu.sh` are
now called from `shell.sh` rather than from a `.conf`, so they dropped straight
out of the "every script named by a bind exists and is executable" scan with no
count reaching zero to say so — the failure that scan exists to catch, happening
to the scan itself. It reads `$MANGO_DIR/scripts/…` inside scripts now too:
14 references became 19. The action check caught its own version of this on the
first run, reporting an action named `rather`, read out of the prose in a
comment; it looks only at `^bind=` lines now.


---

## Review: what the noctalia mode actually does (2026-08-16)

A pass over the running system rather than the source, after the three changes
above were rebuilt and applied (system generation 64). Everything asserted
statically holds at runtime: mango parses the new mode conf and bind file with
**no `Unknown keyword` and no `Key binding conflict`** in the journal, the pin
merged (`predefinedScheme` is `Gruvbox`, clipboard history on, the dead logout
button off), and `NOCTALIA_PAM_SERVICE=swaylock` is in the unit *and* in the
running process's environment.

**One documented claim did not survive the pass, and it is the important one.**
`docs/adr/0020` recorded noctalia's mango support as working — the file
`MangoService.qml` exists, is selected, and announces itself in the log with
`Initializing MangoWC/DWL compositor integration (DWL protocol)`. Every path
inside it is then guarded on `DwlIpc.available`, which is false permanently:
quickshell probes for the Wayland global `zdwl_ipc_manager_v2`, and mango 0.16.0
creates only `wlr_*` globals — its `protocols/` directory holds three `wlr-*`
XML files and no dwl IPC at all. So `rebuildWorkspaces()` and `updateWindows()`
return early, and **the Workspace widget — the centre of noctalia's bar — and
the ActiveWindow widget render nothing.**

Three independent confirmations before writing it down: the absent protocol on
mango's side, the string `zdwl_ipc_manager_v2` in quickshell's binary on the
other, and `WARN quickshell.dwl: DWL is not available` in the unit's journal at
every start.

The failure is exactly the one 0020 named as the reason the integration
mattered, so its own predicted symptom has been the live state for two days. It
went unseen because the claim was read off a file's existence instead of a
running shell — in the repo whose first rule is that a thing that is missing and
a thing that is broken look identical. 0020 is corrected in place rather than
superseded; the method, not the widget, is the lesson, and it is in
`docs/gotchas.md` next to the tell.

Not fixed, and not cheaply fixable: the routes are a QML widget written against
`mmsg watch`, or noctalia's plugin system, which clones git repositories at
runtime and 0020 rejected for that reason. Tag state remains on waybar in the
other two modes.


## Audit: two of yesterday's claims were wrong (2026-08-16)

Follows the review above, going after the same class rather than the same
widget: **which noctalia features read the dead `DwlIpc` path.**

**`SUPER+W` was a dead key, added the day before.** noctalia's own
`launcher windows` opens the launcher in `>win` mode, and `WindowsProvider`
reads `CompositorService.windows` — filled only by `MangoService.updateWindows()`,
which returns early behind the same `DwlIpc.available` guard as the workspace
widget. So the switcher opened and listed nothing. It is now `rofi -show window`
in **every** mode, noctalia included; rofi reads wlr-foreign-toplevel, which
mango does advertise. The general rule, now in §13: `CompositorService` is dead
here, `ToplevelManager` is live — the **dock is fine** because it reads the
latter directly.

**"noctalia's launcher has no calculator" was false.** It ships
`CalculatorProvider.qml` with `handleSearch: true`, so typing `1+1` into the
plain launcher works. The real reason `SUPER+=` stays on rofi is narrower and
was not what got written down: there is no `launcher calculator` IPC function,
so no key can open it directly. Corrected in `docs/adr/0023` and §7.

Both mistakes have the same shape as the one they follow — a capability was
credited from the fact that a file implementing it exists, without checking what
that file reads at runtime. Three for three now.

Also trimmed: the six-line narrative comment added to
`modules/home/default.nix` for the PAM variable is down to two and a pointer,
per `CLAUDE.md` — `docs/PLAN-idiomatic-nix.md` §5d is moving comments *out* of
the Nix, and that edit was pushing the other way.


## The lock after sleep is noctalia's now (2026-08-16)

Reported from the machine, not from a check: **the lock screen that appears
after a sleep is not the one the lock key opens.** Both halves of that were
true, and each was a separate defect.

`docs/adr/0023`, written hours earlier, gave the manual key to noctalia's lock
and deliberately left `services.swayidle` on swaylock — so the only lock ever
seen by hand was noctalia's, and the only lock ever seen after a lid close, a
5-minute idle or a 30-minute suspend was swaylock's. Which is nearly all of
them.

The reason given was that the unattended path must be **synchronous**, and it
must: swayidle holds a logind delay inhibitor and waits, and `-f` returns only
once the lock surface is up. `noctalia-shell ipc call lockScreen lock` cannot
promise that — it returns as soon as the shell reads the message, and nothing
reports back. Confirmed, one at a time, that there is nothing to poll:
`lockScreen` declares exactly one function; `mmsg get` has ten subcommands and
none is about the lock; `loginctl`'s `LockedHint` tracks the logind signal
rather than `ext-session-lock-v1`, so neither locker moves it.

**The answer was already in 0023's own last sentence** — swaylock exits non-zero
when something else holds the lock. So `lockscreen` asks noctalia, waits a
second, and runs swaylock anyway: its *failure* proves the session is locked,
and its *success* means noctalia did not manage it and swaylock is now the lock.
Two outcomes, both locked, and the one-second wait decides only which screen you
see. `docs/adr/0024`. That the wrapper is the single place every lock path goes
through is what made this one edit rather than five.

**And the lock screen's accent was orange.** `ring-color` `d65d0e`,
`key-hl-color` and `text-caps-lock-color` `fe8019` — gruvbox shades used nowhere
else on this machine, against a `palette.nix` that has said `accent = d79921`
since it existed. They were the last hex values typed by hand into
`programs.swaylock.settings`, in the one surface you never see beside another,
so nothing compared them. Now `opaque gruvbox.accent` and
`opaque gruvbox.warnColor`, with `wash` spelling the `55` alpha the indicator
uses to let the background pool through.

Checks: the wrapper's ipc pair joins `shell.sh`'s thirteen in the QML pairing
scan, with a floor on the wrapper's own matches — `lockScreen lock` appears in
both files, so a merged list would have kept passing after the wrapper stopped
calling anything at all, while the sleep lock quietly reverted.

Untested, and it is the same gap 0023 recorded: a lock screen cannot be verified
without the password, and this raises the stakes from one key to every resume.
Confirm noctalia's lock *unlocks* before trusting a sleep to it. `CTRL+ALT+F2`
is the way out; killing the shell is not.


## noctalia lifecycle audit (2026-08-16)

Asked directly: does noctalia shut down completely, does it leave remnants, and
does anything it starts survive it as a second instance. Three answers, and the
third one turned out to point the other way.

**It shuts down completely.** `KillMode=control-group`, and quickshell's
"detached" spawn only calls `setsid()` — which changes the session, not the
cgroup. Verified rather than assumed: a `setsid` grandchild inside a transient
user unit is still in the unit's cgroup and dies on `stop`. No quickshell
process was alive after the switch.

**It leaves 11 MB of RAM behind.** quickshell never removes its instance
directory — 18 of them under `$XDG_RUNTIME_DIR/quickshell/by-id/`, one per start
since 14 August, each with a socket, a lock and a `log.qslog` up to 1.5 MB. It
knows: every failed `ipc call` prints a "Dead instances:" list naming them.
`noctalia-start.sh` now prunes them before starting, deciding liveness from
quickshell's own `by-pid/` index rather than parsing its binary lock.

**The duplicate processes were waybar's, not noctalia's.** Four
`mmsg watch focusing-client`, PPID 1, up to fourteen hours old, ~5 MB each, each
still holding an IPC socket to mango. `WAYBAR_OUTPUT_NAME` in their environment
identified them as `window-title.sh`'s, and their start times line up with
waybar starts exactly: one leaks per `pkill waybar`, so every mode switch and
every `waybar-reload`. A `trap 'pkill -P $$'` fixes it — by parent, since
matching `mmsg` by name would take out the other modules' watchers — and
`PIPE` is in the trap list because a closed bar pipe is how the script actually
dies, and SIGPIPE skips the `EXIT` trap. `scratch-watch.sh` has the same shape
and nothing kills it today; it got the trap anyway, so the check can be a rule
rather than an exception.

**And the leak that mattered ran the other way: noctalia kills our night
light.** `NightLightService.qml` runs `pkill -x wlsunset` in
`Component.onCompleted`, unconditionally, ignoring the `nightLight.enabled` we
pin off. It matches, because wlsunset here is unwrapped. What made it permanent
was systemd: **`Restart=on-failure` does not restart after SIGTERM** — signal
death is only a failure for signals other than TERM/INT/HUP/PIPE — confirmed
with a transient unit (`Result=success`, `NRestarts=0`). And
`night-light-run.sh` ends in `exec wlsunset`, so wlsunset is the main process
and takes the signal itself. noctalia's own journal had been saying so all
along: `NightLight Killed stale wlsunset process from previous session`, three
times today. Now `Restart=always`, with a check.

Two 47-hour-old `nmcli -t monitor` orphans also turned up. They are **not** an
ongoing leak: they sit in `session-3.scope`, from before noctalia became a
systemd unit, when it was an `exec=` line in mango's autostart.

### The launcher was doing nothing, and that is a fifth dead dwl path

Found on the way through `CompositorService`. `MangoService.spawn()` runs
`mmsg -s -d spawn_shell,<cmd>` — the flag form mango answers with
`{"error":"unknown command"}` and exit 0. That is the launcher's default path,
so picking an application launched nothing. Not always: entries whose `Exec` has
quoted or spaced arguments take `app.execute()` instead and worked, which is how
`docs/adr/0023` could record the launcher as reachable without noticing.

Five call sites shared the spelling and all five verbs are in mango's function
table, so the overlay patches them to `mmsg dispatch` (`docs/adr/0025`). The
alternative — noctalia's `customLaunchPrefix` setting — was rejected for fixing
one site of five and for launching applications *inside* `noctalia.service`,
where `KillMode=control-group` would kill them all on the next mode switch.
`mmsg dispatch spawn_shell` makes them children of mango instead; verified by
spawning one and reading its parent and cgroup.

`--replace-fail` makes an upstream rename a build error rather than a silent
revert, and the check pairs every verb against tokens pulled from the mango
binary — because `mmsg` reports an unknown *function* exactly the way it
reported the unknown *command*.

Left alone knowingly: `mmsg -g -A` (display scales) and `mmsg -s -t` (tag
switch) need a different call shape, not a different spelling. The logout button
stays disabled — its call is patched, but it is the one action that cannot be
tested without ending the session.

One of the new checks failed on its first run, and wrongly. It piped mango's
2,000-name token list into `grep -q`, which exits at the first match and
SIGPIPEs the writer: harmless noise on a hit, but on a miss the reader never
sees the rest of the list, so the verdict depends on how much of it arrived. It
reported `quit` as a function mango does not have; mango has it. Reading from a
file instead. A check that answers from a truncated input belongs in the same
catalogue as everything it was written to catch.

The patch then exposed a second-order trap in this repo's own overlay: the
`lockscreen` wrapper still took `prev.noctalia-shell`, the *unpatched*
derivation. quickshell resolves an ipc target by the `shell.qml` path the
instance was started from, so the lock's `ipc call` would have searched for
instances of a path nothing runs — `No running instances`, and every unattended
lock quietly back on swaylock, looking exactly like noctalia being down. Once a
package is overridden, `final.` is the only correct spelling for a consumer;
there is a check pinning the wrapper's copy to the system's.

---

## The power-profile widget was never noctalia's fault (2026-08-17)

`docs/adr/0026`. Started as "noctalia uses a different tool for battery
settings" and turned out not to be about noctalia, or about batteries.

noctalia's power-profile controls drive
`org.freedesktop.UPower.PowerProfiles` — the power-profiles-daemon interface —
which is unowned here, because TLP displaces PPD (`docs/adr/0017`). Read off
`PowerProfileService.qml`: `available` is `powerProfiles.hasPerformanceProfile`,
and every function in the file returns early when it is false. So the control
centre's power button has been sitting greyed out since the mode was added, and
`docs/SYSTEM.md` §13 has carried it as inert since 2026-08-14.

**The framing was wrong, and that was the useful part.** Disabling PPD was
recorded as removing a conflicting *tuner*. It also removed the *answer* — PPD
is the interface desktops ask through, not only the thing that acts. Nothing in
`power.nix` said so, and the cost landed in a program that had not been written
yet.

Two things it is *not*: noctalia 4.7.7 has no charge-threshold support at all
(grepped the package for `charge_control` and `ChargeThreshold` — nothing), so
TLP's 75/85 was never contested. And nothing was visibly broken in the bar:
`showPowerProfiles` defaults `false` and `PowerProfile` is not in the default
*bar* layout. The gap was a missing readout, not a dead button — except in the
control centre, where the button is shipped by default and was grey.

`pkgs/power-profiles-tlp/` now owns the name and answers it from TLP: reads
`/run/tlp/last_pwr`, writes through `power-mode`, and pushes
`PropertiesChanged` when TLP switches on its own at a charger transition. The
control-centre button went live with nothing seeded.

`services.tuned.ppdSupport` is the off-the-shelf version and does claim both PPD
bus names, but it tunes through tuned — a second owner on the cpufreq path
alongside TLP, which is `docs/adr/0005` and would invalidate every measurement
in `docs/adr/0017`.

### Four things the verification caught that reading would not have

**The profile names are UTF-16 in the client binary.** An ASCII `strings` over
`noctalia-qs` finds `Actions`, `Profile`, `Version` — and none of
`power-saver`, `balanced`, `performance`. Which reads as "the names are
unconstrained", not as "the scan missed them". `strings -e l` has all three,
plus the two `PerformanceDegraded` reasons. This repo's oldest lesson, one layer
down: a scan that finds nothing is not evidence.

**The dbus policy was ill-formed, and the XML parser found it, not dbus.** An
XML comment may not contain a double hyphen, and the header comment had one in
ordinary prose. dbus rejects the whole file — and that file is loaded by the
*system* bus, so the blast radius is every service on it. `xmllint --noout` is
now one of the six checks, and `libxml2` joined the static check's inputs.

**`StartLimit*` went in `[Service]` first**, where systemd ignores it —
`docs/adr/0006` says `[Unit]`, and `modules/home/default.nix` had the comment
saying so eight lines from where it was needed. NixOS's `startLimitBurst`
option puts it in the right section.

**And the one that only a live run could find: the daemon worked and noctalia
still did nothing.** `busctl` read and wrote the profile correctly, the CPU
actually changed, the waybar module and the bus agreed — and
`noctalia-shell ipc call powerProfile set balanced` printed nothing and moved
nothing. Printing nothing is *success* by `docs/adr/0023`'s rule, so the call
site looked fine. The reason was an hour old in the journal: quickshell probes
the name at its own startup, tries to **activate** it when unowned, and gives up
permanently — `The name is not activatable`, then `The PowerProfiles service
will not work`. A unit that is running is not a name D-Bus can start, and
nothing in `systemctl status` separates the two. Fixed by shipping
`share/dbus-1/system-services/…PowerProfiles.service` with `SystemdService=`,
which is what upower ships in the same nixpkgs. Seventh check.

Worth stating plainly: the previous six checks all passed against a build that
had this hole in it. They asserted the things that agree *inside* the repo. The
one that mattered was a property of how a client outside it starts.

The daemon was exercised end to end on a private `dbus-launch` bus with a fake
`power-mode` before it was given the real name — set, read back, an external
write standing in for a charger transition, and all five refusal paths. The
`--bus session` and `--pwrfile` flags exist for that and are staying: a daemon
that can only be tested by switching the system does not get tested. Each of the
four content checks was then confirmed to *fail* against a deliberately drifted
copy, because a check that cannot fail is not a check.

Holds are declined rather than implemented — `HoldProfile` raises
`NotSupported`. Recording a hold that changed nothing would be this repo's
signature bug written on purpose, and honouring one would let any application
override a profile whose every value was measured for this chassis.

The one accepted regression: noctalia's control-centre button *cycles*, and the
cycle reaches fanless on the third click. `docs/adr/0017` kept fanless off the
bar's left-click for exactly that reason. Accepted because it is a labelled
button rather than a scroll wheel, and noctalia raises a toast naming the
profile it moved to — the feedback the bar cycle lacked.

---

## Two symptoms, three bugs, none of which announced itself (2026-08-17)

**3 commits, `38f2d07` → `f3e2209`.** Reported as "shutdown and reboot force a
1.5 minute wait, and the login screen appeared broken". Both were real, they were
unrelated to each other, and looking for them turned up a third that nobody had
noticed because it was silent by construction.

### The 1.5 minutes was `DefaultTimeoutStopUSec` to the second

Which is the whole diagnosis: 1 min 30 s is not a plausible amount of time for
anything to *take*, so nothing was slow — something refused to stop and was
eventually shot. `session-N.scope: Stopping timed out. Killing.` names no
process, and the four SIGKILLed survivors were `bash`, `bash`, `sleep`, `sleep`.

The reason those `sleep`s existed is the useful part of the evidence. Their PIDs
were **higher than the PID of the `reboot` that started the shutdown** — so they
were spawned after the machine had been asked to go down. Not a wedged process;
a loop that was still running, ninety seconds in.

`scratch-watch.sh` and `window-title.sh` both carried

```bash
cleanup() { pkill -P $$ 2>/dev/null; }
trap cleanup EXIT PIPE HUP INT TERM
```

which reads as thorough and is the bug. A handler on a terminating signal
**replaces** that signal's default action — bash runs it and then *resumes*. Both
scripts reaped their `mmsg watch`, fell back into `while true`, and spun on
`sleep 1` forever. `window-title.sh` was worse than it looked: the trap had been
added to stop it leaking a watcher per `pkill waybar`, and it had quietly traded
that for leaking *the script itself*.

Split into `trap cleanup EXIT` plus `trap 'exit 0' PIPE HUP INT TERM`, so the
signal kills and `EXIT` reaps once on every path. Verified against the installed
store artifact rather than a copy of the pattern: the real `window-title.sh`
spawns its child, dies on SIGTERM, and leaves zero orphans — the fix does not
undo the leak fix it replaces. `fan-calibrate` had the same shape, where "Ctrl-C
restores the frequency limits" meant "restores them and keeps calibrating".

`checks/static.sh` now resolves each trap's handler by brace depth — a `sed` range
ending at `^}` runs straight past a one-line handler and finds the *next*
function's `exit` — and fails any that cannot exit. Confirmed to fail against
both scripts restored to their broken form, because a check that cannot fail is
not a check. Its floor is set below today's count deliberately: the floor guards
the regex, not the population, and one set to today's three would turn deleting a
trap into a check failure.

### The greeter: the kernel was innocent and the obvious fix was cargo cult

`services.greetd.useTextGreeter` defaults to **false**, and nothing warns when
the configured greeter is tuigreet. greetd.service therefore had no TTY handling
at all — none of `StandardInput/Output=tty`, `TTYPath`, `TTYReset`,
`TTYVHangup`, `TTYVTDisallocate`, the set `getty@` has always carried. greetd
never claimed tty1 and never cleared it, so tuigreet drew over the boot's
leftovers and systemd kept printing `[ OK ] Started …` on top of it afterwards:
`/dev/console` is the *foreground* VT, which is the one the greeter is on.

`Type=idle` was already set and is not a defence. It delays the start until jobs
are dispatched or 5 s pass, whichever is first, and says nothing about output
after that — libvirt, `graphical.target`, the greeter's own user session and
polkitd all landed on the greeter afterwards.

The instinct here is `quiet` and `boot.consoleLogLevel`, and it would have been
wrong. Console loglevel is 4, so only priority < 4 reaches the VT, and
`journalctl -b -k -p err` across the greeter's window is **empty** — the kernel
printed nothing. Lowering it would have changed nothing while looking exactly
like a fix that worked, because boot timing varies run to run and the symptom is
intermittent by nature. Worth keeping as the general shape: *establish which
stream is printing before quietening either one.*

### The third bug: yesterday's daemon had never once run

Found while reading the boot journal for the greeter. `power-profiles-tlp`, from
`fb23e76` the previous day, was not running and had never been running:

```
multi-user.target: Job power-profiles-tlp.service/start deleted to break ordering cycle
Activation request for 'org.freedesktop.UPower.PowerProfiles' failed.
```

A target implicitly gains `After=` on everything in its `Wants=` **unless the
unit already orders itself against that target**, and upstream `tlp.service` is
`After=multi-user.target`. So `wantedBy = [ "multi-user.target" ]` with only
`after = [ "tlp.service" ]` closed a cycle, and systemd resolved it the way it
always does — by deleting a job. D-Bus activation could not rescue it either,
since the cycle is in the transaction, so every attempt failed identically. To a
client this is indistinguishable from the unit not existing.

This is worth stating against the previous entry, which shipped this daemon and
described exercising it end to end on a private bus and through seven checks.
All of that was true and none of it touched the failure, because every one of
those checks asked whether the *unit and its clients agreed*, and this bug was in
whether systemd ever ran the unit. `journalctl -b | grep 'ordering cycle'` is now
in `docs/gotchas.md` as the thing to run after adding any unit that has both
`wantedBy` and `after`. `wifi-resume` in `networking.nix` already had the correct
shape, which is why the fix is to copy it — and why that duplicated-looking
target entry must not be tidied away.

The bus name is served for the first time as of this entry: `ActiveProfile`
reads `power-saver`, `Profiles` lists all three with `Driver=tlp`.

### Confirmed after the reboot

The greeter comes up clean. The reboot that got there **still waited its 90
seconds**, as expected: a rebuild does not restart what `exec-once` launched, so
the pre-rebuild watchers were still live. The timeout names its contents, and
they were the old instance and nothing else —

```
03:06:31 session-3.scope: Stopping timed out. Killing.
03:06:31 session-3.scope: Killing process 2921 (bash) with signal SIGKILL.
03:06:31 session-3.scope: Killing process 63706 (sleep) with signal SIGKILL.
```

PID 2921 started at 02:17, before the switch. Everything else in the scope had
already stopped, which is the useful half of the reading: the blocker was one
script, not a class of them.

Interesting that `scratch-watch.sh` exited cleanly even in its broken form. It
had an accidental escape hatch the other lacked — `pgrep -x mango || exit 0` at
the bottom of its loop, which fires once the compositor is gone. So the same bug
produced a hang in one script and not the other, which is why the first
shutdown's four survivors were two `window-title.sh` instances rather than one of
each.

Then proven rather than predicted, on the live process in the live session scope:
SIGTERM to the running `window-title.sh` killed it and left zero orphaned `mmsg`
watchers, after which `waybar-restart.sh` brought the module back. A sweep of
every process in the scope found nothing else that ignores SIGTERM, bar the
interactive `zsh`, which is by design and exits on SIGHUP when foot closes the
pty — which is why it never appears in a timeout list.

**`SigCgt` does not distinguish the fixed script from the broken one.** Both trap
SIGTERM, so bit 14 is set either way; the difference is only whether the handler
exits. The test is to send the signal and see whether the process is still there,
which is what `checks/static.sh` now enforces statically and what the paragraph
above did dynamically.

### Closed

The next shutdown was instant. **90 s → 1 s**, with no timeout logged at all:

```
03:14:24 reboot requested from client PID 9682 ('reboot')
03:14:24 Session 3 logged out. Waiting for processes to exit.
03:14:25 Stopped Session 3 of User henry.
03:14:25 Reached target System Reboot.
```

The boot after it is the first with all three fixes live from the start, and all
three hold: the watchers come from the fixed generation, the greeter draws clean
with nothing printed over it, `power-profiles-tlp` is active with **zero**
`ordering cycle` lines in the journal where there were four, and the bus answers
`balanced` — tracking TLP rather than the boot-time constant, so the daemon is
not merely running but working. No failed units, system or user.

### The shape shared by all three

Each failure was invisible in the place you would look for it. The scripts were
doing exactly what they were told. The greeter's unit was `active (running)`.
The daemon's absence was reported once, at boot, in a message about
`multi-user.target` rather than about itself, and `systemctl --failed` was empty
throughout — a unit whose start job was deleted has not failed. In all three
cases the answer came from the journal read at the timestamp of the symptom, and
in none of them from the file that contained the mistake.

---

## 2026-08-18 · Gruvbox → Catppuccin Mocha

The first **new scheme** run through `docs/THEME-MIGRATION.md`, which
[0028](adr/0028-one-palette-reaches-every-config-it-can.md) had written but
nothing had yet exercised. The runbook estimated "a day, spread across six
upstreams". The palette half took one file; the rest of the day was the half the
runbook exists to warn about.

Chosen on the evidence rather than by taste: the ten schemes noctalia ships were
ranked by mean OKLCh chroma over their sixteen ANSI colours, and Mocha's
foreground roles were checked against `base` for contrast before anything was
edited — every one clears **AAA** (text 11.3, green 11.0, red 7.1). Contrast is
asserted nowhere in this repo, so it was worth measuring rather than assuming.

### What the runbook got right

Both of its warnings paid for themselves.

**§1: the neutral-`bg0` blocker was real.** Mocha's `#1e1e2e` is blue by 16, and
the lock ramp asserted `R = G = B` in two places. Generalised to "one hue" rather
than deleted — [0029](adr/0029-the-lock-ramp-asserts-hue-not-greyness.md) — and
verified by confirming the *old* gruvbox ramp still passes the new check, and
that a planted hue-drifting stop set still fails it.

**§3: nvim needed the plugin swapped, not overridden.** `gruvbox.nvim` has 54
palette keys and the palette names 20; feeding it Mocha values would have left 34
gruvbox ones in place. Replaced with `catppuccin/nvim`, whose 26 keys are
Catppuccin's own vocabulary, so the 16 the palette names line up without a
translation table and the 10 it does not are *already Mocha*.

### What it did not cover

Three things the runbook will now warn the next person about:

- **A retired vendored package un-hides a nixpkgs tombstone.** Deleting the
  vendored `gruvbox-gtk-theme` from the overlay stopped it shadowing nixpkgs'
  `throw`, and the eval failed from `modules/system/desktop.nix` — a file the
  migration had no reason to open, naming the attribute among `systemPackages`.
- **The stray-hex check carried its own copy of the scheme.** Twenty hardcoded
  gruvbox values which, left alone, would have matched nothing and reported
  success: this repo's signature bug, inside the check written to catch it. The
  needles are now read out of `palette.nix`, with a floor that fails below
  sixteen. That is the fourteenth tick in the palette block, where the runbook
  said thirteen.
- **Three package names, spelled three ways.** `mochaMauve` (attribute),
  `catppuccin-mocha-mauve-standard` (GTK), `catppuccin-mocha-mauve-cursors`
  (cursor), `catppuccin-mocha-mauve` (Kvantum) — none derivable from another, all
  named by hand in four files, and a GTK name matching nothing falls back to
  Adwaita silently.

### The tail the runbook does not list

A repo-wide grep for `gruvbox` after the six packages were done found **five more
live references**, none of them in `docs/THEME-MIGRATION.md`'s tables, because
they are not colours — they are theme *names* held by applications that theme
themselves:

| Where | Was | Now |
|---|---|---|
| `nvim/lua/plugins/ui.lua` | lualine `theme = "gruvbox"` | `"catppuccin"` |
| `nvim/lua/config/lazy.lua` | `install.colorscheme` fallback | `"catppuccin"` |
| `programs.nix` | Zed `Gruvbox Dark`/`Light` | `Catppuccin Mocha`/`Latte`, **plus an extension** |
| `mango/scripts/lib.sh` | Equibop `enabledThemes` | `catppuccin.theme.css`, and the theme itself moved into the repo |
| `programs.nix` | the palette binding, named `gruvbox` | `p` |

Zed is the one worth recording: **Gruvbox ships inside Zed and Catppuccin does
not**, so the rename alone would have left Zed on One Dark with nothing logged.
`programs.zed-editor.extensions = [ "catppuccin" ]` is what makes the theme name
resolvable, and the first launch after the change may still show the fallback
while the extension installs.

**Equibop turned out to be repo work, not user work.** The theme in
`~/.config/equibop/themes/` looked like a downloaded Vencord theme and was not —
`@author henry`, 136 hand-written lines on the midnight-discord framework, with
gruvbox hex in a `:root` block and a set of `.hljs` rules. Untracked, in
`~/.config`, quietly supplying a theme: the same shape as the swaylock config
that `programs.nix` records having replaced.

So it got the **swaync treatment** rather than a rename — the hand-written
layout is now `dotfiles/equibop/theme-body.css` with no hex in it, and the
`:root` block and syntax rules are generated from `palette.nix`. Reversed order
from swaync's split, because CSS requires `@import` to precede every other rule
and the framework is imported at the top.

Three things fell out of doing it properly:

- **`mantle` joined the palette.** Discord needs a recessed tone for pressed
  controls, one step darker than `base`, and the mono ramp had no name for it —
  `bg0` is its darkest. Mocha names it, so it is a lookup rather than an
  invention. It reaches nvim too, now that it exists.
- **The five colour scales are mixed, not typed.** The gruvbox original
  hand-tuned twenty-five `hsl()` values across five ramps, where a typo and a
  considered value are indistinguishable. They are now `color-mix` from one
  palette colour each, so a scheme change moves all five.
- **Two new assertions.** One that the generated theme carries the accent, and
  one that **the filename `lib.sh` enables is the filename home-manager
  generates** — the specific silent failure here, since Equibop ignores a theme
  name matching no file without logging. Verified by renaming one side and
  watching it fail.

The old `gruvbox.theme.css` is left in place, inert. It is the only copy of that
variant and it is the user's own work; nothing reads it once `enabledThemes`
points elsewhere.

**And it caught us on the first rebuild.** Everything else came up Mocha; Equibop
did not. The theme was generated, symlinked and correct in
`~/.config/equibop/themes/`, and `enabledThemes` still said `gruvbox.theme.css`
— because that line is written by `mode.sh`, and the reload done after the
rebuild was `mmsg dispatch reload_config`, which reloads the compositor without
running the mode scripts. A rebuild alone never enables it.

Worth stating plainly, because the static check does **not** cover this: it
asserts the name `lib.sh` writes matches the file home-manager generates, which
is a different claim from "the setting was applied". Both halves were correct
and the theme was still not enabled. The reload tables in `CLAUDE.md` and the
runbook now carry an Equibop row.

### Also done

The yazi flavor left the repo. It was 916 lines of third-party hex under
`dotfiles/`, exempted from the stray-hex rule for that reason; it is now fetched
and assembled into a `.yazi` package by the overlay, so the exemption covers one
thing less. `programs.nix`'s palette binding, still named `gruvbox` after a
scheme it no longer held, became `p` — matching the other two modules.

### Verified by output, not exit status

`nix flake check` passes, but that was never the question. The generated tree was
read directly: mango's `focuscolor=0xcba6f7ff`, fsel's
`rgb(203, 166, 247)`, nvim's 16-key `palette.lua`; the GTK, cursor and Kvantum
names resolved to real directories in their packages; the lock pool's per-channel
means are exactly `30, 30, 46` with all nine tones on `bg0`'s hue; and nvim, run
headless, reported `colors_name=catppuccin-mocha` with `Keyword.fg=#cba6f7` —
the palette reaching an actual highlight, which reading the generated file does
not prove.

Not yet done: `rebuild`, `:Lazy sync`, and looking at it.

---

## 2026-08-18 · A scheme you can switch, and one you can read

Two requests in one pass: make the theme selectable rather than edited in place,
and produce one with enough contrast to read. They turned out to be the same
piece of work, because the thing that makes a scheme switchable — every colour
having exactly one home — is also what makes it auditable.

### Switching

`modules/home/scheme.nix` holds a string. `palette.nix` became a dispatcher over
`modules/home/themes/*.nix` and **kept its interface exactly**: still a flat
`rec` attrset of bare hex, so all thirteen consumers and the overlay read it
unchanged. Adding scheme selection touched no consumer, which is the only reason
it was cheap.

Not a `local.theme` option, and that is the interesting part.
`pkgs/default.nix` builds the lock ramp by `import`ing the palette, and it is an
**overlay** — applied before any module evaluates, unable to see `config.*`. An
option would have reached twelve consumers and missed the thirteenth, and the
one it missed is the lock screen: the surface with nothing beside it to compare
against. `docs/adr/0030`.

### Reading

The complaint was accurate and the diagnosis was not obvious. Every *accent* in
Mocha clears AAA on `base` unaided — it is the **greys** that fail. But the
first pass got the details wrong twice, and both corrections came from measuring
rather than reading:

- Comments are `overlay2` (5.81:1), **not** `overlay0` (3.36:1). Read off the
  plugin source and assumed; `nvim_get_hl` on the running editor said otherwise.
- The first high-contrast draft shifted the whole background ramp down with
  `bg0`, which dropped nvim's LineNr to **1.65:1** — darkening the background
  while also darkening what is drawn on it. Only `bg0` moves now; LineNr is 2.93
  where Mocha has 2.40.

`mocha-high-contrast` is Mocha's hues on Mocha's own `crust`, with the greys
lifted until every text role clears 7:1. The twelve accents are byte-identical
to Mocha's — they already passed, and changing them would have made it a
different scheme rather than a more legible one.

### The check that should have existed all along

`THEME-MIGRATION.md` §4 used to say, in as many words, *"what it does not catch:
whether the new colours are legible"*. It does now: WCAG ratios recomputed for
every text role on every run.

Two details that decided whether it was worth anything:

- **ncspot's `muted` set is measured against its own raised surface**, not
  `bg0`. ncspot fills whole rows with that colour. Against `bg0` three values
  passed that fail where they are actually drawn.
- **The floor is declared by the theme.** Upstream Mocha does not reach WCAG AA
  on its greys, so a global 4.5 would make it impossible to ship Mocha *as*
  Mocha. Stating 4.4 in the file is more honest than quietly raising it.

**It failed on its first run against the theme shipped that morning**: ncspot's
secondary text at 3.13:1, below even Mocha's own declared floor. That value was
this repo's derivation rather than Catppuccin's, so fixing it cost no fidelity —
nothing had ever looked at it.

### And one self-inflicted bug worth keeping

A `#` comment written *inside* the `nvimPalette` `''` string was emitted
verbatim into the generated `palette.lua`, which then would not parse. `nix
flake check` passed. `checks/static.sh` passed — it greps that file for the
accent, and the accent was there. nvim's own failure mode is to report a failed
plugin config and fall back to no colourscheme, which looks like a theme that
did not apply rather than a syntax error.

The derivation now runs `luajit -b` over the generated file, verified by
planting the same `#` and watching the build fail. A generated file that no
gate parses is a gap, not a file.

Palette block: **18 ticks**, up from 16.

---

## 2026-08-18 · The idle inhibitor leaves the bar

Started as a question — *what command toggles the waybar idle inhibitor, so I
can bind a key to it?* — and the answer was **none, and there cannot be one**.
waybar's built-in `idle_inhibitor` keeps its state as a static bool in the
waybar process, toggled by a GTK click on the widget and by nothing else.
`SIGUSR1`/`SIGUSR2` run the configured bar-*visibility* action, the `signal`
option refreshes `custom/*` modules only, and the `ipc` option is Sway's bar
protocol. Read from `waybar.5` and `waybar-idle-inhibitor.5` on 0.15.0, not
from memory.

So the module is now `custom/idle-inhibitor`, the inhibitor is
`wlinhibit.service`, and `SUPER+SHIFT+A` and the click run the same script.
`docs/adr/0031`.

### The bug that was already there

Chasing the *other* half — does anything besides waybar's layer surface get
honoured — turned up a defect nobody had reported. A control run of
`swayidle timeout 1` fired **zero** times in 15 s, which should have been
impossible with nothing inhibiting. It was inhibited: a screenshot of the bar
showed `󰒳`. One `waybar-restart.sh` later the glyph was `󰒲` and the probe fired.

That is the documented behaviour (`gotchas.md` said so) but seeing it happen
reframes it. **The bar is never visibly wrong** — the glyph and the inhibitor
die in the same instant, so there is no moment where the icon lies. It just
silently stops being what you set, on any of `waybar-reload`, a layout switch,
a mode switch or `SUPER+/`, and `minimal` and `hud` do not carry the module at
all. The keybind was the request; this was the reason to do it properly.

### Verified by output, both directions, before any rebuild

The one genuinely uncertain thing was whether mango honours an inhibitor on
wlinhibit's **bare, never-committed `wl_surface`** the way it honours one on
waybar's layer surface. `idleinhibit_ignore_visible=0` made that a real
question. Ran as a transient `systemd-run --user` unit against a `timeout 1`
swayidle probe:

| | idle fires in 15 s |
|---|---|
| wlinhibit running | **0** |
| wlinhibit stopped | **1** |

Same reason as the layer surface, in the end: `checkidleinhibitor` gets
`c = NULL` and takes the `!c` arm. But it was measured before it was believed.

### What the state living outside the bar costs

The built-in could not show a wrong state; this can. A unit that hits its
restart limit has released the inhibitor while the bar still draws something.
Hence three things that would otherwise be over-engineering:

- a `failed` class, **red**, so it does not read as merely on;
- `interval = 30` *underneath* the `SIGRTMIN+12` signal — the signal makes the
  toggle instant, the poll is the floor under a unit that died on its own;
- `idle-inhibit.sh on` re-checks after 0.3 s rather than trusting `systemctl
  start`, which returns once the process is forked. wlinhibit exits 1 when the
  compositor advertises no manager, and that lands *after* the return.

`Restart=on-failure`, deliberately not the `always` wlsunset needs: wlinhibit
exits 0 on SIGTERM, and SIGTERM is what the toggle's off path sends.

### Two smaller things it closed

- **`keep-awake` was the last `fb=none` row in `shell.sh`.** It was noctalia-only
  precisely because no inhibitor outside noctalia could be reached from a key;
  it has a fallback now and the bind moved to `universal/bind.conf`. noctalia
  keeps driving quickshell's own inhibitor — one mechanism serving both would
  leave the other shell's indicator lying (`docs/adr/0023`).
- **`checks/static.sh` gained an assertion for a `[Install]` section that must
  not exist.** An inhibitor armed at every login looks, from the bar, exactly
  like one you pressed for.

### One owner per mode

First draft left this as a stated caveat — an inhibitor armed in tiling stays
armed after a switch to noctalia, where noctalia's indicator reads off — on the
grounds that releasing it would reintroduce the silent mode-switch release the
change exists to remove. Overruled, correctly: the two can never agree.
noctalia's IPC is `toggle`/`enable`/`disable`/`enableFor` with **no getter**
(`IPCService.qml`, 4.7.7), so there is no reading one and setting the other, and
the losing mode's inhibitor holds the machine awake behind an indicator that
says it is not.

So `apply_mode` releases wlinhibit entering noctalia. The objection was really
about *silence*, not about releasing — so it notifies, and the `is-on` guard
means it only notifies when something was actually held. One-way: coming back
out cannot restore it, because nothing can ask noctalia what it was holding.

`idle-inhibit.sh` grew an `is-on` verb for the guard rather than letting lib.sh
run `systemctl is-active wlinhibit.service` itself — the unit name is written in
one file, and a second copy is a thing that can drift. `checks/static.sh`
asserts the handover line survives: deleting it leaves both inhibitors real and
only an indicator wrong, which is the shape nothing here notices.

---

## 2026-08-18 · Two more schemes, and three checks measuring the wrong thing

`docs/adr/0032`. Adds `gruvbox` and `nord` beside the two Mocha variants, and
moves the artefacts the palette cannot colour into the theme file that owns them.

`docs/adr/0030` had ended by saying the theme packages were *"the next commit,
not this one"* — correctly, since both schemes it shipped were Catppuccin and
shared all of them. A scheme from another family removed that excuse.

### What the scheme now reaches

Before, the GTK theme, Kvantum theme, icons, cursor, yazi flavor, noctalia
scheme name, nvim plugin and Zed theme were spelled across `theme.nix`,
`pkgs/default.nix`, two dotfiles, a lua file and a shell script — a six-file
migration with **nothing checking it**, each half failing by falling back to a
default that looks like a theme someone chose.

Now a theme declares `packages` and `apps`, `pkgs/default.nix` resolves the
names, and `checks/static.sh` asserts each resolves to a real directory. Three
files left `dotfiles/` because they held a *name*, not a colour:
`Kvantum/kvantum.kvconfig`, `mango/noctalia/settings-pinned.json`,
`nvim/lua/plugins/colorscheme.lua`. All four schemes were checked one at a time.

### Three defects, none of them visible

The point of the entry: each had shipped, each looked fine, and each needed its
check corrected before it could be seen.

- **ncspot's error row was 1.28:1.** `muted.err` is a *background* — ncspot
  draws `error_fg` (= `muted.fg`) on it — but the check measured it against
  `muted.surface`, a pair ncspot never renders, and reported 7.05:1. Every theme
  had it, including the one added to fix legibility.
- **Four roles were never audited.** The check read hex with `sed`, so
  `okColor = green;` read as "role absent" — all four status roles, in every
  theme. It now takes the palette resolved by Nix as JSON, which also retired
  `mauve`: a key only the check ever read.
- **The lock ramp had a rounding bug.** `blocks.py` interpolated three channels
  independently; Python's `round()` is round-half-to-**even**, so `(5, 8, 14)`
  becomes `(6, 10, 16)` at `t=.25`. It only diverges when the half-case lands
  *and* parities differ, and no shipped scheme can expose it — Gruvbox is three
  equal channels, Mocha and Nord three even ones. Found while evaluating Ayu.
  Fixed structurally: one channel is interpolated, the rest derived from fixed
  offsets. Its checkPhase then failed under *gruvbox*, because ImageMagick writes
  a neutral ramp as Gray and `mean.g` reads 0 — the earlier generalisation from
  `R = G = B` had been tested only against tinted schemes.

### Floors: two, and no minimum under them

Gruvbox's normal red is 2.69:1 by upstream's design, so one floor would have
forced the scheme to declare 2.6 and let `comment` rot to meet it. Split into
`contrastFloor` (what this machine draws text with) and `ansiFloor` (the terminal
slots, which nothing here draws text in).

**`HARD_MIN = 3.0` was removed as an invention** — it arrived with
`mocha-high-contrast` out of a request for readable text, then read like an
external requirement. It would have forbidden Nord, whose comment colour is
1.69:1 as published. The rule that replaced it: **upstream values ship as
published; values this repo derives are chosen to be legible.** Only the ncspot
`muted` set is in the second category.

Measured: mocha 4.4/7.0, mocha-high-contrast 7.0/8.0, gruvbox 4.0/2.6,
nord 1.69/3.0.

### What it costs

- **The scheme set.** Requiring every artefact to be native cut noctalia's ten
  candidates to three. Ayu and Dracula were written, gated, then dropped for
  three stand-ins each. Adding a fourth means packaging something — Rose Pine
  needs one GTK theme.
- **Historic gruvbox was not stock**, if comparing against git history: it
  vendored the GTK theme, the Kvantum `.kvconfig` and a 916-line yazi flavor,
  and used Papirus recoloured yellow. Only the cursor is unchanged.
- Zed is the one pair no check can gate — extension id and theme name both live
  in Zed's registry.
- Two of gruvbox's eight muted values were below 3:1 where drawn and were
  re-derived; they predate the contrast check.

---

## 2026-08-19 → 2026-08-20 · Colour per mode, a control centre, and one mode fewer

**5 commits, `66e9779` → `5af3bb3`.** ADRs [0033](adr/0033-the-control-centre-is-a-reader.md),
[0034](adr/0034-colour-follows-the-mode-artefacts-do-not.md),
[0035](adr/0035-hud-is-removed.md). Checks: 89 → 105 assertions.

### The control centre (0033)

Twelve toggles in one rofi list on `SUPER+C`, plus a bar button in `focus` and
`minimal`. Not a reimplementation of noctalia's panel: every fact it shows
already had one owner, and the row reads that owner. Microphone and phone
joined the bar in the same pass, because a row may only join once the fact has
a home. `phone-status.sh` gained verbs so the device id stays written once.

### Colour follows the mode (0034)

Mode switching stays at **runtime**. A rebuild per mode buys only the artefact
half, which was already one line in `scheme.nix`, and costs the switch plus a
branch in four modules.

So the scheme split in two. `scheme.nix` keeps the artefacts; `modes.nix` names
a scheme per mode for everything whose theme is wholly colour — mango's chrome,
noctalia's palette, Equibop's theme filename, and kitty, foot, rofi and ncspot
through runtime links `apply_theme()` re-points. Keyed by **mode**, never by
scheme: a scheme name on the Nix→shell boundary is the drift `lib.sh` exists to
stop.

Three findings, measured rather than assumed:

- **foot does not fail silently** on a dangling include — exit 230, no
  terminal. That makes the activation seed load-bearing for *having* a
  terminal. kitty is silent, and worse than assumed: every colour drops to a
  built-in default.
- **The contrast floors audited one scheme while the machine wore two.**
  `flake.nix` now passes every scheme in service. Nord's numbers had never been
  measured.
- **An accent needle cannot see the wrong half of the right scheme.** ncspot is
  drawn entirely from `muted`; `p.accent` where `m.accent` was meant passed
  every existing assertion. Every hex in its config must now be a `muted`
  value. Equibop's `@name` had read `Catppuccin Mocha` through two scheme
  changes — generated per mode now, and asserted.

### hud removed (0035)

299 lines of code deleted, 113 added. Unused was not the argument; **hud was
the only instance of four mechanisms**, one of which was a bug. It was the only
mode that also forced a *layout*, so in hud mode the layout picker wrote a
choice that the next restart discarded — accepted, recorded, invisible. It was
also the only second stylesheet, the only layout with a non-zero margin, and
the second of two modes running waybar, so 0034's divergence ceiling had to
assert `tiling` and `hud` agreed with each other. That ceiling is now one
comparison, derived from `modes.nix` rather than naming a mode.

Two things the **checks** found, not a person: `surface` in `waybar/colors.css`
became a colour nothing imported once `style-hud.css` was gone, and the
config-count assertion still expected 4 layouts × 2 positions. That count names
its layouts now — a bare count passes when one vanishes and another is emitted
twice.

### Also

GTK4 was unthemed and had been for two schemes: `gruvbox-dark-gtk` ships no
`gtk-4.0/`, and GTK4 ignores `gtk-theme-name`, so libadwaita apps sat on Adwaita
while GTK3 looked right. The scheme now names `gruvbox-gtk-theme`, built by the
overlay. `gtk4`'s `color-scheme` was also an integer where GTK 4.22 wants the
nick. And tuigreet's `--cmd` inherits greetd's file descriptors, so the
compositor's stdout and stderr were being written into the greeter's VT buffer.

### What it cost

- **Twelve negative tests** across the three ADRs, all failed correctly before
  landing. Two checks were themselves wrong first: a CSS scan that read nothing
  because `.modules-left` is jq for `.modules` minus `left`, and a config scan
  broken by switching `find` to basenames. Only the zero floors caught either.
- **Two silent failures while adding twenty lines** of waybar module — a glyph
  lost writing the Nix (no `\uXXXX` escape; it is literal UTF-8), and a module
  with no CSS rule. Both are asserted now, for every module every layout
  carries.
- **896 lines of comment added, then 147 removed** in a trimming pass. The
  target in `CLAUDE.md` is a one-line reason plus a pointer; the reasoning
  belongs in the ADR. `mode-theme.nix` went 244 → 178 lines, `modes.nix` 45 → 24.

### noctalia's templates stay off (0036)

The last open phase of 0034 closed as **no**. The plan had reserved a "safe set"
of five templates whose hooks were hookless or guarded; measured against the
live package and the running system, **that set is empty** — two write paths
`apply_theme` owns, the rest write files nothing here reads. Reasoning and the
per-template table are in `docs/adr/0036`; the hook failure is in
`docs/gotchas.md` -> Theming.

Nothing on screen changed. What changed is that the pin is now **asserted**:
any non-empty `activeTemplates` fails the build, deliberately blunt rather than
a blocklist that would need updating whenever upstream adds a template.

### What it cost

- **Two negative tests**, both caught, each naming which half was wrong.
- **One pre-existing quirk exposed**, not fixed: the settings-key scan descends
  into arrays, so a non-empty list of strings reports
  `templates.activeTemplates.0` as "not a key noctalia has". Inert while every
  list in the pin is empty. Read `docs/adr/0036` before adding a list-valued
  setting to it.
- **Three copies of one argument written, then two removed.** The routing rule
  in `CLAUDE.md` is decision -> ADR, failure -> `gotchas.md`, cost -> here. The
  first pass put the whole case in all three.
- `DESIGN-per-mode-theming.md` deleted — the scratch note that carried these
  measurements between sessions.

### Night light stops at the noctalia boundary (0037)

Reported from use: switching to noctalia with night light on left a warm screen
with nothing in that mode able to change it — wlsunset's controls are the bar
and the control centre, and its own night light is pinned off.
`noctalia-start.sh` now stops the unit on every entry, beside the waybar and
swaync handovers, and notifies. Not restored on the way out; the two
alternatives are in `docs/adr/0037`.

**Every entry, not just a switch.** The unit is
`WantedBy=graphical-session.target`, so logging straight into noctalia produced
this with no mode script running — putting the stop in `apply_mode` would have
fixed the reported case and missed that one.

### What it cost

- **Two negative tests.** Removing the stop line gave 106 passed / 1 failed,
  naming it. The `pkill` branch needed no test: it fired on the first run,
  against this script's own *comment* about noctalia pkilling wlsunset. The grep
  strips comments now — a scan that reads prose fails on a file that is correct,
  which costs as much trust as one that passes on a file that is not.

### Weather, as a module the menu reads (0038)

Phase 4 of the control-centre queue, and the first fact on this machine with
**no owner at all** — so the whole question was where the owner goes. It goes on
the bar: `scripts/system/weather.sh` fetches, `custom/weather` renders it in the
`full` layout, and the control-centre row reads the same script. A row that
fetched would make a menu the owner of a fact the bar cannot see, which inverts
`docs/adr/0033`.

**Three verbs, because only two may touch the network.** `status` for the bar,
`refresh` for Enter on the row, and `read` — cache only — for the row itself.
The menu renders every row in parallel and costs its slowest one at 73 ms; a
ten-second curl there is the whole menu failing to appear. Asserted, not
commented.

**Coordinates are `local.location` in `options.nix`**, typed `float`, generated
into `mango/universal/weather-location.env`. noctalia's own widget resolves them
through `api.noctalia.dev/geocode`; open-meteo needs only the two numbers, and
`timezone=auto` means `time.timeZone` is not copied either.

`class` `stale` is the point of the exercise — a served cache that does not say
it is a served cache is yesterday's temperature in today's font. Full reasoning
in `docs/adr/0038`; the four failures in `docs/gotchas.md` -> Waybar and ->
Scripts.

### What it cost

- **Four negative tests**, all four caught: a diverged refresh signal, the row
  calling `status`, a WMO code with a phrase and no glyph, and a renamed
  variable in the generated env file.
- **Two failures found by the checks rather than by looking**, both on the first
  run. The generated env file under `scripts/` tripped the existing assertion
  that every `$MANGO_DIR/scripts/…` reference is an executable script — the scan
  was right, and the file moved to `universal/`. And a `grep -q "\\$$v"` in the
  new check expanded `$$` to the shell's PID, so grep read the digits as a back
  reference and reported three variables missing that were all present.
- **One design change mid-build.** The row first cut its description out of the
  module's tooltip and rendered `light` for `light drizzle`. It reads waybar's
  own `alt` field now — the same fix as `jfields`, one layer along.
- **28 WMO codes written out**, against the one value a test fetch returns. Same
  lesson as the phone row's five classes; an unrecognised code says so rather
  than drawing "clear".
- **This machine now tells open-meteo where it is every 15 minutes.** That is
  the feature's real price and caching does not reduce it. One host instead of
  noctalia's two, and it is the host answering the question.

**Corrected after the rebuild.** `custom/weather` shipped in `full` only, on the
reasoning that `focus` drops the readouts. The running bar is `focus` — so the
cache had nothing keeping it warm and the control-centre row read `stale` as its
default rather than its edge case. `focus` drops the *diagnostic* readouts;
weather is ambient, like the clock. It is in both now, and out of `minimal`
deliberately. Found by looking at the running system, not the plan.

### The control-centre queue is closed

`DESIGN-control-centre-additions.md` is deleted. Phases 1–4 are canon
(`docs/adr/0033`, `docs/adr/0038`, `gotchas.md`, `SYSTEM.md`), and both rough
edges it carried were already in `gotchas.md` — the U+F6FF glyph, now fixed, and
`network-menu.sh`'s scan cache. Nothing was lost with it.

Its remaining three phases are **decided against, not pending**:

- **Battery** — cheap off `BAT0`, and redundant with the bar module that is in
  every layout.
- **Brightness** — `brightnessctl -m` reads fine, but there is no picker to
  open, so the row would be display-only unless one is written.
- **Airplane mode** — would be the second thing on screen able to turn wifi off.
  That is the two-owner shape `docs/adr/0033` exists to prevent, for the least
  valuable of the three.

The rule for the next row is the one that earned the first four: build it when a
fact is **invisible everywhere**, the way mic mute was. None of these three is.
### Every rofi menu was twelve rows tall, and the config said otherwise

Reported from use: the control centre paged again after the weather row. The
cause was three facts stacked, none of them what `dotfiles/rofi/config.rasi`
claimed:

- **`dynamic: true` is about filtering**, not fit-to-contents — rofi's own
  wording. The comment in that file said it "shrinks the list to its contents"
  and had said so since the file was written.
- **`lines: 12` is a fixed height.** Measured at 2, 6, 15 and 30 entries: the
  window never changed size. So a two-entry mode picker drew ten blank rows.
- **`-l` loses to the theme on rofi 2.0**, so `control-center.sh`'s computed
  `-l "${#ROWS[@]}"` — added specifically to stop paging — never did anything.
  `rofi -dump-theme -l 15` still prints `lines: 12`.

`lib.sh` grew **`rofi_menu <max>`**: entries on stdin, sized to them with
`-theme-str`, capped at an explicit per-menu ceiling. Ten call sites converted;
four dead `MENU=(rofi -dmenu …)` arrays removed with them. Caps are 12 for the
access-point list and the clipboard, 15 for bluetooth, 20 for the fixed pickers,
24 for the control centre. The password prompt keeps a bare `rofi` — it must not
take `-no-custom` — and now asks for `lines: 0` rather than twelve empty rows.

`network-menu.sh`'s U+F6FF ethernet glyph fixed in the same pass; `fc-match`
confirmed it was resolving to `Unifont Sample`. Documented as broken since
2026-08-19.

### What it cost

- **Three negative tests**, all caught: a menu reverted to bare `rofi -dmenu`,
  an `-l` re-added, and the control centre's ceiling dropped below its row count.
- **The check is the point.** The control centre had a comment explaining at
  length why `-l` was computed rather than hardcoded, and the mechanism it
  described did not exist. A paragraph asserting a fact cannot notice when the
  fact stops being true.
- **Five scripts had to start sourcing `lib.sh`.** They had none of it before,
  which is why each carried its own `MENU` array.

### The menus get the focus border the compositor cannot draw

Reported from use: the menu did not separate from the windows behind it, which
on this theme are the same colour. Three facts explain it, and only the last is
a preference:

- **rofi 2.0 is a layer surface.** `mmsg get all-clients` does not list it while
  it is visible, and `layer_name:rofi` is what reaches it — so mango draws no
  border, and the two `windowrule=…,appid:Rofi` lines in `rule.conf` match
  nothing. **They are dead and were not removed** in this pass.
- **The desktop is flat by decision** — `shadows=0`, `layer_shadows=0` — so
  there is nothing but that border.
- It was `@overlay`: **1.67:1** in gruvbox, **1.45:1** in nord, against a
  `#3c3836` unfocused mango border at 1.27:1.

Now `@subtext` — 5.30:1 gruvbox, 7.37:1 mocha, 8.42:1 mocha-high-contrast,
9.25:1 nord. All four audited, not just the selected one.

**`@accent` was tried first and rejected in use.** The argument for it was good
— it *is* mango's `focuscolor`, on the surface that is always focused when
visible — and it was still wrong: a saturated ring reads as an alert, not an
edge. `bg3` and `comment` are the calmer candidates and both fall to 1.69:1 in
nord, i.e. back to the border being replaced, so `@subtext` is the only
palette role that is neutral AND legible in every scheme. A filled accent chip
for the prompt was tried in the same pass and reverted; the prompt is plain
accent text again. rofi cannot derive a shade from a variable — `@accent / 50%`
and `@accent % 50%` are both parse errors — so a softer version of a palette
colour is not available without hardcoding a hex, which per-mode theming forbids.


---

## 2026-08-20 · The plan, re-measured

No code changed. `docs/PLAN-idiomatic-nix.md` was reviewed end to end and
rewritten 550 → ~570 lines of quite different content: the five closed phases
became a ledger pointing at their ADRs, and every outstanding item gained
steps and a verification. The retrospectives went because each was a second
copy of an argument already in `docs/adr/0010`–`0014`; the one lesson that
lived nowhere else — *a comment inside `''…''` is data* — was kept.

**Everything was re-measured, and the headline number had moved the wrong way.**
Phase 5d's premise was 1,417 comment lines in 3,930 of Nix. It is now **2,222 in
6,390** — the pass on 2026-08-12 did not fail, it was outrun by growth. So the
instrument changed: absolute comment count, five named files, and an explicit
note that ratio is meaningless below ~50 lines of code (`palette.nix` is 50
comments over 1 line and is correct as it stands).

### Four open questions closed with evidence rather than left to drift

- **`lenovo-thinkpad-l14-amd` exists** and this is an L14 Gen 5 / Ryzen 5 Pro
  7535U. Adopting it adds exactly `acpi_backlight=native` and `iommu=soft`.
  `systemd-backlight@` is `active (exited)` with no failed units, so the first
  fixes nothing observable, which leaves SWIOTLB bounce buffers as the whole of
  what changes — on the machine whose defining bug is an amdgpu deadlock nobody
  can reproduce on demand. **Decided against.** Upstream's own comment says BIOS
  1.13 fixed the IOMMU problem; this machine is on 1.21.
- **logseq has no data.** `~/.logseq/graphs/` empty, `preferences.json` stock, no
  `journals/` anywhere under `$HOME`. Drop it and `electron-39.8.10` with it.
- **`electron-40.10.5` is winboat's**, traced by `nix-store --query --referrers`.
  The comment blaming "your Arch install" is wrong about the consumer as well as
  being present-tense Arch narration.
- **Splitting `checks/static.sh`** — no. A section in its own file is a section
  that can stop being sourced.

### The gate does not catch itself

`static.sh` prints `114 passed, 0 failed` and asserts only `FAIL -eq 0`. Delete
a whole section and it prints `90 passed, 0 failed` and exits green. Every scan
*inside* the file has a floor; the file as a whole has none. Now Phase 6, and
item 1 of the order — it is what makes every other item observable.

### Three mango facts, all the opposite of what the comments said

Checked against `nix build nixpkgs#mango.src` and then re-checked by probe:

- **`mango -p` validates whichever config it had when it saw the flag.** `getopt`
  returns on `-p` mid-parse, so `mango -p -c FILE` checks the *live* config and
  exits 0 having never seen `FILE`. `mango -c FILE -p` is the working form.
- **`-p` exits 1 for an unknown keyword and 0 for a `source=` it cannot open**,
  printing to stderr instead. So a bad `source=` is *not* silent, as two config
  comments claim — it is in `journalctl -t mango` — but a check must read stderr,
  not the exit status.
- **Relative `source=` follows the config file's own directory under `-c`.** So a
  check that points `-c` at a mode conf reports all 20 `source=` lines missing.
  Use a fake `HOME` and no `-c`.

All three are now in `docs/gotchas.md` → Desktop.

### Two claims of mine that were wrong, corrected in place

- **`recursive = true` is not just a writability exemption.** It is what lets 12
  generated files coexist with the hand-written mango tree — `waybar.nix:618`
  says so in its own comment. The old plan listed removing it as the prize;
  removing the *writer* is the prize, and the flag stays.
- **`distrobox` being declared twice is not a live bug.** Both entries resolve to
  the same store path, so PATH order changes nothing today. The real divergence
  in the closure is `bind`: system carries the `host` output as a NixOS default,
  `packages.nix:120` declares `dnsutils` for `dig`. That, not name duplication,
  is what §5b's assertion should test — the naive intersection is 21 names and
  would be ignored by the second week.

---

## 2026-08-20 · The gate now catches itself, and parses every mango config

Plan items 1 and 2 (`docs/PLAN-idiomatic-nix.md` → *Suggested order*). Two
assertions, both confirmed against planted defects before being called landed.

### 6a — `static.sh` asserts its own size

`ASSERTION_FLOOR` beside the summary, failing when `PASS + FAIL` drops below it.
Every scan inside the file already had a floor; the file as a whole had none, so
deleting a section printed a smaller number and exited green. A floor, not a
ratchet — adding assertions stays a one-line change. `docs/adr/0039`.

**Confirmed**: with the *Fonts* section deleted, `112 passed, 0 failed` is now
followed by `✗ only 112 assertions ran, floor is 115` and exit 1. The same
deletion exited **0** before the change, so the hole was real.

### 3b — every mango mode config parses under the real binary

New *Mango config parse* section. The mango tree is copied out of the built home
closure into a fake `HOME`, each mode's conf is staged as `config.conf`, and
`mango -p` runs with **no `-c`**. It fails on any stderr and floors on modes
parsed.

**Fails on stderr, not on the exit status**, because `-p` exits **0** for a
`source=` it cannot open. That is the case worth catching: a sourced file goes
missing, its binds stop working, and the session starts anyway.

**Two departures from the plan as written, both better:**

- **`pkgs.mango` did not go into `nativeBuildInputs`.** mango is already in the
  system profile, so the check reads `$SYS/sw/bin/mango` the way the rofi check
  reads `$SYS/sw/bin/rofi`. No dependency edge, and it tests the binary that
  will actually run.
- **`--no-preserve=mode` is not enough on its own.** The first probe copied a
  mode conf to `config.conf` with plain `cp` and the second mode failed with
  `permission denied` — the 0444 store inheritance that `lib.sh` carries
  `install -m 644` for, reproduced from scratch inside the check.

**Confirmed both ways**: renaming `universal/tag.conf` (mango: stderr, exit 0)
and adding `notakey=1` to `tiling.conf` (mango: stderr, exit 1). Each fails the
check naming the mode; the first names both, since both source it.

The gate is now **115 assertions across 14 sections**.

### A correction to this morning's own measurement

The plan rewrite dated today reported the Nix comment problem as *widening*,
"ratio 0.56 → 0.60". It has not widened. 0.56 counted comments against
`total − comments`; 0.60 counted them against code with blanks removed. Two
different denominators, so the arrow pointed the wrong way. Measured the same
way on both sides the ratio **fell** — 0.56 → 0.53, or 0.64 → 0.60, depending
which you use. Comments grew 55% (1,436 → 2,222) while code grew 64%
(2,245 → 3,681).

§5d's conclusion still holds: judge on absolute comment count, since the ratio
can improve while there are 786 more lines to read. But the evidence given for
it was wrong. The table now shows both numbers with their denominators named,
and *How to verify* carries the loop that produced them.

---

## 2026-08-20 · `config.conf` selects instead of duplicating — Phase 3 closed

Plan item 3. `apply_mode`'s `install -m 644 <mode>/<mode>.conf config.conf`
became `ln -sfn`, removing the last runtime **write** into `~/.config/mango`.
`docs/adr/0040`. Phase 3 is closed.

Why it is cheap: mango is still launched with no `-c`, so `cli_config_path`
stays empty and every `./` still resolves against `$HOME/.config/mango/`. All
**20** `source=` lines work untouched and session startup does not change, so
this could be checked in-session rather than after a logout.

### Two things the plan did not ask for, both needed

- **A guard, because the swap loses a failure signal.** `ln -sfn` to a missing
  target **succeeds**; the copy it replaced failed loudly. A dangling
  `config.conf` drops mango to built-in defaults with no keybinds. So
  `apply_mode` checks `[ -s <mode>.conf ]` first, and does it **before
  `state_write`**, so a mode that was not applied does not get recorded as
  active.
- **A second assertion, on the link itself.** Absence from the generation is not
  enough. Reverting to `install`/`cp` would work, and would bring back the
  staleness — a copy goes out of date as soon as a rebuild re-points
  `<mode>.conf`, with nothing reporting it. Both assertions were confirmed
  against planted defects: reverting the `ln -sfn`, and adding a second owner
  for `mango/config.conf` as an `xdg.configFile`.

### The check now stages a symlink, not a copy

Yesterday's `mango -p` check staged each mode's conf with `install -m 644`,
reproducing the 0444 scar from scratch. That is gone: production's
`config.conf` is a symlink now, so the check stages a symlink too, which is
simpler and matches what actually runs. `cp -r --no-preserve=mode` stays, for a
different problem — the copied **directory** is 0555, so nothing can be created
in it.

### Verified without touching the session

A fake `HOME` under `env -i`, all five paths: the activation seed points at
`tiling`; switching to `noctalia` and back re-points the link and moves state; a
mode with no conf returns 1 leaving **both the link and the state untouched**;
and mango parses through the symlink with no diagnostics.

The fresh-machine claim was re-checked rather than inherited, and holds:
`SYSCONFDIR` is `/etc`, and `/etc/mango/config.conf` does not exist on NixOS —
the package ships its default under `$out/etc/`, which never lands there.
`HOME=$empty mango -p` exits 1 saying so.

⚠️ **Migration is lazy.** `[ -e ]` follows symlinks and finds the existing
regular file, so a rebuild leaves `config.conf` a copy until the next mode
switch. Harmless — a stale copy is still a valid config — but `readlink`
returns nothing until then.

### The walker residue was not what it looked like

`rm -rf ~/.config/mango/walker` was step 5. `rmdir` refused it: the directory
was not empty. It held `config.toml`, a **dangling symlink** into a `configs/`
directory that left with walker on 2026-08-14 (`docs/adr/0021`). An `ls | head`
had shown it as empty. Removed after looking at it. This is what the plan cited
it as: a writable tree keeps whatever anything ever wrote there, including links
to things that no longer exist.

---

## 2026-08-20 · logseq is gone, and the insecure pin names its real consumer

Plan item 4 (§5c). Pure subtraction: `logseq` out of `packages.nix`,
`"electron-39.8.10"` out of `permittedInsecurePackages`, and that block's
comment rewritten.

**Both of the plan's claims were re-checked rather than inherited**, since one
of them meant deleting an application:

- `electron-39.8.10` had exactly one referrer, `logseq-0.10.15`.
  `electron-40.10.5` had exactly one, `winboat-0.9.0`. The old comment blamed
  "your Arch install carries electron40-bin too", which named the wrong consumer
  and was present-tense Arch narration on a machine where Arch has been gone
  since `docs/adr/0008`.
- logseq really had no data: 0 entries under `graphs/`, `config.edn` is `{}`,
  `preferences.json` is all nulls, no `journals/` anywhere under `$HOME`. Opened
  once on 2026-07-23, never used.

**Verified against the built closure instead of waiting for a switch** — same
evidence, sooner: `electron-39` and `logseq` are both absent from the new
`toplevel`, `electron-40` is still there because winboat still needs it.

The replacement comment carries the rule instead of the history: name the
consumer beside each entry, drop the entry when that package goes, and use
`nix-store --query --referrers` to check. Three lines of rule replacing nine of
narration, and the nine were wrong.

---

## 2026-08-20 · One owner per package, asserted as divergence

Plan item 5 (§5b). `distrobox` dropped from `packages.nix`, keeping
`virtualisation.nix`'s — it is a user application by the first rule, but it does
nothing without the podman that module enables, so both should be removable at
once. The rule now lives in `packages.nix`'s header, where it was missing.

### The assertion is on divergence, not duplication

Both package lists resolve at eval, so `flake.nix` passes `packages.json` —
name → store path for each — the way `schemes.json` already went. The check
flags a name in **both** lists whose paths **differ**.

That is the design. The naive intersection is 20 names, because
`environment.systemPackages` is 240 entries of which most are NixOS module
defaults rather than this repo's doing. 19 of the 20 are byte-identical, so
flagging all of them would be noise nobody reads.

The exception is `bind`: the system carries the `host` output as a NixOS
default, `packages.nix` declares `dnsutils` for `dig`. Different outputs of one
derivation, so PATH order decides which `host` you get. Real, understood, and
not ours to fix. Recorded in `PKG_EXCEPTIONS` with its reason, in the shape
`statix.toml` uses, and **matched on the name with the version stripped** so a
version bump cannot quietly retire the exemption.

### Verified against two planted defects, one per failure mode

- **Divergence**: `jq` overridden on the home side only — the check names
  `jq-1.8.2` and prints both store paths.
- **The scan breaking**: the jq expression's `.system` key renamed — `only 0
  packages in both lists — the scan is broken, not the repo`. The floor is 10,
  well under today's 20, because the intersection is mostly NixOS defaults and
  does not shrink on its own.

The gate is now **117 assertions across 15 sections**.

---

## 2026-08-20 · `nvd` in the rebuild path, and unfree by name

Plan item 6 — §5f and §5a, one commit.

### 5f — and the command the plan specified was wrong

`nvd` moved from the devShell to `packages.nix`, because an alias calling a
devShell-only binary from an ordinary shell exits 127 silently.

**The plan said to extend all three aliases with
`nvd diff /run/current-system /nix/var/nix/profiles/system`. That is wrong for
`rebuild`.** `switch` activates, so after it those two paths are the **same**
store path — measured on this machine, they are identical — and the diff prints
nothing every time. A command added to show what changed would have shown
nothing exactly when something did.

So the two aliases take different arguments: `rebuild` captures
`prev=$(readlink -f /run/current-system)` before switching; `rebuild-boot` keeps
the plain form, because `boot` does not activate and there the two differ.
`rebuild-test` stays bare — no profile generation, nothing to diff.

`$(…)` and `"$prev"` survive a Nix `''…''` string untouched; only `${` is
interpolation. Confirmed by reading the evaluated alias rather than assuming.

### 5a — the predicate, and six names nobody would have guessed

`allowUnfree = true` became `allowUnfreePredicate` over 22 names. Sixteen were
readable off the two package lists. **Six were only findable by setting the
predicate and rebuilding until it went green:**

- `corefonts` — steam's `programs.steam.fontPackages`.
- `broadcom-bt-firmware`, `b43-firmware`, `xone-dongle-firmware`,
  `facetimehd-calibration`, `facetimehd-firmware` — all from
  `hardware.enableAllFirmware` in `boot.nix:56`, and all for hardware this
  ThinkPad does not have.

They are listed rather than worked around, so the predicate records what is
actually permitted. That the firmware is unfree *and* useless here is a separate
question, untouched — but visible now, which it was not under a blanket `true`.
That is the argument for the change.

**Verified**: adding `discord` fails with `Refusing to evaluate package
'discord-1.0.153' … because it has an unfree license`.

---

## 2026-08-20 · The shell is formatted, and `nix fmt` finally means both languages

Plan item 7 (§5e). 33 files, 1,998 lines of churn, **194 surviving
`git diff -w` in 9 files** — every one read, every one line structure:
`;`-splitting, brace-group splitting, and leading-`\ |` → trailing-`|`
continuation style. No semantics moved.

### Measure the residue with `git diff -w`, not `git diff -w -B`

`-B` marks whole-file rewrites and re-reports every line of them. The same tree
reads as **194 lines in 9 files** under `-w`, and **741 in 13** under `-w -B`,
which overstates the semantic residue about fourfold. The plan recommended `-B`
in three places; all three are corrected.

### Neither exclusion the plan budgeted for was needed

- **`fan-calibrate` was fixed rather than excluded.** shfmt parses `cpu[0-9]*`
  inside an array literal as an associative-array key. Replacing
  `CPUS=(<glob>)` with `CPUS=()` plus a `for` loop over the same glob parses,
  and keeps the glob **exact** — the tempting `cpu*` also matches a future
  `cpuidle/cpufreq`. Verified to resolve the same 12 paths.
- **`menus/shell.sh` took the expansion.** 16 aligned `case` arms became 80
  lines. No file carries an exclusion, so the formatter has no standing
  asterisk.

### Two scans broke, and not for the reason the plan gave

The plan predicted `static.sh:397` would break because *shfmt indents case
arms*. It does not — arms stay at column 0. What broke both scans was the
`;`-splitting moving `ipc=` onto the **next line**. And there were two: the
IPC-pair scan at `:761` read `ipc=` off that same line.

Both failed loudly on their floors instead of passing empty, which is why it was
a five-minute fix. The action scan is now `awk` keyed on the arm label; the IPC
scan anchors on `ipc=` alone, which is all it ever wanted.

### The duplicate-bind scan counted the wrong thing

Not part of 5e, but the same class, and the plan flagged it under §3a:
`binds_seen` incremented **per mode**, not per bind. So if the `source=./`
spelling it matches ever changed, `srcs` would come back empty, the inner loop
would do nothing, and the counter would still reach 2 — printing `ok` for a scan
that had read almost nothing.

Now floored on **binds**. Confirmed by changing the spelling to `include=`: the
scan drops from **232 binds to 2** and fails, where before it passed.

### The gate

`shfmt -d` runs over the same shebang scan the shellcheck check already builds —
one scan, one floor, rather than a second derivation with a second copy of both.
The formatter grew a shell pass, so **`nix fmt` is now a no-op across Nix and
shell**, verified by running it twice and comparing the diff line count. Files
are selected by **shebang, not extension**: half of `dotfiles/scripts/` has no
extension. Verified against a planted mis-indent — the check names the file and
prints the diff.

---

## 2026-08-20 · The comment pass, and eight stale counts it found instead

Plan item 8 (§5d), the last of the eight. **195 comment lines removed, 73
added — net −122** across the five named files. Every cut was checked against
the ADRs, `gotchas.md` and `SYSTEM.md` first; every one was already argued
there, several twice:

| Cut | Where it already lived |
|---|---|
| `programs.nix`'s 44-line header | `docs/SYSTEM.md` §6 *and* `CLAUDE.md`, in fuller form — a **third** copy |
| wlogout icon paths, 22 lines | `docs/gotchas.md` → Desktop |
| lock-ramp `checkPhase`, 28 lines | `docs/adr/0029`, `docs/adr/0032` *and* `gotchas.md` |
| `waybar.nix` header + position variants | `docs/adr/0009`, `docs/adr/0028`, `SYSTEM.md` §6 |
| `power.nix` TLP bounds + the systemd cycle | `gotchas.md` → Power, which has the journal output |

### The `on Arch` / `your` grep found nothing

The plan said to grep for `on Arch` and `your` first, "that is where the wrong
ones are". Two hits, both legitimate. The 2026-08-12 pass had already taken that
class.

**What this pass found instead is harder to spot, because it reads as current.**
Eight stale counts, all from hud's removal (`docs/adr/0035`) and the scheme set
settling at four:

- "this key works in **all three modes**" — two.
- "unlike **the other two modes**" (noctalia.conf), "**the other two** take
  `surface`" (dotfiles.nix) — one other, in both cases.
- "correct for **three of the five schemes**" (static.sh), "a Papirus recolour
  for **three of the five**" (pkgs/default.nix) — four schemes, and two in both
  cases, not three.
- "one of **three actions** with `fb=none`" — there are three, but the sentence
  had drifted anyway.
- `SYSTEM.md` claimed **four waybar layouts in three places**. There are three
  (×2 positions = 6 files).
- Two theme files said the plugin's Mocha values are right "because **this
  machine IS Mocha**". This machine is gruvbox. It is the *theme* that is Mocha.

That is documentation stating something untrue, which is the same problem as a
check that passes by finding nothing. Every one was fixed by **counting** — `ls
modules/home/themes/`, the layout attrs, `grep -c 'fb=none'` — not by reading.

⚠️ **`SYSTEM.md`'s mango row was stale from earlier the same day**: it still
said the mode scripts "genuinely need to `cp` into `config.conf`".
`docs/adr/0040` had made that a link six hours earlier.

### A correction to the verification instrument

Both `drvPath`s are unchanged for every `.nix` edit — bisected, not assumed.
But three of the stale-count fixes were in **`dotfiles/` files, which are store
content**: a comment there is part of the build input and legitimately moves the
hash. The first run showed both hashes moving and looked like a failed comment
pass; stashing `dotfiles/` and re-running showed the Nix side clean.

**The `drvPath` test proves a no-op for Nix comments only.** The plan now says
so.

### Phase 5 and the plan

All eight items in *Suggested order* are done. `nix flake check` is **117
assertions across 15 sections**, and the definition of done is met except for
one line that never had evidence: *a fresh clone plus the age key reproduces a
working machine*. That needs a VM, not a commit, and it is now marked as the one
open item.

---

## 2026-08-20 · Prose pass, and the live checks after the rebuild

No behaviour change.

**The comments and docs written today used rhetorical phrasing where a plain
statement was shorter** — "is the check nobody reads", "not a thing somebody
silenced", "indistinguishable from", "and that is the point", "The conclusion
survives; the evidence didn't". Rewritten to say what happens, across nine code
comments, both new ADRs and these work-log entries. Henry asked for this
directly; it applies to future writing here too.

**Live verification, which needed the rebuild:** `config.conf` was still the
pre-migration regular file, as `docs/adr/0040` predicted — converted by hand
after checking it was byte-identical to `tiling/tiling.conf`. `readlink` now
names the mode, `mango -p` is clean, `reload.sh` returns `{"success":true}`.
`nvd` resolves in a login shell. `electron-39` and `logseq` are absent from
`/run/current-system`, `electron-40` is present for winboat.
`./verify-claims.sh`: 2 passed, 0 failed.

**Five more stale mode counts**, this time in `SYSTEM.md` and `gotchas.md` —
yesterday's pass only fixed the ones in code. The ADRs keep theirs: those counts
were true when the ADRs were written, and `docs/adr/0035` records the change.

---

## 2026-08-20 · The active window border was off in tiling mode

`dotfiles/mango/tiling/tiling.conf` carried `no_border_when_single=1`. On mango
0.16.0 that removes the border from **every** tiled window, not only a lone one.
noctalia mode has always set it to `0`, so the symptom read as mode-specific.

`check_hit_no_border()` (`src/fetch/client.h`) tests
`ISSCROLLTILED(c) && visible_scroll_tiling_clients == 1`, and `ISSCROLLTILED` is
not a scroller-layout test — it is `!floating && !minimized && !killing &&
!unglobal`, true of ordinary `tile` windows. With three windows visible the
counter still read 1. Floating windows kept their borders, which is what
separated the two arms of that condition.

**Measured, because `mmsg get` does not expose `bw`:** `grim` plus a pixel dump
counting the theme's `focuscolor` and `bordercolor` below the bar. Same three
windows, `borderpx=1` — `no_border_when_single=0` gives 11,190 border-coloured
pixels, `=1` gives none.

A nested instance (`XDG_CONFIG_HOME=… WLR_BACKENDS=wayland mango`) sourcing the
same `universal/*.conf` drew borders correctly, so it cleared the config but did
not reproduce the bug. What found it was re-pointing `config.conf` at a scratch
copy and reloading the running compositor. Also ruled out: a stale binary,
`toggle_render_border`, per-tag `no_render_border`, and per-tag staleness — a
fresh tag with two new windows was equally borderless.

**The cost:** a single window on a tag now carries a 1px border where it used to
sit flush. That is what the option existed to prevent, and there is no way to
keep it without keeping the bug. `checks/static.sh` now fails if either mode
config sets it back to `1`.

---

## 2026-08-21 · The launcher is a rofi mode, and the ring is the accent

`SUPER+space` was `fsel`, a TUI launched as `foot -a fsel-launcher -e fsel
--detach` and floated by an appid rule. It worked; what it cost was carried for
one key. `docs/adr/0043` has the argument.

**Removed:** the package line in `modules/system/desktop.nix`, the version
override in `pkgs/default.nix` (3.6.0 over nixpkgs' 3.1.0, two hashes to
re-check on every bump), the generated `fsel/config.toml`, its row in the
palette table in `checks/static.sh`, and the `appid:fsel-launcher` window rule.

**Added:** nothing but flags.

```sh
fb_launcher() { rofi -show drun -matching fuzzy -sort -sorting-method fzf; }
```

`drun` and `run` were already in `config.rasi`'s `modes:` list and reached by
nothing — the state rofi itself was in before ADR 0021.

**The flags are on the command line on purpose.** `matching` and `sort` are
global and the nine `-dmenu` menus want rofi's defaults. Verified with
`rofi -matching fuzzy -dump-config` that the command line wins for both; `-l`
famously does not, which is why this was checked rather than assumed.

**Two things the swap surfaced that were not asked for.**

- The **mode switcher** had no rule in `config.rasi`. `-dmenu` is single-mode,
  so no window here had ever drawn one; `-show drun` draws four tabs. Styled
  flat, selected tab underlined rather than blocked — `selected-normal-background`
  is already an accent block and two of those in one window compete.
- **Icons stay off.** drun with `show-icons: true` resolves the icon *set*,
  which is a `native = false` stand-in on `heartbox` and falls back silently
  (`docs/adr/0041`).

**The border is `@accent`,** replacing the achromatic `@subtext` chosen when
rofi drew menus only. The same surface is the launcher now, and `@accent` is
mango's `focuscolor` — one ring, drawn by whichever of the two is in front.
Measured against `@base` across every scheme in service: heartbox 3.87:1,
gruvbox 5.94:1, nord 5.99:1, mocha 8.07:1, mocha-high-contrast 9.23:1.

**The cost:** pinning is gone — `pin_color`, `pin_icon` and `pinned_order` have
no rofi equivalent, and rofi's own drun history covers only the frecency half.
The pins were unused, which is the whole of why this is affordable. The sidebar
geometry goes too: 420×1000 at x=98, against rofi's centred 40em.

`nix flake check` passes, including the rofi-mode scan — which reads
`-show <mode>` out of the mango tree and asserts rofi loads it, so the new bind
was gated by an assertion that already existed. **Not yet rebuilt**; the theme
was verified with `rofi -no-config -theme … -dump-theme` against a copy, which
parses and leaves no `var(lightbg)`-style built-in unresolved.

---

## 2026-08-21 · The weather module grew a forecast, and a way out of the tooltip

**One request now carries everything the tooltip shows.** `fetch()` asks
open-meteo for 19 fields at `forecast_days=5` instead of 8 at 1 — wind
direction, mean-sea-level pressure, sunrise/sunset, UV index, daily rain
probability, and hourly temperature, rain probability, code and daylight. The
response went from about 1 KB to 5.3 KB, on the same host at the same cadence,
so nothing new learns where this machine is.

The tooltip reads: now and feels-like, today's range with its rain chance,
humidity, UV with its WHO band, wind with the compass point it comes from,
pressure with a trend, sunrise/sunset with the day's length, then the next four
three-hourly steps and the next four days. Both blocks are byte-padded, which
aligns exactly — every value in a column carries the same number of multi-byte
characters, so constant bytes is constant width — and they call `icon_for`, so
the thirteen-glyph WMO ladder still has one owner.

**The pressure trend is the one fact a single response cannot carry**, so the
cache stopped being the response verbatim: it holds `.history`, six hours of
`{t, p}` samples pruned on write. `render()` compares against a sample aged 2–4
hours and **claims no trend when it has none** — a delta measured over the
fifteen minutes since the last poll is noise wearing an arrow. Four branches,
all exercised against doctored caches: falling 1.8 in 3h 1min, rising 2.3 in
2h 38min, `steady` under 1 hPa, and silence at 40 minutes' separation.

**A fourth verb, `open`.** Right-click on the bar module; second entry on the
control-centre row, which is a picker now (Refresh now / Open forecast) rather
than a bare refresh. The page is `local.location.forecastUrl`, generated into
`weather-location.env` beside the coordinates, defaulting to
`weather.com/weather/today/l/<lat>,<lon>` — which resolves to that site's city
page, and is a **second host learning the location**, reached once per click
rather than four times an hour. That trade is why it is an option: open-meteo's
own docs page tells nobody new and is one line away. `setsid -f`, because both
callers wait and `xdg-open` waits on the browser when none is running.

**Three assertions, each mutation-tested.**

| Assertion | Mutation | What it caught |
|---|---|---|
| the query and the tooltip name the same fields, per block, both ways | dropped `pressure_msl` from the URL | `current.pressure_msl is read out of the cache and never asked for` |
| every verb the bar or the control centre passes is implemented | deleted the `open)` branch | `weather.sh is called with a verb it does not implement: open` |
| the https handler resolves to an installed `.desktop` | `zen.desktop` for `zen-beta.desktop` | `mimeapps.list hands https to zen.desktop and nothing installs it` |

The third is the one worth having: it is exactly the failure `universal/bind.conf`
records, where the mime association pointed at a nonexistent `zen.desktop` and
`SUPER+b` silently opened chromium for a month. `weather.sh open` goes through
that same association, so the gate now covers it.

`render()` costs 30 ms against the old 10 ms. The control-centre render costs
its slowest row and this is still not it — 73 ms, measured when that menu was
built.

**Unrelated, in the same pass: menu search is explicitly case-insensitive.**
`case-sensitive: false` in `config.rasi` and `-i` in `lib.sh`'s `rofi_menu`.
Both were already rofi's default, so this pins it rather than changes it — the
file is what actually decides on rofi 2.0, and `kb-toggle-case-sensitivity` (the
backtick) can flip it from inside a running menu.

**Not rebuilt yet.** `nix flake check` passes; everything under `dotfiles/` is a
store path, so the new verb and the widened query need a `rebuild` before the
bar or the control centre sees them.
