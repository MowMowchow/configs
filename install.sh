#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# dotfiles installer — OS dispatcher
#
# Usage:
#   git clone git@github.com:MowMowchow/configs.git ~/.config
#   cd ~/.config && ./install.sh
#
# Detects the host OS and delegates to the platform-specific installer.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)" in
  Darwin)
    exec "$HERE/install-macos.sh" "$@"
    ;;
  Linux)
    if [[ -r /etc/os-release ]] && ! grep -qi '^ID=ubuntu' /etc/os-release; then
      printf '\033[1;33m  ! only Ubuntu is officially supported; trying anyway\033[0m\n' >&2
    fi
    exec "$HERE/install-linux.sh" "$@"
    ;;
  *)
    printf 'unsupported OS: %s\n' "$(uname -s)" >&2
    exit 1
    ;;
esac
