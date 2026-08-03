#!/usr/bin/env bash
# TPM plus the catppuccin plugin. theme-manager's generated conf references
# the catppuccin plugin path behind an if-shell guard, so a missing clone is
# survivable — but the catppuccin family silently does nothing without it.
_TPM="$DOTFILES/tmux/plugins/tpm"
_CATPPUCCIN="$DOTFILES/tmux/plugins/tmux"

tmux_plugins_check() { [ -d "$_TPM" ] && [ -d "$_CATPPUCCIN" ]; }
tmux_plugins_apply() {
  need git || { warn "git missing"; return 1; }
  [ -d "$_TPM" ] || git clone -q https://github.com/tmux-plugins/tpm "$_TPM" \
    || warn "TPM clone failed (offline or proxied?)"
  [ -d "$_CATPPUCCIN" ] || git clone -q https://github.com/catppuccin/tmux "$_CATPPUCCIN" \
    || warn "catppuccin/tmux clone failed"
  return 0
}
