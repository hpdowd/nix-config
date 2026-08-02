# 0010 — `nix flake check` is the gate, and lints are tuned to fire only on real findings

**Status:** Accepted (2026-08-03)

Retires `verify-packages.sh`.

## Context

Until now nothing verified a change before `nixos-rebuild switch` ran it. The
only pre-rebuild tool was `verify-packages.sh`, which parsed the flake and
**evaluated** the closure. Its own header said what it could not do:

> it only evaluates: it cannot catch profile collisions or a derivation that
> fails to build

Which is precisely the problem, because `CLAUDE.md` names `buildEnv` collisions
as **the failure mode to expect when adding packages** — two packages owning one
path, aborting the whole generation. The single most likely way to break this
system was the single thing the checker was structurally incapable of catching.
`docs/archive/MIGRATION.md` records the same gap being noticed three separate
times and worked around by hand each time.

Evaluation-only checking also cannot see a derivation that evaluates fine and
then fails to compile. The `fsel` override in `pkgs/default.nix` did exactly
that: it replaced `src` with a *binary* tarball while nixpkgs builds fsel from
source with `buildRustPackage`, so the cargo vendor step had no `Cargo.lock`.
Evaluation passed; the build would have aborted `nixos-install` partway through.

Separately, `nix fmt` pointed at **`nixpkgs-fmt`**, which is archived upstream.

## Decision

**`nix flake check` is the gate. Run it before `rebuild`.**

`flake.nix` declares four checks:

| Check | What it proves |
|---|---|
| `system` | `system.build.toplevel` **builds** — collisions, failing derivations, eval errors |
| `home` | the home-manager activation package builds |
| `statix` | no lint findings |
| `deadnix` | no unused bindings |

`system` and `home` are real build products rather than assertions, so checking
them exercises the whole closure. `verify-packages.sh` is deleted as a strict
subset.

`verify-claims.sh` **stays**, and is not redundant: it checks assertions about
the **live** system — state paths, `pkill` patterns against wrapped binaries,
whether `wlopm` still enumerates an output — none of which any build can see.

### Both linters are configured, not accepted as shipped

This is the part most likely to be undone by someone who thinks the defaults
were being dodged. **A check that always fails is one you learn to ignore**,
which is worse than no check, so each linter was tuned until every remaining
finding was real:

- **`statix.toml` disables `repeated_keys` (W20).** It fired **69 times, and
  was the only lint that fired at all.** It wants NixOS module config collapsed
  from the flat dotted form into nested attrsets — `nix.settings` +
  `nix.gc` → `nix = { settings = …; gc = …; }`. That is reasonable for general
  Nix and wrong for NixOS module config, where flat dotted keys are what the
  NixOS manual, nixpkgs and effectively every published configuration use.
  Restructuring 22 files to satisfy it would also break up the comment blocks
  that explain each setting.
- **`deadnix` runs with `--no-lambda-pattern-names`.** It flagged 39 things, of
  which **37 were `{ config, lib, pkgs, ... }` module headers** — boilerplate
  the module system requires. The flag drops it to the 2 findings that were
  real, both intentionally-unused overlay arguments, fixed by prefixing them
  with `_`.

### The formatter is nixfmt, wrapped

`nixfmt` (RFC 166), and **plain `nixfmt`, not `nixfmt-rfc-style`** — the two are
the same derivation at this pin and the alias emits a deprecation warning on
every evaluation.

**`formatter.${system} = pkgs.nixfmt` does not work**, and this is worth
recording because neither failure names its cause. nixfmt takes *files*:

- no arguments → it reads **stdin**, gets EOF, and dies with a bare
  `unexpected end of input` pointing at "line 1, empty line". It reads like a
  corrupt source file.
- a directory → an unhandled Haskell exception with a GHC backtrace.

`nix fmt` passes no arguments, so the obvious one-line output fails the first
way. Wrapped in a `writeShellApplication` that finds `.nix` files instead. **If
this ever needs to cover shell, markdown or TOML, adopt `treefmt-nix` rather
than growing the wrapper** — that is the tool for the job.

## Consequences

- **The first run is slow, subsequent runs are near-instant.** `nix flake check`
  builds the closure, so it is cached exactly like a rebuild.
- **`nix fmt` is not free to run casually on a shared branch.** The initial
  reformat touched all 21 files, 618 lines. It was committed **separately** from
  the change that introduced the formatter, so neither buries the other in
  `git blame`. Keep doing that.
- **A reformat can be *proved* a no-op, and on this repo it should be.**
  `waybar.nix` carries literal UTF-8 Nerd Font glyphs, and four network icons
  have already been silently lost to transcription once — invisible until you
  look at the bar. Rather than trusting that "formatters are safe", evaluate
  both build products before and after and compare derivation paths:

  ```
  nix eval --raw .#nixosConfigurations.thinkpad.config.system.build.toplevel.drvPath
  nix eval --raw .#nixosConfigurations.thinkpad.config.home-manager.users.henry.home.activationPackage.drvPath
  ```

  Both were byte-identical across the reformat, which proves the generated
  waybar JSON is unchanged codepoint for codepoint. **This technique generalises
  to any change that should not alter the built system** — a comment edit, a
  refactor, a `let`-binding extraction.
- **Do not reintroduce an evaluate-only checker and believe it covers you.**
  That is the specific mistake this record exists to prevent.
- **The lint config is load-bearing.** Re-enabling `repeated_keys`, or dropping
  `--no-lambda-pattern-names`, makes `nix flake check` fail permanently on an
  untouched tree. Both flags have a comment at their call site saying so.
