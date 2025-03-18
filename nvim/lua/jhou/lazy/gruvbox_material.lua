return {
	"sainnhe/gruvbox-material",
	lazy = true,
	priority = 1000,
	config = function()
		-- Use conditional defaults so theme-manager (extra.lua) can pre-set these
		-- before triggering lazy-load via :colorscheme
		if vim.g.gruvbox_material_background == nil then
			vim.g.gruvbox_material_background = "medium" -- "hard", "medium", "soft"
		end
		if vim.g.gruvbox_material_foreground == nil then
			vim.g.gruvbox_material_foreground = "material" -- "material", "mix", "original"
		end
		vim.g.gruvbox_material_enable_italic = true
		vim.g.gruvbox_material_better_performance = 1
	end,
}
