-- Gruvbox, transparent (carried over). Set at high priority so it loads first.
--
-- `config.palette` is GENERATED from modules/home/palette.nix and does not
-- exist in dotfiles/ — a runCommand in modules/home/dotfiles.nix merges it into
-- this tree. Editing colours here does nothing; edit the palette and rebuild.
--
-- `palette_overrides` is the plugin's own hook (lua/gruvbox.lua): it replaces
-- entries in the base palette before any highlight is built, so this is not a
-- pile of highlight overrides layered on top. Keys the palette does not name
-- (the *_hard/*_soft variants, faded_*, the orange pair and the diff colours)
-- keep upstream's gruvbox values.
return {
  {
    "ellisonleao/gruvbox.nvim",
    priority = 1000,
    lazy = false,
    config = function()
      require("gruvbox").setup({
        terminal_colors = true,
        undercurl = true,
        underline = true,
        bold = true,
        italic = { strings = true, emphasis = true, comments = true, folds = true },
        inverse = true,
        contrast = "",
        transparent_mode = true,
        palette_overrides = require("config.palette"),
      })
      vim.cmd.colorscheme("gruvbox")
    end,
  },
}
