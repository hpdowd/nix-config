# 0007 — Language servers are declared, not installed per-editor

**Status:** Accepted (2026-07-30)

## Context

Neither editor here ships language servers. Neovim is deliberately **mason-free**
and takes servers from `$PATH`; Helix only *configures* servers it expects to
find there. Both therefore depend on something else installing them.

On Arch that something was `pacman`, plus a little AUR and `npm -g`. None of it
survived the migration, and **nobody noticed for a day**, because a missing
server is skipped in silence — no error, no warning, just no completions. LSP
for Nix, Lua, Python, LaTeX, TOML, YAML, Markdown and shell was dead the whole
time; `rust-analyzer` happened to still be present, which made things look
partly fine.

It surfaced only when `hx --health` was run and showed `✘` against every
language but Rust. The nvim docs meanwhile still said to install them with
`pacman`, and listed `clangd` and `live-server` as present when neither was.

The instinct at that point — "nvim has become bloated, move to helix" — would
not have helped. Helix shares the same `$PATH` dependency and would have felt
equally dumb.

## Decision

Language servers are ordinary packages in `modules/home/packages.nix`, declared
once and shared by every editor.

Declared 2026-07-30: `nil`, `lua-language-server`, `bash-language-server`,
`marksman`, `taplo`, `yaml-language-server` — chosen to match what this repo is
made of. Deliberately not added: `pyright`, `ruff`, `texlab`, `tinymist`,
`stylua`, `shfmt`, `clangd`.

## Consequences

- Servers are reproducible and version-pinned with everything else.
- **`hx --health` is the audit tool**, even with Helix unused — one line
  per language, `✘` against anything missing. Nothing else surfaces this.
- `npm install -g` is not an alternative: it writes into a home directory the
  flake does not manage and will not reproduce.
- `clangd` ships in `clang-tools`, not `clang` — a trap here, since `cc` is
  already clang.
- Adding a language to an editor's config is only half the job; the server has
  to be declared too, or the feature silently does not exist.
