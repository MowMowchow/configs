-- nvim-treesitter v1.0+ (main branch). The plugin is now just a parser
-- installer + query collection — it no longer wires up highlight/indent for
-- you. We do that ourselves via FileType autocommands using Neovim's
-- built-in treesitter hooks (`vim.treesitter.start`, `vim.treesitter.foldexpr`,
-- `nvim-treesitter.indentexpr`).
--
-- Requires: nvim 0.12+, tree-sitter-cli >= 0.26.1 on PATH, a C compiler.

local langs = {
  "c", "lua", "vim", "vimdoc",
  "javascript", "typescript", "tsx", "html",
  "python", "go", "rust", "cpp",
  "yaml", "json",
}

return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  -- Upstream explicitly says this plugin does not support lazy-loading.
  lazy = false,
  build = ":TSUpdate",
  config = function()
    require("nvim-treesitter").setup({
      install_dir = vim.fn.stdpath("data") .. "/site",
    })

    -- Async parser install — no-op when already installed.
    require("nvim-treesitter").install(langs)

    -- Custom parser: templ. Registered on TSUpdate so :TSUpdate sees it.
    vim.api.nvim_create_autocmd("User", {
      pattern = "TSUpdate",
      callback = function()
        require("nvim-treesitter.parsers").templ = {
          install_info = {
            url = "https://github.com/vrischmann/tree-sitter-templ.git",
            files = { "src/parser.c", "src/scanner.c" },
            branch = "master",
          },
        }
      end,
    })

    -- Highlighting: Neovim's vim.treesitter.start picks up the right parser
    -- by filetype. No-op for filetypes whose parser isn't installed yet.
    vim.api.nvim_create_autocmd("FileType", {
      pattern = langs,
      callback = function() vim.treesitter.start() end,
    })

    -- Indent: still upstream-experimental, but on for parity with the old
    -- `indent = { enable = true }` behaviour.
    vim.api.nvim_create_autocmd("FileType", {
      pattern = langs,
      callback = function()
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
