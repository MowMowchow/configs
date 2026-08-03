#!/usr/bin/env bash
# Nerd Font glyphs. Without these, eza/lualine/tmux icons render as boxes.
fonts_check() {
  if declare -f platform_fonts_present >/dev/null; then platform_fonts_present; else return 0; fi
}
fonts_apply() {
  if declare -f platform_install_fonts >/dev/null; then platform_install_fonts; else return 0; fi
}
