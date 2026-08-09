-- Syntax highlighting / indentation via tree-sitter (stable `master` branch).
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    cmd = { "TSUpdate", "TSInstall", "TSInstallInfo" },
    opts = {
      highlight = { enable = true },
      indent = { enable = true },
      -- No `latex`/`bibtex` parsers: vimtex handles .tex/.bib syntax, and those
      -- two need the tree-sitter CLI to build. If you later want LaTeX math
      -- rendered inside markdown, `sudo pacman -S tree-sitter-cli` then add
      -- "latex" back here.
      ensure_installed = {
        "bash", "c", "css", "diff", "html", "javascript", "json", "jsonc",
        "lua", "luadoc", "markdown", "markdown_inline", "python", "query",
        "regex", "rust", "toml", "tsx", "typescript", "typst", "vim", "vimdoc",
        "yaml",
      },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
}
