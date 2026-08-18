-- Bootstrap lazy.nvim, then load every spec under lua/plugins/.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- The lockfile lives in state, not next to the config.
--
-- lazy.nvim defaults to stdpath("config")/lazy-lock.json and REWRITES it on
-- every :Lazy sync/update/restore. ~/.config/nvim is a read-only /nix/store
-- path (see docs/adr/0002), so that write cannot succeed — this was the single
-- thing keeping the whole directory out of the store.
--
-- The tracked copy at home/nvim/lazy-lock.json is still the source of truth for
-- a fresh install: seed state from it once, then let lazy own the state copy.
-- After a plugin update, copy it back into the repo and commit to move the pin.
local lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json"
if not (vim.uv or vim.loop).fs_stat(lockfile) then
  local seed = vim.fn.stdpath("config") .. "/lazy-lock.json"
  if (vim.uv or vim.loop).fs_stat(seed) then
    vim.fn.mkdir(vim.fn.fnamemodify(lockfile, ":h"), "p")
    vim.fn.writefile(vim.fn.readfile(seed), lockfile)
  end
end

require("lazy").setup({
  spec = { { import = "plugins" } },
  lockfile = lockfile,
  -- The scheme's own name is GENERATED into lua/config/scheme.lua; "habamax"
  -- ships with nvim and is the fallback if the plugin has not been fetched yet.
  install = { colorscheme = { require("config.scheme").name, "habamax" } },
  checker = { enabled = false },           -- don't auto-check for plugin updates
  change_detection = { notify = false },
  rocks = { enabled = false },             -- no luarocks (neorg is gone)
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin", "netrwPlugin",
      },
    },
  },
})
