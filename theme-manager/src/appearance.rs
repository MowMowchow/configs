//! Appearance (dark/light) detection — platform-dispatched.
//!
//! macOS uses CoreFoundation distributed notifications + `defaults read`.
//! Linux uses `gsettings` (GNOME) + a polling fallback for other DEs.
//!
//! Both backends expose the same `get_current()` and `watch()` interface.

use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Appearance {
    Dark,
    Light,
}

impl fmt::Display for Appearance {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Appearance::Dark => write!(f, "dark"),
            Appearance::Light => write!(f, "light"),
        }
    }
}

#[cfg(target_os = "macos")]
#[path = "appearance_macos.rs"]
mod appearance_macos;
#[cfg(target_os = "linux")]
#[path = "appearance_linux.rs"]
mod appearance_linux;

#[cfg(target_os = "macos")]
pub use appearance_macos::{get_current, watch};
#[cfg(target_os = "linux")]
pub use appearance_linux::{get_current, watch};
