-- VCS — dual-mode
-- Devserver/OD: meta.hg for Mercurial/Sapling (configured in meta.lua).
-- Local Mac: vim-fugitive for git.

local site_managed = require("jhou.env").managed

if site_managed then
  return {}
end

return {
  {
    "tpope/vim-fugitive",
  },
}
