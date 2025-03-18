return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	dependencies = {
		"williamboman/mason.nvim",
	},
	keys = {
		{
			"<leader>fm",
			function()
				require("conform").format({ async = true, lsp_fallback = true })
			end,
			desc = "Format buffer",
		},
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
			format_on_save = {
				-- Opt-in format on save
				lsp_fallback = true,
				async = false,
				timeout_ms = 5000,
			},
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
