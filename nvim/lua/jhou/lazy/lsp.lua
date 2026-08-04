-- LSP configuration — dual-mode
-- When a site plugin owns the language stack it supplies the servers;
-- this file then provides only lspconfig + completion capabilities.
-- Local Mac: Mason + external LSPs for personal development.

local site_managed = require("jhou.env").managed

if site_managed then
  -- Site-managed: the plugin registers its own servers.
  return {
    "neovim/nvim-lspconfig",
    -- Deferred: nothing to attach to until a buffer exists.
    event = { "BufReadPre", "BufNewFile" },
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
    -- Deferred: an LSP client is only useful once there is a buffer to attach
    -- to. BufReadPre fires before the first file is read, so servers still
    -- attach to it -- nothing is lost opening `nvim file.py`.
    --
    -- The Mason commands are listed too because mason.nvim is a dependency
    -- here: without them, `nvim` with no arguments followed by `:Mason` would
    -- find no such command, since no BufReadPre had fired yet.
    event = { "BufReadPre", "BufNewFile" },
    cmd = { "Mason", "MasonInstall", "MasonUninstall", "MasonUninstallAll", "MasonLog", "MasonUpdate" },
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
        -- html is configured and enabled below, so Mason has to actually
        -- install it. It was missing here, so vscode-html-language-server was
        -- never fetched: checkhealth reported "not executable. Configuration
        -- will not be used." and html buffers silently got no LSP at all.
        "html",
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
