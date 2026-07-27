return {
  -- Autopairs, including the $$ math pair you mapped under LazyVim.
  {
    "nvim-mini/mini.pairs",
    event = "VeryLazy",
    opts = {
      modes = { insert = true, command = true, terminal = false },
      skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
      skip_ts = { "string" },
      skip_unbalanced = true,
      markdown = true,
      mappings = {
        ["$"] = { action = "open", pair = "$$", neigh_pattern = "[^\\]." },
      },
    },
  },

  -- Icons (shared by snacks, lualine, render-markdown)
  { "nvim-mini/mini.icons", lazy = true, opts = {} },

  -- Format on save. Markdown is intentionally excluded (carried over).
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true, lsp_format = "fallback" }) end, desc = "Format buffer" },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        python = { "ruff_format" },
        rust = { "rustfmt" },
        markdown = {}, -- no autoformat
      },
      format_on_save = function(bufnr)
        if vim.bo[bufnr].filetype == "markdown" then return end
        return { timeout_ms = 1500, lsp_format = "fallback" }
      end,
    },
  },
}
