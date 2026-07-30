# Neovim config

Minimal, hand-rolled config built on [lazy.nvim](https://github.com/folke/lazy.nvim).
Replaced a LazyVim install (57 plugins → ~18). No mason: language servers come
from `$PATH`. Every file here is small and meant to be edited directly.

## Layout

```
init.lua                  entry point (loads the modules below)
lua/config/
  options.lua             vim options (indent, ui, search, persistence)
  keymaps.lua             global keymaps (windows, scroll-center, knap)
  autocmds.lua            yank-highlight, prose spell/wrap, mkdir-on-save, cursor restore
  lazy.lua                lazy.nvim bootstrap + setup
lua/plugins/
  colorscheme.lua         gruvbox (transparent)
  treesitter.lua          syntax (master branch)
  lsp.lua                 native LSP (nvim-lspconfig + vim.lsp.enable)
  completion.lua          blink.cmp
  coding.lua              mini.pairs ($$ math), mini.icons, conform (format-on-save)
  editor.lua              gitsigns, flash, which-key, snacks (picker/explorer)
  ui.lua                  lualine, render-markdown
  writing.lua             knap, vimtex, typst-preview
  ai.lua                  copilot.lua (ghost text, accept = Alt-l)
scripts/                  knap converter + zen browser wrapper (preserved)
spell/                    your custom dictionary (preserved)
```

## Install the language servers / tools

A server with no binary on `$PATH` is silently skipped, so install only what you
use. Already present on this machine: `rust-analyzer`, `clangd`, `rustfmt`, `live-server`.

```sh
# Official repos
sudo pacman -S --needed lua-language-server pyright ruff texlab \
  yaml-language-server taplo marksman stylua shfmt

# Node servers (npm)
sudo npm install -g typescript typescript-language-server bash-language-server

# AUR (typst LSP + preview server) — use your AUR helper
paru -S tinymist            # or: cargo install tinymist
```

If a name isn't in the repos on your box, check the AUR (`*-bin` variants are common).

## Key bindings (beyond Neovim 0.11 defaults)

`<leader>` is Space. 0.11 already provides `grn` rename, `gra` code action,
`grr` references, `gri` implementation, `K` hover, `[d` / `]d` diagnostics.

| Key | Action |
|---|---|
| `<leader><space>` | smart file picker |
| `<leader>ff` / `<leader>fg` | find files / grep |
| `<leader>fb` `<leader>fr` `<leader>fh` `<leader>fk` | buffers / recent / help / keymaps |
| `<leader>e` | file explorer |
| `<leader>gg` | lazygit |
| `gd` `gD` `gy` | goto definition / declaration / type def |
| `<leader>cf` | format buffer |
| `<leader>cd` | line diagnostics |
| `<leader>ks` `<leader>ka` `<leader>kc` | knap preview once / toggle / close |
| `<leader>tp` | typst preview toggle |
| `<leader>um` | toggle markdown render |
| `s` / `S` | flash jump / treesitter jump |
| `]h` `[h` `<leader>g{h,r,p,b}` | git hunks (next/prev/stage/reset/preview/blame) |
| `<M-l>` | accept Copilot suggestion |

## Rollback

The old config and plugin data were backed up, not deleted:

```sh
rm -rf ~/.config/nvim
mv ~/.config/nvim.bak.<timestamp> ~/.config/nvim
rm -rf ~/.local/share/nvim
mv ~/.local/share/nvim.bak.<timestamp> ~/.local/share/nvim
```

Once you're happy, reclaim the space: `rm -rf ~/.*/nvim.bak.* ~/.local/share/nvim.bak.*`
