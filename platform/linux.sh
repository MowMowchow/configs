#!/usr/bin/env bash
# Linux platform layer. Sourced by install.sh after platform/common.sh.
#
# Supported: Ubuntu 24.04 LTS and newer (24.04 is the primary target and must
# work; 26.04 is supported best-effort). Debian is handled by the same layer.
#
# Known differences across that range, all handled below:
#   24.04  no `fastfetch` in the archive (apt has it from 25.04) -> upstream .deb
#   26.04  enforces PEP 668, so `pip3 --user` is blocked    -> pipx throughout
#   both   apt's neovim/kitty/node are too old              -> see the table
#
# Most of this file is not architecture — it is version archaeology. Ubuntu's
# apt ships versions too old for this config, so several tools come from
# elsewhere. Each of those blocks records WHY in a comment; do not "simplify"
# one back to apt without checking the version it ships.
#
#   neovim  apt 0.9.5  -> snap        (lsp.lua needs vim.lsp.config, 0.11+)
#   kitty   apt 0.32.2 -> tarball     (need >= 0.36 for *.auto.conf switching)
#   node    apt 18.x   -> NodeSource  (Mason servers + prettier want >= 20)
#   fonts   apt subset -> tarball     (Nerd Font glyphs)
#   sapling none       -> tarball     (upstream dropped .debs in May 2025)
#
# Two apt packages install under different names: fd-find provides `fdfind`
# and bat provides `batcat`, so both are shimmed into ~/.local/bin.

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

APT_PACKAGES=(
  tmux git curl wget zsh unzip
  ripgrep fd-find bat fzf zoxide fastfetch chafa
  build-essential pkg-config clang-format
  python3 python3-pip python3-venv pipx
  golang-go luarocks
  zsh-syntax-highlighting
  fonts-jetbrains-mono
  # kitty from apt is too old for auto-switching, but the package still
  # provides the .desktop entry and mime associations; the tarball below
  # overrides the binary via PATH precedence.
  kitty
  # gsettings + schemas: theme-manager's Linux appearance backend shells out
  # to them, and neither is guaranteed inside a container.
  libglib2.0-bin gsettings-desktop-schemas
)

# Not in apt, or apt's version is too old.
CARGO_PACKAGES=(eza stylua)
PIPX_PACKAGES=(sqlfluff black isort)

KITTY_VERSION="${KITTY_VERSION:-0.46.2}"
SAPLING_VERSION="${SAPLING_VERSION:-0.2.20260317-201835+0234c21f}"
XREMAP_VERSION="${XREMAP_VERSION:-0.15.5}"
FASTFETCH_VERSION="${FASTFETCH_VERSION:-2.66.0}"
# Only used for the no-snap tarball fallback; the snap tracks stable itself.
NVIM_VERSION="${NVIM_VERSION:-v0.11.4}"

# ── Preflight ────────────────────────────────────────────────────

platform_preflight() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    fail "do not run as root — this script sudos only where needed"
    fail "running as root would chown ~/.local and ~/.cargo to root"
    return 1
  fi

  # Prime the sudo cache and keep it warm: the tarball downloads below can
  # outlast the default timeout, and a re-prompt mid-run is easy to miss.
  sudo -v || { fail "sudo is required"; return 1; }
  ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

# ── Packages ─────────────────────────────────────────────────────

platform_install_packages() {
  platform_preflight || return 1

  info "Packages (apt)"
  if ! need apt-get; then
    warn "no apt-get — install these yourself: ${APT_PACKAGES[*]}"
    return 0
  fi
  sudo apt-get update -qq || warn "apt-get update failed; using the current index"
  _apt_install_resilient "${APT_PACKAGES[@]}"

  mkdir -p "$LOCAL_BIN"
  need fdfind && [ ! -e "$LOCAL_BIN/fd" ]  && ln -s "$(command -v fdfind)" "$LOCAL_BIN/fd"  && ok "fd  -> fdfind"
  need batcat && [ ! -e "$LOCAL_BIN/bat" ] && ln -s "$(command -v batcat)" "$LOCAL_BIN/bat" && ok "bat -> batcat"

  _install_nerd_font
  _install_neovim
  _install_kitty
  _install_node
  _install_sapling
  _install_cargo_tools
  _install_pipx_tools

  if ! need spicetify; then
    warn "spicetify not installed — Linux Spotify is usually a snap, which blocks"
    warn "  the writable Spotify dir spicetify needs. See https://spicetify.app/docs"
  fi
  warn "aerospace is macOS-only — see sway / i3 / hyprland for Linux tiling"
}

# Batch-install, but never let one unavailable package sink the rest.
#
# `apt-get install a b c` is all-or-nothing: if any name is unknown to the
# archive the whole transaction aborts. Package availability genuinely varies
# across our supported range — `fastfetch`, for one, is absent from 24.04 and
# present from 25.04 — so a plain batch install would fail wholesale on the
# release we care most about. Batch first for speed, then fall back to
# one-at-a-time so we install everything that IS available and report the rest.
_apt_install_resilient() {
  if sudo apt-get install -y -qq "$@" 2>/dev/null; then
    ok "$# apt packages"
    return 0
  fi

  warn "batch install failed — retrying individually to isolate the gaps"
  local p unavailable=""
  for p in "$@"; do
    if dpkg -s "$p" >/dev/null 2>&1; then continue; fi
    sudo apt-get install -y -qq "$p" >/dev/null 2>&1 || unavailable="$unavailable $p"
  done

  if [ -n "$unavailable" ]; then
    warn "not available on this release:$unavailable"
    _apt_fallback_for $unavailable
  else
    ok "$# apt packages (installed individually)"
  fi
  return 0
}

# Best-effort alternatives for packages missing on older releases. Anything
# without an alternative degrades gracefully on its own — zshrc guards the
# fastfetch call with `command -v`, for instance.
_apt_fallback_for() {
  local p
  for p in "$@"; do
    case "$p" in
      fastfetch) _install_fastfetch_deb ;;
      pipx)
        # 24.04 has pipx, but if it is ever missing the python formatters
        # still need a home.
        python3 -m pip install --user pipx >/dev/null 2>&1 \
          && ok "pipx (pip --user fallback)" \
          || warn "  pipx unavailable — black/isort/sqlfluff will be skipped"
        ;;
      *) : ;;
    esac
  done
}

# fastfetch is only in the Ubuntu archive from 25.04, but we target 24.04 LTS.
# Upstream publishes .deb packages that cover "Ubuntu 20.04 or newer", so use
# those rather than a third-party apt source.
#
# Chosen over the alternatives on purpose:
#   ppa:zhangsongcui3371/fastfetch  works on 22.04+ and auto-updates, but adds
#                                   a third-party apt source, which is often
#                                   unwanted (or blocked) on a managed machine.
#                                   Set FASTFETCH_USE_PPA=1 to prefer it.
#   snap                            actively wrong here: fastfetch's whole job
#                                   is host introspection, and snap confinement
#                                   restricts exactly that.
#   linuxbrew / build from source   far too heavy for one banner.
#
# The plain .deb targets current glibc; there is also a `-polyfilled` build for
# older systems, which 24.04 (glibc 2.39) does not need.
_install_fastfetch_deb() {
  if need fastfetch; then
    ok "fastfetch $(fastfetch --version 2>/dev/null | awk '{print $2}')"
    return 0
  fi

  if [ "${FASTFETCH_USE_PPA:-0}" = 1 ]; then
    if sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch >/dev/null 2>&1 \
        && sudo apt-get update -qq && sudo apt-get install -y -qq fastfetch; then
      ok "fastfetch (PPA)"
      return 0
    fi
    warn "  PPA install failed — falling back to the upstream .deb"
  fi

  local arch
  case "$(uname -m)" in
    x86_64)          arch=amd64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    armv7l)          arch=armv7l ;;
    *) warn "  no fastfetch .deb for $(uname -m) — banner will be skipped"; return 0 ;;
  esac

  local tmp; tmp="$(mktemp -d)"
  local url="https://github.com/fastfetch-cli/fastfetch/releases/download/${FASTFETCH_VERSION}/fastfetch-linux-${arch}.deb"
  if curl -fsSL "$url" -o "$tmp/fastfetch.deb" \
      && sudo apt-get install -y -qq "$tmp/fastfetch.deb" >/dev/null 2>&1; then
    # apt-get install of a local .deb resolves dependencies, unlike dpkg -i.
    ok "fastfetch $FASTFETCH_VERSION (upstream .deb)"
  else
    warn "  fastfetch .deb install failed — the shell banner will be skipped"
    warn "  alternative: FASTFETCH_USE_PPA=1 ./install.sh --only packages"
  fi
  rm -rf "$tmp"
}

_install_nerd_font() {
  local dir="$HOME/.local/share/fonts/JetBrainsMono-NerdFont"
  if [ -d "$dir" ] && find "$dir" -name '*.ttf' -print -quit | grep -q .; then
    ok "JetBrainsMono Nerd Font"
    return
  fi
  mkdir -p "$dir"
  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/f.tar.xz" \
      https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz; then
    tar -xf "$tmp/f.tar.xz" -C "$dir"
    fc-cache -f "$dir" >/dev/null 2>&1
    ok "JetBrainsMono Nerd Font (tarball)"
  else
    warn "Nerd Font download failed — icons will render as boxes"
  fi
  rm -rf "$tmp"
}

# apt ships 0.9.5. blink.cmp needs 0.10; lsp.lua uses vim.lsp.config and
# vim.lsp.enable, which are 0.11. Without this the plugin set will not load.
_install_neovim() {
  if snap list nvim >/dev/null 2>&1; then
    ok "nvim $(snap list nvim | awk 'NR==2 {print $2}') (snap)"
    return
  fi
  if need snap; then
    # Remove apt's copy first so PATH resolves to /snap/bin/nvim.
    dpkg -l neovim 2>/dev/null | grep -q '^ii' && sudo apt-get remove -y -qq neovim
    if sudo snap install nvim --classic; then
      ok "nvim $(snap list nvim | awk 'NR==2 {print $2}') (snap)"
      return
    fi
    warn "snap install nvim failed — falling back to the upstream tarball"
  fi
  _install_neovim_tarball
}

# Fallback for hosts with no snapd: Docker/LXC, WSL, minimal cloud images,
# managed images that strip it, and Debian (which common.sh routes here too).
#
# Without this the run finished with NO neovim at all — `neovim` is
# deliberately absent from APT_PACKAGES because apt's 0.9.5 is too old, so the
# snapless path installed nothing and only warned. packages_verify does notice
# the missing nvim, but that downgrades the stage to UNVERIFIED rather than
# failing, and the installer still exits 0.
_install_neovim_tarball() {
  local dir="$HOME/.local/nvim"
  local arch; arch="$(uname -m)"
  case "$arch" in
    aarch64 | arm64) arch=arm64 ;;
    *) arch=x86_64 ;;
  esac
  info "  installing neovim $NVIM_VERSION ($arch) — apt's 0.9.5 is below the 0.11 floor"
  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${arch}.tar.gz" -o "$tmp/nvim.tgz" \
      && rm -rf "$dir" && mkdir -p "$dir" \
      && tar -xzf "$tmp/nvim.tgz" -C "$dir" --strip-components=1; then
    ln -sf "$dir/bin/nvim" "$LOCAL_BIN/nvim"
    ok "nvim $NVIM_VERSION -> $LOCAL_BIN (tarball)"
  else
    warn "neovim tarball failed — no nvim >= 0.11; plugins will not bootstrap"
  fi
  rm -rf "$tmp"
}

# apt ships 0.32.2; the *.auto.conf dark/light switching this whole theme
# system relies on needs >= 0.36. No usable PPA or snap, so: upstream tarball.
_install_kitty() {
  local dir="$HOME/.local/kitty.app"
  local have=""
  [ -x "$dir/bin/kitty" ] && have="$("$dir/bin/kitty" --version 2>/dev/null | awk '{print $2}')"
  if [ "$have" = "$KITTY_VERSION" ]; then
    ok "kitty $KITTY_VERSION (tarball)"
    return
  fi
  # Upstream publishes x86_64 and arm64 builds under different suffixes.
  local arch; arch="$(uname -m)"
  case "$arch" in
    aarch64 | arm64) arch=arm64 ;;
    *) arch=x86_64 ;;
  esac
  info "  installing kitty $KITTY_VERSION ($arch) — apt's 0.32.2 cannot auto-switch"
  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL "https://github.com/kovidgoyal/kitty/releases/download/v${KITTY_VERSION}/kitty-${KITTY_VERSION}-${arch}.txz" -o "$tmp/k.txz" \
      && mkdir -p "$dir" && tar -xJf "$tmp/k.txz" -C "$dir"; then
    ln -sf "$dir/bin/kitty"  "$LOCAL_BIN/kitty"
    ln -sf "$dir/bin/kitten" "$LOCAL_BIN/kitten"
    ok "kitty $KITTY_VERSION -> $LOCAL_BIN (overrides apt via PATH order)"
  else
    warn "kitty tarball failed — apt 0.32.2 remains; auto-switching unavailable"
  fi
  rm -rf "$tmp"
}

_install_node() {
  if need node && [ "$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)" -ge 20 ] 2>/dev/null; then
    ok "node $(node --version)"
    return
  fi
  info "  installing Node.js LTS via NodeSource (apt's is too old for Mason)"
  if curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - >/dev/null 2>&1 \
      && sudo apt-get install -y -qq nodejs; then
    ok "node $(node --version)"
  else
    warn "NodeSource install failed — Mason servers and prettier may not work"
  fi
}

# Upstream stopped shipping .debs in May 2025; the tarball is the canonical
# Linux install. zshrc adds ~/.local/share/sapling to PATH.
_install_sapling() {
  local dir="$HOME/.local/share/sapling"
  local have=""
  [ -x "$dir/sl" ] && have="$("$dir/sl" --version 2>/dev/null | head -1 | awk '{print $2}')"
  if [ "$have" = "$SAPLING_VERSION" ]; then
    ok "sapling $SAPLING_VERSION"
    return
  fi
  local arch; arch="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')"
  # The version contains a literal '+', URL-encoded in the tag path segment
  # but left as-is in the filename — that asymmetry matches upstream's URLs.
  local tag="${SAPLING_VERSION//+/%2B}"
  mkdir -p "$dir"
  if curl -fsSL "https://github.com/facebook/sapling/releases/download/${tag}/sapling-${SAPLING_VERSION}-linux-${arch}.tar.xz" | tar -xJf - -C "$dir"; then
    ln -sf "$dir/sl" "$LOCAL_BIN/sl"
    ok "sapling $SAPLING_VERSION -> $LOCAL_BIN/sl"
  else
    warn "sapling download failed — sl unavailable"
  fi
}

_install_cargo_tools() {
  if ! need cargo; then
    warn "cargo not found — skipping: ${CARGO_PACKAGES[*]} tree-sitter-cli"
    return
  fi
  for p in "${CARGO_PACKAGES[@]}"; do
    if need "$p"; then ok "$p"; else
      cargo install --quiet "$p" && ok "$p (cargo)" || warn "cargo install $p failed"
    fi
  done

  # nvim-treesitter v1.0 (main branch) requires tree-sitter-cli >= 0.26.1;
  # apt has 0.20.8. --no-default-features skips the wasm feature, whose
  # rquickjs-sys dependency needs libclang's stdbool.h path and fails to
  # build on a vanilla Ubuntu box. That flag encodes a real debugging session.
  if need tree-sitter && [ "$(tree-sitter --version 2>/dev/null | awk '{print $2}' | cut -d. -f2)" -ge 26 ] 2>/dev/null; then
    ok "tree-sitter $(tree-sitter --version | awk '{print $2}')"
  else
    cargo install tree-sitter-cli --no-default-features --quiet \
      && ok "tree-sitter-cli (cargo, no wasm)" || warn "tree-sitter-cli failed"
  fi
}

# Ubuntu 26.04 enforces PEP 668, so `pip3 install --user` is blocked outright.
_install_pipx_tools() {
  if ! need pipx; then
    warn "pipx not found — skipping: ${PIPX_PACKAGES[*]}"
    return
  fi
  for p in "${PIPX_PACKAGES[@]}"; do
    if need "$p"; then ok "$p"; else
      pipx install "$p" >/dev/null 2>&1 && ok "$p (pipx)" || warn "pipx install $p failed"
    fi
  done
}

# ── Service ──────────────────────────────────────────────────────

platform_install_daemon() {
  info "theme-manager service (systemd user unit)"
  if ! need systemctl; then
    warn "no systemd — start 'theme-manager watch' however this system does it"
    return 0
  fi

  mkdir -p "$SYSTEMD_USER_DIR"
  cat > "$SYSTEMD_USER_DIR/theme-manager.service" <<EOF
[Unit]
Description=theme-manager — follow the desktop light/dark setting
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$LOCAL_BIN/theme-manager watch
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
  ok "theme-manager.service written"

  systemctl --user daemon-reload 2>/dev/null || true
  if systemctl --user enable --now theme-manager.service 2>/dev/null; then
    ok "enabled and started"
  else
    warn "could not enable (no user session bus?)"
    warn "  over plain SSH try: loginctl enable-linger $USER"
  fi
}

# ── macOS-style Super shortcuts (xremap) ─────────────────────────
# Optional; GNOME/X11 only. See docs/keybinds-linux.md for the design
# and the rollback procedure.

platform_install_keybinds() {
  info "macOS-style Super shortcuts (xremap)"

  # No graphical session: nothing here can ever work, and doing it anyway is
  # not free. `systemctl --user enable --now` blocks for the full 90s start
  # timeout on an ExecStartPre that waits for a DISPLAY which never arrives,
  # then the unit churns on Restart=on-failure for the rest of the session.
  # It also adds the user to the `input` group and installs a uinput udev
  # rule — real keystroke-capture privilege — on a box that will never use it.
  if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    warn "no graphical session — skipping xremap (headless/SSH host)"
    return 0
  fi

  # xremap needs a different build per display server, and the x11 one does
  # not degrade gracefully under Wayland: it starts fine (GNOME exports
  # DISPLAY via XWayland) but cannot read WM_CLASS for Wayland-native
  # windows, so the `application: only:` terminal layer silently stops
  # matching and every binding falls through to the global block. That turns
  # Super+C into SIGINT and Super+S into XOFF inside the terminal — worse
  # than not running at all. Ubuntu 24.04 defaults to Wayland.
  #
  # The gnome build needs the companion Xremap GNOME Shell extension, which
  # cannot be installed non-interactively, so refuse rather than pretend.
  if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    warn "Wayland session — skipping xremap (the x11 build mis-scopes bindings here)"
    echo "      To use it, log into an Xorg session, or install the GNOME build"
    echo "      plus the Xremap GNOME Shell extension by hand:"
    echo "      https://github.com/xremap/xremap#gnome-wayland"
    return 0
  fi

  local dir="$HOME/.local/xremap.app"
  local have=""
  [ -x "$dir/xremap" ] && have="$("$dir/xremap" --version 2>/dev/null | awk '{print $2}')"
  if [ "$have" = "$XREMAP_VERSION" ]; then
    ok "xremap $XREMAP_VERSION"
  else
    local tmp; tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/xremap/xremap/releases/download/v${XREMAP_VERSION}/xremap-linux-$(uname -m)-x11.zip" -o "$tmp/x.zip" \
        && mkdir -p "$dir" && unzip -o "$tmp/x.zip" -d "$dir" >/dev/null; then
      chmod +x "$dir/xremap"
      ln -sf "$dir/xremap" "$LOCAL_BIN/xremap"
      ok "xremap $XREMAP_VERSION -> $LOCAL_BIN/xremap"
    else
      warn "xremap install failed — Super shortcuts unavailable"
      rm -rf "$tmp"; return 0
    fi
    rm -rf "$tmp"
  fi

  # uinput access so xremap runs as the user rather than root.
  if grep -q 'KERNEL=="uinput"' /etc/udev/rules.d/99-input.rules 2>/dev/null; then
    ok "uinput udev rule present"
  else
    echo 'KERNEL=="uinput", GROUP="input", TAG+="uaccess", MODE:="0660", OPTIONS+="static_node=uinput"' \
      | sudo tee /etc/udev/rules.d/99-input.rules >/dev/null
    echo uinput | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
    sudo modprobe uinput 2>/dev/null || true
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
    ok "uinput rule installed (group=input)"
  fi

  if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
    ok "$USER in input group"
  else
    sudo gpasswd -a "$USER" input >/dev/null
    warn "added $USER to the input group — LOG OUT AND BACK IN before xremap works"
  fi

  # GNOME grabs several Super chords itself; free them first.
  case "${XDG_CURRENT_DESKTOP:-}" in
    *GNOME*)
      if need gsettings; then
        gsettings set org.gnome.mutter overlay-key '' 2>/dev/null || true
        gsettings set org.gnome.desktop.wm.keybindings switch-input-source "[]" 2>/dev/null || true
        gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "[]" 2>/dev/null || true
        gsettings set org.gnome.shell.keybindings toggle-overview "['<Super>space']" 2>/dev/null || true
        gsettings set org.gnome.shell.keybindings toggle-message-tray "[]" 2>/dev/null || true
        gsettings set org.gnome.shell.keybindings toggle-application-view "[]" 2>/dev/null || true
        gsettings set org.gnome.settings-daemon.plugins.media-keys screensaver "['<Control><Alt>l']" 2>/dev/null || true
        ok "GNOME shortcuts rebound (lock screen is now Ctrl+Alt+L)"
      fi
      ;;
    *) warn "not GNOME — skipped desktop shortcut rebinds" ;;
  esac

  mkdir -p "$SYSTEMD_USER_DIR"
  cat > "$SYSTEMD_USER_DIR/xremap.service" <<'UNIT'
[Unit]
Description=xremap macOS-style keyboard remapping
After=graphical-session.target
PartOf=graphical-session.target

[Service]
# Wait for the GNOME session to import DISPLAY into the systemd user manager.
# Without this, xremap can start before X accepts connections and silently
# falls back to no-X11 mode, where application-scoped rules stop matching.
ExecStartPre=/bin/sh -c 'until systemctl --user show-environment | grep -q "^DISPLAY="; do sleep 0.2; done'
ExecStart=%h/.local/bin/xremap --watch %h/.config/xremap/config.yml
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical-session.target
UNIT
  ok "xremap.service written"

  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now xremap.service 2>/dev/null \
    && ok "xremap enabled + started" \
    || warn "xremap could not start — usually needs a logout/login first"
}

platform_notes() {
  echo "  - Ensure ~/.local/bin precedes /usr/bin in PATH (zshrc does this)."
  echo "  - Appearance follows org.gnome.desktop.interface color-scheme."
  echo "    On Ubuntu, light mode reports 'default', not 'prefer-light'."
  echo "  - Headless/SSH hosts have no OS appearance; the terminal drives the"
  echo "    theme there. 'theme-manager doctor' will tell you which applies."
  echo "  - xremap needs a logout/login the first time (input group membership)."
  echo "  - Linux support is less battle-tested than macOS; report anything odd."
}

# ── Platform helpers used by the shared stages ───────────────────

platform_fonts_present() {
  local d="$HOME/.local/share/fonts/JetBrainsMono-NerdFont"
  [ -d "$d" ] && find "$d" -name '*.ttf' -print -quit 2>/dev/null | grep -q .
}
platform_install_fonts() { _install_nerd_font; }

platform_install_pyformatters() {
  need pipx || { warn "pipx missing — black/isort unavailable"; return 0; }
  for p in black isort; do
    need "$p" || pipx install "$p" >/dev/null 2>&1 || warn "pipx install $p failed"
  done
  return 0
}

platform_service_running() {
  need systemctl || return 1
  systemctl --user is-active --quiet theme-manager.service 2>/dev/null
}

platform_keybinds_present() {
  [ -x "$HOME/.local/xremap.app/xremap" ] \
    && [ -f "$SYSTEMD_USER_DIR/xremap.service" ] \
    && id -nG "$USER" | tr ' ' '\n' | grep -qx input
}

# ── Stage registration ───────────────────────────────────────────
# Order matters: packages before anything that needs a compiler or git,
# rust before theme_manager, site_bootstrap early enough that a corporate
# proxy is configured before the network-heavy stages run.

stage site_bootstrap work

# curlrc first: a ~/.curlrc pointing at an unreachable proxy breaks every
# download below, and does it in a way that names no cause. Warn before the
# network-heavy stages rather than after they fail mysteriously.
stage curlrc
# rust BEFORE packages: the packages stage calls _install_cargo_tools, which
# needs cargo. With packages first, `need cargo` was false on a clean box and
# eza, stylua and tree-sitter-cli were skipped with only a warning — and since
# nothing persisted ~/.cargo/bin onto the login PATH, every later run skipped
# them again. `alias ls` is eza, so `ls` was broken in every new shell.
stage rust
stage packages
stage fonts
stage ohmyzsh
stage symlinks
stage tmux_plugins
stage formatters
stage theme_manager
stage service
stage keybinds
stage login_shell
stage secrets
