-- Formatting — dual-mode
-- When site-managed, the site plugin configures formatting via none-ls.
-- Local Mac: conform.nvim with external formatters.

local site_managed = require("jhou.env").managed

if site_managed then
  return {}
end

return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  dependencies = {
    "williamboman/mason.nvim",
  },
  config = function()
    require("conform").setup({
      formatters_by_ft = {
        -- Web development
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        vue = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        sql = { "sqlfluff" },
        markdown = { "prettier" },
        -- Rust
        rust = { "rustfmt" },
        -- Python
        python = { "isort", "black" },
        -- Go
        go = { "gofmt", "goimports" },
        -- C/C++
        c = { "clang_format" },
        cpp = { "clang_format" },
        -- Lua
        lua = { "stylua" },
      },
      -- Synchronous on save, so a slow formatter freezes the editor for its
      -- whole budget. 5000ms was long enough to feel like a hang, and sqlfluff
      -- routinely blew past it — you paid the full stall AND lost the format,
      -- since conform discards the result on timeout.
      --
      -- 1000ms covers every fast formatter here (prettier, stylua, rustfmt,
      -- gofmt, clang_format, black/isort) with room to spare.
      format_on_save = function(bufnr)
        -- sqlfluff is the one that cannot meet a blocking budget. Send SQL
        -- down the async path instead: the write completes immediately and the
        -- formatted result lands in a follow-up write.
        if vim.bo[bufnr].filetype == "sql" then
          return nil
        end
        return { lsp_format = "fallback", timeout_ms = 1000 }
      end,
      format_after_save = function(bufnr)
        if vim.bo[bufnr].filetype ~= "sql" then
          return nil
        end
        return { lsp_format = "fallback" }
      end,
      formatters = {
        sqlfluff = {
          command = "sqlfluff",
          args = { "format", "--dialect=postgres", "-" },
          stdin = true,
          cwd = function()
            return vim.fn.getcwd()
          end,
        },
      },
    })
  end,
}
