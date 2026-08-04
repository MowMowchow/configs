return {
	"catppuccin/nvim",
	name = "catppuccin",
	lazy = true,
	priority = 1000, -- load before anything that reads highlight groups
	config = function()
		require("catppuccin").setup({
			flavour = "auto",
			integrations = {
					treesitter = true,
			}
		})
	end

}
