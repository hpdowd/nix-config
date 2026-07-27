-- Autocommands.
local augroup = function(name) return vim.api.nvim_create_augroup("conf_" .. name, { clear = true }) end
local autocmd = vim.api.nvim_create_autocmd

-- Briefly highlight yanked text
autocmd("TextYankPost", {
  group = augroup("highlight_yank"),
  callback = function() vim.hl.on_yank() end,
})

-- Prose filetypes: soft wrap + spell check; markdown also gets diagnostics
-- turned off (carried over from your old config — render-markdown handles it).
autocmd("FileType", {
  group = augroup("prose"),
  pattern = { "markdown", "tex", "plaintex", "typst", "text" },
  callback = function(ev)
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
    if ev.match == "markdown" then
      vim.diagnostic.enable(false, { bufnr = ev.buf })
    end
  end,
})

-- Create missing parent directories when saving a new file
autocmd("BufWritePre", {
  group = augroup("auto_mkdir"),
  callback = function(ev)
    if ev.match:match("^%w%w+:[\\/][\\/]") then return end
    vim.fn.mkdir(vim.fn.fnamemodify(ev.match, ":p:h"), "p")
  end,
})

-- Restore the last cursor position when reopening a file
autocmd("BufReadPost", {
  group = augroup("last_loc"),
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    local lines = vim.api.nvim_buf_line_count(ev.buf)
    if mark[1] > 0 and mark[1] <= lines then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
