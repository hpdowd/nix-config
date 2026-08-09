# Plan — make `nix-config` more maintainable and reproducible

**Live working file.** Moved into the repo on 2026-08-03 — it had been sitting in
a session scratchpad under `/tmp`, one reboot from gone. Delete it when the work
lands; promote individual sections into `docs/adr/` as decisions come out of
them.

Rewritten **2026-08-03** against `main` @ `2f45486`, after Phase 0 landed and
after a complexity audit that changed the plan's shape. Every package attribute
named here resolves at the current pin (nixpkgs `624af665`); every measurement
was taken, not estimated.

---

## Framing

The file tree is **not** the problem. One host, per-concern system modules,
home-manager as a NixOS module, a single overlay point, a documented three-tier
config rule with ten ADRs behind it — that is already better than most public
configs, and reorganising it further is the wrong place to spend effort.

Four gaps, in priority order:

| Gap | Consequence | Phase |
|---|---|---|
| ~~Nothing verifies a change before you run it~~ | closed 2026-08-03 | 0 ✅ |
| ~~Nothing verifies the SHELL~~ | closed 2026-08-03 | 0.5 ✅ |
| ~~Secrets are not managed~~ | closed 2026-08-06 (Phase 2 still open) | 1 ✅ |
| **Dead code is indistinguishable from live code** | Three instances found so far, most recently 765 lines | 4 |
| **Prose has swallowed the code** | 1,417 of 3,930 `.nix` lines are comments; `dotfiles.nix` is 57 lines of code under 249 of narrative | 5 |

### The correction that reshaped this plan

The original version gated Nix and ignored shell. That was backwards:

| | Lines | Files | Gated by |
|---|---|---|---|
| Nix | 3,930 | 22 | full build + statix + deadnix |
| **Shell** | **2,160** | **40** | **nothing** |

**Every failure catalogued in `CLAUDE.md` is a shell failure** — the
`#!/bin/bash` exit-127s, the dead `mmsg -s -d` flags that return 0, `pkill -x`
against wrapped binaries, the `cp` mode-0444 bug, the empty `custom/*` module
text, the state-path disagreement that broke the mode switch one-way. Not one
was a Nix error. Phase 0 built a careful gate around the layer that was not
breaking.

### Deliberately NOT in this plan

State these up front so they don't get reintroduced as "improvements":

- **No `mkEnableOption` toggles on `modules/system/*`.** Standard advice, wrong
  here — speculative generality for a single machine, paying indirection on
  every read to serve a second host that does not exist.
- **No `lib/mkHost`, no `flake-parts`.** Same reason. Add the abstraction the
  day a second host appears.
- **No splitting `packages.nix`.** A 235-line categorised list is readable.
- **No converting `nvim`, `mango`, `swaync` or the waybar CSS to generated
  config.** Each has a recorded reason in `docs/SYSTEM.md` §6 and ADR 0009.
- **No re-enabling statix's `repeated_keys`.** ADR 0010 explains why; it fires
  69 times against standard NixOS module style.

---

# Phase 0 — a gate for Nix ✅ DONE 2026-08-03

Commits `8090a9a` → `c749928` on `main`. `nix flake check` now builds
`system.build.toplevel` and the home-manager activation package and runs
statix + deadnix. `verify-packages.sh` retired as a strict subset. Formatter is
`nixfmt` (RFC 166); devShell + `.envrc` pin the tooling. Recorded in
**ADR 0010**.

**Four things the original plan got wrong** — kept because they would cost the
same time again:

1. **`formatter = pkgs.nixfmt` does not work.** nixfmt takes *files*: no
   arguments → reads stdin, dies on empty input with a bare
   `unexpected end of input`; a directory → Haskell backtrace. `nix fmt` passes
   no arguments. Neither error names the cause. Wrapped in a
   `writeShellApplication`.
2. **`nixfmt-rfc-style` is a deprecated alias** at this pin — same derivation,
   warns on every eval. Use `nixfmt`.
3. **statix fired 69 times, all one lint.** Disabled `repeated_keys`.
4. **deadnix flagged 39, of which 37 were module-header boilerplate.**
   `--no-lambda-pattern-names` leaves the 2 real ones.

The governing rule, learned here and applied to every linter below:
**a check that always fails is one you learn to ignore** — worse than no check.
Tune until every remaining finding is real, and comment the tuning at its call
site so it does not read as dodging the defaults.

---

# Phase 0.5 — a gate for shell ✅ DONE 2026-08-03

Commits `74742c4` (shellcheck + the 24 fixes) and `62ee18b` (static assertions).
Recorded in **ADR 0011**. `nix flake check` now runs 10 checks.

**Both steps landed as planned, with two deviations worth keeping:**

1. **shellcheck went straight to default severity**, not the planned `-S
   warning` → fix → drop. With only 24 findings, fixing them outright was
   cheaper than staging the threshold and left no exemption to forget.
2. **The static checks live in `checks/static.sh`, not inline in `flake.nix`** —
   otherwise the gate would not lint its own gate. Shell embedded in a Nix
   string is exactly the unchecked shell the phase existed to eliminate.

Three things the plan did not anticipate:

- **`cd ${self}` puts you in a read-only store path.** The first shellcheck
  check wrote its file list into the working directory and died with
  `Permission denied` plus a `find: write error`, which reads like a broken
  find. Write to `$TMPDIR`.
- **`head -1` on the repo's PNGs** made bash warn about null bytes in command
  substitution, three times per build. `head -c 64 | tr -d '\0'` instead.
- **The git-based checks could not move verbatim.** `git ls-files` and
  `git check-ignore` have no git inside a derivation, so the symlink check
  became `find -type l` and the tracked check consults git only when `.git`
  exists. Running against `${self}` is *stronger* than the original: it sees
  tracked files only, i.e. what a fresh clone gets.

**The floor assertions are the part to keep.** Every scan fails when it matches
nothing rather than passing — script count ≥30, waybar configs =8, waybar
script references >0. Both gates were confirmed to fail on a planted defect,
because a gate only ever observed passing has not been observed at all.

Still ungated, deliberately: `dotfiles/zsh/conf.d/*.zsh`. No shebang, and
shellcheck does not do zsh.

## Step 1 — shellcheck in `checks` ✅

**It can be turned on cleanly**, unlike statix. Measured against the 38 live
scripts (excluding `docs/archive/`):

```
24 findings: 0 errors, 4 warnings, 20 notes
16 of 24 are SC2015, concentrated in 4 menu scripts
```

**SC2015 is not a style nit.** `A && B || C` is not if-then-else: C also runs
when A succeeds and B fails. In `vpn-menu.sh` that is
`nmcli con up "$name" && notify-success || notify-failure` — a connection that
comes up but whose notification fails reports failure. Exactly this repo's
genre of bug.

Sequence:

1. Add shellcheck as a `checks` entry at **`-S warning`** — passes today except
   for 4 findings, so fix those first and it goes green immediately.
2. Fix the 16 SC2015s, then drop to the default severity.
3. `-e SC1091` permanently: shellcheck cannot follow `. "$HOME/.config/…"`
   source paths statically, and that is not going to change.

⚠️ **Run it via `nix shell nixpkgs#shellcheck -c …`, not `nix run`.** During
this audit `nix run nixpkgs#shellcheck -- … 2>/dev/null` swallowed the findings
and reported **zero**, which looked like a clean bill of health. If a linter
suddenly reports nothing, distrust the invocation before believing the result.

## Step 2 — move the static half of `verify-claims.sh` into `checks` ✅

Six of its eight checks need **no live system** and are currently a manual step
nobody is forced to run:

| Check | Needs a session? |
|---|---|
| no tracked symlinks | no |
| `config.conf` / `walker/config.toml` generated + gitignored | no |
| no script reads the old state path | no |
| `pkill -x` targets are unwrapped binaries | no |
| battery STOP == generated waybar `full-at` | no — reads the built output |
| `wlopm` enumerates an output | **yes** |
| `mmsg` reports a monitor | **yes** |

Move the six into `nix flake check`; leave the two live ones in the script and
say so in its header. The coupling check already proved its worth — it was
silently failing as "could not read" after `config-focus.jsonc` stopped
existing.

**Also worth adding as static checks**, because each encodes a bug that has
already happened:

- **no `#!/bin/bash`** anywhere (there is no `/bin/bash`; this bit 13 scripts)
- **no `mmsg` invoked with dash-flags** — it takes verbs and answers unknown
  commands with `{"error":…}` **and exit 0**
- **every `custom/*` module's `exec` script exists and is executable**

**Definition of done for this phase:** `nix flake check` fails if any tracked
shell script has a shellcheck warning, a `/bin/bash` shebang, or a dash-flag
`mmsg` call.

---

# Phase 1 — secrets (`sops-nix`) ✅ DONE 2026-08-06

Recorded in **ADR 0012**. `nix flake check` now runs 13 checks. The input
landed separately in `c6df2e9`; this is steps 2–5.

**Five things the plan got wrong or did not anticipate:**

1. **`ssh-to-age` was impossible here.** `services.openssh` is not enabled, so
   `/etc/ssh` holds `ssh_config` and `ssh_known_hosts` and no host keys at all.
   Generated standalone with `age-keygen` instead. Step 2 above is corrected.
2. **Only the NixOS module surface was needed, not both.** The plan assumed the
   home-manager module for `pia-auth` because a user script reads it — but
   `sops.secrets.<name>.owner = "henry"` covers that, and the HM module would
   have wanted a *second* age key readable by the user. One key, one surface.
3. **The key must be readable by the editing user, and that is a real choice.**
   `age-keygen` writes it root-owned mode 600, at which point `sops` as henry
   cannot decrypt and the only paths are a second admin key or `sudo sops` —
   which writes the file back root-owned inside a git repo. Chosen: chown to
   henry, and `SOPS_AGE_KEY_FILE` in the devShell so there is no env var to
   remember. Root still reads it at activation.
4. **`pia-auth` was WRITTEN by `vpn-menu.sh`, not just read.** A "Set PIA
   credentials" entry prompted through walker and wrote the file. A sops secret
   is root-installed mode 0400, so that path could not survive; the setter was
   deleted rather than kept as a fallback, because a fallback leaves "no
   plaintext secret outside sops" unenforceable.
5. **`sops <path>` on a file that does not exist opens its `hello: Welcome to
   SOPS!` template for a NEW file** rather than erroring. Running it from
   inside `secrets/` therefore silently edits `secrets/secrets/secrets.yaml`
   and reports `File has not changed, exiting`. Cost two round trips. The
   template is the tell; run from the repo root.

**Stored vs declared is the part to keep.** `sops.secrets.<name>` decrypts to
`/run/secrets/<name>` on every boot, so a declared secret with no consumer is
plaintext on a running system for nothing. Declared: `pia/username`,
`pia/password`. Stored-only, retrieved with `sops -d --extract`: the WireGuard
key (declared in Phase 2, when `ensureProfiles` gives it a consumer) and the
three forge tokens (stored-only permanently — `gh`, `glab` and `tea` each
rewrite their own config, which is the `corectrl` fight from ADR 0002).

**The new static check asserts encryption, and was confirmed against a plant.**
An unencrypted `secrets.yaml` looks exactly like an encrypted one unless you
open it, and the mistake is unrecoverable once pushed. It does **not** check
the values are real — a file full of `REPLACE_ME` encrypts and passes, which
happened twice during this work before the edit took.

---

# Phase 2 — declare the NetworkManager profiles ✅ DONE 2026-08-09

Recorded in **ADR 0013**. The 9 that carry a credential or can hijack the
default route (`homelab` + 8 PIA exits) are generated from `networking.nix`,
with credentials substituted by `envsubst` from a sops template. The ~29
ordinary APs stay in NetworkManager's own state. `checks/static.sh` now runs 16
assertions.

**Four things the plan did not anticipate:**

1. **`ensureProfiles` writes to `/run`, not `/etc`** — and NetworkManager reads
   both. The hand-restored `/etc` copies had to be moved aside or the whole
   declaration would have been a **silent no-op**, in the change meant to end
   silent no-ops. `nmcli -f NAME,FILENAME con show` is the tell. This also
   turns out to be *why* declaring a subset is safe: the unit deletes nothing.
2. **The PIA CA lived in `$HOME`.** All eight profiles referenced
   `~/.local/share/networkmanagement/certificates/nm-openvpn/<name>-ca.pem`,
   left by `nmcli connection import`, and all eight files are byte-identical.
   Vendored as one `modules/system/pia-ca.pem` — it is PIA's public CA.
3. **`vpn-menu.sh`'s importer branch is dead.** It builds a PIA server list from
   `~/Downloads/openvpn/*.ovpn`; that directory does not exist, so the list is
   always empty and the credential-injection path is unreachable. Phase 4
   material, not fixed here.
4. **Three checks in `static.sh` had been scanning `$SRC/home`** since the
   `home/` → `dotfiles/` rename in `859895a`, and so had been passing by
   finding nothing. Fixed in the same commit; the `pkill -x` check went from 0
   targets to 2.

**The two new assertions are the part to keep**, and both were confirmed against
a planted defect: no profile may omit `autoconnect=false`, and every
`password` / `private-key` / `psk` must be a `$`-placeholder rather than a
literal, because `/nix/store` is world-readable and an inlined credential looks
identical to a working profile.

**Verify:** `nmcli -f NAME,FILENAME,AUTOCONNECT connection show` — the nine
report a `/run/...` filename and `no`. `resolvectl status` — no link holds
`Default Route: yes` except the active physical one.

---

# Phase 3 — the desktop layer 🔶 PARTLY DONE

**This is where the complexity actually lives**, and the original plan missed
it entirely by being Nix-centric. `dotfiles/mango/` is 19 directories, 30 scripts
and four stacked config layers. Governing principle:

> **Push variation to build time; let runtime only *select*.**

### Done 2026-08-03 (`2f45486`)

- **Waybar position is a file selection, not a runtime rewrite.** `waybar.nix`
  emits the layout × position matrix (8 files); the script builds a filename.
  Deleted the `sed -E` rewriting, the `margin-swap` placeholder, the temp file.
  `waybar-restart.sh` 79 → 40 lines.
- **State paths and defaults live once**, in `scripts/lib.sh`. Nine scripts had
  each re-derived them. `apply_mode()` moved there too — `modes/tiling.sh` and
  `modes/hud.sh` were byte-identical copies apart from two names.
- **765 lines of unreachable presentation code deleted** (see Phase 4).

### Outstanding — mango config selection

Would remove the **last `recursive = true` writability exemption**, which is
the flag that once destroyed 65 tracked files in this repo.

**Blocked on a prerequisite discovered while scoping it:** the mode configs use
**relative** `source=` lines (`./universal/settings.conf`), so `config.conf`
cannot move out of `~/.config/mango/` until those are absolute. Full sequence:

1. Rewrite the 8 `source=` lines in `tiling.conf` / `hud.conf` to absolute.
2. Point mango at `~/.local/state/mango/config.conf` — the greetd command is
   `tuigreet --cmd mango`, so this touches session startup.
3. Handle the fresh-machine case (no `config.conf` until a mode script runs —
   already true today, but moving it should not make it worse).
4. Drop `recursive = true` from the `mango` entry in `dotfiles.nix`.

⚠️ **Only validatable by logging out.** Its own change, its own session, with
`rebuild-test` and a way back in.

### Also worth doing here

- **`reload.sh` and the menu scripts should source `lib.sh`** for `MANGO_DIR`
  too — partly done, finish it.
- **`vpn-menu.sh` carries 4 of the 24 shellcheck findings** and is the largest
  remaining SC2015 cluster. Fold into Phase 0.5.

---

# Phase 4 — the dead-code class

**Three instances so far**, which makes it a class rather than a coincidence:

| When | What | Size |
|---|---|---|
| 2026-07-30 | `kitty/active-theme.conf`, `foot/active-theme.ini` | symlinks selecting nothing |
| 2026-07-30 | `gtk-*-tiling` variants, `gtk-apply.sh $MODE` | byte-identical to their targets |
| 2026-08-03 | `waybar/style.css`, `walker/configs/default.toml`, `walker/themes/mango/` | **765 lines** |
| 2026-08-09 | `vpn-menu.sh`'s `.ovpn` importer — `~/Downloads/openvpn` does not exist, so the list is always empty | ~35 lines |
| 2026-08-09 | three `static.sh` checks scanning `$SRC/home` after the `dotfiles/` rename | 3 gates, silently disarmed |

Every one *looked maintained*, and the last was documented as the default in
both `CLAUDE.md` and `SYSTEM.md`. The shared mechanism: **a file selected by a
shell conditional is never evaluated, so an unreachable branch is invisible.**

**Step 1 — sweep.** For each directory whose contents are selected at runtime
(`walker/themes/`, `walker/configs/`, `mango/waybar/*.css`, `elephant/menus/`,
`fsel/`), check every file is reachable from some live code path. The technique
that worked: enumerate the possible values of the selecting variable from its
*writers*, then check each branch is reachable.

**Step 2 — prevent.** Add a reachability check to `checks` (Phase 0.5 Step 2):
every file in those directories must be named by some tracked config or script.
The waybar module's asserts are the model — a name with no definition is an
eval error, not an empty module.

---

# Phase 5 — idiomatic cleanups and comment surgery

Independent, low-risk, do any of them alone.

### 5a — `allowUnfree` predicate

`nix-settings.nix` sets `allowUnfree = true`, permitting *any* unfree package
including one pulled in transitively. Replace with a predicate naming the ones
actually accepted. Converts a future surprise into a build error.

### 5b — one owner per package

Packages live in three places: `packages.nix`, `programs.nix` (via module
`enable`), and `environment.systemPackages`. `wlogout` was in two at once,
making *which binary you get* a question of PATH order. No restructuring — an
audit plus a rule recorded in `packages.nix`:

> A package is installed by **exactly one** of: its `programs.*` module, a
> `home.packages` entry, or `environment.systemPackages`. User applications go
> in home; things needed before login or by a system unit go in system.

### 5c — overlay and pin hygiene

- **`fsel` override** pins 3.6.0 over nixpkgs' 3.1.0; its own comment says
  *"if 3.1.0 turns out to be fine, DELETE this block"*. Two hashes to maintain.
- **`permittedInsecurePackages`** — two electron versions for logseq, one
  justified by a comment referencing the Arch install.
- **`nixos-hardware`** — the flake imports generic `lenovo-thinkpad` + AMD
  commons. **Verify** whether a model-specific L14 Gen 5 module exists upstream;
  if so it may supersede hand-tuning in `power.nix`. Not confirmed either way.

### 5d — comments → ADRs ⭐ biggest day-to-day win

| File | comment | code | ratio |
|---|---|---|---|
| `dotfiles.nix` | 249 | 57 | **4.4 : 1** |
| `power.nix` | 139 | 62 | 2.2 : 1 |
| `pkgs/default.nix` | 94 | 62 | 1.5 : 1 |
| `theme.nix` | 83 | 77 | 1.1 : 1 |
| `home/default.nix` | 120 | 113 | 1.1 : 1 |
| **total** | **1,417** | — | — |

The *content* is good — it is the narrative that is misplaced. `dotfiles.nix`
is 57 lines of code wearing a 249-line essay, and it duplicates `CLAUDE.md` and
the ADRs. Keep a **one-line reason plus a pointer** (`# see docs/adr/0002`);
move the story.

**File-by-file with review, not one sweep.** Order by ratio. **Move, never
drop** — check the ADR covers it before cutting. A new ADR on suspend/
hibernation is needed for `power.nix` (material is in `SYSTEM.md` §9 and the
work log).

### 5e — `treefmt-nix`

**Its trigger condition is now met.** Phase 0 said "switch if it ever needs to
format more than Nix" — with 2,160 lines of shell and `shfmt` already in
`packages.nix`, it does. Replaces the `writeShellApplication` nixfmt wrapper
and folds the Phase 0.5 shellcheck gate in at the same time. Do it *after*
Phase 0.5, so the shell gate exists before the tooling changes under it.

### 5f — `nh` or `nvd` in the rebuild path

`nvd` and `nix-tree` are already in the devShell. Remaining question: wrap
`rebuild` to print `nvd diff-closures`, or adopt `nh os switch`. On a config
where "reloading without rebuilding looks exactly like the change having had no
effect" is a documented trap, seeing what actually changed is worth it.

---

# How to verify — techniques, not ceremony

Two developed during this work. Both generalise; use them rather than trusting
that a change is safe.

### Prove a refactor is a no-op

If a change should not alter the built system, compare the derivation paths:

```sh
nix eval --raw .#nixosConfigurations.thinkpad.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage.drvPath
```

Byte-identical before and after is proof. This is how the 618-line `nixfmt`
reformat was cleared — it matters here because `waybar.nix` carries literal
UTF-8 Nerd Font glyphs and this repo has already lost four network icons to
transcription once, invisibly.

### Dry-run a state machine without touching the session

Copy the built config tree into a fake `HOME`, stub the launch command, and
enumerate every combination. This validated all 12 mode/layout/position pairs
plus the fresh-machine and corrupt-state paths before any rebuild.

⚠️ **Override `XDG_STATE_HOME` as well as `HOME`.** The first attempt set only
`HOME`; `XDG_STATE_HOME` leaked from the interactive session, every case read
the *real* state files, and all 12 combinations returned the same answer —
which reads exactly like a catastrophic regression. Use
`env -i PATH="$PATH" HOME=… XDG_STATE_HOME=…`.

---

# Suggested order

| # | Phase | Shape |
|---|---|---|
| ~~1~~ | ~~**0.5** shell gate~~ | ✅ done 2026-08-03 |
| ~~2~~ | ~~**1** sops-nix~~ | ✅ done 2026-08-06 |
| ~~3~~ | ~~**2** ensureProfiles~~ | ✅ done 2026-08-09 |
| 4 | **4** dead-code sweep ⭐ **DO NEXT** | small; Phase 2 found two more instances |
| 5 | **3** mango config selection | own session, needs a logout |
| 6 | **5a–5c, 5f** | one commit each, independent |
| 7 | **5e** treefmt | after 0.5 |
| 8 | **5d** comments → ADRs | one commit per file, reviewed |

**Phase 0.5 before Phase 1 is a real judgement call.** sops-nix closes the
bigger *reproducibility* hole; shellcheck closes the bigger *day-to-day
breakage* hole and is an afternoon rather than a branch. Recommend 0.5 first on
effort alone — but if the machine were rebuilt tomorrow, secrets would be what
you missed.

## Definition of done

- `nix flake check` builds the system and home closure, and fails on: a
  shellcheck warning, a `/bin/bash` shebang, a dash-flag `mmsg` call, an
  unreferenced file in a runtime-selected directory.
- `nix fmt` is a no-op across Nix **and** shell.
- No plaintext secret outside sops.
- A fresh clone plus the age key reproduces a working machine, VPN and forge
  access included.
- No `.nix` file above a ~1:2 comment-to-code ratio.

## Open questions

1. **`nh` vs wrapping `rebuild` with `nvd`** — `nh` is nicer but becomes a
   dependency in the critical path of every rebuild.
2. **Does 5d include `CLAUDE.md` itself?** ~350 lines of dense narrative,
   overlapping `SYSTEM.md` and the ADRs heavily — but it is doing a different
   job (what has bitten us, vs how the system is laid out). Probably out of
   scope; worth deciding rather than drifting.
3. **Is the hud mode still wanted?** It doubles the waybar matrix, owns a
   second stylesheet and a second walker theme, and every dead-code instance so
   far has been residue from a *removed* mode. Not a suggestion to drop it —
   a question worth answering explicitly, since the answer sizes Phase 3 and 4.
