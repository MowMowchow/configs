-- mappings
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- View directory
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

-- Replace symbol
vim.keymap.set("n", "<leader>sr", vim.lsp.buf.rename, { silent = true, desc = "Rename Symbol" })

-- Vertical split
vim.keymap.set('n', '<leader>wvs', ':vsplit<CR>', { desc = 'Vertical split' })

-- Navigate left and right
vim.keymap.set('n', '<leader>wl', '<C-w>h', { desc = 'Go to left window' })
vim.keymap.set('n', '<leader>wr', '<C-w>l', { desc = 'Go to right window' })

-- Only (close other windows)
vim.keymap.set('n', '<leader>wo', ':only<CR>', { desc = 'Close other windows' })

-- Close current window
vim.keymap.set('n', '<leader>wc', ':close<CR>', { desc = 'Close current window' })


vim.api.nvim_set_keymap(
  'n', '<leader>di', ':lua vim.diagnostic.open_float()<CR>',
  { noremap = true, silent = true }
)

-- Format current file (conform locally, site-provided formatter when managed)
vim.keymap.set("n", "<leader>fm", function()
  local ok, conform = pcall(require, "conform")
  if ok and conform then
    conform.format({ async = true, lsp_fallback = true })
  else
    vim.lsp.buf.format({ async = true, timeout_ms = 30000 })
  end
end, { desc = "Format buffer" })
