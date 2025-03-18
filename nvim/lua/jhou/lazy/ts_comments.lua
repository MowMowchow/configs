return {
  "folke/ts-comments.nvim",
  opts = {},
  event = "VeryLazy",
  enabled = vim.fn.has("nvim-0.10.0") == 1,

  config = function()
    require("ts-comments").setup({
      javascript = {
        "// %s",                   -- default commentstring when no treesitter node matches
        "/* %s */",
        call_expression = "// %s", -- specific commentstring for call_expression
        jsx_attribute = "// %s",
        jsx_element = "{/* %s */}",
        jsx_fragment = "{/* %s */}",
        spread_element = "// %s",
        statement_block = "// %s",
      },
      tsx = {
        "// %s",                   -- default commentstring when no treesitter node matches
        "/* %s */",
        call_expression = "// %s", -- specific commentstring for call_expression
        jsx_attribute = "// %s",
        jsx_element = "{/* %s */}",
        jsx_fragment = "{/* %s */}",
        spread_element = "// %s",
        statement_block = "// %s",
      },
      typescript = { "// %s", "/* %s */" }, -- langs can have multiple commentstrings

    }
    )
  end,

}
