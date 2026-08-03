# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles/config repository for macOS development environment. Configurations are symlinked or sourced from `~/.config/`. The repository prioritizes keyboard-driven workflows with consistent theming across tools, driven by `theme-manager/`.

## Tool Configurations

| Directory | Tool | Key Files |
|-----------|------|-----------|
| `nvim/` | Neovim (primary editor) | See `nvim/CLAUDE.md` for detailed docs |
| `tmux/` | Terminal multiplexer | `tmux.conf` |
| `kitty/` | GPU-accelerated terminal | `kitty.conf`, `jhou.conf` |
| `aerospace/` | macOS tiling window manager | `aerospace.toml` |
| `fish/` | Fish shell | `config.fish` |
| `zshrc` | Zsh config | Root-level file |

## Cross-Tool Conventions

**Theme:** `theme-manager/` (Rust) is the single source of truth for Neovim, Tmux, and Kitty, and follows the macOS dark/light setting. Active family lives in `theme-manager/config.toml` (currently gruvbox-material, medium). Palettes are defined once in `theme-manager/src/theme.rs` — never hardcode hex values elsewhere.

On remote hosts (devserver, OnDemand) there is no theme-manager binary; `tmux/theme-apply.sh` sources the generated `tmux/{dark,light}-theme.auto.conf` instead. Live dark/light following there needs tmux >= 3.6.

**Navigation patterns:**
- Tmux prefix: `Ctrl+S` (not default `Ctrl+B`)
- Kitty: `Cmd+1/2/3` mapped to tmux window switching
- Neovim: Space as leader key
- Aerospace: Tiling via keyboard shortcuts

## Tmux Configuration

Prefix: `Ctrl+S`

| Binding | Action |
|---------|--------|
| `prefix + =` | Vertical split |
| `prefix + -` | Horizontal split |
| `prefix + h/j/k/l` | Navigate panes |
| `prefix + r` | Reload config |

Plugins live in `tmux/plugins/` (TPM). Note: currently empty — TPM is not installed, so the `run '~/.tmux/plugins/tpm/tpm'` line in `tmux.conf` is a no-op and the catppuccin family would fail.

## Kitty Terminal

Font: JetBrainsMono Nerd Font Mono (12pt)

Custom bindings integrate with tmux navigation. Config split between `kitty.conf` (defaults) and `jhou.conf` (personal overrides).

## Making Changes

- Neovim plugins: Add specs to `nvim/lua/jhou/lazy/` (auto-loaded by lazy.nvim)
- Tmux plugins: Add to `tmux/plugins/` and update `tmux.conf`
- Test changes in isolation before committing

## Engineering Principles

Reference `nvim/core_principles.json` for detailed engineering philosophy covering system design, distributed systems, performance optimization, and coding practices.
