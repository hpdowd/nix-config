return {
  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-mini/mini.icons" },
    opts = {
      options = {
        -- GENERATED name, from modules/home/themes/<scheme>.nix via
        -- lua/config/scheme.lua. A lualine theme that does not resolve throws
        -- at startup rather than falling back, so this must not be typed here.
        theme = require("config.scheme").lualine,
        globalstatus = true,
        section_separators = "",
        component_separators = "",
      },
      sections = {
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "diagnostics", "filetype" },
      },
    },
  },

  -- In-buffer markdown rendering (carried over; the only markdown renderer now).
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    opts = {
      code = { sign = true, width = "block", right_pad = 1 },
      heading = { sign = true, icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " } },
      checkbox = { enabled = true },
    },
    keys = {
      { "<leader>um", function() require("render-markdown").toggle() end, desc = "Toggle markdown render" },
    },
  },
}
