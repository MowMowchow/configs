#!/usr/bin/env bash
# The toolchain. Entirely platform-specific, so this stage is a thin shim over
# the manifest's platform_install_packages — the ports-and-adapters seam.
packages_check() {
  # No cheap universal "are all packages present" test, and a package manager
  # run is idempotent anyway. Report unsatisfied and let apply be the guard.
  return 1
}
packages_apply() { platform_install_packages; }
# Post-condition: the handful of binaries the rest of the config hard-depends
# on. Deliberately narrow — this catches a broken install, not a partial one.
packages_verify() {
  local missing="" b
  for b in tmux nvim git zsh; do need "$b" || missing="$missing $b"; done
  [ -z "$missing" ] || { warn "still missing:$missing"; return 1; }
  return 0
}
