-- GitHub Copilot ghost-text suggestions (carried over). Run :Copilot auth once.
-- Accept with Alt-l so it doesn't clash with blink.cmp's <C-y>/<Tab>.
return {
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<M-l>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = { enabled = false },
      filetypes = { markdown = true, gitcommit = true, help = false, ["*"] = true },
    },
  },
}
