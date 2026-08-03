# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# ─── Site plugins ───────────────────────────────────────────────
# Employer / machine specific environment. Each site/<name>/env.sh is
# sourced here, early, before Oh My Zsh. Nothing under site/ except the
# API docs and the example is committed — see site/README.md.
for _site_env in "$HOME"/.config/site/*/env.sh; do
  [[ -r "$_site_env" ]] && source "$_site_env"
done
unset _site_env

# Safer sudo rm: --preserve-root=all refuses to recurse into / and
# --one-file-system stops it crossing into other mounts.
if [[ -o interactive ]]; then
  sudo() {
    if [ "$1" = "rm" ]; then
      shift
      command sudo rm --preserve-root=all --one-file-system "$@"
    else
      command sudo "$@"
    fi
  }
fi

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
# Skip Oh My Zsh's compaudit before compinit. It stats every fpath directory
# checking for group/world-writable dirs — ~27ms locally and considerably
# worse over a network home directory, which is the devserver case. On a
# single-user machine it protects against nothing you do not already control.
ZSH_DISABLE_COMPFIX=true

# `git` is deliberately NOT here: it is 197 aliases costing ~40ms, and the
# prompt's git info comes from OMZ's lib/git.zsh, not the plugin. It is
# deferred until after the first prompt instead — see the end of this file.
plugins=(vi-mode)

[[ -f $ZSH/oh-my-zsh.sh ]] && source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='nvim'
else
  export EDITOR='nvim'
fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
#


# SYMLINKS
[[ -e ~/.tmux ]] || ln -s ~/.config/tmux ~/.tmux

# ENVIRONMENT VARIABLES
export EZA_CONFIG_DIR="$HOME/.config/eza"

# Source machine-local secrets (API keys, etc.) — never committed to dotfiles
[ -f "$HOME/.secrets" ] && source "$HOME/.secrets"

# ZSH PLUGINS but not from oh-my-zsh
# ── Deferred startup ─────────────────────────────────────────────
# Anything below is needed only once you actually type something, not to draw
# the first prompt. Loading it from a one-shot precmd hook lets the prompt
# appear immediately and the rest arrive microseconds later, which is the
# latency you actually feel when opening a pane.
_deferred_init() {
  # Run once, then remove the hook so later prompts cost nothing.
  add-zsh-hook -d precmd _deferred_init
  unfunction _deferred_init

  # 197 git aliases (gst, gco, gd, ...). Not needed to render a prompt.
  [[ -r "$ZSH/plugins/git/git.plugin.zsh" ]] && source "$ZSH/plugins/git/git.plugin.zsh"

  # Syntax highlighting must be sourced last, and only matters while typing.
  for _zsh_hl in \
    /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    if [[ -r "$_zsh_hl" ]]; then source "$_zsh_hl"; break; fi
  done
  unset _zsh_hl
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _deferred_init


# EVALS
# eval "$(zoxide init zsh)"  # disabled


# ALIAS
# Guarded: eza is a cargo/brew install that can legitimately be missing (a
# fresh box mid-install, or a host where the cargo tools were skipped).
# Aliasing `ls` to something absent breaks a command muscle memory reaches for
# constantly, and the error names eza rather than the alias, so it reads as
# though ls itself is gone.
if command -v eza >/dev/null; then
  alias ls="eza --long --git --color=always --icons=always"
fi
# alias cd="z"


# COMMANDS
# tmux-window-name
# tmux-window-name() {
# 	($TMUX_PLUGIN_MANAGER_PATH/tmux-window-name/scripts/rename_session_windows.py &)
# }
# add-zsh-hook chpwd tmux-window-name

# System info banner — fastfetch replaced neofetch (archived upstream 2024).
#
# Runs in every shell, including every new tmux window and pane: wanted
# behaviour, not an oversight. It costs ~60ms, which is the single largest
# remaining item in this file — an accepted trade, deliberately made.
# Set DOTFILES_NO_BANNER=1 to suppress it for a shell without editing this.
#
# stderr is dropped: on a managed Mac the kernel-extension query is refused by
# security policy, so fastfetch prints two "Failed to query kext info" lines
# before every banner. They are cosmetic — the banner itself renders fine —
# and this is decoration, so nothing here is worth surfacing an error for.
if [[ -z "${DOTFILES_NO_BANNER:-}" ]] && command -v fastfetch >/dev/null; then
  fastfetch 2>/dev/null
fi


### TMUX WINDOW RENAMING
# Only define these hooks inside tmux.
#
# This was `[[ -z "$TMUX" ]] && return`, which made the entire rest of this
# file dead code in any shell not started under tmux. Everything below the
# guard was silently lost there: the $PATH additions (so ~/.local/bin was
# absent and theme-manager and sl were unreachable), COLORTERM, and the
# aliases. Scoping it to an `if` keeps the guard on the hooks it was meant
# for, and means appending to this file can never silently do nothing.
if [[ -n "$TMUX" ]]; then

  # Function to rename the tmux window based on our conditions
  rename_tmux_window() {
    local cmd="$1"
    local dir_name
    local window_name

    # Get the current directory name (or "root" if at '/')
    dir_name="$(basename "$PWD")"
    [[ -z "$dir_name" ]] && dir_name="root"

    if [[ -n "$VIRTUAL_ENV" && "$cmd" == "nvim" ]]; then
      # If in a virtual environment AND running nvim, prefix with "-> " and append /nvim
      window_name="-> ${dir_name}/nvim"
    elif [[ "$cmd" == "nvim" ]]; then
      # If just running nvim, show "dir/nvim"
      window_name="${dir_name}/nvim"
    elif [[ -n "$VIRTUAL_ENV" ]]; then
      # If in a virtual environment, prefix the directory name with "-> "
      window_name="-> ${dir_name}"
    else
      # Otherwise, just the directory name
      window_name="${dir_name}"
    fi

    # Truncate to 20 characters and add a leading space
    window_name=" ${window_name:0:20}"
    tmux rename-window "$window_name"
  }

  # preexec: before executing any command, update the window name
  preexec() {
    rename_tmux_window "$1"
  }

  # precmd: before the prompt is displayed, update the window name
  precmd() {
    rename_tmux_window ""
  }

  # chpwd hook: update the window name right after a directory change
  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd chpwd_rename_tmux
  chpwd_rename_tmux() {
    rename_tmux_window ""
  }

  # Override the nvim command so that it updates the window name when entering and exiting nvim
  nvim() {
    rename_tmux_window "nvim"
    command nvim "$@"
    rename_tmux_window ""
  }
fi


export COLORTERM=truecolor
export PATH="$PATH:$HOME/.spicetify"

export PATH="$HOME/.local/bin:$PATH"

# Cargo. rustup is installed with --no-modify-path on the assumption that
# "zshrc owns PATH" — this is the line that makes that true. Without it
# ~/.cargo/bin was on nobody's PATH, so cargo-installed tools (eza, stylua,
# tree-sitter-cli) were invisible, and the installer's own `need cargo` was
# false on every run after the first.
export PATH="$HOME/.cargo/bin:$PATH"

# Sapling, per upstream install instructions
# (https://sapling-scm.com/docs/introduction/installation/).
export PATH="$HOME/.local/share/sapling:$PATH"


alias n="nvim"

# Proxies, work aliases and any network-specific setup live in
# site/<name>/env.sh, sourced at the top of this file.
