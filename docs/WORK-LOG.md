# Work log — the declarative pass

**2026-07-30 → 2026-07-31 · 17 commits, `c12388d` → `a7aefcf`.**

Covers the work after the Arch→NixOS migration was already installed and
booting: retiring the old repo, restructuring it, and moving the configuration
from "symlinks into a checkout" to "carried by the flake".

`docs/archive/WORK-LOG.md` is the earlier, separate log covering the migration
itself. `CLAUDE.md` describes how the system *is*; `docs/adr/` records the
decisions; this file records what changed and what it cost.

---

## Current state

| | |
|---|---|
| Repo | `~/src/nix-config`, flake at the root, dotfiles under `home/` |
| Remote | `origin` → `git.henrydowd.dev/henry/nix-config` only (GitHub mirrors removed) |
| Working tree | clean, 0 typechanges, 0 unpushed |
| Dotfile entries | **24 store-based, 1 out-of-store** (`corectrl`) |
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
