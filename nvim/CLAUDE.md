# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Neovim configuration using lazy.nvim as the plugin manager. The configuration is written in Lua and follows a modular structure.

## Architecture

```
init.lua                    # Entry point - loads jhou module
lua/jhou/
  init.lua                  # Main module - loads remap, settings, lazy_init, extra
  remap.lua                 # Key mappings (leader = space)
  settings.lua              # Editor settings (tabs, numbers, etc.)
  extra.lua                 # Autocommands (yank highlight)
  lazy_init.lua             # lazy.nvim bootstrap and setup
  lazy/                     # Plugin specs (auto-loaded by lazy.nvim)
```

## Key Bindings Reference

Leader key: `<Space>`

| Mapping | Action |
|---------|--------|
| `<leader>pv` | Open netrw file explorer |
| `<leader>pf` | Telescope find files |
| `<leader>pg` | Telescope live grep |
| `<leader>sr` | LSP rename symbol |
| `<leader>fm` | Format buffer (conform.nvim) |
| `<leader>di` | Show diagnostics float |
| `<leader>pd` | Peek definition (lspsaga) |
| `<leader>ptd` | Peek type definition (lspsaga) |
| `<leader>gd` | Go to definition (lspsaga) |
| `<leader>gtd` | Go to type definition (lspsaga) |
| `<leader>f` | Find references/implementations (lspsaga) |
| `<leader>hh` | Hover info (lspsaga) |
| `<leader>ha` | Harpoon add file |
| `<leader>hl` | Harpoon list |
| `<C-p>` / `<C-n>` | Harpoon prev/next |
| `<leader>wvs` | Vertical split |
| `<leader>wl` / `<leader>wr` | Navigate left/right windows |
| `<leader>wo` | Close other windows |
| `<leader>wc` | Close current window |

## LSP Configuration

Mason-managed servers (auto-installed):
- `lua_ls` - Lua
- `rust_analyzer` - Rust
- `basedpyright` - Python (with relaxed type checking)
- `clangd` - C/C++
- `ts_ls` - TypeScript/JavaScript
- `snyk_ls` - Security scanning

## Formatting (conform.nvim)

Format on save is enabled. Formatters by filetype:
- JS/TS/Web: prettier
- Rust: rustfmt
- Python: isort + black
- Go: gofmt + goimports
- C/C++: clang_format
- Lua: stylua
- SQL: sqlfluff (postgres dialect)

## Adding New Plugins

Create a new file in `lua/jhou/lazy/` returning a lazy.nvim plugin spec table. The file will be auto-loaded.
