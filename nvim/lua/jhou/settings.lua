vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2

vim.g.python3_host_prog = '/path/to/venv/bin/python3'

-- vim.opt.relativenumber = true
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.swapfile = false
vim.opt.wrap = false

-- Auto-reload files when changed externally
vim.opt.autoread = true

-- Start server socket for remote theme switching (used by theme-manager daemon)
local socket_path = '/tmp/nvim-theme-' .. vim.fn.getpid() .. '.sock'
vim.fn.serverstart(socket_path)

-- Colorscheme is applied after lazy.nvim loads plugins.
-- See extra.lua for the theme-manager startup integration.
