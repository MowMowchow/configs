return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  config = function()
    local configs = require("nvim-treesitter.configs")
    configs.setup({
      ensure_installed = {
        "c", "lua", "vim", "vimdoc",
        "javascript", "typescript", "tsx", "html",
        "python", "go", "rust", "cpp",
        "yaml", "json",
      },

      sync_install = false,
      auto_install = true,

      indent = {
        enable = true
      },

      highlight = {
        enable = true
      },
    })

    local treesitter_parser_config = require("nvim-treesitter.parsers").get_parser_configs()
    treesitter_parser_config.templ = {
      install_info = {
        url = "https://github.com/vrischmann/tree-sitter-templ.git",
        files = { "src/parser.c", "src/scanner.c" },
        branch = "master",
      },
    }

    -- vim.treesitter.language.register("templ", "templ")
  end
}
