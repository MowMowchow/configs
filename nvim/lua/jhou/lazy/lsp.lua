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
		})

		local capabilities = require('blink.cmp').get_lsp_capabilities()

		-- BE
		vim.lsp.config('rust_analyzer', { capabilities = capabilities })
		vim.lsp.config('clangd', { capabilities = capabilities })
		vim.lsp.config('basedpyright', {
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
		vim.lsp.config('lua_ls', {
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
		vim.lsp.config('ts_ls', { capabilities = capabilities })
		vim.lsp.config('html', { capabilities = capabilities })

		-- Enable all configured servers
		vim.lsp.enable('rust_analyzer')
		vim.lsp.enable('clangd')
		vim.lsp.enable('basedpyright')
		vim.lsp.enable('lua_ls')
		vim.lsp.enable('ts_ls')
		vim.lsp.enable('html')

		-- vim.diagnostic.config({
		-- 	-- update_in_insert = true,
		-- 	float = {
		-- 		focusable = false,
		-- 		style = "minimal",
		-- 		border = "rounded",
		-- 		source = "always",
		-- 		header = "",
		-- 		prefix = "",
		-- 	},
		-- })
	end,
}
