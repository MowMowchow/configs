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
  tmux eza fastfetch chafa bat
  zsh-syntax-highlighting zoxide fzf ripgrep fd-find
  python3 python3-pip python3-venv pipx
  luarocks clang-format golang-go kitty
)
# Note: neovim is installed via snap below (apt ships 0.9.5; we need >= 0.11).
# kitty is in apt as a baseline (and for desktop entries / mime associations);
# the upstream tarball below overrides /usr/bin/kitty via $LOCAL_BIN precedence
# because apt's 0.32.2 lacks the native dark/light auto-switching from 0.36+.

sudo apt-get install -y -qq "${APT_PKGS[@]}"
for p in "${APT_PKGS[@]}"; do
  ok "$p"
done

# Neovim — our plugin set requires >= 0.11:
#   - blink.cmp hard-requires 0.10
#   - lsp.lua uses vim.lsp.config / vim.lsp.enable (added in 0.11)
#   - mason-lspconfig automatic_enable assumes vim.lsp.enable
# Ubuntu's apt ships 0.9.5, so we use the snap (tracks latest stable, currently
# v0.12.2). If apt's neovim is already installed, remove it first so $PATH
# resolves to /snap/bin/nvim and not /usr/bin/nvim.
if snap list nvim >/dev/null 2>&1; then
  ok "nvim $(snap list nvim | awk 'NR==2 {print $2}') (snap)"
else
  if dpkg -l neovim 2>/dev/null | grep -q '^ii'; then
    sudo apt-get remove -y -qq neovim
  fi
  if sudo snap install nvim --classic; then
    ok "nvim $(snap list nvim | awk 'NR==2 {print $2}') (snap)"
  else
    warn "snap install nvim failed — your plugin set requires >= 0.11; plugins will not bootstrap"
  fi
fi

# Kitty — apt ships 0.32.2; we need >= 0.36 for the native dark/light
# `*.auto.conf` auto-switching the theme-manager design depends on. There's
# no good apt PPA or snap for kitty, so we install the upstream tarball into
# ~/.local/kitty.app and shim via ~/.local/bin. Bump KITTY_VERSION to upgrade.
KITTY_VERSION="${KITTY_VERSION:-0.46.2}"
KITTY_DIR="$HOME/.local/kitty.app"
kitty_installed_version() {
  [[ -x "$KITTY_DIR/bin/kitty" ]] || return 1
  "$KITTY_DIR/bin/kitty" --version 2>/dev/null | awk '{print $2}'
}
if [[ "$(kitty_installed_version)" == "$KITTY_VERSION" ]]; then
  ok "kitty $KITTY_VERSION (tarball)"
else
  info "  installing kitty $KITTY_VERSION (apt's 0.32.2 lacks native auto-switching)"
  TMP_KITTY="$(mktemp -d)"
  if curl -fsSL "https://github.com/kovidgoyal/kitty/releases/download/v${KITTY_VERSION}/kitty-${KITTY_VERSION}-x86_64.txz" \
       -o "$TMP_KITTY/kitty.txz" \
     && mkdir -p "$KITTY_DIR" \
     && tar -xJf "$TMP_KITTY/kitty.txz" -C "$KITTY_DIR"; then
    ln -sf "$KITTY_DIR/bin/kitty"  "$LOCAL_BIN/kitty"
    ln -sf "$KITTY_DIR/bin/kitten" "$LOCAL_BIN/kitten"
    ok "kitty $KITTY_VERSION -> $LOCAL_BIN/kitty (overrides apt kitty via PATH precedence)"
  else
    warn "kitty $KITTY_VERSION tarball install failed — apt 0.32.2 remains; native auto-switching unavailable"
  fi
  rm -rf "$TMP_KITTY"
fi

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

# Sapling (Meta's source control client). Upstream stopped shipping .debs
# in May 2025; the canonical install on Linux is the upstream tarball
# (https://sapling-scm.com/docs/introduction/installation/). We extract to
# ~/.local/share/sapling (upstream's recommended location) and symlink
# `sl` into ~/.local/bin so it lands on PATH without modifying zshrc.
SAPLING_VERSION="${SAPLING_VERSION:-0.2.20260317-201835+0234c21f}"
SAPLING_DIR="$HOME/.local/share/sapling"
sapling_installed_version() {
  [[ -x "$SAPLING_DIR/sl" ]] || return 1
  "$SAPLING_DIR/sl" --version 2>/dev/null | head -1 | awk '{print $2}'
}
if [[ "$(sapling_installed_version)" == "$SAPLING_VERSION" ]]; then
  ok "sapling $SAPLING_VERSION (tarball)"
else
  info "  installing sapling $SAPLING_VERSION (no apt/snap path on Linux)"
  ARCH="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')"
  # The version string contains a literal '+'; URL-encode it as %2B in the
  # path segment but leave it as-is in the filename (matches upstream URLs).
  SAPLING_TAG_ENC="${SAPLING_VERSION//+/%2B}"
  SAPLING_URL="https://github.com/facebook/sapling/releases/download/${SAPLING_TAG_ENC}/sapling-${SAPLING_VERSION}-linux-${ARCH}.tar.xz"
  mkdir -p "$SAPLING_DIR"
  if curl -fsSL "$SAPLING_URL" | tar -xJf - -C "$SAPLING_DIR"; then
    ln -sf "$SAPLING_DIR/sl" "$LOCAL_BIN/sl"
    ok "sapling $SAPLING_VERSION -> $LOCAL_BIN/sl"
  else
    warn "sapling tarball download failed — sl unavailable"
  fi
fi

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

# tree-sitter-cli >= 0.26.1 is required by nvim-treesitter v1.0 (main branch).
# apt's 0.20.8 is too old. We disable default features to skip the `wasm`
# feature, which pulls in rquickjs-sys — that needs libclang's stdbool.h
# search path and fails on a vanilla Ubuntu 24.04 box.
if need tree-sitter && [[ "$(tree-sitter --version 2>/dev/null | awk '{print $2}' | cut -d. -f2)" -ge 26 ]]; then
  ok "tree-sitter $(tree-sitter --version | awk '{print $2}') already installed"
else
  cargo install tree-sitter-cli --no-default-features --quiet
  ok "tree-sitter-cli (cargo, no wasm feature)"
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
  pipx install black >/dev/null 2>&1 && ok "black (pipx)" || warn "black install failed (may already be installed)"
  pipx install isort >/dev/null 2>&1 && ok "isort (pipx)" || warn "isort install failed (may already be installed)"
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
# Phase 9: systemd user unit (theme-manager daemon)
# ─────────────────────────────────────────────────────────────────
info "Phase 9: systemd user unit"

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
UNIT_FILE="$SYSTEMD_USER_DIR/theme-manager.service"

mkdir -p "$SYSTEMD_USER_DIR"

cat > "$UNIT_FILE" << 'UNIT'
[Unit]
Description=theme-manager appearance daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=%h/.local/bin/theme-manager watch
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
UNIT
ok "theme-manager.service written"

if systemctl --user daemon-reload 2>/dev/null; then
  systemctl --user enable --now theme-manager.service 2>/dev/null && ok "daemon enabled + started" || warn "could not enable daemon (no systemd --user session?)"
else
  warn "systemctl --user not available — daemon will not auto-start"
fi

# ─────────────────────────────────────────────────────────────────
# Phase 10: Secrets reminder
# ─────────────────────────────────────────────────────────────────
info "Phase 10: Secrets"

if [[ -f "$HOME/.secrets" ]]; then
  ok "~/.secrets exists"
else
  warn "~/.secrets not found — create it with your API keys:"
  echo "    cat > ~/.secrets << 'EOF'"
  echo "    export OPENAI_API_KEY=\"...\""
  echo "    EOF"
  echo "    chmod 600 ~/.secrets"
fi

# ─────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────
echo ""
info "Setup complete!"
echo ""
echo "  Linux notes (untested path — expect rough edges):"
echo "    - Auto dark/light requires gsettings (works under GNOME)"
echo "    - aerospace, iterm2, spicetify-cli are skipped"
echo "    - If your shell is still bash: chsh -s \"\$(command -v zsh)\" + log out"
echo ""
echo "  Next steps:"
echo "    1. Open a new terminal (or run: source ~/.zshrc)"
echo "    2. Open nvim — plugins will auto-install on first launch"
echo "    3. In tmux, press Ctrl+S then I to install TPM plugins"
echo "    4. Create ~/.secrets with your API keys (if not done)"
echo "    5. Run: theme-manager set gruvbox-material medium"
echo ""
