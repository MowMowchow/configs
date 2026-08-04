#!/usr/bin/env bash
# Detect a ~/.curlrc that breaks curl on this machine.
#
# curl reads ~/.curlrc unconditionally, and a `proxy = ...` line in it wins
# over the http_proxy/https_proxy environment. There is no conditional syntax
# in that file, so one written for a different machine — a work proxy hostname
# that only resolves inside a corporate network, say — makes every curl on this
# host fail with "Could not resolve proxy", including curl run by other tools.
#
# That failure is unusually nasty because it is invisible from the outside:
#   - Homebrew ignores ~/.curlrc by default, so `brew install` keeps working
#     and the machine looks healthy.
#   - Tools that shell out to curl report their own generic error ("download
#     failed") rather than curl's, so nothing names the real cause.
# It cost a long debugging session here: Neovim's treesitter parsers appeared
# to download forever, and the reason was a proxy line meant for a remote host.
#
# Advisory only, following the same reasoning as login_shell.sh: ~/.curlrc may
# be managed centrally, and silently moving a user's config aside is worse than
# telling them precisely what is wrong.

# Probe URL. Any always-up HTTPS endpoint works; this one answers a HEAD
# request cheaply.
CURLRC_PROBE_URL="${CURLRC_PROBE_URL:-https://api.github.com}"

_curlrc_proxy_line() {
  sed -n 's/^[[:space:]]*proxy[[:space:]]*=[[:space:]]*//p' "$HOME/.curlrc" 2>/dev/null | head -1
}

# Tests the actual failure mode rather than guessing at DNS: does curl work
# with this file, given that it works without it? `-q` must come first — that
# is what makes curl skip ~/.curlrc.
curlrc_check() {
  [ -f "$HOME/.curlrc" ] || return 0
  grep -qiE '^[[:space:]]*proxy[[:space:]]*=' "$HOME/.curlrc" 2>/dev/null || return 0
  need curl || return 0

  # Without the file. If this fails we are offline or behind something else
  # entirely, and the file is not what to blame — say nothing.
  curl -q -sS -I -o /dev/null --connect-timeout 4 --max-time 8 \
       "$CURLRC_PROBE_URL" >/dev/null 2>&1 || return 0

  # With the file. Success here means it is fine on this machine.
  curl -sS -I -o /dev/null --connect-timeout 4 --max-time 8 \
       "$CURLRC_PROBE_URL" >/dev/null 2>&1
}

curlrc_apply() {
  local proxy; proxy="$(_curlrc_proxy_line)"
  warn "~/.curlrc breaks curl on this machine"
  echo "      It sets:  proxy = ${proxy:-<unparsed>}"
  echo "      curl succeeds with -q (which skips ~/.curlrc) and fails without it,"
  echo "      so that proxy is not reachable from here. Every curl on this host"
  echo "      fails, including curl run by other tools — but not Homebrew, which"
  echo "      ignores ~/.curlrc, so the machine can look healthy."
  echo
  echo "      If the proxy belongs to another machine, move it aside:"
  echo "          mv ~/.curlrc ~/.curlrc.unused"
  echo "      The http_proxy/https_proxy environment then applies as normal."
  return 0
}

# Advisory: never fails the run, and never claims to have changed anything.
curlrc_verify() { return 0; }
