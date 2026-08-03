#!/usr/bin/env bash
# Symlink the three files that must live outside ~/.config.

_SYMLINKS="zshrc:$HOME/.zshrc zprofile:$HOME/.zprofile tmux/tmux.conf:$HOME/.tmux.conf tmux:$HOME/.tmux"

symlinks_check() {
  local pair src dst
  for pair in $_SYMLINKS; do
    src="$DOTFILES/${pair%%:*}"; dst="${pair#*:}"
    [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ] || return 1
  done
  return 0
}

symlinks_apply() {
  local pair
  for pair in $_SYMLINKS; do
    link "$DOTFILES/${pair%%:*}" "${pair#*:}"
  done
}
