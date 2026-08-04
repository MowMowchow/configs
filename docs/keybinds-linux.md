# Runbook: macOS-style Super-key shortcuts on Ubuntu GNOME (X11)

Goal — `Super+letter` should feel like macOS `Cmd+letter`, without breaking the
terminal's `Ctrl+C` interrupt.

| Shortcut         | Behaviour                                   |
| ---------------- | ------------------------------------------- |
| `Super+C / V / X / A`  | Copy / paste / cut / select-all       |
| `Super+Z` / `Super+Shift+Z` | Undo / redo                      |
| `Super+S / O / P / F`  | Save / open / print / find            |
| `Super+T / W`    | New tab / close tab                         |
| `Super+L`        | Address bar (apps); clear screen (terminal) |
| `Super+N`        | New window                                  |
| `Super+R`        | Reload (apps); reverse-history-search (terminal) |
| `Super+Q`        | Close window (Alt+F4)                       |
| `Super+Space`    | GNOME overview/search (Spotlight-like)      |
| bare `Super`     | Nothing                                     |
| terminal `Ctrl+C` | Still interrupts foreground process        |
| terminal `Super+S/Z/X` | Dropped (would freeze / suspend / clobber) |

## Architecture

The naive approach — globally swap `Super` and `Ctrl` — breaks the terminal.
Instead, we run [xremap](https://github.com/xremap/xremap) as a user daemon.
xremap intercepts evdev keys before any app sees them and emits replacement
events via `uinput`. Two layered keymaps:

1. **Terminal layer** (matched against `WM_CLASS` regexes): `Super+C` → `Ctrl+Shift+C`, etc., so terminal copy/paste works and `Ctrl+C` still interrupts.
2. **Global fallback**: `Super+letter` → `Ctrl+letter` for everything else.

xremap's config lives in this repo at [`xremap/config.yml`](../xremap/config.yml);
the daemon reads it directly because the repo IS `~/.config`.

## What the installer does for you

`./install.sh` dispatches to `platform/linux.sh`; this is the `keybinds` stage
(`platform/stages/keybinds.sh`):

1. Downloads the upstream prebuilt `xremap-linux-x86_64-x11.zip`, extracts the single binary into `~/.local/xremap.app/`, and shims it at `~/.local/bin/xremap`. (Same pattern as kitty and sapling.)
2. Drops `/etc/udev/rules.d/99-input.rules` granting `input` group members read/write access to `/dev/uinput`, plus `/etc/modules-load.d/uinput.conf` so the module loads at boot.
3. Adds your user to the `input` group (`gpasswd -a $USER input`).
4. If on GNOME, rewrites the conflicting GNOME shortcuts via `gsettings` (see table below).
5. Writes `~/.config/systemd/user/xremap.service` pointing at `~/.config/xremap/config.yml`, then `enable --now`s it.

Everything is idempotent — re-running the installer doesn't double-install or
duplicate udev rules.

### When the stage skips itself

It is not unconditional. Two cases where doing the work would be wrong, and
the stage says so and returns instead:

- **No graphical session** (`DISPLAY` and `WAYLAND_DISPLAY` both unset) — an
  SSH devserver, a container, a server install. `systemctl --user enable
  --now` would otherwise block for the full 90s start timeout waiting on a
  `DISPLAY` that never arrives, then leave the unit restarting for the rest
  of the session; and the `input`-group membership below is real
  keystroke-capture privilege to hand a host that can never use it.

- **A Wayland session**, which is Ubuntu 24.04's default. The prebuilt x11
  binary does not fail cleanly there — it starts (GNOME exports `DISPLAY`
  via XWayland) but cannot read `WM_CLASS` for Wayland-native windows, so
  the terminal layer silently stops matching and every binding falls through
  to the global block. `Super+C` becomes SIGINT and `Super+S` becomes XOFF
  inside your shell, which is worse than not running at all. Using xremap
  under Wayland needs the GNOME build plus the companion Xremap GNOME Shell
  extension, which cannot be installed non-interactively — so log into an
  Xorg session, or set it up by hand.

### GNOME `gsettings` keys we touch

| Key | Default on Ubuntu 24.04 | We set it to | Why |
| --- | ----------------------- | ------------ | --- |
| `org.gnome.mutter overlay-key` | `'Super_L'` | `''` | Disable bare-Super opening Activities |
| `org.gnome.desktop.wm.keybindings switch-input-source` | `['<Super>space', …]` | `[]` | Free Super+Space |
| `org.gnome.desktop.wm.keybindings switch-input-source-backward` | `['<Shift><Super>space', …]` | `[]` | Free Shift+Super+Space |
| `org.gnome.shell.keybindings toggle-overview` | `@as []` | `['<Super>space']` | Spotlight-like launcher |
| `org.gnome.shell.keybindings toggle-message-tray` | `['<Super>v', '<Super>m']` | `[]` | Free Super+V (xremap claims it for paste) |
| `org.gnome.shell.keybindings toggle-application-view` | `['<Super>a']` | `[]` | Free Super+A |
| `org.gnome.settings-daemon.plugins.media-keys screensaver` | `['<Super>l']` | `['<Control><Alt>l']` | Free Super+L |

These are defence-in-depth: xremap intercepts at the input layer before GNOME
sees anything, so even if `screensaver` were left on `<Super>l`, xremap's
`Super+L → Ctrl+L` mapping would fire first. Freeing them avoids surprises if
xremap is stopped.

## After installing — important

Adding yourself to the `input` group only takes effect **on a fresh login**.
Until you log out and back in, the xremap daemon will fail to open `/dev/uinput`.
You'll see this in `journalctl --user -u xremap`:

    Permission denied opening /dev/uinput

Just log out of your GNOME session and back in. (`reboot` works too. `su $USER`
does *not* — other processes still don't have the new group.)

## Verifying

After re-login:

```sh
systemctl --user is-active xremap.service     # should print: active
journalctl --user -u xremap.service -n 20     # should NOT have permission errors
xremap --version                              # 0.15.5
```

Then test interactively:

- In a browser: `Super+T` opens a new tab; `Super+L` focuses the address bar; `Super+W` closes the tab; `Super+C` / `Super+V` copy / paste.
- In kitty: `Super+T` opens a new tmux/kitty tab (depending on your bindings); `Super+C` copies the selected text; `Ctrl+C` still interrupts a running process.
- `Super+Space` opens GNOME overview/search.

## Debugging

**Terminal mappings don't fire.** Your terminal's `WM_CLASS` doesn't match the
regexes. Find the actual class:

```sh
xprop WM_CLASS    # then click the terminal window
# Or
xremap --list-windows
```

Add the new pattern to `xremap/config.yml` under the terminal block's `application.only` list and `systemctl --user restart xremap`.

**A specific mapping doesn't work.** Run xremap in the foreground with debug
logging:

```sh
systemctl --user stop xremap
RUST_LOG=debug xremap --watch ~/.config/xremap/config.yml
# Press the key combo you're investigating; see what xremap sees.
```

When done, restart the service: `systemctl --user start xremap`.

**`xremap` daemon fails to start.** Almost always a permissions issue. Check:

```sh
groups | tr ' ' '\n' | grep input    # must show 'input'
ls -l /dev/uinput                    # must be group-writable for 'input'
journalctl --user -u xremap.service -n 30
```

If `groups` doesn't include `input`, you haven't logged out and back in since
running the installer.

## Extending

Want to add `Super+,` for app preferences (the macOS convention)? Edit
`xremap/config.yml` — add `Super-comma: C-comma` under the global block —
then `systemctl --user restart xremap`. The repo IS `~/.config`, so editing
the file in the repo is editing the live config.

The xremap daemon is started with `--watch`, so plugging in a new keyboard
mid-session works without restart, but config-file changes still require a
service restart.

## Rollback

To remove the macOS layer entirely:

```sh
systemctl --user disable --now xremap.service
rm ~/.config/systemd/user/xremap.service
systemctl --user daemon-reload
```

To restore GNOME's default shortcuts:

```sh
gsettings reset org.gnome.mutter overlay-key
gsettings reset org.gnome.desktop.wm.keybindings switch-input-source
gsettings reset org.gnome.desktop.wm.keybindings switch-input-source-backward
gsettings reset org.gnome.shell.keybindings toggle-overview
gsettings reset org.gnome.shell.keybindings toggle-message-tray
gsettings reset org.gnome.shell.keybindings toggle-application-view
gsettings reset org.gnome.settings-daemon.plugins.media-keys screensaver
```

To remove xremap, the udev rule, and your input-group membership:

```sh
rm -rf ~/.local/xremap.app ~/.local/bin/xremap
sudo rm /etc/udev/rules.d/99-input.rules /etc/modules-load.d/uinput.conf
sudo gpasswd -d "$USER" input
sudo udevadm control --reload-rules && sudo udevadm trigger
```

Reboot.

## Why this design (security note)

Granting `input` access means any process running as your user can read every
keystroke (a keylogger could just open evdev). xremap's docs flag this risk
explicitly; we accept it because the alternative — running xremap as root —
has its own [problems](https://github.com/xremap/xremap/blob/master/doc/running_without_sudo.md).
The remapping is also active when the screen is locked.

## References

- xremap: <https://github.com/xremap/xremap>
- Running xremap without sudo: <https://github.com/xremap/xremap/blob/master/doc/running_without_sudo.md>
- xremap config reference: <https://github.com/xremap/xremap/blob/master/doc/reference_config_options.md>
- GNOME shell keyboard shortcuts: <https://help.gnome.org/gnome-help/shell-keyboard-shortcuts.html>
