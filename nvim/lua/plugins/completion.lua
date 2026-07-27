-- Completion engine (blink.cmp — fast, the same one you used under LazyVim).
return {
  {
    "saghen/blink.cmp",
    version = "*", -- a release tag; ships a prebuilt fuzzy matcher (no rust build)
    event = "InsertEnter",
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      -- <C-y> accept, <C-space> open/close, <C-n>/<C-p> select, <C-e> cancel.
      keymap = { preset = "default" },
      appearance = { nerd_font_variant = "mono" },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
        ghost_text = { enabled = false }, -- copilot owns ghost text
      },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      signature = { enabled = true },
      fuzzy = { implementation = "prefer_rust_with_warning" },
    },
    opts_extend = { "sources.default" },
  },
}
