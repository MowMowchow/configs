-- LSP configuration — dual-mode
-- When a site plugin owns the language stack it supplies the servers;
-- this file then provides only lspconfig + completion capabilities.
-- Local Mac: Mason + external LSPs for personal development.

local site_managed = require("jhou.env").managed

if site_managed then
  -- Site-managed: the plugin registers its own servers.
  return {
    "neovim/nvim-lspconfig",
    dependencies = {
      "saghen/blink.cmp",
    },
    config = function()
      local capabilities = require("blink.cmp").get_lsp_capabilities()
      vim.lsp.config("*", { capabilities = capabilities })
    end,
  }
end

-- On local Mac: Mason + external LSPs
return {
  "neovim/nvim-lspconfig",
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "saghen/blink.cmp",
  },

  config = function()
    require("mason").setup()
    require("mason-lspconfig").setup({
      ensure_installed = {
        "lua_ls",
        "rust_analyzer",
        "basedpyright",
        "clangd",
        "ts_ls",
        "snyk_ls",
        -- "gopls",
      },
      -- Don't auto-attach every Mason-installed server. Only the ones
      -- explicitly listed in vim.lsp.enable() below run. Without this,
      -- snyk_ls auto-attaches to every buffer and floods :messages
      -- with auth-failure errors that overlay floats from lspsaga etc.
      automatic_enable = false,
    })

    local capabilities = require("blink.cmp").get_lsp_capabilities()

    -- BE
    vim.lsp.config("rust_analyzer", { capabilities = capabilities })
    vim.lsp.config("clangd", { capabilities = capabilities })
    vim.lsp.config("basedpyright", {
      capabilities = capabilities,
      settings = {
        basedpyright = {
          analysis = {
            autoSearchPaths = true,
            useLibraryCodeForTypes = true,
            diagnosticSeverityOverrides = {
              reportAny = "none",
              reportExplicitAny = "none",
              reportUnknownVariableType = "none",
              reportUnknownMemberType = "none",
              reportUnknownArgumentType = "none",
              reportMissingTypeStubs = "none",
            },
          },
        },
      },
    })
    vim.lsp.config("lua_ls", {
      capabilities = capabilities,
      settings = {
        Lua = {
          diagnostics = {
            globals = { "vim" },
          },
        },
      },
    })

    -- FE
    vim.lsp.config("ts_ls", { capabilities = capabilities })
    vim.lsp.config("html", { capabilities = capabilities })

    -- Enable all configured servers
    vim.lsp.enable("rust_analyzer")
    vim.lsp.enable("clangd")
    vim.lsp.enable("basedpyright")
    vim.lsp.enable("lua_ls")
    vim.lsp.enable("ts_ls")
    vim.lsp.enable("html")

    -- vim.diagnostic.config({
    --   -- update_in_insert = true,
    --   float = {
    --     focusable = false,
    --     style = "minimal",
    --     border = "rounded",
    --     source = "always",
    --     header = "",
    --     prefix = "",
    --   },
    -- })
  end,
}
