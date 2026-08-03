# dotfiles

Unix dev environment — keyboard-driven, consistently themed, one-command setup.
Runs on **macOS** and **Ubuntu 24.04 LTS+** / Debian. (24.04 is the primary Linux target;
26.04 is supported best-effort.)

## Quick Start

```bash
git clone git@github.com:MowMowchow/configs.git ~/.config
cd ~/.config && ./install.sh
theme-manager doctor        # verify
```

The installer is idempotent — safe to re-run on an existing setup. It detects the OS and
dispatches to a platform layer; nothing OS-specific lives outside `platform/`.

## Structure

```
install.sh          stage driver — detects the OS, loads stages, runs them
platform/
  common.sh         shared helpers, detect_os, link()
  stage.sh          the stage contract and runner (~130 lines)
  stages/*.sh       one file per stage: _check / _apply / [_verify]
  macos.sh          manifest: Homebrew, LaunchAgent, which stages apply
  linux.sh          manifest: apt/snap/tarballs, systemd unit, xremap
site/               employer/machine-specific plugins (gitignored, see site/README.md)
theme-manager/      Rust daemon: one palette, every tool follows the OS
xremap/             Linux: macOS-style Super shortcuts (see docs/keybinds-linux.md)
publish.sh          push the sanitized tree to the public repo (see PUBLISHING.md)
```

### The installer

`install.sh` is a stage driver, not a script. A stage is two or three shell functions in
`platform/stages/<name>.sh`:

| function | required | contract |
|---|---|---|
| `<name>_check`  | yes | return 0 iff the goal is already met; **no side effects** |
| `<name>_apply`  | yes | do the work |
| `<name>_verify` | no  | post-condition, when it differs from the pre-condition |

Each per-OS manifest registers the stages that apply to it with `stage <name> [profile]`. That
is the whole framework — no base class, no registry file: a stage exists because a file defines
it and a manifest registers it.

```bash
./install.sh                      # everything, profile auto-detected
./install.sh --list               # what would run
./install.sh --dry-run            # runs only the _check functions
./install.sh --only theme_manager # or --skip packages
./install.sh --profile personal   # override the auto-detected profile
```

Profile is `work` when a `site/` plugin is present, `personal` otherwise — reusing a signal that
already exists rather than inventing a second one.

**Adding an OS** means adding `platform/<os>.sh` that defines `platform_install_packages`,
`platform_install_daemon` and `platform_notes`, registers its stages, and one line in
`detect_os`. Nothing else changes.

Everything is bash 3.2 compatible: macOS ships 3.2.57 and always will, so no associative arrays,
no `[[ =~ ]]`, no `${x,,}`.

**Adding company-specific config** means creating `site/<name>/` — proxies, internal tooling,
private bootstrap. It is gitignored, the core only ever execs it across a process boundary, and it
can live in its own private repo. See [site/README.md](site/README.md). `make check-public`
refuses to let any of it reach a tracked file.

## What's Inside

| Config | Purpose | Key Bindings |
|--------|---------|-------------|
| **nvim/** | Neovim (lazy.nvim, LSP, Treesitter) | `Space` leader |
| **tmux/** | Terminal multiplexer | `Ctrl+S` prefix |
| **kitty/** | GPU terminal emulator | `Cmd+1/2/3` → tmux windows |
| **aerospace/** | Tiling window manager | Keyboard-driven layouts |
| **zshrc** | Zsh + Oh My Zsh + vi-mode | Symlinked to `~/.zshrc` |
| **theme-manager/** | Rust daemon for unified theming | See [theme-manager/README.md](theme-manager/README.md) |
| **eza/** | `ls` replacement config | `ls` aliased to `eza` |
| **fish/** | Fish shell (alt) | — |
| **spicetify/** | Spotify client theming | — |

## Theme System

`theme-manager` is a Rust binary that keeps kitty, neovim, and tmux in sync, following the OS
light/dark setting: the macOS appearance setting, or `org.gnome.desktop.interface color-scheme`
on GNOME. On a host with no desktop (a remote server, a container) there is no OS appearance —
the terminal drives the theme instead, via tmux's DEC mode 2031 support.

```bash
theme-manager set gruvbox-material medium    # set theme + variant
theme-manager apply                          # re-apply current theme
theme-manager list                           # show available themes
theme-manager watch                          # daemon mode (LaunchAgent / systemd user unit)
theme-manager doctor                         # what can it see, and is it healthy?
```

Supported families: `gruvbox`, `gruvbox-material`, `catppuccin`

## Install Phases

1. **Platform packages** — Homebrew on macOS, apt + cargo on Ubuntu/Debian
2. **Rust toolchain** — via rustup
3. **Oh My Zsh** — zsh framework
4. **Symlinks** — `~/.zshrc`, `~/.tmux.conf`, `~/.tmux`
5. **Tmux plugins** — TPM
6. **theme-manager** — built from source into `~/.local/bin`
7. **Service** — LaunchAgent (macOS) or systemd user unit (Linux)
8. **Site plugins** — each `site/*/bootstrap.sh`, if present

## Secrets

API keys live in `~/.secrets` (never committed):

```bash
cat > ~/.secrets << 'EOF'
export OPENAI_API_KEY="..."
export DATABENTO_API_KEY="..."
EOF
chmod 600 ~/.secrets
```

Sourced automatically by `.zshrc`.

## Post-Install

1. Open a new terminal (or `source ~/.zshrc`)
2. Launch `nvim` — plugins auto-install on first run
3. In tmux: `Ctrl+S` then `I` to install TPM plugins
4. Run `theme-manager set gruvbox-material medium`
