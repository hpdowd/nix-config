-- Core editor settings. (LazyVim used to set these for you — now you own them.)

-- Leader keys MUST be set before lazy.nvim loads.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local o = vim.opt

-- UI
o.number = true
o.relativenumber = true
o.signcolumn = "yes"
o.cursorline = true
o.termguicolors = true
o.showmode = false        -- the statusline shows the mode instead
o.scrolloff = 6
o.sidescrolloff = 8
o.wrap = false
o.splitright = true
o.splitbelow = true
o.winminwidth = 5
o.pumheight = 12          -- max items in the completion popup

-- Indentation (tabstop = 4 carried over from your old config)
o.expandtab = true
o.tabstop = 4
o.shiftwidth = 4
o.shiftround = true
o.smartindent = true

-- Search
o.ignorecase = true
o.smartcase = true
o.inccommand = "nosplit"  -- live preview while typing :substitute

-- Files / persistence
o.undofile = true
o.undolevels = 10000
o.swapfile = false
o.confirm = true          -- prompt to save instead of erroring on :q

-- Editing
o.clipboard = "unnamedplus"
o.completeopt = "menu,menuone,noselect"
o.timeoutlen = 400
o.updatetime = 200
o.virtualedit = "block"

-- Spelling is enabled per-filetype in autocmds.lua; custom words live in spell/
o.spelllang = "en"
