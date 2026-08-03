//! Linux appearance backend (GNOME / Ubuntu 24.04+).
//!
//! Reads `org.gnome.desktop.interface color-scheme`, and watches with
//! `gsettings monitor`, which prints one line per change.
//!
//! Deliberately shells out to `gsettings` rather than speaking D-Bus. The
//! XDG portal (`org.freedesktop.appearance color-scheme`) is the more
//! cross-desktop answer, but it would pull a whole D-Bus stack into a binary
//! whose entire job is to run three subprocesses — and `gsettings monitor` is
//! something you can run by hand when the status bar is wrong at 2am.
//! If a non-GNOME desktop needs support, add a backend here rather than
//! widening this one.

use crate::appearance::Appearance;
use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::Duration;
use std::sync::mpsc::Sender;

/// Minimal `which`: is this executable on PATH?
fn which(bin: &str) -> Option<std::path::PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|d| d.join(bin))
            .find(|p| p.is_file())
    })
}

/// How long to wait before reconnecting a died monitor. Long enough that a
/// missing binary cannot spin the CPU, short enough to be invisible.
const RESTART_BACKOFF: Duration = Duration::from_secs(10);

/// Start `gsettings monitor`, returning the child and its stdout.
///
/// Via stdbuf where available: glib's g_print is block-buffered when stdout is
/// a pipe rather than a tty, so without line buffering the change lines arrive
/// late or in bursts. The backstop poll covers the latency either way.
fn spawn_monitor() -> Option<(std::process::Child, std::process::ChildStdout)> {
    let mut cmd = if which("stdbuf").is_some() {
        let mut c = Command::new("stdbuf");
        c.args(["-oL", "gsettings", "monitor", SCHEMA, KEY]);
        c
    } else {
        let mut c = Command::new("gsettings");
        c.args(["monitor", SCHEMA, KEY]);
        c
    };
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let stdout = child.stdout.take()?;
    Some((child, stdout))
}

pub fn name() -> &'static str {
    "linux-gsettings"
}

const SCHEMA: &str = "org.gnome.desktop.interface";
const KEY: &str = "color-scheme";

/// `gsettings get` quotes its output: `'prefer-dark'`.
fn unquote(s: &str) -> &str {
    s.trim().trim_matches('\'')
}

fn gsettings_get(schema: &str, key: &str) -> Option<String> {
    let out = Command::new("gsettings")
        .args(["get", schema, key])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(unquote(&String::from_utf8_lossy(&out.stdout)).to_string())
}

/// Is there a desktop session bus to observe? Pure env reads plus one stat.
///
/// Check the socket as well as the variable: GIO uses the well-known socket
/// even when DBUS_SESSION_BUS_ADDRESS is unset, and a systemd --user unit
/// always has the variable. Without a bus, reads may still succeed off
/// ~/.config/dconf/user but change notifications never fire — the watcher goes
/// deaf silently, which is exactly the failure the backstop poll exists for.
pub fn session_bus_available() -> bool {
    if std::env::var_os("DBUS_SESSION_BUS_ADDRESS").is_some() {
        return true;
    }
    let runtime = std::env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| format!("/run/user/{}", unsafe { getuid() }));
    Path::new(&runtime).join("bus").exists()
}

extern "C" {
    fn getuid() -> u32;
}

/// Read the current appearance, or None when it cannot be determined.
///
/// None is a real answer and a common one: there is no OS-level appearance on a
/// headless box, in a container, or over SSH with no desktop bus. The caller
/// keeps its previous value rather than guessing, and on such hosts the
/// terminal-provided signal drives the theme instead.
pub fn try_get_current() -> Option<Appearance> {
    let Some(scheme) = gsettings_get(SCHEMA, KEY) else {
        // No color-scheme key at all means GNOME < 42, where dark mode was
        // expressed purely by swapping to a '-dark' GTK theme. Loud, because
        // the substring heuristic breaks on custom themes (Nordic, Orchis-Dark).
        let theme = gsettings_get(SCHEMA, "gtk-theme")?;
        eprintln!(
            "[theme-manager] no color-scheme key (GNOME < 42); \
             guessing from gtk-theme '{theme}'"
        );
        return Some(if theme.to_lowercase().contains("dark") {
            Appearance::Dark
        } else {
            Appearance::Light
        });
    };

    match scheme.as_str() {
        "prefer-dark" => Some(Appearance::Dark),
        "prefer-light" => Some(Appearance::Light),
        // The Ubuntu gotcha. Toggling Settings > Appearance to Dark writes
        // 'prefer-dark', but toggling back writes 'default' — NOT
        // 'prefer-light', which only an explicit `gsettings set` produces. So
        // the values actually seen on Ubuntu are {'default', 'prefer-dark'},
        // and treating anything-but-prefer-light as dark would pin the desktop
        // to dark forever. No preference means the OS default look, i.e. light.
        //
        // kitty resolves the same tri-state independently, so this mapping has
        // to agree with the no-preference-theme.auto.conf the kitty adapter
        // writes, or the two disagree in exactly this case.
        "default" => Some(Appearance::Light),
        other => {
            eprintln!("[theme-manager] unrecognised color-scheme '{other}'");
            None
        }
    }
}

/// Spawn `gsettings monitor`, sending a tick on every change.
///
/// Best effort. If gsettings is missing or there is no session bus this
/// returns quietly and the shared poll carries the load — which on a headless
/// host correctly means "no OS appearance to observe".
pub fn spawn_notifier(tx: Sender<()>) {
    if !session_bus_available() {
        eprintln!(
            "[theme-manager] no session bus; no OS appearance to watch on this host"
        );
        return;
    }

    let Some((child, stdout)) = spawn_monitor() else {
        eprintln!("[theme-manager] gsettings monitor unavailable; polling only");
        return;
    };

    std::thread::spawn(move || {
        let mut child = child;
        let mut stdout = Some(stdout);
        loop {
            if let Some(out) = stdout.take() {
                for line in BufReader::new(out).lines() {
                    match line {
                        // Any line is a change notification; the shared loop
                        // re-reads the authoritative value rather than parsing it.
                        Ok(_) => {
                            if tx.send(()).is_err() {
                                let _ = child.kill();
                                let _ = child.wait();
                                return; // watch loop is gone
                            }
                        }
                        Err(_) => break,
                    }
                }
            }
            let _ = child.wait();

            // The monitor exits when the session bus goes away — a logout, a
            // DE restart, a dbus reload. Reconnect rather than degrading to
            // polling forever. Back off so a missing binary cannot spin.
            std::thread::sleep(RESTART_BACKOFF);
            match spawn_monitor() {
                Some((c, o)) => {
                    child = c;
                    stdout = Some(o);
                }
                None => {
                    eprintln!(
                        "[theme-manager] gsettings monitor gone; {}s poll still active",
                        crate::appearance::POLL_INTERVAL.as_secs()
                    );
                    return;
                }
            }
        }
    });
}

/// Block forever. Unlike macOS there is no run loop to service — the notifier
/// is an ordinary thread — so just park.
pub fn park() -> ! {
    loop {
        std::thread::park();
    }
}
