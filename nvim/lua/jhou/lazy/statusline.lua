return {
	'nvim-lualine/lualine.nvim',
	-- VeryLazy: the statusline is cosmetic, so it can appear a few ms after the
	-- first buffer instead of blocking startup.
	event = "VeryLazy",
	dependencies = { 
		'nvim-tree/nvim-web-devicons' 
	},

	config = function()
		require('lualine').setup {
			options = {
				icons_enabled = true,
				theme = 'auto',
				--component_separators = { left = '', right = ''},
				-- section_separators = { left = '', right = ''},
				component_separators = { left = ' ', right = ' '},
				section_separators = { left = ' ', right = ' '},
				disabled_filetypes = {
					statusline = {},
					winbar = {},
				},
				ignore_focus = {},
				always_divide_middle = true,
				always_show_tabline = true,
				globalstatus = false,
				-- lualine's default is 1000ms. At 100 this redrew the
				-- statusline ten times as often, forever, for no visible gain:
				-- lualine also refreshes on ModeChanged/BufEnter/etc, so the
				-- timer is only a fallback for things nothing signals (clock,
				-- filesize). tabline and winbar are both empty here, so those
				-- two timers never armed at all.
				refresh = {
					statusline = 1000,
					tabline = 1000,
					winbar = 1000,
				}
			},
			sections = {
				lualine_a = {'mode'},
				lualine_b = {'branch', 'diff', 'diagnostics'},
				lualine_c = {'filename'},
				lualine_x = {'encoding', 'fileformat', 'filetype'},
				lualine_y = {'filesize'},
				lualine_z = {'location'}
			},
			inactive_sections = {
				lualine_a = {},
				lualine_b = {},
				lualine_c = {'filename'},
				lualine_x = {'location'},
				lualine_y = {},
				lualine_z = {}
			},
			tabline = {},
			winbar = {},
			inactive_winbar = {},
			extensions = (function()
				local exts = { 'lazy' }
				if not require("jhou.env").managed then
					table.insert(exts, 'mason')
				end
				return exts
			end)()
		}

	end
}
