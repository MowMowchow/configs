vim.api.nvim_create_autocmd('TextYankPost', {
  desc =  'Highlight when yanking text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', {clear = true}),
  callback = function()
    -- vim.hl, not vim.highlight: renamed in 0.11. The old name still works via
    -- a deprecation shim, but it is scheduled for removal.
    vim.hl.on_yank()
  end,
})

-- Auto-reload files when changed externally
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI' }, {
  desc = 'Reload file when changed externally',
  group = vim.api.nvim_create_augroup('auto-reload', { clear = true }),
  callback = function()
    if vim.fn.mode() ~= 'c' and vim.bo.buftype ~= 'nofile' then
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

	-- Dark or light. This was missing entirely: config.toml carries `family`
	-- and `variant`, but `variant` is CONTRAST (medium/soft/hard), not
	-- appearance — so nothing here ever set `background` and every freshly
	-- launched nvim used the default, dark, whatever the system was set to.
	--
	-- Live switching always worked, because theme-manager's neovim adapter
	-- pushes `set background=...` over the socket in settings.lua to instances
	-- that are already running. Only startup was wrong, which is why it looked
	-- intermittent: correct after a theme change, wrong on a new window.
	--
	-- The pointer first: it is a file read, it is what theme-manager now
	-- writes on every apply, and it is the only option on a remote host with
	-- no OS appearance to query. Fall back to asking macOS directly, which
	-- costs a ~20ms fork and so is not the default path.
	local appearance
	local pf = vim.fn.expand("~/.local/state/theme-manager/appearance")
	local pok, pdata = pcall(vim.fn.readfile, pf)
	if pok and pdata and pdata[1] then
		local a = vim.trim(pdata[1])
		if a == "dark" or a == "light" then appearance = a end
	end
	if not appearance and vim.fn.has("mac") == 1 then
		-- `defaults read` exits non-zero in Light mode, when the key is absent.
		local out = vim.fn.system({ "defaults", "read", "-g", "AppleInterfaceStyle" })
		appearance = (vim.v.shell_error == 0 and out:match("Dark")) and "dark" or "light"
	end
	vim.o.background = appearance or "dark"

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

