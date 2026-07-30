-- ~/.config/nvim/init.lua
-- Minimal, hand-rolled Neovim config (replaced the LazyVim distro).
-- Everything here is yours to read and change. Load order matters:
-- options/keymaps/autocmds are plain vim settings, then lazy bootstraps plugins.

require("config.options")
require("config.keymaps")
require("config.autocmds")
require("config.lazy")
