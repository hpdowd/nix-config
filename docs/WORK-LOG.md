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
nothing unique), the GitHub remotes removed, `home/fish/` dropped (the shell is
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

## Structural change — flattening `home/mango/`

The nesting existed because the config tree doubled as the **backup** unit: only
directories worth keeping lived under `mango/`. Once everything became
declarative and tracked, that rationale expired, and what remained was a cost —
neither app sat at the XDG path it looks in by default, so **eight** call sites
had to name the config explicitly.

```
home/mango/wlogout/  →  home/wlogout/     (7 files)
home/mango/swaync/   →  home/swaync/      (1 file)
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
