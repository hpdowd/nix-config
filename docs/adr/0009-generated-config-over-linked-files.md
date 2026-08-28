# 0009 — Generate config from Nix where a module exists; link files only where one does not

**Status:** Accepted (2026-08-01)

Supersedes the *default* set by [0002](0002-out-of-store-dotfiles.md). 0002's
rule still governs the files that remain; it is no longer the first question to
ask.

## Context

[0002](0002-out-of-store-dotfiles.md) framed dotfile management as a binary:
store-based (read-only, reproducible) versus out-of-store (writable, not
reproducible), decided by *"does a running program rewrite this file?"*.

That was the right question for the migration and the wrong place to stop. Both
options treat the config as **a hand-written file that Nix moves around**. The
file is still the artefact; Nix only decides where it lives and whether it is
writable. Everything that makes NixOS worth the friction — typed options, a
single owner per concern, values shared between consumers — sits in the tier
above, and this repo was not using it. As of 2026-07-31, exactly seven native
`programs.*`/`services.*` modules were in use (`zsh`, `git`, `zoxide`, `fzf`,
`direnv`, `gtk`, `qt`) against roughly twenty linked config directories.

The framing persisted because it was never revisited after the constraint that
created it went away. Before [0001](0001-flake-at-repo-root.md) the dotfiles sat
*outside* the flake root and were unreachable by any relative path, so
`mkOutOfStoreSymlink` was the only mechanism that worked at all. 0001 removed
that, 0002 took the step from out-of-store to store-based — and then the
question stopped being asked, because store-based *felt* like the destination.
It was a waypoint.

What that cost, concretely:

- **Silent-failure surface.** The recurring failure here is config that is wrong
  in a way nothing reports: the dead `mmsg -s -d` flags (which exit 0), waybar
  `custom/*` modules rendering empty on exit 127, `appid:zen` window rules that
  never matched, six language servers missing from `lsp.lua` with no diagnostic.
  A hand-written file that Nix copies verbatim reproduces the typo faithfully.
  Typed options are the only mechanism available here that converts any of this
  into a build failure.
- **Split ownership.** `kitty` was declared in `packages.nix`; `kitty/` was
  declared in `dotfiles.nix`. Nothing connected them, so removing one left the
  other. The same split existed for foot, helix, htop, ncspot, imv, yazi, zed —
  and for `wlogout`, whose package was in `environment.systemPackages` while its
  config was in home-manager, putting the binary in one profile and its
  stylesheet in another.
- **Duplicated values.** The Gruvbox palette existed twice, as
  `kitty/gruvbox-orange.conf` and `foot/gruvbox-colors.ini` — the same sixteen
  hex codes in two spellings, with nothing to keep them in step.
- **Dead weight that looks live.** Because a linked file is never evaluated,
  an *empty* one is indistinguishable from a correct one.
  `dotfiles/lazygit/config.yml` was zero bytes; `dotfiles/ghostty/config.ghostty` was
  zero bytes; `dotfiles/bottom/bottom.toml` was the upstream sample with every line
  commented out. All three were listed in `dotfiles.nix` as though they
  configured something. Eleven further files were tracked and referenced by
  nothing at all.

## Decision

**Three tiers, in order of preference.**

1. **Generated** — a native home-manager module produces the file from typed
   Nix options. No config file exists in the repo. This is the default.
2. **Store-based file** (`source = ../../dotfiles/X`) — where no module exists, or
   where the content is *data* rather than settings.
3. **Out-of-store** (`mkOutOfStoreSymlink`) — only where a program rewrites a
   tracked file and the writer cannot be relocated. `corectrl` alone.

Converted on 2026-08-01: **kitty, foot, helix, zed, htop, ncspot, imv, yazi,
wlogout**. Each package moved out of `packages.nix` (and `wlogout` out of
`systemPackages`) in the same change, because the module installs it — one
owner, or none.

**Not converted, deliberately.** These are decisions, not a backlog:

| Config | Reason |
|---|---|
| `nvim` | ~22 files of lazy.nvim config. `programs.neovim` with Nix-managed plugins is a rewrite, not a conversion — it trades `:Lazy sync` for a rebuild per plugin bump, and the store path already delivers reproducibility |
| `mango` | No module exists, and the mode scripts genuinely must `cp` into `config.conf` — the `recursive = true` case from 0002 |
| `swaync` | `services.swaync` works, but declares `systemd.user.services.swaync` — the unit masked under [0005](0005-one-owner-per-daemon.md), because `autostart.conf` owns swaync so restyles apply on mode switch. Adopting it flips that ownership and needs its own record |
| `helix/themes/gruvbox.toml` | 264 lines of scope mappings. Generating *settings* pays; a colour scheme is data, and transcribing it into attrsets risks a silent typo for no gain |
| `glow`, `nwg-look` | no module at the current pin |

## Consequences

- **Editing these configs now requires a rebuild.** There is no file to change.
  The reload table in `CLAUDE.md` gained a `rebuild`-first warning, because
  reloading without rebuilding is indistinguishable from the change having had
  no effect — the same trap the `mango` store conversion introduced.
- **Two conversions changed behaviour, both benignly.** `programs.kitty` sets
  `shell_integration no-rc` and wires kitty's integration into zsh directly
  instead of letting kitty inject an rc file — same features, cleaner
  mechanism. `programs.htop` emits the legacy `left_meters`/`right_meters` keys
  and omits `config_reader_min_version`; htop reads both formats, and the
  combination is internally consistent.
- **"Declarative" stopped implying "read-only".** `programs.zed-editor` does
  not link a file: it merges the declared settings into the real writable
  `settings.json` at activation with `jq -n '$dynamic * $static'`. Zed keeps
  saving its own state, and declared keys are reasserted every rebuild. 0002's
  central trade-off — reproducibility *or* a writable config — turns out to
  have been an artefact of only having symlinks available. Check for a merging
  module before accepting it.
- **One conversion nearly introduced a silent bug.** `dotfiles/wlogout/style.css`
  referenced its PNGs relatively (`url("icons/lock.png")`), which worked only
  because the whole directory was linked. `programs.wlogout` renders
  `style.css` as a standalone store file, so a relative reference would resolve
  next to a lone `.css` and find nothing — and GTK draws its missing-image box
  for a failed `url()` **without logging anything**. Fixed by interpolating each
  PNG's own store path. This is the one safe class of absolute path: computed at
  build time, impossible to leave stale.
- **The audit is the valuable part, not the diff.** Three configs turned out to
  be empty and eleven files unreferenced. None of that was visible while they
  were being faithfully symlinked into place; it surfaced only because
  conversion forces a reading of what is being converted.
