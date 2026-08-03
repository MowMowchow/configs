#!/usr/bin/env bash
set -uo pipefail

# ─────────────────────────────────────────────────────────────────
# dotfiles installer
#
#   ./install.sh [--profile personal|work] [--only a,b] [--skip c]
#                [--dry-run] [--list]
#
# Idempotent — safe to re-run. Every stage checks before it acts.
#
#   platform/stage.sh      the stage driver + contract
#   platform/stages/*.sh   stage definitions (check / apply / verify)
#   platform/<os>.sh       manifest: platform helpers + stage registration
#   site/<name>/           employer-specific, gitignored (see site/README.md)
#
# No `set -e` on purpose: a non-zero _check is normal control flow, and a
# flaky corporate network should produce warnings and a summary, not an
# abort two-thirds of the way through.
# ─────────────────────────────────────────────────────────────────

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"

# shellcheck source=platform/common.sh
. "$DOTFILES/platform/common.sh"
# shellcheck source=platform/stage.sh
. "$DOTFILES/platform/stage.sh"

WANT_LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
    --only)    ONLY="$(echo "${2:?--only needs a value}" | tr ',' ' ')"; shift 2 ;;
    --skip)    SKIP="$(echo "${2:?--skip needs a value}" | tr ',' ' ')"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --list)    WANT_LIST=1; shift ;;
    -h|--help) sed -n '4,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "unknown flag: $1"; exit 2 ;;
  esac
done

OS="$(detect_os)"
PLATFORM_SCRIPT="$(platform_script_for "$OS")"
info "Detected: $OS"
if [ -z "$PLATFORM_SCRIPT" ] || [ ! -r "$PLATFORM_SCRIPT" ]; then
  fail "no platform layer for '$OS'"
  echo "    Supported: macos, ubuntu, debian, linux"
  echo "    Add platform/<os>.sh — see platform/stage.sh for the contract."
  exit 1
fi

load_stage_definitions
# shellcheck source=/dev/null
. "$PLATFORM_SCRIPT"

# Resolution order: --profile > $DOTFILES_PROFILE > site/ present ? work : personal
PROFILE="${PROFILE:-${DOTFILES_PROFILE:-$(default_profile)}}"
case "$PROFILE" in
  personal|work) ;;
  *) fail "unknown profile '$PROFILE' (expected personal or work)"; exit 2 ;;
esac

ok "$(basename "$PLATFORM_SCRIPT"), profile=$PROFILE$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')"

# The manifest contract. Worth asserting: a typo here otherwise shows up as a
# silently skipped stage much later.
declare -f platform_notes >/dev/null || { fail "$PLATFORM_SCRIPT defines no platform_notes"; exit 1; }
[ -n "$STAGES" ] || { fail "$PLATFORM_SCRIPT registered no stages"; exit 1; }

if [ "$WANT_LIST" = 1 ]; then
  info "Stages for $OS / $PROFILE"
  list_stages
  exit 0
fi

run_stages
stage_summary

info "Done"
platform_notes
echo "  - Verify with: theme-manager doctor"
echo "  - Open a new shell, then launch nvim (lazy.nvim bootstraps itself)."
