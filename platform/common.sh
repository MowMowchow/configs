#!/usr/bin/env bash
# Shared helpers and OS detection for the installer.
# Sourced by install.sh and by platform/<os>.sh — never executed directly.

DOTFILES="${DOTFILES:-$HOME/.config}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"

info() { printf "\033[1;34m==> %s\033[0m\n" "$1"; }
ok()   { printf "\033[1;32m  ✓ %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m  ! %s\033[0m\n" "$1"; }
fail() { printf "\033[1;31m  ✗ %s\033[0m\n" "$1"; }

need() { command -v "$1" >/dev/null 2>&1; }

# Symlink $2 -> $1, backing up anything already there.
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    ok "$dst (already linked)"
  elif [ -e "$dst" ] || [ -L "$dst" ]; then
    mv "$dst" "$dst.bak"
    ln -s "$src" "$dst"
    ok "$dst (linked, old backed up to $dst.bak)"
  else
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    ok "$dst"
  fi
}

# Echoes one of: macos, ubuntu, debian, linux, unsupported
detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux)
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}${ID_LIKE:-}" in
          *ubuntu*) echo ubuntu ;;
          *debian*) echo debian ;;
          *) echo linux ;;
        esac
      else
        echo linux
      fi
      ;;
    *) echo unsupported ;;
  esac
}

# Which platform script implements this OS. Debian and unknown Linux both use
# the linux layer; it degrades rather than assuming apt exists.
platform_script_for() {
  case "$1" in
    macos) echo "$DOTFILES/platform/macos.sh" ;;
    ubuntu | debian | linux) echo "$DOTFILES/platform/linux.sh" ;;
    *) echo "" ;;
  esac
}

# ── Portable phases (identical on every OS) ──────────────────────

install_symlinks() {
  info "Symlinks"
  link "$DOTFILES/zshrc" "$HOME/.zshrc"
  link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
  link "$DOTFILES/tmux" "$HOME/.tmux"
}

install_tmux_plugins() {
  info "Tmux plugins"
  local tpm="$DOTFILES/tmux/plugins/tpm"
  if [ -d "$tpm" ]; then
    ok "TPM already installed"
  elif need git; then
    git clone -q https://github.com/tmux-plugins/tpm "$tpm" && ok "TPM installed" \
      || warn "TPM clone failed (offline or proxied network?)"
  else
    warn "git not available — skipping TPM"
  fi
}

build_theme_manager() {
  info "theme-manager"
  if ! need cargo; then
    warn "cargo not found — skipping theme-manager build"
    return
  fi
  ( cd "$DOTFILES/theme-manager" && cargo build --release ) || { fail "build failed"; return 1; }
  mkdir -p "$LOCAL_BIN"
  # rm before cp: overwriting a running binary in place invalidates its code
  # signature on macOS and every later invocation dies with SIGKILL.
  rm -f "$LOCAL_BIN/theme-manager"
  cp "$DOTFILES/theme-manager/target/release/theme-manager" "$LOCAL_BIN/theme-manager"
  ok "theme-manager -> $LOCAL_BIN"
}

# Run every site plugin's bootstrap.sh. See site/README.md.
run_site_bootstrap() {
  info "Site plugins"
  local found=0
  for manifest in "$DOTFILES"/site/*/plugin.toml; do
    [ -r "$manifest" ] || continue
    local dir name
    dir="$(dirname "$manifest")"
    name="$(basename "$dir")"
    found=1
    if [ -x "$dir/bootstrap.sh" ]; then
      info "  bootstrapping site:$name"
      bash "$dir/bootstrap.sh" || warn "site:$name bootstrap returned non-zero"
    else
      ok "site:$name (no bootstrap.sh)"
    fi
  done
  [ "$found" -eq 0 ] && ok "none installed"
  return 0
}
