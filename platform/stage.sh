#!/usr/bin/env bash
# platform/stage.sh — the stage driver. Sourced by install.sh, never executed.
#
# ── CONTRACT ─────────────────────────────────────────────────────────────
# A stage is two or three shell functions sharing a name prefix. The name must
# be a shell identifier and the stage lives in platform/stages/<name>.sh.
#
#   <name>_check    REQUIRED. Return 0 iff the goal is ALREADY met.
#                   MUST have no side effects — it is the only thing that
#                   runs under --dry-run.
#   <name>_apply    REQUIRED. Do the work. Return non-zero on failure.
#   <name>_verify   OPTIONAL. Return 0 iff the goal holds AFTER apply.
#                   Defaults to <name>_check. Define it only where the
#                   post-condition genuinely differs from the pre-condition,
#                   e.g. "unit file written" vs "daemon actually running".
#
# Register with:  stage <name> [profile ...]
#                 No profiles listed = runs in every profile.
#
# That is the whole framework. No base class, no inheritance, no registry
# file: a stage exists because a file defines it and a manifest registers it.
#
# ── PORTABILITY ──────────────────────────────────────────────────────────
# bash 3.2 only. macOS ships 3.2.57 and always will (Apple will not ship
# GPLv3), and requiring a newer bash is chicken-and-egg on a fresh box. So:
# space-separated strings rather than associative arrays, `case` globs rather
# than [[ =~ ]] or ${x,,}. Do not "modernise" this file.
#
# There is deliberately no `set -e`: a non-zero _check is normal control flow,
# and the installer should warn and continue rather than abort two-thirds
# through on a flaky corporate network.
# ─────────────────────────────────────────────────────────────────────────

STAGES=""    # "name:profile,profile" entries, in registration order
_RESULTS=""  # "name=STATUS" entries, filled by run_stages

PROFILE="${PROFILE:-}"
DRY_RUN="${DRY_RUN:-0}"
ONLY=""      # space-separated allowlist; empty means all
SKIP=""      # space-separated denylist

stage() {
  local name="$1"; shift
  local profiles=""
  if [ $# -gt 0 ]; then profiles="$(IFS=,; echo "$*")"; fi
  STAGES="$STAGES $name:$profiles"
}

# Personal unless told otherwise. A site plugin on disk means this is a work
# machine — reuse the signal that already exists rather than inventing a
# second one, so "why is this happening" stays answerable with `ls`.
default_profile() {
  local m
  for m in "$DOTFILES"/site/*/plugin.toml; do
    [ -r "$m" ] && { echo work; return; }
  done
  echo personal
}

_stage_wanted() {
  local name="$1" profiles="$2"
  if [ -n "$profiles" ]; then
    case ",$profiles," in *",$PROFILE,"*) ;; *) return 1 ;; esac
  fi
  if [ -n "$ONLY" ]; then
    case " $ONLY " in *" $name "*) ;; *) return 1 ;; esac
  fi
  if [ -n "$SKIP" ]; then
    case " $SKIP " in *" $name "*) return 1 ;; esac
  fi
  return 0
}

list_stages() {
  local entry name profiles
  for entry in $STAGES; do
    name="${entry%%:*}"; profiles="${entry#*:}"
    if _stage_wanted "$name" "$profiles"; then
      printf '  %-22s %s\n' "$name" "${profiles:-all profiles}"
    else
      printf '  %-22s %s (filtered out)\n' "$name" "${profiles:-all profiles}"
    fi
  done
}

run_stages() {
  local entry name profiles post
  for entry in $STAGES; do
    name="${entry%%:*}"; profiles="${entry#*:}"
    _stage_wanted "$name" "$profiles" || continue

    if ! declare -f "${name}_check" >/dev/null \
       || ! declare -f "${name}_apply" >/dev/null; then
      fail "$name: missing ${name}_check or ${name}_apply"
      _RESULTS="$_RESULTS $name=BROKEN"; continue
    fi

    if "${name}_check"; then
      ok "$name (already satisfied)"
      _RESULTS="$_RESULTS $name=SKIP"; continue
    fi

    if [ "$DRY_RUN" = 1 ]; then
      info "$name — WOULD APPLY"
      _RESULTS="$_RESULTS $name=PLAN"; continue
    fi

    info "$name"
    if ! "${name}_apply"; then
      fail "$name: apply failed"
      _RESULTS="$_RESULTS $name=FAILED"; continue
    fi

    if declare -f "${name}_verify" >/dev/null; then post="${name}_verify"
    else                                            post="${name}_check"; fi

    if "$post"; then
      ok "$name"
      _RESULTS="$_RESULTS $name=OK"
    else
      warn "$name: applied, but the post-condition does not hold"
      _RESULTS="$_RESULTS $name=UNVERIFIED"
    fi
  done
}

stage_summary() {
  local entry bad=0
  printf '\n\033[1m%-22s %s\033[0m\n' STAGE RESULT
  for entry in $_RESULTS; do
    printf '%-22s %s\n' "${entry%%=*}" "${entry#*=}"
    case "${entry#*=}" in FAILED | BROKEN | UNVERIFIED) bad=1 ;; esac
  done
  if [ "$bad" = 1 ]; then
    warn "some stages need attention (see above)"
  fi
  return 0
}

# Source every stage definition. Manifests register the ones they want.
load_stage_definitions() {
  local f
  for f in "$DOTFILES"/platform/stages/*.sh; do
    [ -r "$f" ] || continue
    # shellcheck source=/dev/null
    . "$f"
  done
}
