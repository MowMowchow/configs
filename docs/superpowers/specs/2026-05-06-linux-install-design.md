# Linux (Ubuntu 26.04 LTS) Install Design

**Status:** Spec — pending implementation
**Date:** 2026-05-06
**Scope:** Add Linux/Ubuntu 26.04 LTS support to the dotfiles install pipeline, including a port of `theme-manager` to compile and run on Linux.

## Context

The repo is a personal dotfiles tree symlinked from `~/.config/`. Today's `install.sh` assumes macOS — Homebrew, `launchctl`, `/opt/homebrew/*` paths, AppleInterfaceStyle for dark mode detection. We want a parallel Linux install path so the same `git clone … && ./install.sh` works on Ubuntu 26.04.

The Linux path is acknowledged **untested** at design time — we will add disclaimers in README and at install completion. Auto dark/light switching depends on `gsettings`, which exists under GNOME (Ubuntu's default DE) but not on every desktop. A polling fallback covers the gap with reduced UX (5s detection lag).

Out of scope: replacing aerospace with a Linux tiling WM, supporting older Ubuntu releases, supporting KDE/sway-specific dark-mode backends beyond polling, auto-installing spicetify-cli on Linux.

## High-Level Architecture

Install entrypoint becomes a dispatcher; current macOS logic moves to a sibling file; new Linux script mirrors the phase structure.

```
~/.config/
├── install.sh              dispatcher (15-20 lines, OS detection)
├── install-macos.sh        verbatim copy of today's install.sh, renamed
└── install-linux.sh        new (~250 lines)
```

`install.sh` body:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -s)" in
  Darwin) exec "$HERE/install-macos.sh" "$@" ;;
  Linux)
    if ! grep -qi 'ubuntu' /etc/os-release 2>/dev/null; then
      echo "warning: only Ubuntu is officially supported; trying anyway" >&2
    fi
    exec "$HERE/install-linux.sh" "$@" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
```

Rationale: keeps the README quick-start unchanged (`./install.sh`); each platform script stays focused without nested OS branches; macOS users see no risk because their script is untouched aside from the rename.

## `install-linux.sh` Phases

Mirror of `install-macos.sh`'s 10 phases. Same `info()/ok()/warn()/fail()` helpers, same `link()` symlink helper, same overall idempotency contract (re-running is safe).

| Phase | macOS | Linux |
|------:|-------|-------|
| 1 | Homebrew bootstrap | `apt update`, refuse-as-root check, sudo cache prime |
| 1.5 | (covered by cask) | Fonts: `apt install fonts-jetbrains-mono` (fallback) **then** download `JetBrainsMono.tar.xz` from `github.com/ryanoasis/nerd-fonts/releases/latest` into `~/.local/share/fonts/JetBrainsMono-NerdFont/`, then `fc-cache -f`. Skip if directory already non-empty. |
| 2 | brew formulae + casks | `apt install` core packages + supplemental installs (see Package Map) |
| 3 | rustup | rustup (identical `curl … \| sh -s -- -y`) |
| 4 | Oh My Zsh | Oh My Zsh; print hint about `chsh -s "$(command -v zsh)"` rather than running it (interactive) |
| 5 | symlinks (`~/.zshrc`, `~/.tmux.conf`, `~/.tmux`) + `~/.local/bin` shims (`bat → batcat`, `fd → fdfind`) | Same set of symlinks plus the two binary-name shims |
| 6 | TPM + Catppuccin tmux plugin | Identical (`git clone`) |
| 7 | Neovim formatters: `npm i -g prettier`, `pip3 install --user black isort` | `npm i -g prettier`, **`pipx install black; pipx install isort`** (Ubuntu 26.04 enforces PEP 668 / `--break-system-packages`) |
| 8 | `cargo build --release` of theme-manager | Same — Rust port (see below) |
| 9 | LaunchAgent plist | systemd `--user` unit |
| 10 | Secrets reminder | Identical |

### Phase 1 — apt prelude

```bash
[[ $EUID -eq 0 ]] && fail "do not run as root; the script will sudo when needed"
sudo -v && ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
sudo apt update
```

The background `sudo -v` keeper runs only for the lifetime of the script. We avoid `sudo apt upgrade` — too destructive for an install script.

### Phase 1.5 — Nerd Font install (idempotent)

```bash
sudo apt install -y fonts-jetbrains-mono
NF_DIR="$HOME/.local/share/fonts/JetBrainsMono-NerdFont"
if [[ -d "$NF_DIR" ]] && find "$NF_DIR" -name '*.ttf' -print -quit | grep -q .; then
  ok "JetBrainsMono Nerd Font already installed"
else
  mkdir -p "$NF_DIR"
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/JetBrainsMono.tar.xz" \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
  tar -xf "$TMP/JetBrainsMono.tar.xz" -C "$NF_DIR"
  rm -rf "$TMP"
  fc-cache -f "$NF_DIR"
  ok "JetBrainsMono Nerd Font installed"
fi
```

### Phase 2 — Package Map

| Homebrew formula/cask | Ubuntu source | Notes |
|---|---|---|
| `tmux` | `apt: tmux` | — |
| `neovim` | `apt: neovim` | If `nvim --version` reports < 0.10, fall back to AppImage download from `github.com/neovim/neovim/releases/latest/download/nvim.appimage` into `~/.local/bin/nvim` and `chmod +x`. lazy.nvim requires ≥ 0.9.5. |
| `eza` | `apt: eza` | Present in Ubuntu 24.04+. |
| `neofetch` | `apt: neofetch` | Upstream-archived but still in repos; we keep parity since the repo includes a config. |
| `bat` | `apt: bat` | Binary is `batcat` on Ubuntu — phase 5 creates `~/.local/bin/bat` symlink to `/usr/bin/batcat`. |
| `zsh-syntax-highlighting` | `apt: zsh-syntax-highlighting` | Path differs (`/usr/share/...`); see `zshrc` patch below. |
| `zoxide` | `apt: zoxide` | — |
| `fzf` | `apt: fzf` | — |
| `ripgrep` | `apt: ripgrep` | — |
| `fd` | `apt: fd-find` | Binary is `fdfind` — phase 5 creates `~/.local/bin/fd` symlink. |
| `node` | NodeSource deb | `curl -fsSL https://deb.nodesource.com/setup_lts.x \| sudo -E bash -` then `apt install -y nodejs`. Skip if `node --version` reports a major ≥ 20. |
| `python@3.13` | `apt: python3 python3-pip python3-venv pipx` | We don't pin to 3.13; Ubuntu 26.04 ships 3.12+ which is sufficient. `pipx` is required for phase 7. |
| `luarocks` | `apt: luarocks` | — |
| `stylua` | `cargo install stylua` | Not in apt; cargo is on PATH after phase 3. Skip if `command -v stylua`. |
| `clang-format` | `apt: clang-format` | — |
| `sqlfluff` | `pipx install sqlfluff` | Not in apt. |
| `go` | `apt: golang-go` | Acceptable lag; advanced users override. |
| `spicetify-cli` | **skip with hint** | Linux Spotify is typically snap/flatpak; spicetify needs a writable Spotify dir which snap blocks. Print a one-line note pointing to spicetify docs. |
| `kitty` (cask) | `apt: kitty` | — |
| `font-jetbrains-mono-nerd-font` (cask) | covered by phase 1.5 | — |
| `aerospace` (cask) | **skip with hint** | Print one-line hint suggesting sway / i3 / hyprland; do not auto-install. |

Loop pattern is identical to today's macOS script — array of formulae, iterate, `apt list --installed` check before install for idempotency.

### Phase 5 — symlinks and `~/.local/bin` shims

Adds two new shim creations beyond what macOS does:

```bash
link "/usr/bin/batcat"   "$LOCAL_BIN/bat"
link "/usr/bin/fdfind"   "$LOCAL_BIN/fd"
```

The existing `link()` helper in `install-macos.sh` is the same function — copy it verbatim into `install-linux.sh`. (Could later factor a shared `install-common.sh` if duplication grows; not worth it for the current size.)

### Phase 9 — systemd user unit (replaces LaunchAgent)

Write to `~/.config/systemd/user/theme-manager.service`:

```ini
[Unit]
Description=theme-manager appearance daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=%h/.local/bin/theme-manager watch
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

Then:

```bash
systemctl --user daemon-reload
systemctl --user enable --now theme-manager.service
```

Logs are reachable via `journalctl --user -u theme-manager`. Idempotent: `enable --now` re-applies safely if the service already exists.

## `theme-manager` — Linux Port

Same CLI surface (`set / get / list / apply / watch`), same `config.toml` schema. The macOS-specific code becomes one of two backends; the rest is unchanged.

### Module Structure

```
src/
├── main.rs               unchanged
├── config.rs             unchanged
├── theme.rs              unchanged
├── cmd.rs                add resolve_bin() helper
├── appearance.rs         becomes a thin dispatcher (cfg-gated re-exports)
├── appearance_macos.rs   NEW — current CF + defaults code, moved verbatim
├── appearance_linux.rs   NEW — gsettings-based detection + watch
└── adapters/
    ├── mod.rs            unchanged
    ├── kitty.rs          1-line: use resolve_bin if needed (currently uses pkill which works on Linux unchanged)
    ├── tmux.rs           replace tmux_bin() with resolve_bin("tmux")
    └── neovim.rs         replace find_nvim() with resolve_bin("nvim")
```

### `appearance.rs` (after refactor)

```rust
#[cfg(target_os = "macos")]
mod appearance_macos;
#[cfg(target_os = "linux")]
mod appearance_linux;

#[cfg(target_os = "macos")]
pub use appearance_macos::{get_current, watch};
#[cfg(target_os = "linux")]
pub use appearance_linux::{get_current, watch};

// Shared types — kept in this file so both backends can import them.
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Appearance { Dark, Light }

impl fmt::Display for Appearance {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Appearance::Dark => write!(f, "dark"),
            Appearance::Light => write!(f, "light"),
        }
    }
}
```

### `appearance_macos.rs`

Verbatim move of today's `appearance.rs` body (CFNotificationCenter FFI, `defaults read`, `pub fn watch`). The `Appearance` enum and its `Display` impl move to `appearance.rs` (used by both backends), so this file imports them via `use super::Appearance`.

### `appearance_linux.rs`

```rust
use super::Appearance;
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::Duration;

/// Detect current appearance via GNOME's color-scheme key.
/// Falls back to dark on any failure (matches macOS behavior of being
/// permissive about the default).
pub fn get_current() -> Appearance {
    let out = Command::new("gsettings")
        .args(["get", "org.gnome.desktop.interface", "color-scheme"])
        .output();

    match out {
        Ok(o) if o.status.success() => {
            let s = String::from_utf8_lossy(&o.stdout);
            // gsettings prints values quoted: 'prefer-dark' / 'prefer-light' / 'default'
            if s.contains("prefer-light") {
                Appearance::Light
            } else if s.contains("prefer-dark") {
                Appearance::Dark
            } else {
                // 'default' — GNOME treats this as light for most themes
                Appearance::Light
            }
        }
        _ => Appearance::Dark,
    }
}

/// Watch for appearance changes. Uses two sources:
///   1. `gsettings monitor` subprocess — event-driven, instant on GNOME
///   2. 5-second polling fallback — covers non-GNOME desktops
///
/// Same dual-source contract as the macOS implementation.
pub fn watch<F: Fn(Appearance) + Send + 'static>(on_change: F) -> ! {
    let (tx, rx) = mpsc::channel::<()>();

    // Initial trigger so the daemon applies once at startup.
    tx.send(()).unwrap();

    // Polling fallback (5s, same cadence as macOS).
    let poll_tx = tx.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(5));
        let _ = poll_tx.send(());
    });

    // gsettings monitor — line-buffered subprocess. Each emitted line is an
    // event on the watched key.
    let monitor_tx = tx.clone();
    std::thread::spawn(move || loop {
        let child = Command::new("gsettings")
            .args(["monitor", "org.gnome.desktop.interface", "color-scheme"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn();

        match child {
            Ok(mut c) => {
                if let Some(stdout) = c.stdout.take() {
                    for line in BufReader::new(stdout).lines().map_while(Result::ok) {
                        if !line.is_empty() {
                            let _ = monitor_tx.send(());
                        }
                    }
                }
                let _ = c.wait();
                // If the subprocess dies (gsettings missing, DE killed it),
                // fall through to the sleep + retry at the bottom of the loop.
            }
            Err(_) => {
                // gsettings not installed — polling thread carries the load.
            }
        }
        std::thread::sleep(Duration::from_secs(10));
    });

    // Handler: dedupe so we don't re-apply on every poll tick.
    let mut last: Option<Appearance> = None;
    while rx.recv().is_ok() {
        let current = get_current();
        if last.map_or(true, |l| l != current) {
            on_change(current);
            last = Some(current);
        }
    }

    unreachable!("rx.recv() should never close — senders are owned by long-lived threads")
}
```

Notes:
- No new crates. `std::process` + `std::thread` + `std::sync::mpsc` cover everything.
- The `gsettings monitor` thread auto-restarts if the subprocess exits, with a 10s back-off so a missing binary doesn't spin.
- The handler dedupes by tracking `last`, so the 5-second polling thread doesn't re-apply when nothing changed.

### `cmd.rs::resolve_bin()`

```rust
pub fn resolve_bin(name: &str) -> String {
    let candidates: &[&str] = if cfg!(target_os = "macos") {
        &["/opt/homebrew/bin", "/usr/local/bin"]
    } else {
        &["/usr/local/bin", "/usr/bin"]
    };
    for dir in candidates {
        let p = format!("{}/{}", dir, name);
        if std::path::Path::new(&p).exists() {
            return p;
        }
    }
    name.to_string()
}
```

The three adapter `*_bin()` helpers collapse to:

```rust
fn tmux_bin() -> String { crate::cmd::resolve_bin("tmux") }
```

`adapters/neovim.rs::find_nvim()` — same simplification, returns `Option` for compatibility (returns `None` only if the resolved path doesn't exist after `resolve_bin`'s probe — practically `Some` on every system that has nvim).

### `Cargo.toml`

No dependency changes. The CoreFoundation FFI block is in-line `extern "C"` and `#[link]` — cfg-gating its module is sufficient. Linux builds will not pull or link against anything new.

### Build behavior

- `cargo build --release` on macOS: identical output to today.
- `cargo build --release` on Linux: builds without `CoreFoundation`, includes `appearance_linux` instead.
- Cross-compile is not a goal; each install builds locally.

## Cross-Cutting Fixes (existing files)

### `tmux/tmux.conf:74`

```diff
-run-shell '/Users/jhou/.local/bin/theme-manager apply 2>/tmp/theme-manager-tmux-init.err || true'
+run-shell '~/.local/bin/theme-manager apply 2>/tmp/theme-manager-tmux-init.err || true'
```

`~/.local/bin` is on PATH on both platforms (set by `zshrc` and `install-macos.sh`); tmux's `run-shell` performs tilde expansion. Verified mac-compatible.

### `zshrc` (zsh-syntax-highlighting source path)

Append a third branch to the existing if/elif chain:

```bash
if [[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [[ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
```

### `fish/config.fish`

Wrap the conda init block in an existence check so it silently no-ops on Linux when conda isn't at the macOS path:

```fish
if test -f /Users/jhou/anaconda3/bin/conda
    eval /Users/jhou/anaconda3/bin/conda "shell.fish" "hook" $argv | source
end
```

(Block is already wrapped in `if test -f`; nothing to change. Verified during exploration. **No change needed.**)

### `README.md`

Add a "Linux (Ubuntu 26.04 LTS, untested)" section after the macOS quick-start. Note the install command is the same; mention skipped configs (aerospace, iterm2) and the gsettings dependency for theme-manager auto-switching.

### `.gitignore`

No change. `theme-manager/target/` already covers Linux build artifacts.

## Idempotency & Safety Contract

Same contract as today's `install-macos.sh`:

- Re-running `install-linux.sh` on a fully-installed system completes with no destructive ops.
- Each phase checks for existing state before installing or writing.
- Symlinks at `~/.zshrc`, `~/.tmux.conf`, `~/.tmux` are preserved if already pointing at our targets; if a non-symlink file exists at the destination, it's moved to `*.bak` once.
- The systemd unit is overwritten on every run (it's autogenerated and small) but `systemctl --user enable --now` is idempotent.

## Caveats Surfaced to the User

Printed at the end of `install-linux.sh` and documented in the README:

1. The Linux path has not been tested end-to-end. Expect rough edges around nvim AppImage fallback, Nerd Font download, NodeSource setup script.
2. Auto dark/light requires `gsettings` (works on GNOME). On KDE/sway/wlroots compositors, the polling thread will still detect changes if the desktop writes to the GNOME color-scheme key — otherwise the user must run `theme-manager apply` manually after toggling appearance.
3. `aerospace`, `iterm2`, `spicetify-cli` are skipped on Linux.
4. The user is reminded that they may need `chsh -s "$(command -v zsh)"` and to log out/in for shell change to take effect.

## Files Touched (final)

| File | Change | Type |
|---|---|---|
| `install.sh` | Replaced with dispatcher | rewrite, ~20 lines |
| `install-macos.sh` | Renamed from old `install.sh` | git mv |
| `install-linux.sh` | New | new file (~250 lines) |
| `theme-manager/src/appearance.rs` | Becomes dispatcher | small refactor |
| `theme-manager/src/appearance_macos.rs` | Moved code | new file (move from appearance.rs) |
| `theme-manager/src/appearance_linux.rs` | gsettings-based impl | new file (~80 lines) |
| `theme-manager/src/cmd.rs` | Add `resolve_bin()` | small addition |
| `theme-manager/src/adapters/kitty.rs` | (no change — `pkill` works on both) | none |
| `theme-manager/src/adapters/tmux.rs` | Use `resolve_bin()` | small simplification |
| `theme-manager/src/adapters/neovim.rs` | Use `resolve_bin()` | small simplification |
| `tmux/tmux.conf` | `~/.local/bin/theme-manager` | 1-line edit |
| `zshrc` | Add Linux zsh-syntax-highlighting branch | 2-line addition |
| `README.md` | Linux section | doc addition |

## Out of Scope

- Aerospace replacement (i3 / sway / hyprland config).
- KDE/sway-specific color-scheme detection (covered by polling fallback).
- Auto-installing spicetify-cli on Linux.
- Older Ubuntu (24.04, 22.04). Possible later, but the current target is 26.04 LTS only.
- Refactoring `install-macos.sh` and `install-linux.sh` to share helpers via `install-common.sh`. Not worth it at current size; reconsider if either grows past ~400 lines.

## Validation Plan

Manual checks after implementation:

1. `cargo build --release` succeeds on a Linux host (Docker `ubuntu:26.04` is sufficient).
2. `theme-manager set gruvbox-material hard` → kitty auto.conf files written, tmux options applied if running, nvim sockets messaged if running.
3. `systemctl --user status theme-manager` reports active after install.
4. Toggle GNOME color-scheme via `gsettings set org.gnome.desktop.interface color-scheme prefer-light` and verify daemon picks it up within 5s.
5. macOS regression: re-run `./install.sh` on a Mac, confirm dispatcher routes to `install-macos.sh` and existing flow is unchanged.
