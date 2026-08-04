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
    -- Deferred to first use. Fugitive defines these up front; anything not
    -- listed would not trigger a load, so the list is deliberately broad.
    cmd = {
      "G", "Git", "Gedit", "Gsplit", "Gvsplit", "Gtabedit",
      "Gdiffsplit", "Gvdiffsplit", "Gread", "Gwrite", "Gwq",
      "Ggrep", "Glgrep", "Gclog", "Gllog", "GMove", "GRename",
      "GDelete", "GRemove", "GBrowse",
    },
  },
}
