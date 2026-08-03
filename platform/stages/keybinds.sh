#!/usr/bin/env bash
# macOS-style Super shortcuts on Linux (xremap). No macOS analogue — the
# manifest simply does not register this stage there.
keybinds_check() {
  if declare -f platform_keybinds_present >/dev/null; then platform_keybinds_present; else return 0; fi
}
keybinds_apply() {
  if declare -f platform_install_keybinds >/dev/null; then platform_install_keybinds; else return 0; fi
}
keybinds_verify() { return 0; }   # needs a logout/login to take effect
