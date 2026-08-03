#!/usr/bin/env bash
# Run once per machine by install.sh, after the platform layer.
# MUST be idempotent — it may be re-run at any time.
set -uo pipefail

# Example: configure a package manager proxy only if not already set.
# if ! git config --global --get http.proxy >/dev/null 2>&1; then
#   git config --global http.proxy "http://proxy.internal:8080"
# fi

echo "  (example plugin: nothing to bootstrap)"
