-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"--branch=stable",
		lazyrepo,
		lazypath
	})
end
vim.opt.rtp:prepend(lazypath)

-- Setup lazy.nvim
require("lazy").setup({
	spec = "jhou.lazy",
	-- `notify`, not `notifyu`. The typo meant lazy silently ignored the option
	-- and kept popping "Config change detected. Reloading..." on every edit —
	-- an unknown key is not an error, so nothing ever said so.
	change_detection = { notify = false },
	-- No plugin here uses luarocks (lazy's own health check says so), but the
	-- probe still runs and warns that Lua 5.1 is missing — Homebrew ships 5.5.
	-- Turning it off removes two permanent checkhealth warnings that no action
	-- of ours could ever satisfy.
	rocks = { enabled = false },
	-- {
	--   -- import your plugins
	--   { import = "plugins" },
	-- },
	-- install = { colorscheme = { "habamax" } },
	-- checker = { enabled = true },
})
