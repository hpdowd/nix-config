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

### Phase 1 — cursor

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

**Open:** whether `special` should be `infoColor` or `warnColor`. Upstream maps
it per-cursor from a `special_map` (help → blue, copy → green, not-allowed →
red), which is more considered than one role. Reproducing that map is ~20 lines
and worth it.

---

### Phase 2 — Kvantum

A Kvantum theme is an INI `.kvconfig` holding explicit colour keys, plus `.svg`
frame art that is near-monochrome in the themes worth basing on. The keys are
generatable; the art is reused unchanged across palettes.

`modules/home/dotfiles.nix` already generates `Kvantum/kvantum.kvconfig` (which
names the theme) and manages it as a **file**, leaving the directory writable —
so the shape this phase needs already exists and the two-owners trap
(`docs/adr/0002`) is already avoided here.

**Steps**
1. Pick the base for its SVG, not its colours — the flatter and more monochrome
   the frame art, the better it survives an arbitrary palette.
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

### Phase 3 — GTK

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

- **Build cost, unmeasured.** 68 SVGs × 6 sizes through `resvg`, plus `sassc`
  over Colloid, per scheme in service, on every `nix flake check` that misses
  cache. Measure after phase 1 and record it here; if it is minutes, the
  generators may need to be flake outputs built once rather than closure inputs.
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
