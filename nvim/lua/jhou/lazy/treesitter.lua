-- nvim-treesitter v1.0+ (main branch). The plugin is now just a parser
-- installer + query collection — it no longer wires up highlight/indent for
-- you. We do that ourselves via FileType autocommands using Neovim's
-- built-in treesitter hooks (`vim.treesitter.start`, `vim.treesitter.foldexpr`,
-- `nvim-treesitter.indentexpr`).
--
-- Requires: nvim 0.12+ (a normal stable release, not a nightly),
-- tree-sitter-cli >= 0.26.1 on PATH, and a C compiler.
--
-- Note the >= : upstream never published 0.26.1 exactly — the series goes
-- 0.25.x then 0.26.3 — so 0.26.3+ is what satisfies it. Sources, in order of
-- preference: `:MasonInstall tree-sitter-cli` (no sudo, works on every
-- platform, installs under ~/.local/share/nvim so it survives an ephemeral
-- host), brew, cargo, dnf, npm.
--
-- On 0.11 the plugin still LOADS — the version check is a checkhealth error,
-- not a load guard — but treat that as degraded, not supported.

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

    -- `langs` holds tree-sitter PARSER names, which is what install() wants —
    -- but a FileType autocmd pattern matches &filetype, and the two namespaces
    -- are not the same. There is no filetype called `tsx` (a .tsx file is
    -- `typescriptreact`), none called `vimdoc` (that is `help`), and
    -- `javascriptreact` has no parser of its own so it never appeared here at
    -- all. Those patterns simply never fired, so .tsx and .jsx buffers silently
    -- fell back to regex syntax and the ftplugin indentexpr.
    --
    -- get_filetypes does the mapping properly: nvim-treesitter's
    -- plugin/filetypes.lua registers the aliases (tsx -> typescriptreact,
    -- typescript.tsx) and lazy.nvim sources plugin/ before running config, so
    -- they are registered by the time this runs.
    -- Dotted names are skipped: get_filetypes also returns legacy compound
    -- filetypes like `typescript.tsx`, which Neovim no longer recognises and
    -- checkhealth flags as unknown. The plain `typescriptreact` in the same
    -- list already covers every real buffer, so they add nothing but noise.
    local fts, seen = {}, {}
    for _, lang in ipairs(langs) do
      for _, ft in ipairs(vim.treesitter.language.get_filetypes(lang)) do
        if not ft:find("%.") and not seen[ft] then
          seen[ft] = true
          fts[#fts + 1] = ft
        end
      end
    end

    -- Highlighting: Neovim's vim.treesitter.start picks up the right parser
    -- by filetype. No-op for filetypes whose parser isn't installed yet.
    vim.api.nvim_create_autocmd("FileType", {
      pattern = fts,
      callback = function() vim.treesitter.start() end,
    })

    -- Indent: still upstream-experimental, but on for parity with the old
    -- `indent = { enable = true }` behaviour.
    vim.api.nvim_create_autocmd("FileType", {
      pattern = fts,
      callback = function()
        vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
