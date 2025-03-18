return {
	'nvimdev/lspsaga.nvim',
	dependencies = {
		'nvim-treesitter/nvim-treesitter', -- optional
		'nvim-tree/nvim-web-devicons',     -- optional
	},

	config = function()
		require('lspsaga').setup({
			definition = {

			},
			ui = {
				code_action = '',
			},
			finder = {
				max_height = 0.6,
			},
		})

		-- lsp saga peek definition for selection/highlight
		vim.keymap.set({'n', 'v'}, '<leader>pd', function()
		  	local visual_selection = function()
		  		vim.cmd('noau normal! "vy"')
		  	  	return vim.fn.getreg('v')
		  	end

		  	local word = vim.fn.expand("<cword>")  -- Get word under cursor
		  	local search_term = vim.fn.mode() == "v" and visual_selection() or word  -- Use visual selection if in visual mode

			local lspsaga_definition = require('lspsaga.definition')
		  	if search_term and search_term ~= "" then
		  		lspsaga_definition:init(1, 1)
		  	else
				print("No word or selection found")
		  	end
		end, { silent = true })

		-- lsp saga peek type definition for selection/highlight
		vim.keymap.set({'n', 'v'}, '<leader>ptd', function()
		  	local visual_selection = function()
		  		vim.cmd('noau normal! "vy"')
		  	  	return vim.fn.getreg('v')
		  	end

		  	local word = vim.fn.expand("<cword>")  -- Get word under cursor
		  	local search_term = vim.fn.mode() == "v" and visual_selection() or word  -- Use visual selection if in visual mode

			local lspsaga_type_definition = require('lspsaga.definition')
		  	if search_term and search_term ~= "" then
		  		lspsaga_type_definition:init(2, 1)
		  	else
				print("No word or selection found")
		  	end
		end, { silent = true })

		-- lsp saga go to definition for selection/highlight
		vim.keymap.set({'n', 'v'}, '<leader>gd', function()
		  	local visual_selection = function()
		  		vim.cmd('noau normal! "vy"')
		  	  	return vim.fn.getreg('v')
		  	end

		  	local word = vim.fn.expand("<cword>")  -- Get word under cursor
		  	local search_term = vim.fn.mode() == "v" and visual_selection() or word  -- Use visual selection if in visual mode

			local lspsaga_go_definition = require('lspsaga.definition')
		  	if search_term and search_term ~= "" then
		  		lspsaga_go_definition:init(1, 2)
		  	else
				print("No word or selection found")
		  	end
		end, { silent = true })


		-- lsp saga go to type definition for selection/highlight
		vim.keymap.set({'n', 'v'}, '<leader>gtd', function()
		  	local visual_selection = function()
		  		vim.cmd('noau normal! "vy"')
		  	  	return vim.fn.getreg('v')
		  	end

		  	local word = vim.fn.expand("<cword>")  -- Get word under cursor
		  	local search_term = vim.fn.mode() == "v" and visual_selection() or word  -- Use visual selection if in visual mode

			local lspsaga_go_type_definition = require('lspsaga.definition')
		  	if search_term and search_term ~= "" then
		  		lspsaga_go_type_definition:init(2, 2)
		  	else
				print("No word or selection found")
		  	end
		end, { silent = true })


		-- lsp saga finder references/implementations for selection/highlight
		vim.keymap.set({'n', 'v'}, '<leader>f', function()
		  	local visual_selection = function()
		  		vim.cmd('noau normal! "vy"')
		  	  	return vim.fn.getreg('v')
		  	end

		  	local word = vim.fn.expand("<cword>")  -- Get word under cursor
		  	local search_term = vim.fn.mode() == "v" and visual_selection() or word  -- Use visual selection if in visual mode

			local lspsaga_finder = require("lspsaga.finder")
		  	if search_term and search_term ~= "" then
		  		lspsaga_finder:new({search = search_term})
		  	else
				print("No word or selection found")
		  	end
		end, { silent = true })

		-- lsp saga type hint hover info for selection/highlight
		vim.keymap.set({'n', 'v'}, '<leader>hh', function()
		  	local visual_selection = function()
		  		vim.cmd('noau normal! "vy"')
		  	  	return vim.fn.getreg('v')
		  	end

		  	local word = vim.fn.expand("<cword>")
		  	local search_term = vim.fn.mode() == "v" and visual_selection() or word

			local lspsaga_hover = require('lspsaga.hover')
			if search_term and search_term ~= "" then
				lspsaga_hover:render_hover_doc({search = search_term})
			end
		end, {silent = true})

	end,
}

