return {
	"echasnovski/mini.files",
	version = false,

	-- Deferred: a file explorer is only needed once you ask for it.
	keys = {
		{ "<leader>e", desc = "Toggle file explorer" },
		{ "<leader>E", desc = "Toggle file explorer (cwd)" },
	},
	config = function()
		require("mini.files").setup({
			content = {
				filter = function(fs_entry)
					return fs_entry.name ~= ".git" and fs_entry.name ~= ".DS_Store"
				end,
			},
			mappings = {
				close = "q",
				go_in = "l",
				go_in_plus = "L",
				go_out = "h",
				go_out_plus = "H",
				mark_goto = "'",
				mark_set = "m",
				reset = "<BS>",
				reveal_cwd = "@",
				show_help = "g?",
				synchronize = "=",
				trim_left = "<",
				trim_right = ">",
			},
			options = {
				permanent_delete = false,
				use_as_default_explorer = true,
			},
			windows = {
				preview = true,
				width_focus = 45,
				width_nofocus = 45,
				width_preview = 45,
			},
		})

		-- Toggle: open at current file's directory, or close if already open
		vim.keymap.set("n", "<leader>e", function()
			if not MiniFiles.close() then
				MiniFiles.open(vim.api.nvim_buf_get_name(0))
			end
		end, { desc = "Toggle file explorer" })

		-- Open at cwd
		vim.keymap.set("n", "<leader>E", function()
			if not MiniFiles.close() then
				MiniFiles.open()
			end
		end, { desc = "Toggle file explorer (cwd)" })

		-- Open in splits from within the explorer
		vim.api.nvim_create_autocmd("User", {
			pattern = "MiniFilesBufferCreate",
			callback = function(args)
				local buf_id = args.data.buf_id

				vim.keymap.set("n", "<C-s>", function()
					local state = MiniFiles.get_explorer_state()
					local new_target = vim.api.nvim_win_call(state.target_window, function()
						vim.cmd("belowright horizontal split")
						return vim.api.nvim_get_current_win()
					end)
					MiniFiles.set_target_window(new_target)
					MiniFiles.go_in({ close_on_file = true })
				end, { buffer = buf_id, desc = "Open in horizontal split" })

				vim.keymap.set("n", "<C-v>", function()
					local state = MiniFiles.get_explorer_state()
					local new_target = vim.api.nvim_win_call(state.target_window, function()
						vim.cmd("belowright vertical split")
						return vim.api.nvim_get_current_win()
					end)
					MiniFiles.set_target_window(new_target)
					MiniFiles.go_in({ close_on_file = true })
				end, { buffer = buf_id, desc = "Open in vertical split" })
			end,
		})
	end,
}
