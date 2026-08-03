#!/usr/bin/env bash
# macOS platform layer. Sourced by install.sh after platform/common.sh.

BREW_FORMULAE=(
  tmux neovim eza fastfetch bat chafa
  zsh-syntax-highlighting zoxide fzf ripgrep fd
  node python@3.13 luarocks
  stylua clang-format go
  # nvim-treesitter's main branch is a parser *installer*: it shells out to
  # this to compile every grammar, so without it no parser builds and nothing
  # highlights. Linux gets it from _install_cargo_tools; the Mac had no path
  # to it at all. See nvim/lua/jhou/lazy/treesitter.lua (needs >= 0.26.1).
  tree-sitter-cli
  spicetify-cli
)

BREW_CASKS=(
  kitty
  font-jetbrains-mono-nerd-font
  aerospace
)

platform_install_packages() {
  info "Homebrew"
  if need brew; then
    ok "Homebrew already installed"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    ok "Homebrew installed"
  fi

  info "Packages (brew)"
  for f in "${BREW_FORMULAE[@]}"; do
    if brew list --formula "$f" >/dev/null 2>&1; then
      ok "$f"
    else
      brew install "$f" >/dev/null 2>&1 && ok "$f" || warn "failed to install $f"
    fi
  done
  for c in "${BREW_CASKS[@]}"; do
    if brew list --cask "$c" >/dev/null 2>&1; then
      ok "$c (cask)"
    else
      brew install --cask "$c" >/dev/null 2>&1 && ok "$c (cask)" || warn "failed to install $c"
    fi
  done
}

platform_install_daemon() {
  info "theme-manager service (LaunchAgent)"

  local plist="$HOME/Library/LaunchAgents/com.user.theme-manager.plist"
  mkdir -p "$(dirname "$plist")"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.user.theme-manager</string>
  <key>ProgramArguments</key>
  <array>
    <string>$LOCAL_BIN/theme-manager</string>
    <string>watch</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/theme-manager.log</string>
  <key>StandardErrorPath</key><string>/tmp/theme-manager.err</string>
</dict>
</plist>
EOF
  ok "wrote $plist"

  # bootout+bootstrap is the modern replacement for unload/load, and
  # kickstart -k restarts an already-running one onto the new binary.
  launchctl bootout "gui/$(id -u)/com.user.theme-manager" 2>/dev/null || true
  if launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null; then
    ok "loaded"
  else
    launchctl kickstart -k "gui/$(id -u)/com.user.theme-manager" 2>/dev/null \
      && ok "restarted" || warn "could not load the LaunchAgent"
  fi

  echo "      logs: tail -f /tmp/theme-manager.err"
}

platform_notes() {
  echo "  - Appearance follows the system setting (System Settings > Appearance)."
  echo "  - kitty picks dark/light itself from the generated *.auto.conf files."
}

# ── Platform helpers used by the shared stages ───────────────────

# Homebrew's font cask handles this; if the cask installed, the font is there.
platform_fonts_present() {
  brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1
}
platform_install_fonts() {
  brew install --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1
}

# macOS has no PEP 668 restriction, but pipx keeps the tools isolated and
# matches what Linux does, so the two platforms behave the same way.
platform_install_pyformatters() {
  need pipx || brew install pipx >/dev/null 2>&1
  need pipx || { warn "pipx unavailable — black/isort skipped"; return 0; }
  for p in black isort; do
    need "$p" || pipx install "$p" >/dev/null 2>&1 || warn "pipx install $p failed"
  done
  return 0
}

platform_service_running() {
  launchctl print "gui/$(id -u)/com.user.theme-manager" >/dev/null 2>&1
}

# ── Stage registration ───────────────────────────────────────────
# No `keybinds` stage: xremap is Linux-only and aerospace is configured
# declaratively rather than installed by a stage.

stage site_bootstrap work
stage packages
stage fonts
stage rust
stage ohmyzsh
stage symlinks
stage tmux_plugins
stage formatters
stage theme_manager
stage service
stage login_shell
stage secrets
