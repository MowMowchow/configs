return {
	"catppuccin/nvim",
	name = "catppuccin",
	lazy = true,
	priority = 1000, -- highest priority besides luarocks
	config = function()
		require("catppuccin").setup({
			flavour = "auto",
			integrations = {
					treesitter = true,
			}
		})
	end

}
