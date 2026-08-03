# Login-shell profile. Symlinked to ~/.zprofile by the `symlinks` stage.
#
# Kept deliberately lean: tmux spawns a LOGIN shell for every new window and
# pane, so anything slow here is paid on every split. Measured on macOS, the
# eager nvm load below used to cost 1.2s of a 1.4s login — see the note.
#
# Interactive-only configuration belongs in zshrc, not here.

# Homebrew environment, set statically.
#
# `eval "$(brew shellenv)"` costs ~40 ms because it forks brew — a Ruby
# program — and its output then re-runs path_helper a second time. The output
# is deterministic for a given prefix, so set it directly. Everything below is
# exactly what `brew shellenv` emits, minus the two subprocesses.
#
# Re-runnable: the PATH guard means a nested login shell does not duplicate
# entries, which the eval form would.
for _brew_prefix in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
  if [ -x "$_brew_prefix/bin/brew" ]; then
    export HOMEBREW_PREFIX="$_brew_prefix"
    export HOMEBREW_CELLAR="$_brew_prefix/Cellar"
    export HOMEBREW_REPOSITORY="$_brew_prefix"
    case ":$PATH:" in
      *":$_brew_prefix/bin:"*) ;;
      *) export PATH="$_brew_prefix/bin:$_brew_prefix/sbin:$PATH" ;;
    esac
    export MANPATH="$_brew_prefix/share/man:${MANPATH-}"
    export INFOPATH="$_brew_prefix/share/info:${INFOPATH-}"
    fpath=("$_brew_prefix/share/zsh/site-functions" $fpath)
    break
  fi
done
unset _brew_prefix

# ── nvm, lazy-loaded ─────────────────────────────────────────────
# Sourcing nvm.sh costs ~1.2s — measured as ~95% of login-shell startup, and
# the reason a new tmux pane took most of a second to become usable.
#
# Instead, install shims for the commands nvm provides. The first one you run
# loads nvm properly, removes all the shims, and re-execs the real command.
# Interactive cost drops to zero; the 1.2s is paid once, on first node use,
# in the shell where you asked for it.
#
# Verified: after the first call, `node` resolves to the real binary and
# subsequent calls cost ~21ms each, not 1.2s.
export NVM_DIR="$HOME/.nvm"

if [ -s "$NVM_DIR/nvm.sh" ]; then
  _nvm_load() {
    unset -f nvm node npm npx corepack yarn 2>/dev/null
    \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  }
  for _nvm_cmd in nvm node npm npx corepack yarn; do
    eval "${_nvm_cmd}() {
      _nvm_load
      if command -v ${_nvm_cmd} >/dev/null 2>&1; then
        ${_nvm_cmd} \"\$@\"
      else
        echo \"${_nvm_cmd}: not provided by the active nvm version\" >&2
        return 127
      fi
    }"
  done
  unset _nvm_cmd
fi
