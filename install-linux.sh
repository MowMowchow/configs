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
# Done
# ─────────────────────────────────────────────────────────────────
echo ""
info "install-linux.sh — phases pending: 1.5/2/3/4/5/6/7/8/9/10"
