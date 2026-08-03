#!/usr/bin/env bash
# Build the Rust binary and install it. Deliberately rm-then-cp: overwriting
# a running binary in place invalidates its code signature on macOS and every
# later invocation dies with SIGKILL.
theme_manager_check() {
  [ -x "$LOCAL_BIN/theme-manager" ] || return 1
  # Rebuild when the source is newer than the installed binary.
  [ -z "$(find "$DOTFILES/theme-manager/src" -newer "$LOCAL_BIN/theme-manager" -name '*.rs' -print -quit 2>/dev/null)" ]
}

theme_manager_apply() {
  need cargo || { warn "cargo missing — cannot build theme-manager"; return 1; }
  ( cd "$DOTFILES/theme-manager" && cargo build --release ) || return 1
  mkdir -p "$LOCAL_BIN"
  rm -f "$LOCAL_BIN/theme-manager"
  cp "$DOTFILES/theme-manager/target/release/theme-manager" "$LOCAL_BIN/theme-manager"

  _seed_theme_config

  # Generate the theme artifacts kitty and tmux read. Non-fatal: a headless
  # box has no appearance to apply and that is not an error.
  "$LOCAL_BIN/theme-manager" apply >/dev/null 2>&1 || true
}

# config.toml holds the active theme, which changes whenever you run
# `theme-manager set`, so it is gitignored rather than tracked — otherwise the
# working tree is permanently dirty and every pull conflicts on it.
#
# The consequence is that a fresh clone has no config, and the binary's
# built-in default is catppuccin/mocha, not the gruvbox-material this setup
# actually uses. So seed it here. Only when missing: never clobber a choice
# the user has already made.
_seed_theme_config() {
  local cfg="$DOTFILES/theme-manager/config.toml"
  if [ -f "$cfg" ]; then
    ok "theme config exists ($(sed -n 's/^family = "\(.*\)"/\1/p' "$cfg" | head -1))"
    return 0
  fi
  cat > "$cfg" <<'TOML'
[theme]
family = "gruvbox-material"
variant = "medium"

[paths]
kitty_config = "~/.config/kitty"
tmux_config = "~/.config/tmux"
nvim_socket_pattern = "/tmp/nvim-theme-*.sock"
catppuccin_tmux_plugin = "~/.config/tmux/plugins/tmux/catppuccin.tmux"
TOML
  ok "theme config seeded (gruvbox-material / medium)"
}

# `get` and not `--version`: the clap command has no version attribute, so
# `--version` exits 2 ("unexpected argument") and this reported UNVERIFIED
# after every successful build. `get` just reads config.toml, so it works
# headlessly, and unlike a check for the file it proves the binary actually
# executes — which is what catches a broken code signature on macOS, where
# overwriting the running binary makes every later invocation die on SIGKILL.
# Not `doctor`: that deliberately exits non-zero when it finds problems, such
# as an undeterminable appearance on a headless box.
theme_manager_verify() { "$LOCAL_BIN/theme-manager" get >/dev/null 2>&1; }
