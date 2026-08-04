-- Treesitter-aware commentstring: picks `//` vs `{/* */}` inside JSX by looking
-- at the node under the cursor.
--
-- The language table has to sit under `lang`. It used to be passed at the top
-- level (`setup{ javascript = {...} }`), one level too high — the plugin reads
-- `options.lang[<lang>]`, so every key was merged somewhere nothing looks and
-- was silently discarded. An unknown key is not an error, so there was no sign
-- of it: JSX comments just kept using the built-in defaults.
--
-- Also no `opts` alongside `config`. lazy.nvim hands opts to config as its
-- second argument and this config ignores it, so `opts = {}` was misleading
-- noise implying the table below got merged with something.
return {
  "folke/ts-comments.nvim",
  event = "VeryLazy",
  enabled = vim.fn.has("nvim-0.10.0") == 1,

  config = function()
    local jsx = {
      "// %s", -- default when no treesitter node matches
      "/* %s */",
      call_expression = "// %s",
      jsx_attribute = "// %s",
      jsx_element = "{/* %s */}",
      jsx_fragment = "{/* %s */}",
      spread_element = "// %s",
      statement_block = "// %s",
    }

    require("ts-comments").setup({
      lang = {
        javascript = jsx,
        tsx = jsx,
        typescript = { "// %s", "/* %s */" }, -- langs can have several
      },
    })
  end,
}
