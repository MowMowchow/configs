//! Fallback backend for platforms with no appearance source we understand
//! (BSDs, or Linux without GNOME once that is the case).
//!
//! This is not a stub that pretends: it reports "unknown" rather than guessing
//! a value. The adapters still work, so `theme-manager apply dark|light` and
//! the terminal-driven remote path both function — only automatic following of
//! an OS-level setting is unavailable, which is accurate.

use crate::appearance::Appearance;
use std::sync::mpsc::Sender;

pub fn name() -> &'static str {
    "unsupported"
}

pub fn try_get_current() -> Option<Appearance> {
    None
}

pub fn spawn_notifier(_tx: Sender<()>) {
    eprintln!(
        "[theme-manager] no appearance backend for this platform; \
         use `theme-manager apply dark|light` explicitly"
    );
}

pub fn park() -> ! {
    loop {
        std::thread::park();
    }
}
