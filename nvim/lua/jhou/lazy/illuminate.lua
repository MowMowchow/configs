return {
  "RRethy/vim-illuminate",
  -- Deferred: highlighting other occurrences of the word under the cursor is
  -- meaningless until a real file is open.
  event = { "BufReadPost", "BufNewFile" },
  opts = {
    providers = {
      "lsp",
      "treesitter",
      "regex",
    },
    delay = 100,
    filetype_overrides = {},
    filetypes_denylist = {
      "dirbuf",
      "dirvish",
      "fugitive",
    },
    filetypes_allowlist = {},
    modes_denylist = {},
    modes_allowlist = {},
    providers_regex_syntax_denylist = {},
    providers_regex_syntax_allowlist = {},
    -- under_cursor = true,
    large_file_cutoff = 10000,
    large_file_overrides = nil,
    min_count_to_highlight = 1,
    should_enable = function(bufnr)
      return true
    end,
    case_insensitive_regex = false,
    disable_keymaps = false,
  },
  config = function(_, opts)
    require("illuminate").configure(opts)
  end,
}
