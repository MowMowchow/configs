#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# dotfiles installer
#
# Usage:
#   git clone git@github.com:MowMowchow/configs.git ~/.config
#   cd ~/.config && ./install.sh
#
# Idempotent — safe to re-run. Skips steps that are already done.
# ─────────────────────────────────────────────────────────────────

DOTFILES="$HOME/.config"
LOCAL_BIN="$HOME/.local/bin"

info()  { printf "\033[1;34m==> %s\033[0m\n" "$1"; }
ok()    { printf "\033[1;32m  ✓ %s\033[0m\n" "$1"; }
warn()  { printf "\033[1;33m  ! %s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m  ✗ %s\033[0m\n" "$1"; }

need() {
  if ! command -v "$1" &>/dev/null; then
    return 1
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────
# Phase 1: Homebrew
# ─────────────────────────────────────────────────────────────────
info "Phase 1: Homebrew"

if need brew; then
  ok "Homebrew already installed"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  ok "Homebrew installed"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 2: Packages
# ─────────────────────────────────────────────────────────────────
info "Phase 2: Homebrew packages"

FORMULAE=(
  tmux neovim eza fastfetch chafa bat
  zsh-syntax-highlighting zoxide fzf ripgrep fd
  node python@3.13 luarocks
  stylua clang-format sqlfluff go
  spicetify-cli
)

CASKS=(
  kitty
  font-jetbrains-mono-nerd-font
  aerospace
)

for f in "${FORMULAE[@]}"; do
  if brew list --formula "$f" &>/dev/null; then
    ok "$f"
  else
    brew install "$f" && ok "$f" || warn "failed to install $f"
  fi
done

for c in "${CASKS[@]}"; do
  if brew list --cask "$c" &>/dev/null; then
    ok "$c (cask)"
  else
    brew install --cask "$c" && ok "$c (cask)" || warn "failed to install $c"
  fi
done

# ─────────────────────────────────────────────────────────────────
# Phase 3: Rust toolchain
# ─────────────────────────────────────────────────────────────────
info "Phase 3: Rust toolchain"

if need rustc; then
  ok "Rust already installed ($(rustc --version))"
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
  ok "Rust installed"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 4: Oh My Zsh
# ─────────────────────────────────────────────────────────────────
info "Phase 4: Oh My Zsh"

if [[ -d "$HOME/.oh-my-zsh" ]]; then
  ok "Oh My Zsh already installed"
else
  RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "Oh My Zsh installed"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 5: Symlinks
# ─────────────────────────────────────────────────────────────────
info "Phase 5: Symlinks"

mkdir -p "$LOCAL_BIN"

link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    ok "$dst (already linked)"
  elif [[ -e "$dst" ]]; then
    warn "$dst exists and is not a symlink — backing up to ${dst}.bak"
    mv "$dst" "${dst}.bak"
    ln -s "$src" "$dst"
    ok "$dst (linked, old file backed up)"
  else
    ln -s "$src" "$dst"
    ok "$dst"
  fi
}

link "$DOTFILES/zshrc"          "$HOME/.zshrc"
link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
link "$DOTFILES/tmux"           "$HOME/.tmux"

# ─────────────────────────────────────────────────────────────────
# Phase 6: Tmux plugins (TPM)
# ─────────────────────────────────────────────────────────────────
info "Phase 6: Tmux plugins"

TPM_DIR="$DOTFILES/tmux/plugins/tpm"
if [[ -d "$TPM_DIR" ]]; then
  ok "TPM already installed"
else
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  ok "TPM installed"
fi

CATPPUCCIN_DIR="$DOTFILES/tmux/plugins/tmux"
if [[ -d "$CATPPUCCIN_DIR" ]]; then
  ok "Catppuccin tmux already installed"
else
  git clone https://github.com/catppuccin/tmux "$CATPPUCCIN_DIR"
  ok "Catppuccin tmux installed"
fi

# Install TPM plugins non-interactively
if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
  "$TPM_DIR/bin/install_plugins" &>/dev/null && ok "TPM plugins installed" || warn "TPM plugin install had issues"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 7: Neovim (lazy.nvim auto-bootstraps on first launch)
# ─────────────────────────────────────────────────────────────────
info "Phase 7: Neovim"

ok "lazy.nvim will auto-bootstrap on first nvim launch"
ok "Mason LSPs will auto-install on first nvim launch"

# Install formatters used by conform.nvim
if need npm; then
  npm list -g prettier &>/dev/null || npm install -g prettier
  ok "prettier"
fi

if need pip3; then
  pip3 install --user --quiet black isort 2>/dev/null && ok "black + isort" || warn "pip install black isort failed"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 8: theme-manager
# ─────────────────────────────────────────────────────────────────
info "Phase 8: theme-manager"

THEME_MGR="$DOTFILES/theme-manager"

if [[ -f "$LOCAL_BIN/theme-manager" ]]; then
  ok "theme-manager binary exists"
else
  if [[ -f "$THEME_MGR/Cargo.toml" ]]; then
    (cd "$THEME_MGR" && cargo build --release)
    cp "$THEME_MGR/target/release/theme-manager" "$LOCAL_BIN/"
    ok "theme-manager built and installed"
  else
    fail "theme-manager source not found at $THEME_MGR"
  fi
fi

# Create default config if it doesn't exist
if [[ ! -f "$THEME_MGR/config.toml" ]]; then
  cat > "$THEME_MGR/config.toml" << 'TOML'
[theme]
family = "gruvbox-material"
variant = "medium"

[paths]
kitty_config = "~/.config/kitty"
tmux_config = "~/.config/tmux"
nvim_socket_pattern = "/tmp/nvim-theme-*.sock"
catppuccin_tmux_plugin = "~/.config/tmux/plugins/tmux/catppuccin.tmux"
TOML
  ok "theme-manager config.toml created"
else
  ok "theme-manager config.toml exists"
fi

# Write kitty auto-conf files
if need theme-manager || [[ -x "$LOCAL_BIN/theme-manager" ]]; then
  "$LOCAL_BIN/theme-manager" apply &>/dev/null && ok "theme applied" || warn "theme apply failed (kitty/tmux may not be running)"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 9: LaunchAgent (theme-manager daemon)
# ─────────────────────────────────────────────────────────────────
info "Phase 9: LaunchAgent"

PLIST_NAME="com.user.theme-manager.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

mkdir -p "$HOME/Library/LaunchAgents"

if [[ -f "$PLIST_DST" ]]; then
  ok "LaunchAgent already exists"
else
  cat > "$PLIST_DST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.theme-manager</string>
    <key>ProgramArguments</key>
    <array>
        <string>$LOCAL_BIN/theme-manager</string>
        <string>watch</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/theme-manager.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/theme-manager.err</string>
</dict>
</plist>
PLIST
  ok "LaunchAgent created"
fi

# Load the agent
launchctl load "$PLIST_DST" 2>/dev/null && ok "daemon loaded" || ok "daemon already loaded"

# ─────────────────────────────────────────────────────────────────
# Phase 10: Secrets reminder
# ─────────────────────────────────────────────────────────────────
info "Phase 10: Secrets"

if [[ -f "$HOME/.secrets" ]]; then
  ok "~/.secrets exists"
else
  warn "~/.secrets not found — create it with your API keys:"
  echo "    cat > ~/.secrets << 'EOF'"
  echo "    EOF"
  echo "    chmod 600 ~/.secrets"
fi

# ─────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────
echo ""
info "Setup complete!"
echo ""
echo "  Next steps:"
echo "    1. Open a new terminal (or run: source ~/.zshrc)"
echo "    2. Open nvim — plugins will auto-install on first launch"
echo "    3. In tmux, press Ctrl+S then I to install TPM plugins"
echo "    4. Create ~/.secrets with your API keys (if not done)"
echo "    5. Run: theme-manager set gruvbox-material medium"
echo ""
