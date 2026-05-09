# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

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
plugins=(git vi-mode)

source $ZSH/oh-my-zsh.sh

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
# zsh-syntax-highlighting
# zsh-syntax-highlighting (works on both Apple Silicon and Intel Macs)
if [[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [[ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi


# EVALS
# eval "$(zoxide init zsh)"  # disabled


# ALIAS
alias ls="eza --long --git --color=always --icons=always"
# alias cd="z"


# COMMANDS
# tmux-window-name
# tmux-window-name() {
# 	($TMUX_PLUGIN_MANAGER_PATH/tmux-window-name/scripts/rename_session_windows.py &)
# }
# add-zsh-hook chpwd tmux-window-name

# system info banner — fastfetch is the active maintained replacement for neofetch
fastfetch


### TMUX WINDOW RENAMING
# Only run these hooks if we're inside tmux
[[ -z "$TMUX" ]] && return

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


export COLORTERM=truecolor
export PATH="$PATH:$HOME/.spicetify"

export PATH="$HOME/.local/bin:$PATH"
export CLAUDE_CODE_EFFORT_LEVEL="MAX"
export PATH="$HOME/.local/share/sapling:$PATH"
export PATH="$HOME/.local/share/sapling:$PATH"
