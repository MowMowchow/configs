vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.softtabstop = 2

-- Remote providers: all off.
--
-- These power *remote plugins* (rplugin) written in Python/Node/Perl/Ruby.
-- Nothing here is one — `~/.local/share/nvim/rplugin.vim` does not exist and no
-- installed plugin ships an rplugin manifest. black, isort and prettier are
-- invoked by conform.nvim as plain executables, which does not involve the
-- provider mechanism at all, and treesitter's "python" is a parser, not this.
--
-- Leaving them on costs a `checkhealth` warning apiece plus an executable probe
-- at startup for each. This line replaces
-- `vim.g.python3_host_prog = '/path/to/venv/bin/python3'` — a literal
-- placeholder that was never filled in, so the provider pointed at a path that
-- does not exist and checkhealth reported it as a hard error.
vim.g.loaded_python3_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- vim.opt.relativenumber = true
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.swapfile = false
vim.opt.wrap = false

-- Auto-reload files when changed externally
vim.opt.autoread = true
vim.opt.updatetime = 300  -- CursorHold fires after 300ms idle (default 4000)

-- Server socket for remote theme switching (used by the theme-manager daemon).
--
-- Guarded, because serverstart THROWS if the path is taken rather than
-- returning an error, and this file is required before lazy_init and extra —
-- so an uncaught throw here aborts the whole config: no plugins, no LSP, no
-- colorscheme. That is reachable in normal use: nothing removed the socket on
-- exit, so every crash or SIGKILL left one behind, macOS only prunes /tmp
-- after three days, and PIDs get recycled.
--
-- On collision, assume the owner is gone (a live one would hold the same PID)
-- and take the path over. VimLeavePre stops the accumulation at the source.
local socket_path = '/tmp/nvim-theme-' .. vim.fn.getpid() .. '.sock'
if not pcall(vim.fn.serverstart, socket_path) then
  pcall(vim.fn.delete, socket_path)
  pcall(vim.fn.serverstart, socket_path)
end
vim.api.nvim_create_autocmd('VimLeavePre', {
  desc = 'Remove the theme socket so stale ones do not pile up in /tmp',
  group = vim.api.nvim_create_augroup('theme-socket-cleanup', { clear = true }),
  callback = function() pcall(vim.fn.delete, socket_path) end,
})

-- Colorscheme is applied after lazy.nvim loads plugins.
-- See extra.lua for the theme-manager startup integration.
