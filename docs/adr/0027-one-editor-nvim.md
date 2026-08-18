# 0027 — One editor: nvim. Helix is removed

**Status:** Accepted (2026-08-17)

Amends [0009](0009-generated-config-over-linked-files.md), which listed
`helix/themes/gruvbox.toml` among the configs deliberately left as files, and
[0007](0007-language-servers-declared.md), which declared language servers for
two editors rather than one.

## Context

Helix was a second editor, kept because it was cheap: `programs.helix` was
`enable`, one `theme` setting, and a Python language-server override. The theme
was a 264-line file, and 0009 recorded the reason it stayed one — a colour
scheme is data, and transcribing it into Nix attrsets risks a silent typo for
no gain.

Cheap to *declare* is not the same as free. Carrying it cost:

- **A second answer to every editor question.** `docs/gotchas.md` and
  `docs/SYSTEM.md` both had to say which editor a fact applied to. Two of those
  facts were live rough edges: helix had no Python type checking (its defaults
  are `ty`, `ruff`, `jedi-language-server`, `pylsp`, none of which is the
  declared `pyright`), and its binary is `hx`, so the desktop entry worked while
  typing `helix` did not.
- **A palette that could not follow the others.** The theme file was one of
  twelve independent copies of Gruvbox in this repo, and one of the two that
  [0009](0009-generated-config-over-linked-files.md) had explicitly declined to
  derive from `modules/home/palette.nix`.
- **`$EDITOR` was never in doubt.** It is `nvim` — git, `sudoedit`,
  `systemctl edit`, lazygit and yazi all open it. Helix was a second option that
  nothing routed to.

## Decision

**Remove helix.** `programs.helix` and its `xdg.configFile` entry are gone from
`modules/home/programs.nix`, and `dotfiles/helix/` is deleted. nvim is the
editor; zed remains for the cases it is better at.

**The language servers all stay.** Every one of them was reachable from nvim;
none existed only to serve helix. The comments in `modules/home/packages.nix`
that explained a server in terms of helix's defaults now explain it plainly.

**`delve` is the one exception worth naming.** Its comment recorded that helix
has built-in DAP and is preconfigured for it — and nvim has no dap config at
all, so nothing now drives `dlv` from an editor. It is kept as a standalone CLI
debugger, deliberately, and the comment says so rather than leaving the next
reader to rediscover that the package's stated consumer is gone.

## Consequences

- **`hx --health <lang>` is gone, and it was the best audit tool here.** One
  line per language with `✘` against anything missing — a real instance of this
  repo's "verify by output" rule, in the area where silent absence bites most
  (0007 exists because six servers were missing and nothing said so). The
  replacements are the `command -v` loop in `docs/gotchas.md` → Editors and
  `:checkhealth lsp`. Both must be read by output; neither is as terse. This is
  a genuine loss, recorded rather than glossed.
- **The palette's unreachable set shrinks by one.** Helix's theme was one of the
  two files 0009 declined to generate. What is left in that category is yazi's
  `noctalia.yazi` flavor.
- **nvim's colours are reachable after all.** The reason nvim looked
  unconvertible was that its scheme comes from the `gruvbox.nvim` plugin rather
  than a file here. The plugin exposes `palette_overrides`, a flat
  `{ name = "#hex" }` table, which is the shape `palette.nix` already has — so
  the surviving editor can be driven from the same palette as the terminals.
  Not done in this change.
- **Nothing else referenced it.** No mango window rule, no keybind, no mimetype,
  no shell alias, and no check in `checks/static.sh`. The removal is confined to
  `programs.nix`, `packages.nix` comments, and documentation.
