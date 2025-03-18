vim.api.nvim_create_autocmd('TextYankPost', {
  desc =  'Highlight when yanking text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', {clear = true}),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Auto-reload files when changed externally
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  desc = 'Reload file when changed externally',
  group = vim.api.nvim_create_augroup('auto-reload', { clear = true }),
  callback = function()
    if vim.fn.mode() ~= 'c' then
      vim.cmd('checktime')
    end
  end,
})

vim.api.nvim_create_autocmd('FileChangedShellPost', {
  desc = 'Notify when file is reloaded',
  group = vim.api.nvim_create_augroup('auto-reload-notify', { clear = true }),
  callback = function()
    vim.notify('File changed on disk. Buffer reloaded.', vim.log.levels.WARN)
  end,
})

-- Apply colorscheme from theme-manager config.
-- This runs after lazy_init.lua, so all plugins are available for lazy-loading.
pcall(function()
	local config_path = vim.fn.expand("~/.config/theme-manager/config.toml")
	local ok, lines = pcall(vim.fn.readfile, config_path)
	if not ok then
		vim.cmd("colorscheme catppuccin")
		return
	end

	local family, variant
	for _, line in ipairs(lines) do
		local f = line:match('^%s*family%s*=%s*"([^"]+)"')
		if f then family = f end
		local v = line:match('^%s*variant%s*=%s*"([^"]+)"')
		if v then variant = v end
	end

	if family == "gruvbox-material" then
		vim.g.gruvbox_material_background = variant or "medium"
		vim.g.gruvbox_material_foreground = "material"
		vim.cmd("colorscheme gruvbox-material")
	elseif family == "gruvbox" then
		local contrast = (variant == "medium") and "" or (variant or "")
		require("gruvbox").setup({ contrast = contrast })
		vim.cmd("colorscheme gruvbox")
	else
		vim.cmd("colorscheme catppuccin")
	end
end)

-- Track recently visited files for recency list
vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'Track file visits for recency list',
  group = vim.api.nvim_create_augroup('recency-tracking', { clear = true }),
  callback = function()
    local filepath = vim.fn.expand('%:p')
    if filepath ~= '' and vim.bo.buftype == '' then
      require('jhou.recency').record_visit(filepath)
    end
  end,
})

