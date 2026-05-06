//! Linux appearance detection — gsettings-based for GNOME / GTK environments.
//!
//! Falls back to Dark on any failure. Other desktop environments without
//! gsettings will only get the polling-fallback half of watch() (see B4).

use super::Appearance;
use std::process::Command;

/// Detect current appearance via the GNOME color-scheme key.
///
/// `gsettings get org.gnome.desktop.interface color-scheme` prints one of:
/// - `'prefer-dark'`
/// - `'prefer-light'`
/// - `'default'`  (GNOME treats this as light for most stock themes)
///
/// On failure (gsettings not installed, key unset on a non-GNOME DE), we
/// default to Dark — same permissive default the macOS backend uses for
/// unknown system state, just inverted because most Linux power users
/// run dark themes.
pub fn get_current() -> Appearance {
    let out = Command::new("gsettings")
        .args(["get", "org.gnome.desktop.interface", "color-scheme"])
        .output();

    match out {
        Ok(o) if o.status.success() => {
            let s = String::from_utf8_lossy(&o.stdout);
            if s.contains("prefer-light") {
                Appearance::Light
            } else if s.contains("prefer-dark") {
                Appearance::Dark
            } else {
                // 'default' — GNOME treats this as light for stock themes
                Appearance::Light
            }
        }
        _ => Appearance::Dark,
    }
}

/// Watch for appearance changes. Blocks the calling thread.
///
/// Two detection sources, same dual-source contract as macOS:
/// 1. `gsettings monitor` subprocess — event-driven, instant on GNOME
/// 2. 5-second polling fallback — catches DEs that don't fire monitor events
///
/// The handler dedupes via a `last` cache so steady-state polling doesn't
/// re-apply the theme every 5 seconds.
pub fn watch<F: Fn(Appearance) + Send + 'static>(on_change: F) -> ! {
    use std::io::{BufRead, BufReader};
    use std::process::Stdio;
    use std::sync::mpsc;
    use std::time::Duration;

    let (tx, rx) = mpsc::channel::<()>();

    // Initial trigger so the daemon applies once at startup.
    tx.send(()).unwrap();

    // Polling fallback — same 5s cadence as the macOS backend.
    let poll_tx = tx.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(5));
        let _ = poll_tx.send(());
    });

    // gsettings monitor — line-buffered subprocess. Each emitted line is an
    // event on the watched key. Auto-restarts on subprocess exit (gsettings
    // killed, DE restarted, etc.) with a 10s back-off so a missing binary
    // doesn't spin.
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
            }
            Err(_) => {
                // gsettings not installed — polling thread carries the load.
            }
        }
        std::thread::sleep(Duration::from_secs(10));
    });

    eprintln!("[theme-manager] watching (gsettings monitor + 5s polling fallback)");

    // Handler: dedupe so we don't re-apply on every poll tick.
    let mut last: Option<Appearance> = None;
    while rx.recv().is_ok() {
        let current = get_current();
        if last.map_or(true, |l| l != current) {
            on_change(current);
            last = Some(current);
        }
    }

    unreachable!("rx.recv() should never close — senders owned by long-lived threads")
}
