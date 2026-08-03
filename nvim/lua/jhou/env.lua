-- Environment detection for conditional plugin loading.
--
-- Site plugins (see ~/.config/site/README.md) may ship an `nvim/init.lua`
-- returning:
--
--   { managed = <bool>, specs = { <lazy.nvim specs> } }
--
-- `managed = true` means that plugin supplies its own LSP, formatter and VCS
-- stack, so the portable defaults in jhou/lazy/ stand down rather than fight
-- it. Nothing here knows about any particular employer — the public config
-- only knows that *a* site plugin is present and what it claims to own.

local M = {}

M.plugins = {} -- loaded site nvim modules, in discovery order
M.specs = {} -- their combined lazy.nvim specs
M.managed = false -- does a site plugin own the language tooling?

local site_root = vim.fn.expand("~/.config/site")

for _, entry in ipairs(vim.fn.glob(site_root .. "/*/nvim/init.lua", false, true)) do
  local ok, mod = pcall(dofile, entry)
  if ok and type(mod) == "table" then
    table.insert(M.plugins, mod)
    if mod.managed then
      M.managed = true
    end
    for _, spec in ipairs(mod.specs or {}) do
      table.insert(M.specs, spec)
    end
  else
    -- Loud, not silent: a broken site plugin should be visible, but must not
    -- take the editor down with it.
    vim.notify(
      ("site nvim plugin failed to load: %s\n%s"):format(entry, tostring(mod)),
      vim.log.levels.WARN
    )
  end
end

return M
