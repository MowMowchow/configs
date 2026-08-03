#!/usr/bin/env bash
ohmyzsh_check() { [ -d "$HOME/.oh-my-zsh" ]; }
ohmyzsh_apply() {
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    >/dev/null 2>&1
}
