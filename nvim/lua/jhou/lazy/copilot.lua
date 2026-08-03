-- AI completions — dual-mode
-- Devserver/OD: Metamate (configured in meta.lua).
-- Local Mac: disabled (uncomment copilot below if desired).

local site_managed = require("jhou.env").managed

if site_managed then
  return {}
end

-- Uncomment to enable GitHub Copilot on local Mac:
-- return {
--   "github/copilot.vim",
--   config = function()
--     vim.api.nvim_set_keymap(
--       'i', '<C-g>', 'copilot#Accept()', { expr = true, silent = true, noremap = false }
--     )
--   end,
-- }

return {}
