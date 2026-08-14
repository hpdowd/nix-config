# 0019 — elephant builds only the providers something reaches

**Status:** Superseded by [0021](0021-rofi-replaces-walker-and-elephant.md)
(2026-08-14) — walker and elephant are gone, so there is no provider list left
to trim. Kept, because the measurement below is what decided 0021. The trim cut
the store path 807 → 546 MB exactly as recorded here, and did **not** move the
resident set: measured 2026-08-14, **305 MB at 15 providers**, against the
295 MB at 25 that this record predicted would fall. Consequences flagged that as
a prediction rather than evidence. It was wrong, and 546 MB that could not be
cut further by the same technique is why rofi won.

Originally **Accepted (2026-08-13)**.

Extends [0014](0014-declare-the-namer-not-just-the-file.md) (assert reachability
both ways, per selector) and [0011](0011-shell-is-gated-too.md) (the floor rule).

## Context

`elephant` was the largest thing in the system closure by a wide margin, and the
largest resident process on the desktop:

| | |
|---|---|
| store path | **807 MB**, of which `lib/elephant/providers/` is 782 MB |
| RSS at idle | **295 MB** — 2.5× the rest of the shell stack combined |
| providers built | 25 |
| providers anything in this repo reaches | 15 |

The shape is not a leak or an index. Each provider is a **Go plugin**, built
with `-buildmode=plugin`, so every one statically links its own copy of the Go
runtime: ~26 MB apiece, `symbols.so` 144 MB, `todo.so` 37 MB. The daemon
`dlopen`s every `.so` in its provider directory at startup, which is where the
resident set comes from.

Ten of the twenty-five were reachable from nothing at all: `archlinuxpkgs`,
`aptpackages` and `dnfpackages` (this is NixOS, and [0008](0008-arch-removed.md)
removed the last Arch fallback), `niriactions` and `nirisessions` (the
compositor is mango), `1password` and `protonpass` (we use bitwarden via `rbw`),
plus `playerctl`, `snippets` and `unicode`.

Installing the all-in-one package was the right call under Arch, where tracking
fifteen separate packages by hand is real work. Under Nix the list *is* the
config, it lives next to everything else it has to agree with, and it is checked
by the same gate.

## Decision

**Build the providers something names, and let the build fail when those two
lists disagree.**

`modules/system/desktop.nix` passes `enabledProviders` to `elephant.override`.
nixpkgs supports this directly — with `enabledProviders = null` (the default) the
derivation globs `internal/providers/*/`, otherwise it builds exactly the listed
set and drops the matching `runtimeDeps` (`fd`, `bluez`, `libqalculate`,
`wl-clipboard`, `imagemagick`) along with them.

The fifteen split into two groups worth keeping distinct in the list:

- **reached by a keybind, a waybar click, or a walker default/empty set** —
  `desktopapplications`, `calc`, `websearch`, `menus`, `providerlist`,
  `clipboard`, `bitwarden`, `bluetooth`, `wireplumber`;
- **reached only by a prefix** typed into walker — `symbols` (`.`), `files`
  (`/`), `todo` (`!`), `bookmarks` (`%`), `windows` (`$`), `runner` (`>`).

The second group is kept deliberately. `symbols` alone is 144 MB — 26% of what
remains — and dropping it is the obvious next cut if the store path matters more
than the `.` picker.

### The list is checked against its callers, both ways

This trades one silent failure for another: a `[[providers.prefixes]]` entry or a
`walker.sh -m <name>` naming a provider that is no longer built opens an empty
window and exits 0 — the exact signature of the missing-`rbw` bug in
`docs/gotchas.md`, and indistinguishable from it at the keyboard.

So `checks/static.sh` enumerates both sides and asserts the correspondence, per
[0014](0014-declare-the-namer-not-just-the-file.md):

- every provider named by a `provider =` prefix, a `default`/`empty` set, or a
  `-m` flag is in `enabledProviders`;
- every provider in `enabledProviders` is named by at least one of those.

`menus:connectivity` is truncated to `menus` before comparison, since the
sub-entries come from one `.so`. The `-m` scan is anchored on lines mentioning
`walker`, or `install -m 644` in `scripts/lib.sh` enters the list as a provider
named `644`. Reading either list as empty **fails** rather than passing on a
match of nothing.

## Consequences

- **Store path 807 MB → 546 MB; closure 1.2 GiB → 970 MiB.** RSS should fall
  with the number of plugins loaded, but that is a prediction until measured —
  `elephant listproviders` and `smaps_rollup` after the rebuild are the evidence,
  not this document.
- **elephant no longer comes from the binary cache.** An override is a different
  derivation, so it builds from source on every version bump. It is a Go build of
  fifteen plugins, not a long one, but `nix flake check` is no longer instant
  after a `nix flake update` that moves elephant.
- **Adding a walker prefix is now two edits.** The prefix and the provider, or
  the build fails. That is the point.
- **Upstream adding a provider changes nothing here.** The list is explicit, so a
  new provider in a future release is simply not built until something names it.
