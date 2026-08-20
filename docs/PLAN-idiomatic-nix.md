# Plan — what is left to make `nix-config` maintainable

**Live working file.** Everything decided here has been promoted to
`docs/adr/`; what stays is what has not been decided, or not been done. Delete
it when it empties.

Rewritten **2026-08-20** against `main` @ `53783bf`, replacing the 2026-08-03
version. The five closed phases are a ledger now rather than five
retrospectives — each has an ADR, and a second copy of an argument is two
copies that drift (`CLAUDE.md` → Write it short). Every number below was
measured today, not carried forward.

**Starting work: go to *Suggested order* at the bottom, then read that item's
section.** Every outstanding item carries **Steps** and **Verify**. The `file:line`
references were accurate on 2026-08-20 and the first edit will move some of
them; the surrounding quote is the durable half.

---

## The ledger

| Phase | Closed | Record |
|---|---|---|
| **0** — a gate for Nix | 2026-08-03 | `docs/adr/0010` |
| **0.5** — a gate for shell | 2026-08-03 | `docs/adr/0011` |
| **1** — secrets in sops | 2026-08-06 | `docs/adr/0012` |
| **2** — NetworkManager profiles declared | 2026-08-09 | `docs/adr/0013` |
| **4** — the dead-code class | 2026-08-09 | `docs/adr/0014` |
| **6** — the gate catches itself | 2026-08-20 | `docs/adr/0039` |
| **3** — the desktop layer | 2026-08-20 | `docs/adr/0040`, §3 below |
| **5** — idiomatic cleanups | 🔶 partly | §5 below |

**What the gate is today.** `nix flake check` runs six checks: the system
closure, the home closure, statix, deadnix, shellcheck over 43 tracked scripts,
and `checks/static.sh` — **115 assertions across 14 sections, 0 failing**. It
was 19 assertions when Phase 4 closed. Two live checks that need a running
compositor stay in `./verify-claims.sh` (69 lines).

## The framing, corrected

The 2026-08-03 version named four gaps. Three closed. The fourth has not — the
absolute burden is up by half:

| | Then (2026-08-03) | Now | |
|---|---|---|---|
| `.nix` comment lines | 1,436 | **2,222** | +55% |
| `.nix` code lines (blanks and comments excluded) | 2,245 | **3,681** | +64%, so the *ratio* fell 0.64 → **0.60** |
| `.nix` files over 1:2 | "nine" | **20 of 31** | |
| shell under `dotfiles/` | 2,160 in 40 files | **3,291 in 41** | |
| `checks/static.sh` | — | **2,402 lines** | the gate is now the second-largest body of shell in the repo |

⚠️ **The 2026-08-20 rewrite of this table read "ratio 0.56 → 0.60" and called
that a widening. It was neither.** 0.56 counted comments against
`total − comments`; 0.60 counted them against code with blanks removed — two
denominators, one arrow, and the sign came out backwards. Measured the same way
on both sides the ratio *fell*, under either convention (0.56 → 0.53, or
0.64 → 0.60). Comments grew slightly slower than the code they sit in. What is
true is the absolute number: 786 more comment lines than the pass that was
supposed to remove them. Re-measure with the loop in *How to verify* below;
do not carry these forward.

Two conclusions follow, and they are the shape of what is left:

- **Phase 5d is not converging, and the ratio is the wrong instrument.**
  `palette.nix` is 50 comment lines over 1 line of code and is correct as it
  stands; `programs.nix` is 262 over 337 and is not. Judge on absolute comment
  count and on whether a line earns itself. See §5d.
- **The gate has become the thing most worth getting right.** It is what
  catches everything else, and nothing catches it except shellcheck and its own
  floors. Every new assertion below is specified to fail on a planted defect
  before it counts as landed.

  ✅ It now catches its own size too — Phase 6, closed 2026-08-20,
  `docs/adr/0039`. It still cannot catch a section that runs and asserts
  something vacuous, which is why the planted-defect rule above is the part
  that has to be kept by hand.

Phase numbers below are historical, not an order. The order is at the bottom.

## Deliberately NOT in this plan

Stated so they don't get reintroduced as improvements:

- **No `mkEnableOption` toggles on `modules/system/*`** — speculative
  generality for a single machine.
- **No `lib/mkHost`, no `flake-parts`.** Same reason. Add the abstraction the
  day a second host appears.
- **No splitting `packages.nix`.** 254 categorised lines is readable.
- **No converting `nvim`, `mango`, `swaync` or the waybar CSS to generated
  config.** Reasons in `docs/SYSTEM.md` §6 and `docs/adr/0009`.
- **No re-enabling statix's `repeated_keys`.** `statix.toml` says why; it fires
  69 times against standard NixOS module style.
- **No splitting `checks/static.sh`**, at 2,402 lines. A section in its own file
  is a section that can stop being sourced, and a check that stops running is
  indistinguishable from one that passes. Phase 6 is the answer instead.
- **No adopting `nh`.** A wrapper in the critical path of every rebuild is a
  thing you debug during a rebuild. §5f.

---

# Phase 3 — the desktop layer ✅ CLOSED 2026-08-20

Governing principle, unchanged: **push variation to build time; let runtime
only *select*.** Done 2026-08-03 (`2f45486`): waybar position became a file
selection, state paths and defaults moved into `scripts/lib.sh`, 765 lines of
unreachable presentation code deleted. Done 2026-08-20: the menu scripts source
`lib.sh`, and no script under `scripts/` re-derives `MANGO_DIR` or `STATE_DIR`.

## 3a — mango config selection ✅ DONE 2026-08-20

`lib.sh:171` is the **only** runtime write into `~/.config/mango`:

```sh
install -m 644 "$MANGO_DIR/$mode/$mode.conf" "$MANGO_DIR/config.conf"
```

so `config.conf` is a verbatim copy of whichever mode is active — the one file
in the tree that git must not track, that no `xdg.configFile` may claim, and
that carries the `install -m 644` scar from the day `cp` inherited a store
path's 0444 and every switch after the first died with `Permission denied`.

**Decision: make it a link, not a copy.**

```sh
ln -sfn "$MANGO_DIR/$mode/$mode.conf" "$MANGO_DIR/config.conf"
```

mango is still launched with no `-c`, so `cli_config_path` stays empty and every
`./` in the tree still resolves against `$HOME/.config/mango/`
(`parse_config.h:3276`). That buys the whole benefit and pays none of the cost:

- **No `source=` rewrite.** There are **20** `source=` lines across three files
  — `tiling.conf` 9, `noctalia.conf` 10, and one nested in
  `universal/settings.conf:83` that a rewrite of "the mode configs" would miss.
- **No session-startup change**, so this stops being logout-only and becomes
  validatable in-session. That alone changes the risk class.
- `config.conf` joins the family `apply_theme` already defines — a link path
  owned by `apply_theme` and by nothing else — and gets the same assertion the
  other four have: absent from the generation.
- **Seed it at activation**, exactly as `mode-theme.nix:172` seeds the four
  theme links. That closes the fresh-machine hole rather than preserving it:
  today, with no `config.conf`, mango falls back to `$SYSCONFDIR/mango/config.conf`,
  which does not exist here, and starts on built-in defaults with no keybinds.

**`recursive = true` stays, and that is the correction to the old plan.** It was
listed as the last writability exemption to be removed. It is not only that: it
is the mechanism that lets **12 generated files** live in the tree — five in
`dotfiles.nix:321-365` (both `colors-<mode>.conf`, `weather-location.env`,
`cursor.conf`, `settings-pinned.json`) and seven from `waybar.nix:626-643`,
whose own comment at `waybar.nix:618` says so. Removing the *writer* is the
whole win; removing the *flag* costs a twelve-file rehoming and buys
bookkeeping. It fails loudly at `nix flake check` if attempted anyway.

**Not chosen, and why.** mango has a `load_config_file` dispatch
(`bind_define.h:2284`, `docs/bindings/keys.md:187`) reachable over IPC —
`parse_func_name` is the same table the binds use (`ipc.h:410`). So
`mmsg dispatch load_config_file,$MANGO_DIR/$mode/$mode.conf` plus `mango -c` at
login removes `config.conf` entirely, which is the purest form of the governing
principle. It pays: the 20-line `source=` rewrite (relative paths resolve
against `dirname(cli_config_path)`, so they break *because* the file moves); a
fourth spelling of the state path inside a system module (`desktop.nix:20`),
crossing the boundary `lib.sh` exists to guard; a silently disarmed check
(below); and it stays logout-only. Revisit if `config.conf` ever has to leave
`~/.config/mango` for some other reason. Verify the file exists before
dispatching — `reload_config` calls `set_value_default()` before parsing, so a
path mango cannot open leaves the session on stock defaults.

⚠️ **That dispatch was traced through the source, never fired.** Sending it into
the running session would have re-pointed `cli_config_path` for the rest of that
session, changing how every later reload resolves `./`. If B is ever picked,
that is the first thing to test — in a nested instance with its own `HOME`, not
here.

⚠️ **`checks/static.sh:363` is disarmed by any `source=` rewrite.** It reads the
sourced files with `sed -n 's|^source=\./||p'` to build the per-mode bind set.
Change the spelling and `srcs` goes empty, the inner loop does nothing, and
`binds_seen` still increments per mode — so the duplicate-bind scan drops from
**117 binds to 1** and prints `ok`. That is the Phase 4 class inside the gate
itself. `checks/static.sh:1476` keys off the same literal but fails loudly.
Whichever design lands, give `363` a floor on binds seen, not on modes seen.

**Landed** as `docs/adr/0040`. All five steps, with two additions the plan did
not call for:

- **A guard, because the swap loses a failure signal.** `ln -sfn` to a missing
  target *succeeds* where `install` failed loudly, so `apply_mode` now checks
  `[ -s <mode>.conf ]` first — and does it **before `state_write`**, since
  recording a mode that was not applied is the one-way switch `lib.sh`'s header
  exists to foreclose.
- **A second assertion, on the link itself.** Absence from the generation is not
  enough: a revert to `install`/`cp` would *work*, and would quietly
  reintroduce staleness. `checks/static.sh` now asserts the `ln -sfn` is there.

Step 2 went in as its own `seedModeConfig` block rather than inside
`dotfiles.nix:603` — that block is `unlinkStaleConfigDirs`, an
`entryBefore [ "checkLinkTargets" ]`, which is the wrong phase. It mirrors
`mode-theme.nix`'s `seedModeTheme` instead, and the built `activate` script
orders them `linkGeneration` → `seedModeConfig` → `seedModeTheme`.

**The fresh-machine claim was re-checked rather than trusted, and it holds.**
`SYSCONFDIR` is `/etc`, and `/etc/mango/config.conf` does not exist on NixOS —
the package ships its default under `$out/etc/`, which never lands there. Probed:
`HOME=$empty mango -p` exits 1 with `Failed to open config file:
/etc/mango/config.conf`.

**Verified offline** in a fake `HOME`, all five paths: seed points at `tiling`;
switching to `noctalia` and back re-points the link and moves state; a mode with
no conf returns 1 leaving **both the link and the state untouched**; and mango
parses through the symlink with no diagnostics.

⚠️ **Migration is lazy, by design.** `[ -e ]` follows symlinks and finds the
existing *regular file*, so a rebuild leaves it a copy until the next mode
switch re-points it. Harmless — the stale copy is a valid config — but
`readlink` returns nothing until then.

**Verify** — in-session, which is the point of choosing this design:
`readlink ~/.config/mango/config.conf` names the mode before and after a switch;
`~/.config/mango/scripts/reload.sh` returns `{"success":true}`; a keybind from
`universal/bind.conf` still fires, proving the sources resolved.

## 3b — `mango -p` as a check ✅ DONE 2026-08-20

Two findings, verified against 0.16.0 by probe, not by reading:

1. **Flag order decides what gets validated.** `getopt` returns on `-p`
   mid-parse (`mango.c:7797`), so `mango -p -c FILE` validates the live
   `~/.config/mango/config.conf` and exits 0 having never seen `FILE`.
   `mango -c FILE -p` is the working form. A validator that reports success
   while checking a different file is this repo's signature bug with a CLI flag
   on it.
2. **`-p` exits 1 for an unknown keyword and 0 for an unresolvable `source=`** —
   the return value is discarded at `parse_config.h:3248`. It *does* print
   `[ERROR]: Failed to open config file: …` to stderr, so the comments in
   `tiling.conf` and `noctalia.conf` calling this silent are half wrong: under
   `systemd-cat` it lands in `journalctl -t mango`.

⚠️ **Do not reach for `-c` to point at a mode conf.** Relative sources resolve
against `dirname(cli_config_path)`, so `mango -c …/mango/tiling/tiling.conf -p`
looks for `…/mango/tiling/universal/…` and reports **all 20 `source=` lines as
missing**. Twenty failures on day one is the check you learn to ignore, and the
natural fix is to relax it into uselessness.

**Use a fake `HOME` and no `-c` at all**, which reproduces production exactly
and sidesteps the flag-order trap because there is no flag to order.

**Landed** as the *Mango config parse* section of `checks/static.sh`: the mango
tree is copied out of the built home closure into a fake `HOME`
(`cp -r --no-preserve=mode`), each mode's conf is installed as `config.conf`,
and `mango -p` runs with no `-c`. It fails on any stderr, and floors on modes
parsed.

**Step 1 of the plan was not needed, and skipping it is the better shape.**
`pkgs.mango` did not go into `nativeBuildInputs`: mango is already in the system
profile, so the check reads `$SYS/sw/bin/mango`, exactly as the rofi check reads
`$SYS/sw/bin/rofi`. That adds no dependency edge at all *and* validates the
binary that will actually run rather than one the check happened to pull in.

**Verified against both planted defects**, which is the only reason it counts as
landed:

| Defect | mango | check |
|---|---|---|
| `universal/tag.conf` renamed | stderr, **exit 0** | ✗ names both modes |
| `notakey=1` in `tiling.conf` | stderr, exit 1 | ✗ names the file and line |

⚠️ **The read-only store bit twice here, in two different places** — and 3a
then removed one of them:

| Guard | Without it | Fails on |
|---|---|---|
| `cp -r --no-preserve=mode` | the copied **directory** is 0555, so nothing can be created in it | the **first** mode |
| ~~`install -m 644` (not `cp`)~~ | ~~the tree is symlinks *into* the store, so a plain `cp` inherits **0444**~~ | ~~the **second** mode~~ |

The second was the scar `lib.sh` carried, reproduced from scratch inside the
check. It is gone: once 3a made production's `config.conf` a symlink, the check
stages a symlink too — which is both simpler and a faithful reproduction rather
than an approximation of one. The first guard stays and is unrelated.

---

# Phase 5 — idiomatic cleanups

Independent, low-risk, do any of them alone.

### 5a — `allowUnfree` predicate

`nix-settings.nix:50` sets `allowUnfree = true`, permitting *any* unfree package
including one pulled in transitively. Replace with a predicate naming the ones
actually accepted. Converts a future surprise into a build error.

**Steps**: swap for `allowUnfreePredicate = p: builtins.elem (lib.getName p) [ … ]`,
build, and add whatever the build names until it goes green. **Budget for
steam** — nixpkgs splits it across `steam`, `steam-unwrapped` and `steam-run`,
so the list is longer than the app list and the first failure arrives
mid-rebuild rather than mid-edit.

**Verify**: `nix flake check` green, and a deliberately added unfree package
fails the build naming itself.

### 5b — one owner per package ✅ DONE 2026-08-20

`distrobox` is declared twice — `environment.systemPackages`
(`virtualisation.nix:32`) *and* `home.packages` (`packages.nix:213`). **Measured
before claiming: both resolve to the same store path**, so PATH order changes
nothing today. It is a rule violation with latent risk — the day one side is
overridden or pinned, the split becomes silent — not a live bug. No
restructuring; fix that one, then record the rule in `packages.nix`, where it is
still missing:

> A package is installed by **exactly one** of: its `programs.*` module, a
> `home.packages` entry, or `environment.systemPackages`. User applications go
> in home; things needed before login or by a system unit go in system — **and
> a tool that is inert without a system service lives with that service.**

That last clause is what decides `distrobox`: it is a user application by the
first rule, but it is useless without the podman `virtualisation.nix` enables,
and the two should be removable together. **Drop the `packages.nix:213` entry,
keep `virtualisation.nix:32`.**

**Write the assertion, not the rule** — but not the obvious one. Both lists are
readable at eval, and the naive intersection is **21 names**, because
`environment.systemPackages` is 240 entries of which most are NixOS module
defaults, not this repo's. Twenty-one findings on day one is the check nobody
reads.

**Assert divergence, not duplication:** flag a name in both lists whose
**store paths differ**. Measured today that is exactly one — `bind`, where the
system carries the `host` output as a NixOS default and `packages.nix:120`
declares `dnsutils` for `dig`. Real (which `host` you get is PATH order) and not
this repo's doing, so it is an exception with a reason next to it, in the shape
`statix.toml` already uses. Everything else, `distrobox` included, is
byte-identical and correctly ignored.

**Landed** as the *Package ownership* section. `packages.json` is passed to
`static.sh` the way `schemes.json` already was — both name→outPath maps,
resolved by Nix, so ownership is answered at eval rather than by grepping two
files. `PKG_EXCEPTIONS` carries `bind` with its reason, matched on the name with
the version stripped so a version bump cannot silently retire the exemption.

The intersection is **20** now, not 21: dropping `distrobox` from
`home.packages` removed one. 19 resolve identically, `bind` is the exception.

**Verified against two planted defects**, one per failure mode:

| Defect | Result |
|---|---|
| `jq` overridden on the home side only | ✗ names `jq-1.8.2` with **both** store paths |
| the jq expression's `.system` key renamed | ✗ `only 0 packages in both lists — the scan is broken, not the repo` |

The rule itself now lives in `packages.nix`'s header, where it was missing.

### 5c — overlay and pin hygiene ✅ DONE 2026-08-20

Two of the three are now answered:

- **`fsel` — settled, not open.** nixpkgs is still 3.1.0 at this pin and the
  override still builds 3.6.0, which is what our `config.toml` is written for.
  The old note quoted a "delete this block if 3.1.0 is fine" comment that no
  longer exists. Nothing to do until nixpkgs catches up.
- **`nixos-hardware` — the module exists.** `lenovo-thinkpad-l14-amd` is real,
  and this machine is a ThinkPad L14 Gen 5 / Ryzen 5 Pro 7535U. It is a superset
  of the four modules `flake.nix:66-69` already import, plus exactly two kernel
  params: `acpi_backlight=native` (so the backlight save/restore unit works) and
  `iommu=soft`. **Adopting it is a real decision, not a free upgrade** —
  upstream's own comment says the IOMMU problem was fixed in BIOS 1.13 and the
  param is kept defensively for people below that; this machine is on 1.21. It
  is *not* established that this touches the amdgpu/TTM freeze `boot.nix`
  documents — that oops leaks `lru_lock`, which is a different failure from
  "the driver cannot attach".
  **Decided 2026-08-20: leave it.** `systemd-backlight@` is `active (exited)`
  with no failed units, so `acpi_backlight=native` fixes nothing observable
  here, and that leaves `iommu=soft` — SWIOTLB bounce buffers — as the whole of
  what adoption would change, on the one machine whose defining bug is an
  amdgpu deadlock that cannot be reproduced on demand. Revisit only if backlight
  restore or GPU behaviour regresses.
  ⚠️ If it is ever revisited: `boot.kernelParams` is the one case where
  `rebuild-test` is exactly wrong — it writes no boot entry, so test-then-reboot
  silently lands back on the previous generation. Use `switch` or `boot`
  (`CLAUDE.md`).
- **`permittedInsecurePackages`** — `nix-settings.nix:56`, two entries, and the
  comment is wrong about both. `electron-39.8.10` is logseq's, and **logseq has
  no data**: `~/.logseq/graphs/` is empty, `preferences.json` is stock, and there
  is no `journals/` anywhere under `$HOME`. It was opened once and never used, so
  dropping it and the entry costs nothing. `electron-40.10.5` is **winboat's**,
  not the "Arch install carrying electron40-bin" the comment claims — keep the
  entry, name the real consumer. The block is also **the best surviving example
  of the 5d class**: present-tense second-person Arch narration on a machine
  where Arch has been gone since ADR 0008.

  **✅ DONE 2026-08-20.** Both claims re-checked by `--referrers` rather than
  inherited: `electron-39.8.10` had exactly one consumer (`logseq-0.10.15`) and
  `electron-40.10.5` exactly one (`winboat-0.9.0`) — nothing Arch-shaped in
  either. logseq's emptiness re-checked too: 0 graphs, `config.edn` is `{}`,
  `preferences.json` all nulls, no `journals/` anywhere.

  Verified against the **built** closure rather than waiting for a switch, which
  is the same evidence sooner: `electron-39` and `logseq` are both absent from
  the new `toplevel`, and `electron-40` is still there because winboat still
  needs it.

### 5d — comments → ADRs 🔶 MOSTLY DONE 2026-08-12, and not holding

One pass over the six worst by ratio on 2026-08-12: **261 lines removed, 127
added**, proved a no-op by derivation path. It surfaced a class worth keeping:
**stale Arch narration in the present tense**. Grep for `on Arch` and `your`.

Since then the comment count has gone **1,436 → 2,222** while code went
2,245 → 3,681. The pass did not fail, and it did not lose ground proportionally
either — comments grew a little slower than code. It was simply outrun in
absolute terms, which is the term that costs reading. So change the instrument:

- **Target absolute comment count, not ratio.** In descending order:
  `programs.nix` 262, `pkgs/default.nix` 232, `dotfiles.nix` 231,
  `waybar.nix` 217, `power.nix` 131. Those five are 1,073 of the 2,222.
- **Ratio is meaningless below ~50 lines of code.** `palette.nix` (50 comments,
  1 line of code) and `scheme.nix` (11 / 1) are header files pointing elsewhere
  and are right as they are. Nine of the 20 "over 1:2" files are this shape.
- The theme files (`mocha` 119, `nord` 98, `gruvbox` 86,
  `mocha-high-contrast` 98) are a fifth of the total and carry per-role
  justifications that `docs/adr/0032` argues for. Leave them.

**Steps**: one pass over those five files, checking each narrative against the
ADRs, `gotchas.md` and `SYSTEM.md` before cutting — this moves text, it does not
drop it. Grep for `on Arch` and `your` first; that is where the wrong ones are.

**Verify**: the derivation-path comparison below. A comment pass that moves
either hash has changed the system and is no longer a comment pass — bisect
rather than assuming, because a comment inside `''…''` is data.

### 5e — format the shell too

Trigger condition met: 3,291 lines of shell under `dotfiles/` plus 2,402 in
`checks/`, indented inconsistently (`lib.sh` alone mixes tabs and four spaces),
with `shfmt` already in `packages.nix`. `flake.nix:202` points here.

**The churn was measured, not estimated** — `shfmt` 3.13.1 over the 45 tracked
scripts:

| | |
|---|---|
| files changed | 34 of 45 |
| lines changed | 1,979 |
| **surviving `git diff -w -B`** | **205, in 10 files** |

and every one of those 205 is line structure, not semantics: pipe-continuation
style in `static.sh`, `;`-splitting in `shell.sh`. So the pass **is** verifiable
— not by `drvPath`, which a reformat moves by design, but by `diff -w -B` plus
reading what is left. Run it **without `-s`**: simplify is the only mode that
rewrites code rather than layout, and it is the only part `diff -w` cannot
clear.

Two things must be settled before it can be gated, or the gate is red on day one:

- **`dotfiles/scripts/fan-calibrate` does not parse.**
  `CPUS=(/sys/devices/system/cpu/cpu[0-9]*/cpufreq)` — shfmt reads the glob as
  an associative-array key and errors at `23:34`. Exclude the file or restructure
  the glob.
- **`menus/shell.sh`'s dispatch table is a real loss.** Fifteen column-aligned
  one-line `case` arms become 75 lines. `-kp` does not save it (tested); the
  `;`-splitting rule is unconditional. Accept it, or exclude the one file.

And one check breaks, loudly: `static.sh:397` reads that table with
`sed -n 's/^\([a-z-]*\))…'`, anchored at column 0, and shfmt indents case arms.
It has a floor, so it fails rather than passing empty. One-line fix, in the same
commit.

**The rest of the gate's source-scraping survives**, which was the real question
— audited, not assumed. `fn_body` counts brace depth rather than matching
indentation; the `MODES=`, `rofi -dmenu` and control-centre `ROWS=` scans are
format-brittle but every one has a floor. The floor discipline already defends
this.

`treefmt-nix` is the standard way to run both formatters, but with exactly two
languages it is not required: four lines added to the `writeShellApplication`
at `flake.nix:203` do the same job with no new flake input. Take treefmt when a
third language appears.

**Steps**, in this order — formatting before gating, or the gate is red:

1. Settle the two exclusions above. **Exclude `docs/archive/` as well**, which
   the shellcheck check at `flake.nix` already does and which accounts for 26 of
   the 205 residue lines: it is history, not instructions.
2. `shfmt -w` the rest, without `-s`, in one commit that does nothing else.
3. Read the residue: `git diff -w -B`. Anything that is not line structure is a
   finding, not churn.
4. Fix `static.sh:397` in the same commit.
5. Then add the `shfmt -d` pass to the formatter and a check, and only then is
   `nix fmt` a no-op across both languages.

**Verify**: `nix flake check` green, and `git diff -w -B` on step 2's commit
shows only the residue you read.

### 5f — `nvd` in the rebuild path

On a config where "reloading without rebuilding looks exactly like the change
having had no effect" is a documented trap, seeing what actually changed is
worth it. **Wrap the `rebuild` aliases at `modules/home/shell.nix:81-83`**
rather than adopting `nh`: `nh` is a new dependency in the critical path of
every rebuild, and when it breaks you debug your rebuild tool mid-rebuild.

⚠️ `nvd` is in the **devShell only**. An alias calling it from an ordinary shell
exits 127 — silently, this repo's signature bug — so moving it into
`packages.nix` is part of the change, not a follow-up.

**Steps**: move `nvd` from the devShell list in `flake.nix` to
`modules/home/packages.nix`; extend the three aliases to
`… && nvd diff /run/current-system /nix/var/nix/profiles/system`. Leave
`rebuild-test` alone — it creates no profile generation, so there is nothing to
diff against.

**Verify**: `rebuild` on a no-op change prints an empty diff rather than
nothing at all; `command -v nvd` resolves in a login shell, not just the
devShell.

---

# Phase 6 — the gate catches itself ✅ CLOSED 2026-08-20

## 6a — a floor on `static.sh`'s own assertion count ✅ DONE 2026-08-20

`checks/static.sh` ends with `printf '%d passed, %d failed'` and then asserts
only `FAIL -eq 0`. **Delete a whole section and it prints `90 passed, 0 failed`
and exits green.** Every scan inside the file has a floor — script count ≥30,
waybar configs =8, traps ≥2, "the scan is broken, not the repo" — and the file
as a whole has none. It is the one place the discipline is not applied to
itself, and it is the place that matters most, because every other item in this
plan is verified *by* this file.

**Landed**: `ASSERTION_FLOOR` next to the summary, dated, failing when
`PASS + FAIL` drops below it. A floor, not a ratchet — adding assertions stays a
one-line change. 3b raised it 114 → **115** in the commit that added the
assertion, which is the discipline this exists to make possible.

**Verified**: with the *Fonts* section deleted the run prints `112 passed,
0 failed` and then `✗ only 112 assertions ran, floor is 115`, exiting 1. Before
the change that same deletion exited 0.

---

# How to verify — techniques, not ceremony

### Prove a refactor is a no-op

Compare derivation paths; byte-identical before and after is proof.

```sh
nix eval --raw .#nixosConfigurations.thinkpad.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage.drvPath
```

⚠️ **A comment inside `''…''` is data, not a comment.** One line in
`programs.zsh.initContent` was the only thing in the whole 5d pass that moved
the hash. Bisect rather than assuming; a ratio scan cannot tell the two apart.

### Measure the comments the same way twice

The 2026-08-20 rewrite reported a rise that was a fall, by using one denominator
for the old number and another for the new. Use this, on both sides, and name
which figure you quote:

```sh
tot=0; com=0; blank=0
for f in $(git ls-files '*.nix'); do
  tot=$((tot + $(wc -l < "$f")))
  com=$((com + $(grep -c '^[[:space:]]*#' "$f")))
  blank=$((blank + $(grep -c '^[[:space:]]*$' "$f")))
done
echo "comments $com / code $((tot - com - blank)) / total $tot"
```

`git ls-files`, not `find` — `.direnv/` carries a script and a vendored tree
that are not this repo's to count. Quote **comments and code**; total lines is
not a denominator anyone means.

### Ask the closure, not the source

Both package lists resolve at eval, so ownership questions are answerable
exactly rather than by grep. This is the probe §5b's assertion is built from —
it is what produced "21 duplicate names, one real divergence":

```sh
nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.);
  c = f.nixosConfigurations.thinkpad.config; l = f.inputs.nixpkgs.lib;
  idx = ps: l.listToAttrs (map (p: { name = p.name or "?"; value = p.outPath or "?"; }) ps);
  s = idx c.environment.systemPackages; h = idx c.home-manager.users.henry.home.packages;
in l.filter (n: s.${n} != h.${n}) (l.intersectLists (l.attrNames s) (l.attrNames h))'
```

Same shape answers "what pulls this in": `nix-store --query --referrers` on the
store path, which is how `electron-40.10.5` was traced to winboat rather than to
the Arch install its comment claimed.

### Read the compositor's source, don't infer its behaviour

Every mango claim in §3 was checked against `nix build nixpkgs#mango.src` and
then re-checked by probe, because two of them were the opposite of what the
existing comments said. Cite `file:line` into that source so the next reader can
disagree with the evidence rather than with the summary.

### Dry-run a state machine without touching the session

Copy the built config tree into a fake `HOME`, stub the launch command, and
enumerate every combination — this validated all mode/layout/position pairs plus
the fresh-machine and corrupt-state paths before any rebuild. Override
`XDG_STATE_HOME` as well as `HOME`, with `env -i`: `docs/gotchas.md` records why
the first attempt returned the same answer for all 12 cases.

---

# Suggested order

| # | Item | Shape |
|---|---|---|
| ~~1~~ | ~~**6a** the floor on `static.sh` itself~~ | ✅ 2026-08-20 |
| ~~2~~ | ~~**3b** `mango -p` check~~ | ✅ 2026-08-20 |
| ~~3~~ | ~~**3a** mango config selection~~ | ✅ 2026-08-20 |
| ~~4~~ | ~~**5c** drop logseq, name winboat~~ | ✅ 2026-08-20 |
| ~~5~~ | ~~**5b** one owner per package~~ | ✅ 2026-08-20 |
| 6 | **5f** `nvd` wrapper, **5a** predicate | one commit each; `nvd` moves to `packages.nix` — **next** |
| 7 | **5e** format the shell | exclusions → format → fix `static.sh:397` → gate |
| 8 | **5d** comments | the five files listed, then stop |

Nothing above needs a logout, which is what the 3a decision bought.
**5c nixos-hardware is not in the list** — decided against, above.

## Definition of done

- `nix flake check` builds both closures and fails on: a shellcheck warning, a
  `/bin/bash` shebang, a dash-flag `mmsg` call, an unreferenced file in a
  runtime-selected directory, **a mango config whose `source=` does not
  resolve**, **a package declared in two places that resolve differently**, and
  **its own assertion count falling**.
- `nix fmt` is a no-op across Nix **and** shell.
- Nothing writes into `~/.config/mango` at runtime except one link swap that
  `checks/static.sh` knows the name of.
- No plaintext secret outside sops.
- A fresh clone plus the age key reproduces a working machine, VPN and forge
  access included.
- Every new assertion has been confirmed against a planted defect. A gate only
  ever observed passing has not been observed.

## Open questions

1. **Does 5d include `CLAUDE.md` itself?** At 259 lines it overlaps `SYSTEM.md`
   and the ADRs heavily, but does a different job — what has bitten us, versus
   how the system is laid out. Leaning out of scope: trimming it moves cost from
   documents nobody reads to the one document loaded into every session. Give it
   a ceiling instead — past ~350 lines, look again.
2. **`menus/shell.sh`'s dispatch table under 5e** — accept the 15 aligned lines
   becoming 75, or carry one file exclusion forever. The table is the clearest
   thing in that file; the exclusion is a permanent asterisk.

*Closed, with the evidence, rather than left to drift:*

- *Is the hud mode still wanted?* No — removed, `docs/adr/0035`. Every remaining
  `hud` string in the repo is a comment recording that.
- *Does `static.sh` need splitting?* No — Deliberately NOT, above; Phase 6 instead.
- *`nh` vs `nvd`?* `nvd` — §5f.
- *Adopt `lenovo-thinkpad-l14-amd`?* No — §5c, with the backlight measurement.
