# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles/config repository. The repo *is* `~/.config`. Runs on **macOS** and
**Ubuntu 24.04 LTS+** (24.04 is the primary Linux target; 26.04 best-effort). Keyboard-driven
workflows with consistent theming across tools, driven by `theme-manager/`.

`./install.sh` detects the OS and dispatches to `platform/{macos,linux}.sh`. Nothing OS-specific
lives outside `platform/`. Work is decomposed into stages under `platform/stages/`, each a file
implementing `<name>_check` / `<name>_apply` / optional `<name>_verify`, run by `platform/stage.sh`.
Stages must be idempotent: `_apply` has to achieve exactly what `_check` tests for, so a second
run is a no-op.

Shared shell code must stay **bash 3.2 compatible** — macOS ships 3.2.57 and always will. No
associative arrays, no `${x,,}`, no `[[ =~ ]]` where it can be avoided.

## Before Committing

`make check` — runs `check-public` (privacy guard), `lint-tmux`, and the theme-manager tests.
Publishing goes through `./publish.sh`, never a direct push; see `PUBLISHING.md`.

`site/` holds employer/machine-specific plugins and is gitignored in full except `README.md`
and `example/`. Nothing internal may reach a tracked file — `make check-public` enforces it.

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

Plugins live in `tmux/plugins/` (TPM, installed).

**Format-string gotcha.** tmux formats are not shell. `#{window_name:0:20}` is shell substring
syntax; tmux has no such modifier, does not warn, and silently expands the whole thing to the
empty string — a blank status bar with nothing anywhere saying why. Truncation is `#{=20:var}`.
`make lint-tmux` guards against this class; run it after editing any `tmux/*.conf`.

**Ownership.** `theme-manager` (or `tmux/theme-apply.sh` on hosts without the binary) owns every
colour and both `window-status-*` formats — it sources a palette conf at the bottom of
`tmux.conf`. The plain formats set in `tmux.conf` are only the fallback for before that runs.
Because sourcing `tmux.conf` re-asserts those fallbacks over the themed values, `theme-apply.sh
--init` deliberately bypasses its `@theme_state` cache and re-sources unconditionally; without
that, `prefix + r` strips the theme until the theme identity happens to change.

## Kitty Terminal

Font: JetBrainsMono Nerd Font Mono (12pt)

Custom bindings integrate with tmux navigation. Config split between `kitty.conf` (defaults) and `jhou.conf` (personal overrides).

## Making Changes

- Neovim plugins: Add specs to `nvim/lua/jhou/lazy/` (auto-loaded by lazy.nvim)
- Tmux plugins: Add to `tmux/plugins/` and update `tmux.conf`
- Test changes in isolation before committing

## Engineering Principles

Reference `nvim/core_principles.json` for detailed engineering philosophy covering system design, distributed systems, performance optimization, and coding practices.
