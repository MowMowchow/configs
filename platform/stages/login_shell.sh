#!/usr/bin/env bash
# Advise when the login shell is not zsh.
#
# Deliberately never runs chsh: changing the login shell is a user-affecting
# decision (it can lock you out of a box if the shell is not in /etc/shells),
# and on a corporate machine it may be centrally managed. Advise, do not act.

_login_shell() {
  # getent is the portable answer on Linux; macOS has no getent, so fall back
  # to dscl, then to $SHELL.
  if need getent; then
    getent passwd "$USER" 2>/dev/null | cut -d: -f7
  elif need dscl; then
    dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
  else
    echo "${SHELL:-}"
  fi
}

# Compare the basename, not the full path. The login shell is commonly the
# system /bin/zsh while `command -v zsh` finds a newer Homebrew or /usr/local
# one; both are zsh and neither needs changing, so an exact-path comparison
# reports a problem that does not exist.
login_shell_check() {
  [ "$(basename "$(_login_shell)")" = "zsh" ]
}

login_shell_apply() {
  local zsh_path; zsh_path="$(command -v zsh 2>/dev/null)"
  if [ -z "$zsh_path" ]; then
    warn "zsh is not installed — cannot suggest a shell change"
    return 0
  fi
  warn "login shell is $(_login_shell), not zsh"
  echo "      chsh -s \"$zsh_path\"      # then log out and back in"
  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    echo "      (first: echo \"$zsh_path\" | sudo tee -a /etc/shells)"
  fi
  return 0
}

# Advisory only — never fails the run, and never claims to have changed it.
login_shell_verify() { return 0; }
