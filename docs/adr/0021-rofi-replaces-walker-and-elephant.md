# 0021 — rofi replaces walker and elephant

**Status:** Accepted (2026-08-14), **amended 2026-08-21 — the launcher moved to
rofi too** ([0043](0043-the-launcher-is-rofis-drun.md))

Supersedes [0019](0019-elephant-builds-only-reached-providers.md) (elephant
builds only the providers something reaches). Follows
[0005](0005-one-owner-per-daemon.md) (one owner per daemon) and
[0014](0014-declare-the-namer-not-just-the-file.md) (declare the namer, assert
reachability both ways).

## Context

The menu layer here was **walker** (the window) over **elephant** (a daemon
serving providers). Nine scripts and four keybinds went through it. Two things
about that arrangement were only discovered by measuring it.

**walker 2.x cannot draw a window without elephant, and does not say so.**
Tested with the walker daemon up and only elephant killed: `walker -d` **exits
0, prints nothing, and opens no window**. Not an error, not a log line — from
the keyboard it is indistinguishable from having pressed Escape, and from a
script it is indistinguishable from the user cancelling, because every caller
here reads a cancel as `|| exit 0`. The control run with elephant up exits 124,
because the window is still open when the timeout fires. So a 546 MB daemon was
load-bearing for a mode picker, and its absence was silent — this repo's
signature failure, in the one component that mediated nine others.

**The cost was 427 MB resident for two menus.**

| | store | RSS |
|---|---|---|
| elephant | 546 MB | 305 MB |
| walker | 8.2 MB | 122 MB |
| **rofi** | **256 KB** | **none — no daemon** |

And [0019](0019-elephant-builds-only-reached-providers.md)'s central prediction
did not hold. It recorded 295 MB RSS at 25 providers and reasoned that resident
memory would fall with the number of plugins `dlopen`ed. Measured on
2026-08-14 after the trim: **305 MB at 15 providers.** The store path did fall,
807 → 546 MB, exactly as recorded. The resident set did not move at all. That
was the deciding number: the remaining 546 MB could not be cut further by the
same technique, because the technique had already been shown not to touch RSS.

Against that, the inventory of what was actually used: of walker's nine
prefixes, **two** — `=` calc and `.` symbols. `@` websearch, `/` files, `!`
todo, `%` bookmarks, `$` windows, `>` runner and `;` providerlist were reached
by nothing but curiosity, and `$` windows is already covered twice over by
`ALT+Tab` toggleoverview and noctalia's `>win`.

`rofi` was **already in `modules/system/desktop.nix` and invoked by nothing** —
Arch carryover, installed and forgotten, along with two `layer_name:rofi`
animation rules in `universal/rule.conf` that had never matched anything.

## Decision

**Replace walker and elephant with rofi. No daemon, no provider backend, and
the launcher stays where it was.**

`fsel` keeps `SUPER+space` (**no longer true — [0043](0043-the-launcher-is-rofis-drun.md)**);
noctalia mode keeps its own launcher. rofi is the
**menu** layer only — `-dmenu` for the nine scripts, and two plugin modes for
the two prefixes that were used.

Plugins go through the wrapper, not the package list:

```nix
(rofi.override { plugins = [ rofi-calc rofi-emoji ]; })
```

nixpkgs `rofi` is a `symlinkJoin` over `rofi-unwrapped` that adds
`-plugin-path` pointing into its own `lib/rofi`. Listing `rofi-calc` as a
separate `systemPackages` entry therefore drops a `.so` into a directory rofi
never looks in — `-show calc` then prints `Mode calc is not found` to a stderr
nobody reads and exits 1, which is a dead key. `rofi-rbw` is **not** a plugin
but a standalone front-end over `rbw`, so it stays an ordinary package.

The four `-m` binds resolve as: `providerlist` deleted (meaningless without
elephant), `bitwarden` → `rofi-rbw`, `clipboard` → `cliphist list | rofi -dmenu`
(cliphist has been storing all along; walker's provider was only ever a reader
of it), `bluetooth` → `menus/bluetooth-menu.sh`, **which already existed,
hand-written, bound to nothing** — the elephant provider had quietly displaced
it. The same script and `menus/volume-menu.sh` take over the two waybar clicks.

### One config, and something asserts it is reachable

walker needed a config per mode, symlinked into place by each
`autostart.conf` — a generated path that was simultaneously tracked in git,
which is what broke activation on 2026-07-31. rofi has one
`~/.config/rofi/config.rasi` for every mode, so that whole class is gone along
with the `.gitignore` rule and one of the three per-mode files
`checks/static.sh` was asserting.

What replaces 0019's provider check is narrower and stronger, because it reads
the **built binary** rather than the Nix that asked for it:

- `rofi -no-config -h` lists `Detected modes` — exactly what `dlopen` succeeded
  on, so a plugin that builds but fails to load is caught, which the old check
  could not do;
- every mode named by `config.rasi`'s `modes:` or by a `rofi -show <x>` in the
  mango tree must be in that list;
- every `rofi-<x>` in the `plugins` list must be both loaded and reached, or it
  is 700 KB nothing points at.

Reading either list as empty **fails**, per [0011](0011-shell-is-gated-too.md).
Both directions were negative-tested before this was written.

### The theme is derived, not transcribed

The 337 lines of tuned Gruvbox GTK CSS under `walker/themes/` do not port —
rasi is a different language, not a dialect. The first cut imported rofi's own
shipped `gruvbox-dark` on the theory that a gruvbox is a gruvbox. **It is not.**
Seen against the running system it disagreed with every convention this desktop
has: 2px borders against `tiling.conf`'s `borderpx=1`, an `#a89984` border
matching nothing here, `#665c54` selection where the terminals use `#504945`,
and alternate rows striped `#32302f` where nothing else stripes at all.

So `config.rasi` carries the **shape** — square, 1px, flat, one accent — read
off `tiling.conf` and `style-solid.css` rather than invented, and the
**colours** come from `modules/home/palette.nix`, generated into a sibling
`colors.rasi` that it `@import`s. Same split the bar already had: rules by
hand, palette derived. `waybar/colors.css` moved onto the same source in the
same change, so one file now defines every colour on this machine.

One rofi-specific trap is worth stating, because it is invisible until it
fires: **overriding widgets is not enough, you must override the roles.** A
widget with no rule of its own resolves through rofi's built-in role variables,
and those are *Solarized light* — `urgent-background` is `#fdf6e3`. Styling
`element selected` and stopping leaves cream-on-teal waiting in every state
nothing has exercised yet. `rofi -dump-theme` is the check: nothing in the
output should still read `var(lightbg)`, `var(blue)` or `var(red)`.

`checks/static.sh` asserts the palette both ways, per
[0014](0014-declare-the-namer-not-just-the-file.md) — every generated colour is
referenced by a stylesheet, and every `@name` a stylesheet references is
defined. Both halves fail silently otherwise: GTK drops a rule naming an
undefined colour and renders the module in whatever it inherited, and rofi
falls back to the built-in role.

`no-custom` is set **per call**, not globally, and that is not a style
preference: rofi has no negation for it. `-no-no-custom` is accepted, ignored,
and exits 0 — so a global setting could not be lifted for the one prompt in
`menus/network-menu.sh` where the typed string *is* the answer.

## Consequences

- **427 MB resident and ~554 MB of store path go away**, and there is one fewer
  daemon whose absence looks like a working system.
- **rofi comes from the binary cache again** — but only until the override.
  `rofi.override { plugins = ... }` is a different derivation, so it builds from
  source on a version bump. It is a small C build, unlike elephant's fifteen Go
  plugins.
- **The palette is now one file for the whole machine.** That was not the goal
  of this change and is its most useful side effect: adding rofi would have
  made a fourth copy of the same sixteen hex codes, which forced the question.
  `modules/home/palette.nix` feeds the terminals, the bar and the menus; the
  generated `colors.css` came out byte-identical to the hand-written one it
  replaced, so the unification is provably a no-op for what was already there.
- **Sizing moved from the caller to the theme.** Every walker call carried a
  `--maxheight` that had to be re-guessed when a menu grew an entry;
  `listview { dynamic: true; }` shrinks to fit, so a three-item menu is three
  items tall on its own. hud mode no longer gets a narrower launcher — walker's
  wrapper injected that, and one theme now serves all three modes. If it is
  wanted back it is one `-theme-str` in the hud branch, not a wrapper script.
- **rofi's widget tree is opt-out, not opt-in.** Naming `mainbox`'s children
  removes the ones you did not name, and rofi-calc's live preview draws through
  the `message` widget — so pinning that list turned the calculator into a
  press-Enter-and-hope box with nothing logged. Verified live after the fix by
  screenshotting `rofi -show calc -filter '17*24'`; see `docs/gotchas.md`.
- **`=` and `.` became real keys.** They were reachable before only by typing
  into walker's main window, which **no bind opened** — they were one `walker`
  invocation away from being unreachable already. They are now `SUPER+equal`
  and `SUPER+semicolon` (`SUPER+period` is `focusmon`).
- **`websearch`, `files`, `todo`, `bookmarks`, `windows` and `runner` are
  gone.** Not ported, not stubbed. `rofi -show run`/`drun` and `filebrowser` are
  built in if any of them is missed.
- **0019 is superseded, not deleted.** Its measurement — that trimming plugins
  cuts store size and does not touch RSS — is the reason this record exists.
