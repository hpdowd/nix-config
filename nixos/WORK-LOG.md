# Migration work log — what was done, and why

**Covers 2026-07-28 → 2026-07-29 · 18 commits, `bf7094d` → `ee9f6fe`.**

This file explains the *purpose* of the work. It is the answer to "why is the
config like this?" and "what was actually wrong?", written so it still makes
sense in six months.

The other three files, and what each is for:

| File | Purpose |
|---|---|
| `MIGRATION-GUIDE.md` | The procedure. Standalone, start to finish. Follow this. |
| `INSTALL.md` | Condensed version of the same procedure. |
| `MIGRATION.md` | Rationale for the *design* — why side-by-side, why these packages. |
| `WORK-LOG.md` | **This file.** What was fixed and why it mattered. |

---

## Where it started, where it ended

**Before:** a flake that evaluated cleanly and looked finished. The docs said
"no blockers", the closure resolved, and every package name existed.

**After:** the same flake, with **six defects removed that would each have
produced a broken or failed install** — three of them silent. The evaluation
was never the problem; it passed the whole time. That is the theme of the
work: *a thing that evaluates is not a thing that works.*

---

## 1. The symlink bug class — the biggest theme

Four separate instances of the same underlying mistake. Worth understanding as
one idea rather than four fixes.

`home-manager` writes `xdg.configFile."foo"` **to** `~/.config/foo`. The
dotfiles strategy points those entries at a live checkout using
`mkOutOfStoreSymlink`, so the file stays editable. The mistake is letting the
*source* and the *destination* be the same path, or letting two things own one
path.

`flake.nix` sets `backupFileExtension = "hm-bak"`, which turns every one of
these from a loud error into a silent one: activation renames your real
directory aside, then creates a link to the path it just vacated. You get a
dangling symlink, no config, and **no error printed**.

| Instance | What was wrong | Fix |
|---|---|---|
| **B1** (pre-existing) | `dots` was `~/.config`, so all 26 entries linked to themselves | Repointed to `~/src/arch-config` |
| **B3a** — `~/.scripts` | Still self-referential. The B1 fix missed it because it does not go through the `link` helper | Declaration removed; `~/.scripts` survives via `@home` and is already on `PATH` |
| **B3b** — 5 credential dirs | `gh`, `glab-cli`, `gpu-screen-recorder`, `opencode` are excluded from git *because they hold tokens*, so a clone never produces them. `mpv` is allowlisted but empty | Links removed. Restored by hand from the backup instead |
| **fish** | `dotfiles.nix` linked all of `~/.config/fish` while `programs.fish` wrote `config.fish` inside it | fish dropped entirely — zsh is the login shell per `/etc/passwd` |
| **gtk** | `dotfiles.nix` linked `~/.config/gtk-3.0` while the `gtk` module wrote `settings.ini` inside it | Resolved as a side effect of the theming decision (§4) |

**Why B3b mattered more than it looks.** `INSTALL.md` told you to restore those
directories with `cp -a "$B/.config/gh" ~/.config/`. `cp -a` onto a *dangling
symlink* writes through to the resolved path — so that restore step would have
deposited `hosts.yml` and `restore_token` **inside the git clone**. A dangling
link plus a documented restore step equals credentials in version control.

**The rule that came out of it:** when home-manager owns any file inside a
directory, link the *subdirectory*, never the parent. `zsh` already did this
correctly (`zsh/conf.d`, not `zsh`), which is why it was the one that worked.

`verify-packages.sh` cannot catch this class — a path collision only fails when
the home-files derivation is *built*. A cheap eval that lists overlapping
managed paths is now in the guide as Step 2b.

---

## 2. Identity — the one that would have corrupted `/home`

`@home` is **reused by NixOS and stays mounted by Arch** throughout the
side-by-side period. Both systems must agree on who owns those files.

Evaluating the config gave:

```
uid = null; group = "users"; hasHenryGroup = false; usersGid = 100
```

The docs had flagged the uid and advised pinning it. That advice was
insufficient. `uid = null` would probably have landed on 1000 by luck — but
`isNormalUser` defaults the primary **group** to `users` (gid 100), while every
file under `/home/henry` is gid 1000. Result: your entire home directory under
an unmapped group on NixOS, and anything NixOS created showing as gid 100 back
on Arch.

**Fixed:** `uid = 1000`, `group = "henry"`, and `users.groups.henry.gid = 1000`.

---

## 3. What the flake silently failed to reproduce

An earlier sweep listed the gaps by reading the *contents* of
`~/.config/systemd/user/`. That directory holds enabled units, superseded
units, and never-enabled units all mixed together. Checking
`*.target.wants/` — the only record of what actually runs — changed three
conclusions:

| Unit | The sweep said | Reality |
|---|---|---|
| `rclone-nextcloud.service` | port it | **Not enabled.** `~/Nextcloud` uses the desktop sync client |
| `rclone@ProtonDrive.service` | not mentioned | **Enabled, and missed entirely.** Now ported |
| `elephant.service` | port it | Not enabled, and redundant — `mango/*/autostart.conf` already starts it |
| `gpu-screen-recorder-ui.service` | not mentioned | **Enabled, and missed.** It is package-provided, so it lives in `/usr/lib`, not `~/.config` |
| `claude-message.timer` | port it | Enabled but **broken since June** — `ExecStart` said `claude-scheduler`, the script is `claude_scheduler` |

Porting `rclone@ProtonDrive` needed two things beyond rewriting paths to the
store: `programs.fuse.userAllowOther` (its `--allow-other` flag fails without
`user_allow_other` in `/etc/fuse.conf`, which on Arch was a hand-edited file),
and a single-line `ExecStart` — home-manager writes these through an INI
generator, where the original's backslash continuations would split the file.

**The rule:** check `*.target.wants/` before porting anything.

```bash
ls ~/.config/systemd/user/{default,timers,multi-user}.target.wants/
```

---

## 4. Theming — an unresolved decision that was silently breaking things

`theme.nix` declared a `gtk` block; `mango/scripts/system/gtk-apply.sh` sets
the same dconf keys at runtime. Both writes succeed, but home-manager
reasserts its values on every rebuild and at login — so **a mode switch's theme
change would silently revert.** The file had documented this and recommended
option (a) for weeks, while still shipping option (b).

**Decided:** the mode scripts own the GTK theme. Mode switching is the point of
the setup. The `gtk` block is gone; the theme *packages*, the Qt platform theme
and the cursor stay in Nix.

That decision exposed a real breakage. With `settings.ini` now authoritative,
the theme it names is `Gruvbox-Yellow-Dark` — used in **seven** places across
the repo. The stock nixpkgs `gruvbox-gtk-theme` builds **only** `Gruvbox-Dark`
and `Gruvbox-Light`; verified by building it and listing `share/themes`. On
Arch the yellow variant comes from the AUR build passing `-t yellow`.

**Every GTK app on the new system would have fallen back to Adwaita** — with no
error, just a wrong-looking desktop. `pkgs/default.nix` now overrides the
package with `themeVariants = [ "yellow" ]`.

The same check caught the cursor: `theme.nix` said `Adwaita` while
`settings.ini` asks for `Capitaine Cursors (Gruvbox)`. That would have split
the cursor — Capitaine in GTK apps, Adwaita for Wayland. Now matched, using
`capitaine-cursors-themed`, which provides that exact name.

---

## 5. Evaluation is not buildability — the `fsel` near-miss

The most dangerous defect, found last, by doing the one thing nobody had done:
running an actual build.

The `fsel` override set `src` to the release **binary** tarball. nixpkgs builds
fsel with `rustPlatform.buildRustPackage` **from source**, so the cargo vendor
step had no `Cargo.lock` and died. Every evaluation had passed for weeks.

`fsel` is the `SUPER+Space` launcher and is in the system closure, so
`nixos-install` would have **aborted partway through, after writing to the
disk**.

Fixed by overriding with the GitHub source for the tag and regenerating
`cargoDeps` via `rustPlatform.fetchCargoVendor`. The version was stale too —
the comment claimed 3.5.2; `fsel --version` reports **3.6.0**. Now pinned to
3.6.0, and the built binary reports the same string as the live one.

**The rule:** any hand-written or overridden derivation must be *built* at
least once. `fsel` and `gruvbox-gtk-theme` are the two in the closure and both
are now verified. `curseforge` and `brother-mfc-l3740cdw` are defined in the
overlay but not installed — still uncompiled, still untested.

Applying the same rule to the rest of the closure: the only packages the
installer must build locally rather than fetch are `logseq`, `winboat` and
`claude-desktop` (plus the Electron runtimes they pull). **All three were built
on 2026-07-29 and all three succeeded**, in about nine minutes total. So
nothing in the closure is now unproven — the install will not stop on a build
failure.

That also settled a question the earlier docs got wrong. Those Electron
runtimes are missing from `cache.nixos.org` because they are flagged insecure
and Hydra skips such packages — *not* because they are source builds. Each
fetches upstream's prebuilt `linux-x64` zip and unpacks it. Nine minutes for
three Electron apps is the proof; a Chromium compile would have been hours and
would likely have run out of RAM.

---

## 6. Reproducibility and correctness of the plan itself

- **No `flake.lock` existed.** Inputs floated on every evaluation, so
  "verified" described whatever nixpkgs happened to be current that day. Now
  pinned to `624af665`. A pleasant consequence: the `nixos-unstable` installer
  ISO resolves to that same revision, so the installer substitutes from cache
  rather than rebuilding.
- **`environment.d/` was not reproduced.** It sets `GTK_THEME` and the Wayland
  Qt variables. It had to be `systemd.user.sessionVariables`, not
  `home.sessionVariables` — the latter writes `hm-session-vars.sh`, which
  interactive shells source and **systemd user units do not**, and the entire
  reason the file exists is `xdg-desktop-portal-gtk`, which is a user unit.
- **The rebuild aliases pointed at `~/.config/nixos`**, which the B1 fix made
  wrong — `dotfiles.nix` does not link `nixos/`, so that path will not exist.
- **`swap` was written as `@swap` in five places.** It is the one subvolume
  without the prefix. The cleanup phase deletes subvolumes *by name*, so the
  wrong spelling is a command that fails at the point you are already deleting
  things.
- **Free space had drifted** from 149 GiB to 110 GiB while the plan sat
  unchanged. Against a ~37 GiB closure the margin went from ~112 GiB to ~73
  GiB, which is close to the 60–80 GiB that 30 days of generations will use.

---

## 7. Repository hygiene

The flake reads a *clone* at `~/src/arch-config`, not `~/.config`. Creating it
closed B1, and revealed a hazard worth stating plainly:

**There are two working trees, and which is live depends on which OS booted.**
While Arch is your daily driver, `~/.config` is live and the clone goes stale.
After migrating, the direction reverses. `nixos-install` reads the clone — so
it must be re-synced immediately before installing.

Also resolved, because the install would otherwise have carried them along:

- `homelab` (9 files) and `learning` (1) committed and pushed.
- `paraphrase-detector`'s `backup/local-main-pre-sync-20260704` branch — 4
  commits including the final thesis report, on no remote — pushed **as a
  branch**, deliberately not merged into `main`.
- `aur-malware-check` and `Azure-in-bullet-points` deleted. Both third-party
  clones; the Azure one carried ~4.3 MB of your own LaTeX work on top, which
  was flagged before deleting and **is still on the backup drive**.

---

## 8. The documentation, and why it was rewritten

`INSTALL.md` had accumulated six rounds of "DONE" annotations layered over a
plan whose Phase 0 was entirely finished — the kind of document you stop
trusting. It was rewritten from a fresh verification pass rather than edited
again.

`MIGRATION-GUIDE.md` was then written as the standalone version, because
neither of the others is readable on its own if the machine is mid-install.
A copy lives on the backup drive so it can be read from a phone.

Writing it *while checking each step* caught four more errors, which is the
argument for that method:

1. The wallpaper restore copied `~/.config/mango/wallpaper` into the clone —
   but by that point `~/.config/mango` **is** a symlink to the clone. A no-op
   onto itself. The real directory is `~/.config/mango.hm-bak`.
2. It claimed the flake is reached through the `~/.config` symlinks. It is
   not; `nixos/` is deliberately unlinked.
3. `capture-root-state.sh` saves `/etc/cups`, and nothing restored it.
   Restoring it wholesale would fight the `services.printing` module, so the
   guide now tries driverless IPP first.
4. The hardware-config `diff` was unusable — the committed file is
   hand-written with a `let` block, so the diff is nearly all formatting noise.
   Replaced with targeted greps.

---

## 9. The decision register

Things deliberately dropped or chosen. Recorded so they are not rediscovered
as bugs later.

| Decision | Reason |
|---|---|
| Mode scripts own the GTK theme | Mode switching is the point of the setup; Nix would silently revert it |
| fish dropped | zsh is the login shell per `/etc/passwd`; fish also collided with its own dotfiles link |
| Flatpak dropped entirely | The three apps are not wanted, so the daemon has nothing to run |
| `claude-message` dropped | Broken since June; kept broken rather than half-fixed |
| `gpu-screen-recorder-ui` dropped | No nixpkgs equivalent; plain CLI kept |
| User password set at install, not declared | Keeps a password hash out of git |
| `~/.scripts` unmanaged | In no git repo; survives via `@home`, already on `PATH` |
| Credential dirs unmanaged | Linking a credential directory into a git repo is how tokens get committed |
| Two nixpkgs (claude-desktop's own pin) | It references removed `nodePackages`; forcing our nixpkgs breaks its evaluation |
| Azure repo deleted | Third-party clone; own work confirmed recoverable from the backup |

---

## 10. What is left

Worked through on 2026-07-29. All four open decisions are now closed.

| Was open | Decision |
|---|---|
| NixOS ISO on a USB stick | Done by hand |
| `paraphrase-detector` branch | **Leave as a branch.** `main` and the branch genuinely diverged — 4 commits on the branch (incl. the final thesis report), 6 on main (incl. "removing report images"), 49 files, 2 merge conflicts. Main looks deliberately slimmed for GitHub, so merging would fight an earlier decision. It is pushed and safe |
| Dead `magnet:`/`.torrent` handler | **`qbittorrent`.** Added to `packages.nix`; `xdg.mimeApps` now names `org.qbittorrent.qBittorrent.desktop`, verified by building it and reading `share/applications` rather than guessing. Covers the torrent half only — FDM's HTTP download manager has no equivalent |
| `piavpn-bin` | **No work needed** — see below |
| The AUR tail | **Dropped**, with `distrobox` as the escape hatch |

### The VPN turned out to be a non-problem

The plan was to replace the unpackaged proprietary client with
NetworkManager + OpenVPN. Checking first showed that is **already how you run
it**: 8 PIA region profiles exist, all of service-type
`org.freedesktop.NetworkManager.openvpn`.

Everything it needs already survives the migration:

- profiles in `/etc/NetworkManager/system-connections` — captured by
  `capture-root-state.sh`, restored in Part 10
- `password-flags = 0`, so credentials are in those files, not the keyring
- CA certs in `~/.local/share/networkmanagement/certificates/` — survive via
  `@home`, and are in the backup

The certs are referenced by *absolute* path, which resolves unchanged only
because the uid and home path were pinned identical (§2). The only real loss
is PIA's own GUI — the kill switch and port-forwarding toggle.

### The AUR tail, and one thing it turned up

`quickmedia`, `pipemixer`, `r-quick-share`, `haroopad`, `mdview`,
`pdf-compress`, `qrookie-vrp` are dropped. `distrobox` is already installed,
so an Arch container covers anything you miss — better than packaging seven
things before knowing which you use.

Both fonts were checked rather than assumed, and both are genuinely unused:
`nerd-fonts-sf-mono` appears only in a **commented-out** line in
`foot/foot.ini`, and `ttf-phosphor-icons` is referenced nowhere (it was a
DankMaterialShell dependency, and DMS is gone).

That grep found the opposite problem, though: `mango/waybar/style.css` asks
for **`"3270 Nerd Font"`**, which the flake never declared. Waybar would have
fallen back to a generic monospace — visible, but the kind of thing you notice
a week later and cannot place. `nerd-fonts._3270` is now in `fonts.nix`.

### Still genuinely outstanding

- **Delete `system-state/root-only` from the backup drive** once you are
  settled — SSH host keys, `/root`, and 38 WiFi PSKs in cleartext on an
  unencrypted disk. **Not yet:** Part 10 restores from it, so it is needed
  until the migration is done.
- **FDM's HTTP download-manager side** has no replacement. If you used it for
  more than torrents, you will notice.

**The honest summary:** the configuration is sound and every defect found has
been fixed and verified. But this config has never been booted. Evaluation and
builds prove it *can* exist; they do not prove mango starts. That is why the
guide's only goal for day one is that the compositor comes up, and why Arch
stays bootable for a month.
