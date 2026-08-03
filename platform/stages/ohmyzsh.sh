#!/usr/bin/env bash
ohmyzsh_check() { [ -d "$HOME/.oh-my-zsh" ]; }
# KEEP_ZSHRC=yes is not optional here. Without it, upstream's setup_zshrc
# moves an existing ~/.zshrc aside and writes its own template — and ours is
# the symlink to this repo, so a re-run after a failed first attempt (the
# `./install.sh --only ohmyzsh` workflow the README suggests) would replace
# the whole config with the stock one. With KEEP_ZSHRC upstream returns before
# both that move and its [Y/n] overwrite prompt.
#
# </dev/null for the prompt specifically: stdout and stderr are discarded but
# stdin stays attached to the tty, so if upstream ever does prompt, the
# question is invisible and the stage hangs with no indication why.
ohmyzsh_apply() {
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    >/dev/null 2>&1 </dev/null
}
