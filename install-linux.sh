#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# dotfiles installer — Ubuntu 26.04 LTS
#
# Usage:
#   ./install.sh   (which exec's into this script on Linux)
#
# Idempotent — safe to re-run. Skips steps already done.
# ─────────────────────────────────────────────────────────────────

DOTFILES="$HOME/.config"
LOCAL_BIN="$HOME/.local/bin"

info()  { printf "\033[1;34m==> %s\033[0m\n" "$1"; }
ok()    { printf "\033[1;32m  ✓ %s\033[0m\n" "$1"; }
warn()  { printf "\033[1;33m  ! %s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m  ✗ %s\033[0m\n" "$1"; }

need() {
  command -v "$1" >/dev/null 2>&1
}

# Idempotent symlink: if dst is already a symlink (any target) we leave it;
# if it's a regular file we move to .bak first; otherwise we link fresh.
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

# ─────────────────────────────────────────────────────────────────
# Phase 1: apt prelude
# ─────────────────────────────────────────────────────────────────
info "Phase 1: apt prelude"

if [[ $EUID -eq 0 ]]; then
  fail "do not run as root; this script will sudo when needed"
  exit 1
fi

# Prime sudo cache, then refresh in the background so long phases don't time out.
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

sudo apt-get update -qq
ok "apt updated"

# ─────────────────────────────────────────────────────────────────
# Phase 1.5: Fonts (apt fallback + Nerd Font tarball)
# ─────────────────────────────────────────────────────────────────
info "Phase 1.5: Fonts"

sudo apt-get install -y -qq fonts-jetbrains-mono
ok "fonts-jetbrains-mono (apt baseline)"

NF_DIR="$HOME/.local/share/fonts/JetBrainsMono-NerdFont"
if [[ -d "$NF_DIR" ]] && find "$NF_DIR" -name '*.ttf' -print -quit | grep -q .; then
  ok "JetBrainsMono Nerd Font already installed"
else
  mkdir -p "$NF_DIR"
  TMP="$(mktemp -d)"
  if curl -fsSL -o "$TMP/JetBrainsMono.tar.xz" \
       https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz; then
    tar -xf "$TMP/JetBrainsMono.tar.xz" -C "$NF_DIR"
    fc-cache -f "$NF_DIR" >/dev/null
    ok "JetBrainsMono Nerd Font installed (tarball)"
  else
    warn "Nerd Font download failed — apt fallback in use; icons may render as boxes"
  fi
  rm -rf "$TMP"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 2: apt packages + supplemental installs
# ─────────────────────────────────────────────────────────────────
info "Phase 2: apt packages"

APT_PKGS=(
  tmux neovim eza neofetch bat
  zsh-syntax-highlighting zoxide fzf ripgrep fd-find
  python3 python3-pip python3-venv pipx
  luarocks clang-format golang-go kitty
)

sudo apt-get install -y -qq "${APT_PKGS[@]}"
for p in "${APT_PKGS[@]}"; do
  ok "$p"
done

# NodeSource: apt's nodejs lags; install LTS via the official deb script
# if no recent node is already on PATH.
if need node && [[ "$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)" -ge 20 ]]; then
  ok "node $(node --version) already installed"
else
  info "  installing Node.js LTS via NodeSource"
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y -qq nodejs
  ok "node $(node --version)"
fi

# spicetify-cli — print hint, do not auto-install (snap Spotify breaks it).
if ! need spicetify; then
  warn "spicetify-cli not installed (Linux Spotify is typically snap; spicetify needs a writable Spotify dir which snap blocks)"
  warn "  see https://spicetify.app/docs/getting-started if you want it"
fi

# aerospace — macOS-only, no auto-install on Linux.
warn "aerospace is macOS-only — see sway / i3 / hyprland for Linux tiling WMs"

# ─────────────────────────────────────────────────────────────────
# Phase 3: Rust toolchain (via rustup)
# ─────────────────────────────────────────────────────────────────
info "Phase 3: Rust toolchain"

if need rustc; then
  ok "Rust already installed ($(rustc --version))"
else
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"
  ok "Rust installed"
fi

# stylua + sqlfluff — not in apt
if need stylua; then
  ok "stylua already installed"
else
  cargo install stylua --quiet
  ok "stylua"
fi

if need sqlfluff; then
  ok "sqlfluff already installed"
else
  pipx install sqlfluff
  ok "sqlfluff"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 4: Oh My Zsh
# ─────────────────────────────────────────────────────────────────
info "Phase 4: Oh My Zsh"

if [[ -d "$HOME/.oh-my-zsh" ]]; then
  ok "Oh My Zsh already installed"
else
  sudo apt-get install -y -qq zsh
  RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "Oh My Zsh installed"
fi

# We don't run chsh automatically — that changes the login shell, which
# is a user-affecting decision. Print a hint instead.
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
  warn "default shell is not zsh — run: chsh -s \"\$(command -v zsh)\" then log out and back in"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 5: Symlinks + ~/.local/bin shims
# ─────────────────────────────────────────────────────────────────
info "Phase 5: Symlinks"

mkdir -p "$LOCAL_BIN"

link "$DOTFILES/zshrc"          "$HOME/.zshrc"
link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
link "$DOTFILES/tmux"           "$HOME/.tmux"

# Ubuntu installs `bat` as `batcat` and `fd` as `fdfind` to avoid name
# collisions with older packages. The rest of the dotfiles assume the
# standard names — symlinks bridge the gap with no per-OS branching.
if [[ -x /usr/bin/batcat ]]; then
  link "/usr/bin/batcat" "$LOCAL_BIN/bat"
fi
if [[ -x /usr/bin/fdfind ]]; then
  link "/usr/bin/fdfind" "$LOCAL_BIN/fd"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 6: Tmux plugins (TPM + Catppuccin)
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

if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
  "$TPM_DIR/bin/install_plugins" >/dev/null 2>&1 && ok "TPM plugins installed" || warn "TPM plugin install had issues"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 7: Neovim formatters (lazy.nvim auto-bootstraps on first launch)
# ─────────────────────────────────────────────────────────────────
info "Phase 7: Neovim"

ok "lazy.nvim will auto-bootstrap on first nvim launch"
ok "Mason LSPs will auto-install on first nvim launch"

if need npm; then
  if npm list -g prettier >/dev/null 2>&1; then
    ok "prettier (npm)"
  else
    sudo npm install -g prettier
    ok "prettier (npm)"
  fi
fi

# Ubuntu 26.04 enforces PEP 668 — pip3 install --user is blocked. Use pipx.
if need pipx; then
  pipx install black >/dev/null 2>&1 || true
  pipx install isort >/dev/null 2>&1 || true
  ok "black + isort (pipx)"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 8: theme-manager (build + install + initial config)
# ─────────────────────────────────────────────────────────────────
info "Phase 8: theme-manager"

THEME_MGR="$DOTFILES/theme-manager"

if [[ -f "$LOCAL_BIN/theme-manager" ]]; then
  ok "theme-manager binary exists"
else
  if [[ -f "$THEME_MGR/Cargo.toml" ]]; then
    ( cd "$THEME_MGR" && cargo build --release )
    cp "$THEME_MGR/target/release/theme-manager" "$LOCAL_BIN/"
    ok "theme-manager built and installed"
  else
    fail "theme-manager source not found at $THEME_MGR"
  fi
fi

# Default config — only if missing.
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

# Apply once so kitty *.auto.conf files are written. Failure is non-fatal
# — kitty / tmux may not be running yet on a fresh box.
"$LOCAL_BIN/theme-manager" apply >/dev/null 2>&1 && ok "theme applied" || warn "theme apply failed (kitty/tmux may not be running)"

# ─────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────
echo ""
info "install-linux.sh — phases pending: 9/10"
