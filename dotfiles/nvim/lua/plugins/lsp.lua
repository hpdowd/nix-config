-- Language servers via Neovim's native LSP (no mason — servers come from $PATH).
-- Install the server binaries yourself; see README.md. A server whose binary is
-- missing is simply skipped (no error), so this config works before they're all in.
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "saghen/blink.cmp" },
    config = function()
      local servers = {
        "lua_ls", "rust_analyzer", "pyright", "ruff", "clangd",
        "ts_ls", "bashls", "gopls", "texlab", "tinymist", "marksman", "taplo", "yamlls",
      }

      -- Defaults applied to every server (completion capabilities from blink).
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(),
      })

      -- Per-server tweaks
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
            diagnostics = { globals = { "vim", "Snacks" } },
          },
        },
      })
      vim.lsp.config("tinymist", { settings = { exportPdf = "onSave" } })

      for _, name in ipairs(servers) do
        vim.lsp.enable(name)
      end

      -- Diagnostics presentation
      vim.diagnostic.config({
        virtual_text = { spacing = 2, prefix = "●" },
        severity_sort = true,
        float = { border = "rounded", source = true },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN] = " ",
            [vim.diagnostic.severity.HINT] = " ",
            [vim.diagnostic.severity.INFO] = " ",
          },
        },
      })

      -- Extra buffer-local maps. Neovim 0.11+ already provides grn (rename),
      -- gra (code action), grr (references), gri (implementation) and K (hover).
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local function bmap(keys, fn, desc)
            vim.keymap.set("n", keys, fn, { buffer = ev.buf, desc = "LSP: " .. desc })
          end
          bmap("gd", vim.lsp.buf.definition, "Goto definition")
          bmap("gD", vim.lsp.buf.declaration, "Goto declaration")
          bmap("gy", vim.lsp.buf.type_definition, "Goto type definition")
        end,
      })
    end,
  },
}
