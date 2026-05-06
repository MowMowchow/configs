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

/// Placeholder — full impl arrives in the next task (B4).
/// Kept here so the module compiles and macOS regression tests still pass.
pub fn watch<F: Fn(Appearance) + Send + 'static>(_on_change: F) -> ! {
    unimplemented!("watch() implementation arrives in task B4")
}
