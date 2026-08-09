-- Global keymaps. Buffer-local LSP maps live in plugins/lsp.lua.
local map = vim.keymap.set

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- Window navigation
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Keep the cursor centered on half-page scrolls (carried over)
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up (centered)" })

-- Keep selection after indenting
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Move lines / selections up and down
map("n", "<A-j>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
map("n", "<A-k>", "<cmd>m .-2<cr>==", { desc = "Move line up" })
map("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- Save
map({ "n", "i", "x" }, "<C-s>", "<cmd>silent! write<cr><esc>", { desc = "Save file" })

-- Diagnostics
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })

-- knap: live preview for markdown / LaTeX / typst (carried over).
-- require() inside the callback makes lazy.nvim load knap on first use.
map("n", "<leader>ks", function() require("knap").process_once() end, { desc = "knap: preview once" })
map("n", "<leader>ka", function() require("knap").toggle_autopreviewing() end, { desc = "knap: toggle autopreview" })
map("n", "<leader>kc", function() require("knap").close_viewer() end, { desc = "knap: close viewer" })
