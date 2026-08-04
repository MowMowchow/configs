return {
	"nvim-telescope/telescope.nvim",

	tag = "0.1.8",

	-- Deferred: nothing here is needed until you actually open a picker.
	-- lazy.nvim installs stub mappings for `keys` and loads the plugin on first
	-- press, so the bindings behave identically -- they just cost nothing at
	-- startup. `cmd` covers :Telescope invoked directly.
	cmd = "Telescope",
	keys = {
		{ "<leader>pf", desc = "Telescope find files" },
		{ "<leader>pg", desc = "Telescope live grep" },
	},

	dependencies = {
		"nvim-lua/plenary.nvim"
	},

	config = function()
		local builtin = require('telescope.builtin')
		vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
		vim.keymap.set('n', '<leader>pg', builtin.live_grep, {})
	end
}
		-- basic telescope configuration
		-- local harpoon = require('harpoon')
		-- harpoon:setup({})
		-- local conf = require("telescope.config").values
		-- local function toggle_telescope(harpoon_files)
		-- 	local file_paths = {}
		-- 	for _, item in ipairs(harpoon_files.items) do
		-- 		table.insert(file_paths, item.value)
		-- 	end
		-- 	
		-- 	require("telescope.pickers").new({}, {
		-- 		prompt_title = "Harpoon",
		-- 		finder = require("telescope.finders").new_table({
		-- 			results = file_paths,
		-- 		}),
		-- 		previewer = conf.file_previewer({}),
		-- 		sorter = conf.generic_sorter({}),
		-- 	}):find()
		-- end
		-- 
		-- vim.keymap.set("n", "<leader>hlf", function() toggle_telescope(harpoon:list()) end,
		-- 	{ desc = "Open harpoon window" }
		-- )
	-- end

