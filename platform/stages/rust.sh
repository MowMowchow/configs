#!/usr/bin/env bash
# theme-manager is built from source, so cargo is not optional.
rust_check() { need cargo; }
rust_apply() {
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path || return 1
  # shellcheck source=/dev/null
  [ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
  # --no-modify-path keeps rustup out of the user's rc files; zshrc owns PATH.
  # Without this the rest of the run cannot see cargo.
  case ":$PATH:" in *":$HOME/.cargo/bin:"*) ;; *) PATH="$HOME/.cargo/bin:$PATH"; export PATH ;; esac
}
