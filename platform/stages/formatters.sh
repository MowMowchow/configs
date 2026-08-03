#!/usr/bin/env bash
# Formatters that nvim/lua/jhou/lazy/formatter.lua expects to exist.
# prettier is npm everywhere; python tools differ (pipx on Linux for PEP 668,
# brew on macOS) so the platform layer supplies platform_install_pyformatters.

formatters_check() { need prettier && need black && need isort; }

formatters_apply() {
  if need npm && ! need prettier; then
    npm install -g prettier >/dev/null 2>&1 || sudo npm install -g prettier >/dev/null 2>&1 \
      || warn "prettier install failed"
  fi
  if declare -f platform_install_pyformatters >/dev/null; then
    platform_install_pyformatters
  fi
  return 0
}
