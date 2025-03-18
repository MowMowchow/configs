#!/opt/homebrew/bin/bash
#
# set-theme.sh - Switch the active theme family across all tools
#
# Usage:
#   set-theme.sh <family> [contrast]
#   set-theme.sh catppuccin
#   set-theme.sh gruvbox [hard|medium|soft]
#   set-theme.sh gruvbox-material [hard|medium|soft]
#
# This updates:
#   1. theme-config file (for theme-watcher.sh to read)
#   2. Kitty auto-switch theme files
#   3. Triggers an immediate theme refresh

set -euo pipefail

readonly CONFIG_DIR="$HOME/.config"
readonly THEME_CONFIG="$CONFIG_DIR/scripts/theme-config"
readonly KITTY_DIR="$CONFIG_DIR/kitty"

# ──────────────────────────────────────────────────────────────
# Validation
# ──────────────────────────────────────────────────────────────
usage() {
    echo "Usage: set-theme.sh <family> [contrast]"
    echo ""
    echo "Families:"
    echo "  catppuccin                    Catppuccin Mocha/Latte"
    echo "  gruvbox [hard|medium|soft]    Gruvbox Original"
    echo "  gruvbox-material [hard|medium|soft]  Gruvbox Material"
    echo ""
    echo "Available kitty themes:"
    ls "$KITTY_DIR/themes/" 2>/dev/null | grep -v '^catppuccin\|^diff-' | sed 's/.conf$//' | sed 's/^/  /'
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

family="$1"
contrast="${2:-medium}"

# Validate family
if [[ ! "$family" =~ ^(catppuccin|gruvbox|gruvbox-material)$ ]]; then
    echo "ERROR: Unknown theme family '$family'"
    usage
fi

# Validate contrast
if [[ ! "$contrast" =~ ^(hard|medium|soft)$ ]]; then
    echo "ERROR: Unknown contrast '$contrast'. Must be: hard, medium, soft"
    exit 1
fi

# ──────────────────────────────────────────────────────────────
# Update theme config
# ──────────────────────────────────────────────────────────────
cat > "$THEME_CONFIG" << EOF
# Active theme configuration
# THEME_FAMILY: catppuccin | gruvbox | gruvbox-material
# CONTRAST: hard | medium | soft (only applies to gruvbox/gruvbox-material)
THEME_FAMILY=$family
CONTRAST=$contrast
EOF

echo "Updated theme config: family=$family, contrast=$contrast"

# ──────────────────────────────────────────────────────────────
# Update Kitty auto-switch theme files
# ──────────────────────────────────────────────────────────────
update_kitty_themes() {
    local dark_src light_src

    case "$family" in
        catppuccin)
            dark_src="$KITTY_DIR/themes/mocha.conf"
            light_src="$KITTY_DIR/themes/latte.conf"
            ;;
        gruvbox)
            dark_src="$KITTY_DIR/themes/gruvbox-dark-${contrast}.conf"
            light_src="$KITTY_DIR/themes/gruvbox-light-${contrast}.conf"
            ;;
        gruvbox-material)
            dark_src="$KITTY_DIR/themes/gruvbox-material-dark-${contrast}.conf"
            light_src="$KITTY_DIR/themes/gruvbox-material-light-${contrast}.conf"
            ;;
    esac

    if [[ -f "$dark_src" ]]; then
        cp "$dark_src" "$KITTY_DIR/dark-theme.auto.conf"
        echo "Kitty dark theme -> $(basename "$dark_src")"
    else
        echo "WARNING: Dark theme file not found: $dark_src"
    fi

    if [[ -f "$light_src" ]]; then
        cp "$light_src" "$KITTY_DIR/light-theme.auto.conf"
        echo "Kitty light theme -> $(basename "$light_src")"
    else
        echo "WARNING: Light theme file not found: $light_src"
    fi
}

update_kitty_themes

# ──────────────────────────────────────────────────────────────
# Trigger immediate theme refresh
# ──────────────────────────────────────────────────────────────
echo ""
echo "Triggering theme refresh..."

# Detect current system appearance
current_mode=$(/opt/homebrew/bin/dark-notify -e 2>/dev/null || echo "dark")

# Run theme-watcher to update tmux + neovim
"$CONFIG_DIR/scripts/theme-watcher.sh" "$current_mode"

# Reload kitty config (if kitty is running)
if command -v kitty &>/dev/null; then
    # Send SIGUSR1 to kitty to reload config
    pkill -USR1 kitty 2>/dev/null && echo "Kitty config reloaded" || true
fi

echo ""
echo "Theme switched to: $family ($contrast)"
echo "All tools updated: kitty, tmux, neovim"
