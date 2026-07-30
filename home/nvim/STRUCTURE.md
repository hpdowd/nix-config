# Neovim config — structural analysis

_Snapshot of the hand-rolled config at `~/.config/nvim` (Neovim 0.12.3, lazy.nvim, 18 plugin specs). Written for analysis: load order, lazy-load triggers, coupling, and external dependencies._

---

## 1. File tree

```
~/.config/nvim/
├── init.lua                  entry point — 4 requires, nothing else
├── lua/
│   ├── config/
│   │   ├── options.lua        leader keys + vim.opt settings
│   │   ├── keymaps.lua        global (non-plugin) keymaps
│   │   ├── autocmds.lua       4 autocmd groups
│   │   └── lazy.lua           lazy.nvim bootstrap + setup()
│   └── plugins/               one spec file per concern (auto-imported)
│       ├── colorscheme.lua    gruvbox
│       ├── treesitter.lua     nvim-treesitter (master)
│       ├── lsp.lua            nvim-lspconfig + native vim.lsp
│       ├── completion.lua     blink.cmp
│       ├── coding.lua         mini.pairs, mini.icons, conform
│       ├── editor.lua         gitsigns, flash, which-key, snacks
│       ├── ui.lua             lualine, render-markdown
│       ├── writing.lua        knap, vimtex, typst-preview
│       └── ai.lua             copilot.lua
├── scripts/                  preserved assets (referenced by knap)
│   ├── typst_md_to_html.lua   md→HTML converter for knap preview
│   └── zen-wrapper            browser launcher for live-server
├── spell/                    custom dictionary (en.utf-8.add[.spl])
├── stylua.toml               formatter config for conform/stylua
├── README.md                 user-facing quick reference
└── STRUCTURE.md              this file
```

Config is **~84 KB**; everything is plain Lua, no generated files, no `lazy-lock.json` committed yet (lazy regenerates it on first sync).

---

## 2. Load sequence

```
nvim starts
  └─ init.lua
       ├─ require("config.options")   ① leader keys set FIRST (before lazy)
       ├─ require("config.keymaps")   ② global maps
       ├─ require("config.autocmds")  ③ autocmd registration
       └─ require("config.lazy")      ④ bootstrap + require("lazy").setup{ spec = {{ import = "plugins" }} }
                                          └─ imports every lua/plugins/*.lua
                                          └─ installs missing, then:
                                             • loads eager plugins now (lazy=false)
                                             • registers triggers for the rest
```

**Why this order matters:** `options.lua` sets `vim.g.mapleader = " "` before lazy.nvim loads — required, because plugin `keys=` specs capture the leader at definition time. Options/keymaps/autocmds are pure Neovim and have no plugin dependency, so they run synchronously up front.

---

## 3. Plugin inventory & lazy-load triggers

| Plugin | File | Load trigger | Eager? |
|---|---|---|---|
| `gruvbox.nvim` | colorscheme | `priority=1000`, `lazy=false` | **startup** |
| `snacks.nvim` | editor | `priority=900`, `lazy=false` | **startup** |
| `knap` | writing | `lazy=false` | **startup** |
| `nvim-treesitter` | treesitter | `event` BufReadPost/BufNewFile; `cmd` TS* | file open |
| `nvim-lspconfig` | lsp | `event` BufReadPre/BufNewFile | file open |
| `gitsigns.nvim` | editor | `event` BufReadPre/BufNewFile | file open |
| `blink.cmp` | completion | `event` InsertEnter | first insert |
| `copilot.lua` | ai | `event` InsertEnter; `cmd` Copilot | first insert |
| `mini.pairs` | coding | `event` VeryLazy | after UI |
| `flash.nvim` | editor | `event` VeryLazy + `keys` s/S | after UI |
| `which-key.nvim` | editor | `event` VeryLazy | after UI |
| `lualine.nvim` | ui | `event` VeryLazy | after UI |
| `conform.nvim` | coding | `event` BufWritePre; `cmd`; `keys` `<leader>cf` | first save |
| `render-markdown.nvim` | ui | `ft` markdown | markdown buffer |
| `vimtex` | writing | `ft` tex/plaintex/bib | tex buffer |
| `typst-preview.nvim` | writing | `cmd` + `keys` `<leader>tp` | on demand |
| `mini.icons` | coding | `lazy=true` (dependency) | when required |
| `friendly-snippets` | completion | dependency of blink | with blink |

**Eager set = 3** (gruvbox, snacks, knap). Everything else defers. Measured cold startup: **~28 ms**.

- `gruvbox` is eager + high priority so the colorscheme is applied before UI paints (avoids a flash of default theme).
- `snacks` is eager because it provides the picker/explorer/notifier surface and its `keys=` need to be live immediately; it self-defers its heavy submodules internally.
- `knap` is eager only because it's a tiny single-file plugin and it's simplest to set `vim.g.knap_settings` via its `init` and have the keymaps in `keymaps.lua` work without a load-trigger dance.

---

## 4. Dependency graph

```
nvim-lspconfig ──needs──▶ blink.cmp          (capabilities at config time)
blink.cmp ─────────────▶ friendly-snippets   (snippet source)
render-markdown ───────▶ nvim-treesitter     (markdown parser)
render-markdown ───────▶ mini.icons
lualine ───────────────▶ mini.icons
knap ──────(runtime)───▶ scripts/typst_md_to_html.lua, scripts/zen-wrapper, live-server
typst-preview ─(runtime)▶ tinymist (system binary)
vimtex ───────(runtime)▶ latexmk + zathura (system binaries)
```

The only **declared** (lazy `dependencies`) edges are the top four. The rest are runtime/external. Notably `nvim-lspconfig` declares `blink.cmp` as a dependency so blink loads first and `require("blink.cmp").get_lsp_capabilities()` is always available when LSP configures — no ordering race.

---

## 5. LSP architecture (mason-free)

```
plugins/lsp.lua
  ├─ vim.lsp.config("*", { capabilities = blink caps })   global default
  ├─ vim.lsp.config("lua_ls", {...})                      per-server override
  ├─ vim.lsp.config("tinymist", {...})
  ├─ vim.lsp.enable({ 12 servers })                       activate by name
  ├─ vim.diagnostic.config({...})                         signs/virtual_text/float
  └─ LspAttach autocmd → buffer maps gd / gD / gy
```

- Uses **Neovim 0.11+ native LSP** (`vim.lsp.enable`), with `nvim-lspconfig` supplying the per-server `cmd`/`root_markers`/`filetypes` definitions only. No `mason`, no `mason-lspconfig`.
- Servers enabled: `lua_ls, rust_analyzer, pyright, ruff, clangd, ts_ls, bashls, texlab, tinymist, marksman, taplo, yamlls`.
- **Failure mode is graceful:** a server whose binary isn't on `$PATH` is silently not started — no error, the rest still attach. This is what makes the config usable before every server is installed.
- 0.11 already provides `grn` rename, `gra` code action, `grr` references, `gri` impl, `K` hover, `[d`/`]d` diagnostics — so `lsp.lua` only adds `gd`/`gD`/`gy`.

---

## 6. Keymap ownership

| Source | Namespace | Examples |
|---|---|---|
| `config/keymaps.lua` (global) | windows, edit, knap | `<C-hjkl>`, `<A-j/k>`, `<C-d>zz`, `<leader>k{s,a,c}` |
| `plugins/lsp.lua` (LspAttach, buffer-local) | goto | `gd`, `gD`, `gy` |
| `plugins/editor.lua` (`keys=` + gitsigns on_attach) | find/git/jump | `<leader>f*`, `<leader>g*`, `s`/`S`, `]h`/`[h` |
| `plugins/coding.lua` | format | `<leader>cf` |
| `plugins/ui.lua` / `writing.lua` | toggles | `<leader>um`, `<leader>tp` |
| Neovim 0.11 native | LSP defaults | `grn`, `gra`, `grr`, `K` |

`which-key` only declares **group labels** (`<leader>c/f/g/k/u`), not bindings — so there's a single source of truth per key.

---

## 7. External (non-plugin) dependencies

| Need | Used by | Status on this machine |
|---|---|---|
| `cc` / `gcc` | treesitter parser compile | ✅ present |
| `git`, `curl` | lazy.nvim | ✅ present |
| `rust-analyzer`, `clangd`, `rustfmt` | LSP/format | ✅ present |
| `lua-language-server`, `pyright`, `ruff`, `texlab`, `taplo`, `yaml-language-server`, `marksman`, `stylua`, `shfmt` | LSP/format | ⬜ install via pacman |
| `typescript-language-server`, `bash-language-server` | LSP | ⬜ install via npm |
| `tinymist` | typst LSP + preview | ⬜ AUR / cargo |
| `live-server` | knap markdown preview | ✅ present |
| `latexmk`, `zathura` | vimtex compile + view | ⬜ latexmk missing |
| Copilot account | copilot.lua | run `:Copilot auth` |

Install block is in `README.md §"Install the language servers"`.

---

## 8. Tree-sitter specifics

- Pinned to the classic **`master`** branch (`require("nvim-treesitter.configs").setup`), `build = ":TSUpdate"`.
- 23 parsers in `ensure_installed`, compiled to `lazy/nvim-treesitter/parser/*.so` with system `cc`.
- `latex` and `bibtex` are **intentionally excluded** — they require the `tree-sitter` CLI to regenerate, and vimtex already owns `.tex`/`.bib` syntax. (Re-add them + `pacman -S tree-sitter-cli` only if LaTeX-math-in-markdown rendering is wanted.)

---

## 9. Disk footprint

```
config (~/.config/nvim)            84 KB
data   (~/.local/share/nvim)      751 MB
  └─ lazy/copilot.lua             635 MB   ← 85% of all data (bundled copilot-language-server + .git)
  └─ everything else             ~116 MB
```

**The dominant cost is Copilot, not the editor.** Dropping `plugins/ai.lua` would take the data dir to ~116 MB.

---

## 10. Observations for analysis

1. **Footprint is Copilot, full stop.** The 18-plugin core is ~116 MB; `copilot.lua` is 635 MB because it vendors the language server. This is the only place where "minimal" is contradicted, and it's a one-file toggle.
2. **Eager-load set is minimal (3).** Startup ~28 ms. `snacks.nvim` is the only large eager plugin; if startup ever regresses it's the first candidate to defer (`lazy=true` + rely on its `keys`).
3. **Mason-free is a deliberate tradeoff:** leaner + Arch-idiomatic (pacman owns servers), but moves install burden to the user and means LSP coverage is "whatever is on `$PATH`." Graceful degradation hides missing servers — good for resilience, but a missing server fails *silently* (check `:checkhealth lsp` / `:LspInfo` if a language seems dead).
4. **Tree-sitter on `master`** is the stable-but-maintenance branch. It works today; the ecosystem is migrating to the `main` rewrite. No urgency, but it's the most likely future migration point.
5. **Low coupling.** Only 4 declared inter-plugin dependencies; each `plugins/*.lua` is independently removable. Deleting any concern file (e.g. `ai.lua`, `writing.lua`) cleanly drops that feature with no dangling references.
6. **Single source of truth for keys** (which-key declares groups, not binds) — no hidden rebinds, easy to audit.
7. **Preserved-asset risk:** `knap` hard-codes absolute paths to `scripts/typst_md_to_html.lua` and `scripts/zen-wrapper` and `~/.tmp/`. If the config dir is ever relocated or those scripts removed, markdown preview breaks silently. These are the only intra-repo path dependencies.
