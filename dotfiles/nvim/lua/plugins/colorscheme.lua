-- Catppuccin Mocha, transparent. Set at high priority so it loads first.
--
-- `config.palette` is GENERATED from modules/home/palette.nix and does not
-- exist in dotfiles/ — a runCommand in modules/home/dotfiles.nix merges it into
-- this tree. Editing colours here does nothing; edit the palette and rebuild.
--
-- `color_overrides.<flavour>` is the plugin's own hook: it replaces entries in
-- the flavour's palette before any highlight is built, so this is not a pile of
-- highlight overrides layered on top.
--
-- The palette names 18 of Mocha's 26 keys. The other eight (crust, flamingo,
-- maroon, peach, sky, sapphire, lavender, overlay2) keep
-- upstream's values — and upstream IS Mocha, so unlike the gruvbox arrangement
-- this replaced, the unnamed keys are already in scheme rather than merely in
-- family. That is the whole reason §3 of the migration runbook says to swap the
-- plugin instead of overriding a foreign one.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    lazy = false,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha",
        transparent_background = true,
        term_colors = true,
        styles = {
          comments = { "italic" },
          conditionals = { "italic" },
        },
        color_overrides = { mocha = require("config.palette") },
      })
      vim.cmd.colorscheme("catppuccin")
    end,
  },
}
