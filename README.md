# dotfiles

macOS dev environment — keyboard-driven, consistently themed, one-command setup. Linux (Ubuntu 26.04 LTS) is supported on a best-effort basis.

## Quick Start

```bash
git clone git@github.com:MowMowchow/configs.git ~/.config
cd ~/.config && ./install.sh
```

`install.sh` detects the host OS and dispatches to `install-macos.sh` or `install-linux.sh`. Both are idempotent — safe to re-run on an existing setup.

### Linux (Ubuntu 26.04 LTS, untested)

The Linux path is best-effort and may need fixing on first run. Notable differences from macOS:

- Auto dark/light switching depends on `gsettings` (works on GNOME — Ubuntu's default; KDE/sway/etc. fall back to 5-second polling).
- `aerospace`, `iterm2`, and `spicetify-cli` are skipped.
- Fonts: apt's `fonts-jetbrains-mono` is installed as a baseline, plus the JetBrainsMono Nerd Font tarball from `github.com/ryanoasis/nerd-fonts` for icon glyphs.
- The theme-manager daemon runs as a `systemd --user` unit instead of a LaunchAgent. Logs: `journalctl --user -u theme-manager`.
- You may need to set zsh as your login shell after install: `chsh -s "$(command -v zsh)"`.

## What's Inside

| Config | Purpose | Key Bindings |
|--------|---------|-------------|
| **nvim/** | Neovim (lazy.nvim, LSP, Treesitter) | `Space` leader |
| **tmux/** | Terminal multiplexer | `Ctrl+S` prefix |
| **kitty/** | GPU terminal emulator | `Cmd+1/2/3` → tmux windows |
| **aerospace/** | Tiling window manager | Keyboard-driven layouts |
| **zshrc** | Zsh + Oh My Zsh + vi-mode | Symlinked to `~/.zshrc` |
| **theme-manager/** | Rust daemon for unified theming | See [theme-manager/README.md](theme-manager/README.md) |
| **eza/** | `ls` replacement config | `ls` aliased to `eza` |
| **fish/** | Fish shell (alt) | — |
| **spicetify/** | Spotify client theming | — |

## Theme System

`theme-manager` is a Rust binary that keeps kitty, neovim, and tmux in sync. It auto-switches between dark/light variants when macOS appearance changes.

```bash
theme-manager set gruvbox-material medium    # set theme + variant
theme-manager apply                          # re-apply current theme
theme-manager list                           # show available themes
theme-manager watch                          # daemon mode (runs via LaunchAgent)
```

Supported families: `gruvbox`, `gruvbox-material`, `catppuccin`

## Install Phases

1. **Homebrew** — package manager
2. **Packages** — tmux, neovim, eza, bat, fzf, ripgrep, fd, node, python, go, etc.
3. **Rust** — toolchain via rustup
4. **Oh My Zsh** — zsh framework + plugins
5. **Symlinks** — `~/.zshrc`, `~/.tmux.conf`, `~/.tmux`
6. **Tmux plugins** — TPM + catppuccin
7. **Neovim** — lazy.nvim auto-bootstraps; formatters (prettier, black, isort) installed
8. **theme-manager** — built from source, installed to `~/.local/bin`
9. **LaunchAgent** — theme-manager daemon starts at login
10. **Secrets** — reminds you to create `~/.secrets` for API keys

## Secrets

API keys live in `~/.secrets` (never committed):

```bash
cat > ~/.secrets << 'EOF'
export OPENAI_API_KEY="..."
export DATABENTO_API_KEY="..."
EOF
chmod 600 ~/.secrets
```

Sourced automatically by `.zshrc`.

## Post-Install

1. Open a new terminal (or `source ~/.zshrc`)
2. Launch `nvim` — plugins auto-install on first run
3. In tmux: `Ctrl+S` then `I` to install TPM plugins
4. Run `theme-manager set gruvbox-material medium`
