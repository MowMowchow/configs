#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Apply the theme-manager palette to this tmux server.
#
# Runs on hosts with no theme-manager binary (remote servers, containers).
# Sources dark-theme.auto.conf / light-theme.auto.conf, both generated
# on the Mac from theme-manager's theme.rs — this script holds no
# colour values of its own.
#
# Appearance precedence:
#   1. explicit argument   dark|light
#   2. #{client_theme}     tmux >= 3.6, fed by DEC mode 2031 over the terminal
#   3. pointer file        seeded at sync time, survives disconnect
#   4. dark                last resort
#
# Usage:
#   theme-apply.sh [dark|light]   apply now
#   theme-apply.sh --init         install hooks, then apply
# ─────────────────────────────────────────────────────────────────
set -uo pipefail

TM_DIR="${TM_DIR:-$HOME/.config/tmux}"
POINTER="${TM_POINTER:-$HOME/.local/state/theme-manager/appearance}"
# Overridable so the script can be exercised against a scratch server
# instead of whichever tmux happens to own $TMUX. See the tests in the repo.
TMUX_BIN="${TM_TMUX:-tmux}"

# Outputs of resolve(). RESOLVED_FROM records which tier answered: only "arg"
# and "native" are observations; "pointer" is replayed state, "fallback" a guess.
#
# These are globals rather than a return value on purpose. `x=$(resolve)` would
# run resolve in a subshell, so RESOLVED_FROM would never make it back to the
# caller and every result would look like a guess.
RESOLVED_APPEARANCE=""
RESOLVED_FROM=""

# ── Resolve appearance ────────────────────────────────────────────
resolve() {
  case "${1:-}" in
    dark|light) RESOLVED_APPEARANCE="$1"; RESOLVED_FROM=arg; return ;;
  esac

  # tmux >= 3.6 only; empty string on older builds or before the
  # terminal has answered.
  local native
  native=$($TMUX_BIN display -p '#{client_theme}' 2>/dev/null)
  case "$native" in
    dark|light) RESOLVED_APPEARANCE="$native"; RESOLVED_FROM=native; return ;;
  esac

  if [ -r "$POINTER" ]; then
    local saved
    saved=$(cat "$POINTER" 2>/dev/null)
    case "$saved" in
      dark|light) RESOLVED_APPEARANCE="$saved"; RESOLVED_FROM=pointer; return ;;
    esac
  fi

  RESOLVED_APPEARANCE=dark
  RESOLVED_FROM=fallback
}

# ── Install hooks (idempotent) ────────────────────────────────────
# Feature-detect rather than parse `tmux -V`: some distros ship forks
# whose version string we should not have to reason about. Setting an
# unknown hook name fails, a known one succeeds.
install_hooks() {
  local detection="pointer-only (tmux < 3.6)"
  local self="$TM_DIR/theme-apply.sh"

  if $TMUX_BIN set-hook -gu client-dark-theme 2>/dev/null; then
    $TMUX_BIN set-hook -g client-dark-theme  "run-shell '$self dark'"
    $TMUX_BIN set-hook -g client-light-theme "run-shell '$self light'"
    detection="native DEC-2031 ($($TMUX_BIN -V))"
  fi

  # Re-resolve on every attach / new session. Cheap because the
  # @theme_state guard below makes a redundant call a 3-fork no-op.
  # This is the whole fallback tier on tmux < 3.6, and it also repairs
  # a theme change that happened while the client was detached.
  #
  # -g (replace) not -a (append): --init runs on every tmux.conf load, and
  # appending would stack a duplicate hook every time.
  $TMUX_BIN set-hook -g client-attached        "run-shell '$self'"
  $TMUX_BIN set-hook -g session-created        "run-shell '$self'"
  $TMUX_BIN set-hook -g client-session-changed "run-shell '$self'"

  $TMUX_BIN set -g @theme-detection "$detection"
}

# ── Apply ─────────────────────────────────────────────────────────
main() {
  local arg="${1:-}"

  if [ "$arg" = "--init" ]; then
    install_hooks
    arg=""
  fi

  local appearance conf
  resolve "$arg"
  appearance="$RESOLVED_APPEARANCE"
  conf="$TM_DIR/${appearance}-theme.auto.conf"

  [ -r "$conf" ] || { echo "theme-apply: missing $conf" >&2; exit 1; }

  # Guard on the full theme identity, not just dark/light — otherwise a
  # family or variant change (gruvbox-material -> gruvbox) would be
  # skipped because the appearance did not flip.
  local want have
  want=$(sed -n 's/^# theme-id: //p' "$conf")
  # -q so an unset @theme_state is not logged as "invalid option" on first run.
  have=$($TMUX_BIN show -gqv @theme_state 2>/dev/null)
  if [ -n "$want" ] && [ "$want" = "$have" ]; then
    exit 0
  fi

  $TMUX_BIN source-file "$conf" || exit 1
  $TMUX_BIN set -g @theme_state "$want"

  # Persist for the next cold start (new tmux server, fresh host) — but only
  # when we actually observed the appearance. Writing the "fallback" guess
  # would launder it into durable state that later runs then trust, so an
  # unknown would harden into a wrong assertion that never self-corrects.
  case "$RESOLVED_FROM" in
    arg | native)
      mkdir -p "$(dirname "$POINTER")" 2>/dev/null
      # Atomic: a concurrent hook may be reading this file.
      if printf '%s' "$appearance" > "$POINTER.tmp" 2>/dev/null; then
        mv -f "$POINTER.tmp" "$POINTER" 2>/dev/null || rm -f "$POINTER.tmp"
      fi
      ;;
  esac

  exit 0
}

main "$@"
