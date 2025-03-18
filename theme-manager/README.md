# theme-manager

Unified theme switching for macOS. A single Rust binary that keeps kitty, neovim, and tmux in sync — including automatic dark/light mode switching when macOS appearance changes.

## How it works

```
┌──────────────────────┐
│  macOS appearance     │──── CF notifications + 5s polling ────┐
│  (System Settings)    │                                       │
└──────────────────────┘                                       ▼
                                                    ┌──────────────────┐
                                                    │  theme-manager   │
                                                    │  watch (daemon)  │
                                                    └────────┬─────────┘
                                                             │
                                    ┌────────────────────────┼────────────────────────┐
                                    ▼                        ▼                        ▼
                            ┌──────────────┐       ┌──────────────┐       ┌──────────────────┐
                            │    kitty      │       │    tmux       │       │    neovim         │
                            │  pkill -USR1  │       │  tmux set -g  │       │  nvim --server    │
                            │  (auto.conf)  │       │  (palette)    │       │  --remote-send    │
                            └──────────────┘       └──────────────┘       └──────────────────┘
```

**Config** (`config.toml`) stores the active family + variant. The daemon reads it on every appearance change, so you can `theme-manager set ...` and the next toggle picks it up.

## Supported themes

| Family | Variant axis | Options | Dark/Light |
|--------|-------------|---------|------------|
| `catppuccin` | flavor | `mocha`, `macchiato`, `frappe` | Light is always `latte` |
| `gruvbox` | contrast | `hard`, `medium`, `soft` | Both |
| `gruvbox-material` | contrast | `hard`, `medium`, `soft` | Both |

## CLI

```
theme-manager set <family> [variant]    # Set theme and apply immediately
theme-manager get                       # Show current config + system appearance
theme-manager list                      # Show all themes (* = active)
theme-manager apply [dark|light]        # Apply for given or auto-detected appearance
theme-manager watch                     # Daemon mode (run by LaunchAgent)
```

### Examples

```bash
theme-manager set gruvbox-material hard
theme-manager set catppuccin mocha
theme-manager set gruvbox soft
theme-manager apply              # re-apply for current system appearance
theme-manager get
# Family:     gruvbox-material
# Contrast:   hard
# Appearance: dark (system)
```

## Config

`~/.config/theme-manager/config.toml`:

```toml
[theme]
family = "gruvbox-material"
variant = "hard"

[paths]
kitty_config = "~/.config/kitty"
tmux_config = "~/.config/tmux"
nvim_socket_pattern = "/tmp/nvim-theme-*.sock"
catppuccin_tmux_plugin = "~/.config/tmux/plugins/tmux/catppuccin.tmux"
```

The `variant` field is universal — its meaning depends on the family (contrast for gruvbox, flavor for catppuccin). The old `contrast` key is accepted as an alias for backward compatibility.

## Architecture

```
src/
├── main.rs           CLI (clap) + orchestration
├── config.rs         Config load/save with atomic writes + validation
├── theme.rs          ThemeFamily, palettes, CatppuccinFlavor
├── appearance.rs     macOS appearance detection (CFNotifications + polling)
├── cmd.rs            Subprocess execution with timeouts
└── adapters/
    ├── kitty.rs      Write auto.conf files, signal reload
    ├── tmux.rs       Set status bar colors / run catppuccin plugin
    └── neovim.rs     Remote-send to all nvim instances via sockets
```

### Adapter details

**Kitty**: Writes `dark-theme.auto.conf` and `light-theme.auto.conf` from the palette. Kitty natively selects the right one based on system appearance. A `pkill -USR1` triggers config reload.

**Tmux**: For gruvbox families, sets all `status-style`, `window-status-*`, and `pane-border-*` options directly via `tmux set -g`. For catppuccin, clears stale `@thm_*` variables and re-runs the catppuccin tmux plugin with the correct flavor.

**Neovim**: Finds all instances via `/tmp/nvim-theme-*.sock` sockets (started by `settings.lua`). Sends `--remote-send` with the appropriate `:set background`, plugin config, and `:colorscheme` commands. New nvim instances read `config.toml` at startup (see `extra.lua`).

### Daemon

The `watch` command runs as a LaunchAgent (`com.user.theme-manager`). It uses two detection sources:

1. **CoreFoundation distributed notifications** — event-driven, instant response
2. **5-second polling fallback** — catches any missed notifications

All subprocess calls have timeouts (5s tmux, 3s neovim, 2s kitty) so a hung adapter never blocks future appearance changes. Each adapter runs independently — one failure doesn't affect others.

### Binary path resolution

The daemon runs under launchd with a minimal PATH (`/usr/bin:/bin`). Both the tmux and neovim adapters resolve binary paths by checking `/opt/homebrew/bin/` and `/usr/local/bin/` before falling back to PATH lookup.

## Build & install

```bash
cd ~/.config/theme-manager
cargo build --release
cp target/release/theme-manager ~/.local/bin/
```

## LaunchAgent

`~/Library/LaunchAgents/com.user.theme-manager.plist` — starts `theme-manager watch` at login with `KeepAlive: true`.

```bash
# Restart after rebuilding
launchctl unload ~/Library/LaunchAgents/com.user.theme-manager.plist
launchctl load ~/Library/LaunchAgents/com.user.theme-manager.plist
```

Logs: `/tmp/theme-manager.err`

## Neovim integration

- `settings.lua` starts a server socket at `/tmp/nvim-theme-{pid}.sock`
- `extra.lua` reads `config.toml` on startup and applies the correct colorscheme
- Theme plugins (`gruvbox.lua`, `gruvbox_material.lua`, `catpuccin.lua`) are `lazy = true` — loaded on-demand by the `:colorscheme` command

## Tmux integration

`tmux.conf` runs `theme-manager apply` after TPM loads, so the status bar is themed on startup. The daemon handles subsequent dark/light switches. The catppuccin TPM plugin is installed but not auto-loaded — theme-manager runs it explicitly when catppuccin is the active family.
