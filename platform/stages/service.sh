#!/usr/bin/env bash
# The theme-manager daemon: LaunchAgent on macOS, systemd user unit on Linux.
service_check() {
  if declare -f platform_service_running >/dev/null; then platform_service_running; else return 1; fi
}
service_apply() { platform_install_daemon; }
# The unit existing is not the same as the daemon running, which is exactly
# the case _verify exists for.
service_verify() {
  if declare -f platform_service_running >/dev/null; then
    platform_service_running || { warn "service installed but not running yet"; return 1; }
  fi
  return 0
}
