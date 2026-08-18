# 0030 — The scheme is a file, not an option; and contrast is asserted

**Status:** Accepted (2026-08-18)

Follows [0028](0028-one-palette-reaches-every-config-it-can.md) (one palette
reaches every config it can) and [0029](0029-the-lock-ramp-asserts-hue-not-greyness.md)
(the ramp follows the palette's hue). Both were prerequisites: the first made
one file own every colour, the second removed the last thing that hardcoded a
property of one particular scheme.

## Context

Changing scheme meant editing `palette.nix` in place, so the machine could wear
exactly one and switching back meant a revert. The obvious fix is a
home-manager option — `local.theme = "mocha"` — and it does not work.

`pkgs/default.nix` builds the lock-background pool, and it reads the palette by
`import ../modules/home/palette.nix`. It is an **overlay**: it is applied to
nixpkgs before any module evaluates, and it cannot see `config.*`. An option
would have reached twelve consumers and not the thirteenth — and the one it
missed is the lock screen, the surface with nothing beside it to compare
against, which is precisely where a stale colour goes unnoticed. That is the
failure 0029 was written about, reintroduced by a different route.

Separately, the migration in
[0029](0029-the-lock-ramp-asserts-hue-not-greyness.md)'s commit shipped a
scheme that was hard to read, and every gate passed. `THEME-MIGRATION.md` §4
said so in as many words — *"what it does not catch: whether the new colours are
legible"* — and the gap behaved exactly as this repo's failures do: each colour
was individually plausible, so the result read as a considered choice rather
than a mistake.

## Decision

**The scheme is `modules/home/scheme.nix`: a file containing a string.**

`palette.nix` becomes a dispatcher, `import ./themes/${import ./scheme.nix}.nix`,
and its *interface* is unchanged — still a flat `rec` attrset of bare hex. Every
consumer, and the overlay, reads it exactly as before. Adding scheme selection
touched no consumer, which is the property that made it worth doing this way.

A file rather than an option because a file is what both sides of the
module/overlay boundary can `import`. The typed-enum benefit is not lost: `rec`
makes a missing key an eval error, and a scheme name with no matching file is a
"file not found" before anything builds.

**And contrast is now asserted, per theme.** `checks/static.sh` recomputes WCAG
relative luminance for every text-bearing role on each run — thirteen against
`bg0`, five against ncspot's own raised surface, because ncspot fills whole rows
with it and `bg0` is the wrong reference there.

The floor is declared *by the theme* rather than fixed globally. Upstream
Catppuccin Mocha does not reach WCAG AA on its greys — `brBlack` is 4.44:1 — so
a global 4.5 floor would make it impossible to ship Mocha *as Mocha*. Stating
the weak number in the file is more honest than quietly raising it, and the
assertion still catches any later edit that dims it further. A hard minimum of
3.0 stops the floor being declared away.

## Consequences

- Switching scheme is one line and a rebuild. Switching *back* is the same,
  which it was not before.
- **The check found a real defect on its first run.** `mocha`'s ncspot
  secondary text sat at 3.13:1, below even its own declared floor. That value
  was this repo's derivation rather than Catppuccin's, so lifting it cost no
  fidelity — but nothing had ever looked at it.
- Two things the palette did not name turned out to be escaping it, both found
  by asking the running editor rather than reading the theme: nvim paints
  `Comment` with `overlay2`, and NonText/Conceal/FoldColumn with `overlay1`.
  A first pass assumed `overlay0` and was wrong. The palette gains a `comment`
  role; **the lesson is that "which colour does this program actually use" is a
  measurement, not a reading.**
- What this does **not** switch is the six theme packages (GTK, icons, cursor,
  Kvantum, noctalia, yazi). Both current schemes are Catppuccin-hued and share
  them, so per-theme package fields would be machinery with no consumer — the
  thing `THEME-MIGRATION.md` §1 warns against for colours, applied to packages.
  A scheme from another family needs them moved, and that is the next commit,
  not this one.
- Cost: two files where there was one, and a theme file must supply every key
  the others do. That is the same constraint `rec` already imposed, now spread
  across a directory.
