#!/usr/bin/env bash
# Run each site plugin's bootstrap.sh. See site/README.md for the contract.
# Always re-runs: plugins are required to be idempotent, and a corporate
# network's proxy/cert setup is exactly the thing you want re-asserted.
site_bootstrap_check() {
  local m
  for m in "$DOTFILES"/site/*/plugin.toml; do [ -r "$m" ] && return 1; done
  return 0   # nothing installed == nothing to do
}

site_bootstrap_apply() {
  local m dir name
  for m in "$DOTFILES"/site/*/plugin.toml; do
    [ -r "$m" ] || continue
    dir="$(dirname "$m")"; name="$(basename "$dir")"
    if [ -x "$dir/bootstrap.sh" ]; then
      info "  site:$name"
      bash "$dir/bootstrap.sh" || warn "site:$name bootstrap returned non-zero"
    else
      ok "site:$name (no bootstrap.sh)"
    fi
  done
  return 0
}

site_bootstrap_verify() { return 0; }   # plugins own their own success criteria
