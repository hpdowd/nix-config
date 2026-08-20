# Plan — generate the artefact half from the palette

**Live working file.** The decision is `docs/adr/0041`; this is how it lands.
Delete it when it empties.

Written **2026-08-20** against `main` @ `1de8aa3`. Every fact below was measured
today against the pinned nixpkgs and the live upstreams, not read off
documentation.

**Goal.** A scheme change is one line in `modules/home/scheme.nix` and a
rebuild, and it reaches the cursor, the Kvantum widget art and the GTK theme —
which today it does not. The motivating scheme is `heartbox`, and it is
deliberately the **last** step.

**The one rule that shapes every phase.** A substitution that stops matching
produces a valid, complete, unrecoloured artefact. The build succeeds, the name
resolves, the existing "does this directory exist" check passes, and the cursor
is still someone else's purple. So every generator ships three assertions
together, in the same commit as the generator:

1. **No sentinel survives** — grep the generated tree for the source's
   placeholder values, expect zero.
2. **A floor on the count of files changed** — 68 SVGs, 35 SCSS variables. Zero
   matches is the pass state everywhere else in `checks/static.sh`, so it must
   not be the pass state here.
3. **`--replace-fail` on every upstream name relied on**, as
   `pkgs/default.nix` already does for noctalia's mango backend
   (`docs/adr/0025`).

---

## Phases

### Phase 1 — cursor ✅ done 2026-08-20

**Landed.** `paletteCursors` in `pkgs/default.nix`; all four theme files take
their cursor from it; two new assertions in `checks/static.sh`. Built against
`gruvbox` and looked at.

| | |
|---|---|
| Build | **18 s**, 12 MB — the open question below is answered, and the answer is that it does not matter |
| Gate | `nix flake check` 74 s, all checks passing |
| Output | 46 cursors + 74 alias links, from 68 source SVGs (`progress` and `wait` are 12 frames each) |

**Two failures found by building it, both of the class this repo is named for:**

- **`grep` exits 1 when it matches nothing, which is the PASSING case** for the
  "no sentinel survived" assertion — and stdenv runs the build under
  `set -eo pipefail`. The check killed the build precisely when it succeeded,
  with no output whatsoever. Every grep in that derivation now ends `|| true`,
  and says why.
- **`index.theme` was missing from the output.** Upstream copies it in its
  *outer* `build` script, not the `scripts/build-cursors` this repo calls — and
  that one `rm -rf`s its output directory first. The result passed the existing
  artefact check (which only looks for the directory by name) while resolving to
  nothing in GTK and wlroots. Now copied, asserted in the derivation, and
  asserted again in the gate.

**Four negative tests, all failing with the right message:** upstream art
changed (sentinel count), a substitution that stops matching, `index.theme`
removed, and an artefact wearing another palette's colours.

The original notes follow.

The cheapest and the most verifiable, which is why it goes first.

`catppuccin/cursors` v2.0.0 carries `src/svgs/` — **68 SVG files**, art from
Volantes by way of KDE Breeze — in which every colour is one of three sentinel
hexes:

| Sentinel | Role | Take from |
|---|---|---|
| `FF0000` | inner fill | `accent` |
| `00FF00` | border | `base` |
| `0000FF` | special (help, copy, progress, …) | `infoColor` |

Recolouring is a three-way string replace. Upstream reaches it through
`whiskers` and three `.tera` templates; **we skip that layer** — it exists to
resolve *Catppuccin flavour names*, which we do not have, and it would put a
scheme name on a boundary for nothing.

Hotspots are a hidden `<path id="hotspot">` in each SVG, which is why the
assembly step cannot be hand-rolled from `xcursorgen` alone.

**Steps**
1. `pkgs/default.nix`: `fetchFromGitHub` catppuccin/cursors at a pinned rev,
   for `src/svgs/` and `src/cursorList` only. **Check the licence on the art
   before anything else** — Volantes and Breeze are permissive, confirm it.
2. Substitute the three sentinels from `modules/home/palette.nix`. Not a
   `sed -i` over the tree — a per-file replace whose *changed-file count* is
   returned, so assertion 2 has something to count.
3. Render with `resvg` (pure Rust, already in nixpkgs, far faster than
   `inkscape` for 68 × 6 sizes).
4. Assemble with `clickgen`'s `ctgen`, which reads hotspots itself.
5. Generate `index.theme` from the scheme name.

**Verify**
- `grep -rl 'FF0000\|00FF00\|0000FF'` over the generated SVGs returns nothing,
  and the substitution reports exactly 68 files changed.
- The theme resolves where `checks/static.sh:1723`'s existing artefact check
  looks — `$GEN/home-path/share/icons` — with `find -L`, which is load-bearing
  there for the reason that check documents.
- **Look at it.** `hyprcursor`/X11 cursors at 24px are where a bad `accent`
  choice shows up, and nothing automated sees it.

**Settled:** upstream's per-cursor `special_map` was reproduced rather than
collapsing it to one role — help → `infoColor`, copy → `okColor`,
not-allowed → `errColor`, progress and wait → `accent`. Ten entries and a
default.

**Also settled:** the body is `fg0` over a `base` outline, not `accent`.
That keeps phase 1 a change of where the colour comes FROM rather than a change
of look, which is what made it judgeable against the capitaine cursors it
replaced. `inner = p.accent` in `pkgs/default.nix` is the bolder alternative.

---

### Phase 2 — Kvantum ✅ done 2026-08-20

**Landed.** `paletteKvantum` in `pkgs/default.nix` plus
`pkgs/kvantum-recolour.py`; all four theme files take their Kvantum theme from
it; three new assertions in `checks/static.sh`. Build: **7 s**.

**The base was chosen by measurement, and the plan's guess was wrong.** This
file assumed the art would be "near-monochrome in the themes worth basing on".
`gruvbox-kvantum`, the theme actually in service, is **31 colours** of somebody
else's gruvbox — not monochrome at all. So all 37 themes Kvantum ships were
counted:

| | distinct colours | size |
|---|---|---|
| **KvantumAlt** | **21** — 18 of them exact greys | 25 KB |
| every other theme | 39–97 | 75–182 KB |

KvantumAlt is achromatic, so it has a lightness ramp and nothing else, and a
lightness ramp maps onto this palette's own `mantle`→`fg0` axis without
inventing a single relationship. The base is chosen for being greyscale, not
for being pretty.

**Not pinned by rev**, unlike phase 1 — the source is nixpkgs' own Kvantum,
which moves on `nix flake update`. So the assertions are a floor plus a
notation test rather than an exact count: a bump that retouches the art must
not break the build, and a substitution that stops working still must.

**The find: an assertion that could not fail was hiding a real bug.** The first
version checked that every colour in the output was one the run had produced —
a subset test on a set built from the same regex, so it was true by
construction. Asking what it could actually catch turned up **eight
three-digit colours** (`fill:#fff`, `#555`, `stop-color:#fff`) that a
six-digit regex skips in silence, leaving pure white highlights in a theme with
no white in it. Both the generator and the gate now handle the short form, and
the assertion was replaced with one that tests for colour notations the script
cannot express.

**Five negative tests, all failing with the right message:** the recolour regex
rotting, an unhandled notation appearing upstream, the base theme moving out of
the package, Kvantum renaming a `[GeneralColors]` key, and an unrecoloured grey
reaching the generation.

The original notes follow.


A Kvantum theme is an INI `.kvconfig` holding explicit colour keys, plus `.svg`
frame art that is near-monochrome in the themes worth basing on. The keys are
generatable; the art is reused unchanged across palettes.

`modules/home/dotfiles.nix` already generates `Kvantum/kvantum.kvconfig` (which
names the theme) and manages it as a **file**, leaving the directory writable —
so the shape this phase needs already exists and the two-owners trap
(`docs/adr/0002`) is already avoided here.

**Steps**
1. Pick the base for its SVG, not its colours — the flatter and more monochrome
   the frame art, the better it survives an arbitrary palette. *(Done by
   counting distinct colours across all 37 shipped themes; KvantumAlt won by a
   factor of two.)*
2. Generate `<scheme>.kvconfig` from the palette; copy the base `.svg`.
3. Install to `~/.config/Kvantum/<scheme>/`, which is where Kvantum reads —
   **not** `share/Kvantum`. `checks/static.sh`'s `pkg_roots` already searches
   both and documents why.

**Verify**
- Every colour key in the generated `.kvconfig` matches a palette value; no
  literal hex survives from the base.
- Qt apps under the current scheme, by eye. `nwg-look` and `corectrl` are the
  two Qt surfaces on this machine.

---

### Phase 3 — GTK ✅ done 2026-08-20

**Landed.** `paletteGtk` in `pkgs/default.nix` plus `pkgs/colloid-palette.py`;
all four theme files take their GTK theme from it; one new assertion in
`checks/static.sh`. Build: **14 s**, 3.2 MB, both toolkits.

**No install.sh patching was needed.** `_color-palette-default.scss` is
overwritten rather than a sixth scheme added, because `$colorscheme` stays
`default` and is only ever special-cased for `dracula` — checked in
`_colors-public.scss` and both `_common-*.scss`. Adding a scheme would have
meant patching three places in `install.sh`; overwriting the default patches
none.

**The grey ramp is anchored, not interpolated end to end.** Upstream's own
`_color-palette-gruvbox.scss` was read off against `themes/gruvbox.nix` and its
stops land exactly on that palette's ramp — `$grey-150 = fg1`, `$grey-350 =
fg4`, `$grey-400 = comment`, `$grey-550..700 = bg3..bg0`, `$black = mantle`.
That is reproduced, and only the gaps between anchors are interpolated. Two of
Colloid's eight hues have no role here (`purple`, `orange`) and are blended
from the ones that do; `$pink` and `$orange` turn out to be used only by theme
variants this build does not produce, and `$purple` only by `$link-visited`.

**Renamed to `<scheme>-gtk`**, so all three generated artefacts read the same
way in a theme file. That broke the build once: nixpkgs' installPhase runs
`jdupes --link-soft` across the three size variants, so renaming left dangling
symlinks — caught immediately by nixpkgs' own `noBrokenSymlinks`, and fixed by
re-pointing rather than un-deduplicating.

**A comment was wrong and the negative test caught it.** The postInstall
assertion was written believing sassc silently drops a declaration whose
variable it cannot resolve. It does not — it stops with `Undefined variable:
"$grey-700"`. What *is* silent is the palette file being written and never
**imported**, which is what the assertion actually guards and what NEG M
demonstrates: sassc succeeds, the theme installs and resolves, and it is
Colloid's own blue.

**`gruvbox-gtk-theme` was deleted** — 61 lines of overlay that existed only
because nixpkgs' `gruvbox-dark-gtk` ships no GTK4. That stops being a
per-scheme problem once the theme is built here.

**Four negative tests:** a variable renamed upstream, the sass tree
reorganising, the generator writing a short file, and the palette compiling but
never being imported.

The original notes follow.


The largest, and better-shaped than expected. Colloid does **not** need
patching: `src/sass/` already contains one palette file per scheme —
`_color-palette-gruvbox.scss`, `_color-palette-nord.scss`,
`_color-palette-catppuccin.scss`, `_color-palette-dracula.scss`,
`_color-palette-everforest.scss` — all with identical variable names, selected
by `install.sh --tweaks <name>`.

So this is a **file addition**, not a patch of upstream internals, which
removes most of `docs/adr/0041`'s coupling concern for this artefact.

The interface is 72 lines, about 35 variables:

- **8 hue pairs** — `$red-light`/`$red-dark`, pink, purple, blue, teal, green,
  yellow, orange. Map from the palette's bright/normal ANSI pairs. `orange` and
  `purple` have no palette role and need deriving.
- **A 16-step grey ramp**, `$grey-050` … `$grey-900`. Interpolate `bg0` → `fg0`.
  `pkgs/default.nix` already builds the lock-background ramp this way; reuse
  that code rather than writing a second interpolator.

**Steps**
1. Generate `_color-palette-<scheme>.scss` from the palette.
2. Fork `colloid-gtk-theme` in `pkgs/default.nix`: drop the file into
   `src/sass/`, add the name to `install.sh`'s tweak list with
   `--replace-fail`, build with `sassc` as nixpkgs already does.
3. Keep `themeVariants`/`sizeVariants` as they are — this changes colour only.

**Verify**
- **`gtk-4.0/gtk.css` exists in the built theme.** `checks/static.sh` already
  asserts this and records why: GTK4 ignores `gtk-theme-name`, home-manager
  writes an `@import` of it, and a theme without it drops every libadwaita app
  to Adwaita *while GTK3 stays themed* — so the two toolkits merely look
  different. `gruvbox-dark-gtk` shipped exactly that.
- The generated SCSS declares all ~35 variables; a floor on the count, because
  a missing variable falls back to Colloid's default silently.
- By eye, across a GTK3 app and a libadwaita app. Thunar and nwg-look.

---

### Phase 3.5 — yazi and Zed ✅ done 2026-08-20

Not in the original plan. Both turned out to be **pure colour data**, which is
the test `docs/adr/0041` actually set, and both were blocking Heartbox: neither
publishes a Heartbox version, so leaving them named meant two artefacts that
could never follow a new scheme.

**yazi** — `pkgs/yazi-flavor.nix`, 220 lines of colour and nothing else.
`packages.yazi` is gone from all four theme files; it used to be four unrelated
upstreams pinned by rev and hash, agreeing on the schema and nothing else.
Three role assignments differ from what the fetched flavours had, and only
where upstream's pick was not a role: gruvbox put `fg0` on the notification
**warning** title and its pink on the **error** one.

*The glyph trap, exactly as `CLAUDE.md` describes it.* The powerline
separators were typed as characters and **both vanished silently** — the line
looked identical. They are `\ue0be` written literally now: a lone backslash is
not an escape in a Nix indented string, so the text reaches the TOML unchanged
and TOML resolves it, which is how upstream spells it too. Verified by parsing
the generated TOML and dumping codepoints.

**Zed** — `pkgs/zed-theme.py`, 135 style keys, 43 syntax keys, 8 players, at
exact parity with Zed's own theme (diffed both ways, nothing missing, nothing
invented — the count assertion caught one key I had made up).

*Authored from roles, not transformed from Zed's own theme.* Substituting into
Zed's Gruvbox was the obvious route and it is wrong: that file holds **63
distinct colours** for a palette with about twenty, because its values have
drifted — `#fb4a35` where gruvbox is `#fb4934`, and three different spellings
of its yellow. Mapping them back would copy somebody else's rounding into every
scheme this repo ever wears.

*This closed a hole the repo had written down as unclosable.* The theme used to
come from Zed's extension registry, and `modules/home/programs.nix` said so:
"**THE ONE PAIR NO CHECK HERE CAN GATE**" — both halves lived on Zed's servers,
so the gate could assert a name was declared and nothing more. A theme written
into the generation is gateable like everything else, and now is: it exists, it
carries the palette, and the name `settings.json` asks for is the name the
theme declares. `apps.zed` is gone from the theme files.

---

### Phase 4 — icons stay named, and the theme file says so

Decided, not deferred (`docs/adr/0041`). Upstreams parameterise only the folder
and accent hue; app icons are brand colours that must not follow a palette.

A neutral pack is the answer, and it is the **first legitimate use of
`native = false`** — the marker `modules/home/palette.nix` documents and which
nothing currently sets. `why` carries the reason.

**Verify:** `checks/static.sh` already counts and reports stand-ins rather than
passing over them. It will now report one, which is correct, and the message
should read as a decision rather than a gap.

---

### Phase 5 — `heartbox`

Only now. Flipping earlier means judging three new generators against a palette
nobody has seen on this machine, where wrong and unfamiliar are the same thing.

Heartbox is in `noctalia-dev/noctalia-colorschemes` (not in noctalia-shell
4.7.7, which ships ten schemes without it), and its source file carries a **full
sixteen-slot terminal palette** — the registry entry drops it, the file does
not. Measured on its `#1A1214` background: worst audited ANSI slot 3.87:1
(`red`), `mOnSurfaceVariant` 4.02:1.

**Steps**
1. `modules/home/themes/heartbox.nix`, transcribing upstream's values.
   `mantle` and the `muted` set are derived, as they are for every scheme.
2. Generate noctalia's `Heartbox.json` **from that file** rather than fetching
   it, so one source of truth reaches both. `ColorSchemeService.qml:67` scans
   `~/.config/noctalia/colorschemes` with `find -L … -mindepth 2`, so a managed
   *file* at `colorschemes/Heartbox/Heartbox.json` is picked up and the parent
   stays writable for noctalia's own downloader.
   - Four keys have no palette role — `mHover`, `mShadow`, `mOnPrimary`,
     `mOnHover` — and get derived. The `light` variant is generated too or the
     scheme is dark-only; decide when writing it.
   - Widen `checks/static.sh:703`, which today asserts the pinned scheme ships
     **with the package**.
3. `modules/home/scheme.nix` → `"heartbox"`, and `modes.nix` with it.
4. `nord` leaves service. Leave the file: `flake.nix:196` audits only schemes in
   service, and `nord.nix` is the worked example a `nord-high-contrast` would
   start from.

---

## Suggested order

1 → 2 → 3 → 4 → 5, each landing on its own with its assertions. **Develop 1–3
against `gruvbox`**, the scheme currently on screen — a generator judged against
a known-good reference is the only way to tell a bad mapping from an unfamiliar
one. Stopping after any phase leaves a working machine.

## Open questions

- ~~**Build cost, unmeasured.**~~ **Answered by phase 1: 18 s and 12 MB** for
  the cursor set — 68 SVGs at eleven scales through inkscape, which was the
  step expected to hurt. `nix flake check` went from 41 s to 74 s cold. No
  reason to move the generators out of the closure. Re-measure at phase 3;
  `sassc` over Colloid is the remaining unknown.
- **Whether `pkgs/default.nix` is still the right home.** It is an overlay, so
  it cannot read `config.*` — which is exactly why `scheme.nix` is a file
  (`docs/adr/0030`) and why this works at all. But it is about to grow three
  builders, and `pkgs/lock-backgrounds` is already a directory. A
  `pkgs/artefacts/` sibling is probably right.
- **`docs/THEME-MIGRATION.md` becomes mostly wrong** at phase 3 — it is a
  runbook for changing six *named* packages. Rewrite it in the same task, not
  after.
- **The stale counts in `CLAUDE.md`**: "four ship", "All four shipped schemes
  are fully native", and `palette.nix`'s "nixpkgs fully serves three of them, so
  those are the three here" — all three sentences are wrong from phase 4
  onwards.
