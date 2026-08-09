-- Document authoring: markdown / LaTeX / typst. This is your main use case, so
-- each tool here covers a distinct format (no more overlapping previewers).
return {
  -- knap: live HTML/PDF preview (markdown via scripts/typst_md_to_html.lua +
  -- live-server). Keymaps are in config/keymaps.lua.
  {
    "frabjous/knap",
    lazy = false,
    init = function()
      vim.g.knap_settings = {
        mdtohtml = "nvim -l ~/.config/nvim/scripts/typst_md_to_html.lua %srcfile% ~/.tmp/knap_preview.html",
        mdtohtmlviewerlaunch = "live-server -q ~/.tmp/knap_preview.html --watch='~/.tmp/knap_preview.html' --browser=/home/henry/.config/nvim/scripts/zen-wrapper --port=9999",
        mdtohtmlviewerrefresh = "none",
        delay = 200,
      }
    end,
  },

  -- LaTeX editing + compilation (zathura is your system PDF viewer).
  {
    "lervag/vimtex",
    ft = { "tex", "plaintex", "bib" },
    init = function()
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_quickfix_mode = 0
      vim.g.vimtex_mappings_prefix = "<localleader>l"
    end,
  },

  -- Typst live preview (backed by the system tinymist binary).
  {
    "chomosuke/typst-preview.nvim",
    cmd = { "TypstPreview", "TypstPreviewToggle" },
    opts = { dependencies_bin = { ["tinymist"] = "tinymist" } },
    keys = {
      { "<leader>tp", "<cmd>TypstPreviewToggle<cr>", desc = "Typst preview toggle" },
    },
  },
}
