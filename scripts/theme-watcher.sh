#!/opt/homebrew/bin/bash
#
# theme-watcher.sh - Unified theme switcher for macOS appearance changes
# Called by dark-notify with "dark" or "light" as $1
#
# Supports: tmux, neovim
# Kitty handles its own switching via *.auto.conf files

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────
readonly TMUX_BIN="/opt/homebrew/bin/tmux"
readonly NVIM_BIN="/opt/homebrew/bin/nvim"
readonly NVIM_SOCKET_PATTERN="/tmp/nvim-theme-*.sock"
readonly LOG_FILE="/tmp/theme-watcher.log"
readonly CONFIG_DIR="$HOME/.config"
readonly THEME_CONFIG="$CONFIG_DIR/scripts/theme-config"

# ──────────────────────────────────────────────────────────────
# Theme mappings
# ──────────────────────────────────────────────────────────────

# Catppuccin
declare -A CATPPUCCIN_FLAVOR=(
    [dark]="mocha"
    [light]="latte"
)

# Vim background
declare -A VIM_BACKGROUND=(
    [dark]="dark"
    [light]="light"
)

# Neovim colorscheme names per family
declare -A NVIM_COLORSCHEME=(
    [catppuccin]="catppuccin"
    [gruvbox]="gruvbox"
    [gruvbox-material]="gruvbox-material"
)

# ──────────────────────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────────────────────
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# ──────────────────────────────────────────────────────────────
# Config Reading
# ──────────────────────────────────────────────────────────────
read_config() {
    local family="catppuccin"
    local contrast="medium"

    if [[ -f "$THEME_CONFIG" ]]; then
        # Source the config, filtering out comments
        while IFS='=' read -r key value; do
            key=$(echo "$key" | tr -d '[:space:]')
            value=$(echo "$value" | tr -d '[:space:]')
            case "$key" in
                THEME_FAMILY) family="$value" ;;
                CONTRAST) contrast="$value" ;;
            esac
        done < <(grep -v '^#' "$THEME_CONFIG" | grep '=')
    fi

    echo "$family" "$contrast"
}

# ──────────────────────────────────────────────────────────────
# Input Handling
# ──────────────────────────────────────────────────────────────
get_theme() {
    local theme
    if [[ -n "${1:-}" ]]; then
        theme="$1"
    else
        read -r theme
    fi

    # Validate
    if [[ ! "$theme" =~ ^(dark|light)$ ]]; then
        log "ERROR: Invalid theme '$theme'. Must be 'dark' or 'light'."
        exit 1
    fi

    echo "$theme"
}

# ──────────────────────────────────────────────────────────────
# Tmux Theme Switching
# ──────────────────────────────────────────────────────────────
switch_tmux_catppuccin() {
    local theme="$1"
    local flavor="${CATPPUCCIN_FLAVOR[$theme]}"

    # Clear all Catppuccin theme variables
    local theme_vars=(
        @thm_bg @thm_fg @thm_crust @thm_mantle
        @thm_surface_0 @thm_surface_1 @thm_surface_2
        @thm_overlay_0 @thm_overlay_1 @thm_overlay_2
        @thm_subtext_0 @thm_subtext_1
        @thm_blue @thm_flamingo @thm_green @thm_lavender
        @thm_maroon @thm_mauve @thm_peach @thm_pink
        @thm_red @thm_rosewater @thm_sapphire @thm_sky @thm_teal @thm_yellow
    )

    for var in "${theme_vars[@]}"; do
        $TMUX_BIN set -gu "$var" 2>/dev/null || true
    done

    $TMUX_BIN set -g @catppuccin_flavor "$flavor"

    if ! $TMUX_BIN run ~/.config/tmux/plugins/tmux/catppuccin.tmux 2>&1; then
        log "ERROR: Failed to run catppuccin.tmux"
        return 1
    fi

    log "Tmux theme set to catppuccin-$flavor"
}

switch_tmux_gruvbox() {
    local theme="$1"
    local conf="$CONFIG_DIR/tmux/gruvbox-${theme}.conf"

    if [[ -f "$conf" ]]; then
        $TMUX_BIN source-file "$conf"
        log "Tmux theme set to gruvbox-$theme"
    else
        log "ERROR: Tmux gruvbox theme file not found: $conf"
    fi
}

switch_tmux_gruvbox_material() {
    local theme="$1"
    local conf="$CONFIG_DIR/tmux/gruvbox-material-${theme}.conf"

    if [[ -f "$conf" ]]; then
        $TMUX_BIN source-file "$conf"
        log "Tmux theme set to gruvbox-material-$theme"
    else
        log "ERROR: Tmux gruvbox-material theme file not found: $conf"
    fi
}

switch_tmux_theme() {
    local theme="$1"
    local family="$2"

    [[ ! -x "$TMUX_BIN" ]] && return 0
    $TMUX_BIN list-sessions &>/dev/null || return 0

    case "$family" in
        catppuccin)         switch_tmux_catppuccin "$theme" ;;
        gruvbox)            switch_tmux_gruvbox "$theme" ;;
        gruvbox-material)   switch_tmux_gruvbox_material "$theme" ;;
        *)                  log "ERROR: Unknown tmux theme family: $family" ;;
    esac
}

# ──────────────────────────────────────────────────────────────
# Neovim Theme Switching
# ──────────────────────────────────────────────────────────────
switch_nvim_theme() {
    local theme="$1"
    local family="$2"
    local contrast="$3"

    [[ ! -x "$NVIM_BIN" ]] && return 0

    local bg="${VIM_BACKGROUND[$theme]}"
    local colorscheme="${NVIM_COLORSCHEME[$family]:-catppuccin}"

    # Build the command sequence
    local cmd="<Cmd>set background=${bg}<CR>"

    # For gruvbox, set contrast before applying colorscheme
    if [[ "$family" == "gruvbox" ]]; then
        cmd+="<Cmd>lua require('gruvbox').setup({contrast='${contrast}'})<CR>"
    elif [[ "$family" == "gruvbox-material" ]]; then
        cmd+="<Cmd>let g:gruvbox_material_background='${contrast}'<CR>"
    fi

    cmd+="<Cmd>colorscheme ${colorscheme}<CR>"

    local count=0

    # Enable nullglob so unmatched patterns expand to nothing
    shopt -s nullglob

    for socket in $NVIM_SOCKET_PATTERN; do
        # Clean up orphaned sockets
        if [[ ! -S "$socket" ]]; then
            rm -f "$socket" 2>/dev/null || true
            continue
        fi

        if $NVIM_BIN --server "$socket" --remote-send "$cmd" 2>/dev/null; then
            ((count++)) || true
        fi
    done

    shopt -u nullglob

    if [[ $count -gt 0 ]]; then
        log "Neovim theme set to $colorscheme ($bg, contrast=$contrast) ($count instance(s))"
    fi
}

# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────
main() {
    local theme
    theme=$(get_theme "${1:-}")

    local config
    config=$(read_config)
    local family contrast
    family=$(echo "$config" | awk '{print $1}')
    contrast=$(echo "$config" | awk '{print $2}')

    switch_tmux_theme "$theme" "$family"
    switch_nvim_theme "$theme" "$family" "$contrast"
}

main "$@"
