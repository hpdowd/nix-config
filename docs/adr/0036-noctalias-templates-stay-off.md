# 0036 — noctalia's auto-theming templates stay off

**Status:** Accepted (2026-08-20)

Settles phase 3b of
[0034](0034-colour-follows-the-mode-artefacts-do-not.md), which was left "not
done, and gated on a decision". Closes it as **no**, permanently, rather than
leaving it a toggle somebody flips later without the measurements.

## Context

noctalia ships a template engine: for each app in `activeTemplates` it renders
its current palette into a **sidecar** file, then runs an optional **post-hook**
that edits the app's real config to point at that sidecar. Turned on, it themes
kitty, foot, GTK, Qt, Zed, Discord clients, yazi, mango and a dozen more from
one place, following its wallpaper.

[0034](0034-colour-follows-the-mode-artefacts-do-not.md) deliberately shaped
this repo's four runtime links to keep that a **toggle rather than a redesign**:
`kitty/current-theme.conf` is exactly the name noctalia's kitty hook writes, and
`foot/themes/noctalia` is exactly the path its foot hook greps for. The names
were chosen so the two systems could meet.

Two objections were recorded then and stand:

- **`foot/themes/noctalia` would have two writers.** `apply_theme` links it per
  mode; noctalia's foot template writes it. The mode switch is the last writer,
  so it wins — but that is a race resolving in our favour, not a decision.
- **Wallpaper-derived colour is ungated by construction.** The contrast floors,
  the per-consumer accent spellings and the drift ceiling that
  [0034](0034-colour-follows-the-mode-artefacts-do-not.md) added all go blind
  for anything a template writes. Every assertion in
  `checks/static.sh` reads generated files; a template writes at runtime.

The plan that survived those two was to enable a **restricted set** — the
templates that are hookless, or whose hook is guarded — and named it as kitty,
zed, qt, helix and discord. Three were already excluded on their hooks alone:

| Template | Hook behaviour | Verdict |
|---|---|---|
| GTK | `gtk-refresh.py` detects a "read-only symlink (e.g. NixOS)" and **unlinks `gtk.css`, writing a local copy** | un-manages the path |
| mango | `cp --remove-destination` over read-only symlinks; strips colour vars from every top-level `*.conf` | fights `colors-<mode>.conf` |
| yazi | `sed -i` on `theme.toml`, which **is** a home-manager symlink | conflicts with `flavors.scheme` |

Those three are the interesting failure, and it is this repo's signature bug
wearing upstream's clothes: nothing crashes. The config is replaced by a
writable local copy, the app still starts, and the repo has quietly stopped
owning the file. The next `nixos-rebuild switch` does not restore it and does
not complain.

## What the measurement found

Measured 2026-08-20 against
`/nix/store/x4fkw5z8hhg4i0csziiyki7hskzpm1p9-noctalia-shell-4.7.7` — the live
one, whose `Assets/Templates` is byte-identical to the path the earlier note
read — and against the running system. The reserved "safe" set is **empty**.
Every member of it is either a second writer on a path
[0034](0034-colour-follows-the-mode-artefacts-do-not.md) gave one owner, or
writes a file nothing on this machine reads:

| Template | Writes | Why it is not safe here |
|---|---|---|
| kitty | sidecar `kitty/themes/noctalia.conf`, then hook `ln -sf themes/noctalia.conf current-theme.conf` | **second writer on link path 1.** The hook refuses to edit an unwritable `kitty.conf` — that is what "safe" meant — but it writes `current-theme.conf` regardless, which is `apply_theme`'s |
| foot | sidecar **is** `foot/themes/noctalia` | **second writer on link path 2**, at the sidecar, before any hook |
| zed | `zed/themes/noctalia.json` | inert. `programs.zed-editor` sets `theme.dark`/`.light` from the theme file ([0032](0032-the-theme-file-owns-its-artefacts.md)) — currently `Gruvbox Dark`/`Gruvbox Light`. Nothing ever selects `noctalia` |
| qt | `qt{5,6}ct/colors/noctalia.conf` | inert. `qt6ct.conf` has `color_scheme_path=…/style-colors.conf` and `style=kvantum-dark`; the palette comes from Kvantum, not from `colors/` |
| helix | `helix/themes/noctalia.toml` | inert. helix was removed ([0027](0027-one-editor-nvim.md)); there is no `~/.config/helix` |
| discord | `equibop/themes/noctalia.theme.css` | inert. `apply_theme` sets `enabledThemes` to exactly `["<mode>.theme.css"]`, and the mode names are `tiling` and `noctalia` — this repo already generates `equibop/themes/noctalia.theme.css` itself, so the template would **overwrite a generated file with an unaudited one under the same name** |

The last row is the sharpest. `equibop/themes/noctalia.theme.css` is a
home-manager symlink into the store *today*, because `noctalia` is a mode name
and every mode gets a generated Equibop theme. The template's output path is
that string. Enabling `discord` aims a runtime writer at a generated path whose
collision is pure coincidence of naming.

## Decision

**`templates.enableUserTheming = false` and `activeTemplates = [ ]`, and that
is not provisional.** noctalia gets its own palette from `predefinedScheme`,
which `modules/home/modes.nix` supplies and `checks/static.sh` asserts. It
themes its own shell and nothing else.

**The four link names in
[0034](0034-colour-follows-the-mode-artefacts-do-not.md) keep their spelling.**
They were chosen for compatibility with a feature now declined, so the reason to
keep them has changed: `themes/noctalia` and `current-theme.conf` are now simply
the names, load-bearing in `apply_theme` and in `mode-theme.nix`'s seed, and
renaming them buys nothing. Do not rename them to "clean up" — the seed, the
links and the check all agree on these strings, and foot does not start without
its one.

**The pin is asserted, not merely written.** `checks/static.sh` now reads the
generated `settings-pinned.json` and fails if `enableUserTheming` is true or
`activeTemplates` is non-empty.

## Consequences

- **Nothing on screen changes.** The pin has been in place since the settings
  file was generated; this records why and stops it drifting.
- **A flip is now a build failure, not a surprise.** That is the point: the
  symptom of enabling these is not an error but two writers on kitty's and
  foot's colours, and — for GTK, mango and yazi — a store symlink silently
  replaced by a local file. A check is the only thing that catches a class of
  failure whose signature is "everything still works".
- **The assertion is deliberately blunt.** It refuses *any* non-empty
  `activeTemplates`, not a blocklist of the harmful ones. A blocklist would need
  updating every time upstream adds a template, and would pass by finding
  nothing when a name changed — the failure mode every floor in
  `checks/static.sh` is shaped to avoid. Enabling one later means editing the
  check, which is where the reasoning above is one link away.
- **This is reversible, and the cost of reversing it is stated.** To enable a
  template, the app must first have **no other owner here** — not "a guarded
  hook". `zed`, `qt` and `discord` fail that test today not because they are
  dangerous but because this repo already themes those three from the palette,
  and a second source of colour that no check can see is exactly what
  [0028](0028-one-palette-reaches-every-config-it-can.md) exists to prevent.
- **`DESIGN-per-mode-theming.md` is deleted.** It was an untracked scratch note
  carrying these measurements between sessions; they are here now.

Two negative tests before it landed: `enableUserTheming = true` with
`activeTemplates = [ ]`, and `activeTemplates = [ "kitty" ]` with
`enableUserTheming = false`. Both were caught, each naming which half was wrong.
A check that has never failed proves nothing.

**The second test also exposed a pre-existing quirk in a neighbouring scan.**
The settings-key check walks every leaf path in `settings-pinned.json` and
asserts noctalia has that key; a non-empty list of strings yields
`templates.activeTemplates.0`, which is an *element*, not a key, so it reports a
mismatch for a setting that is perfectly valid. Inert today — every list in the
pin is empty — and left alone rather than fixed blind, because the honest fix is
to stop descending into arrays and that wants its own test. Worth knowing before
adding any list-valued setting to the pin.
