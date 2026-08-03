//! OS-specific appearance detection.
//!
//! Every backend exposes the same four functions, and `appearance.rs` owns all
//! the logic that is not OS-specific (deduplication, panic isolation, retry).
//! Adding an OS means adding a file here, not touching the watch loop:
//!
//!   name()             -> a label for logs
//!   try_get_current()  -> Some(appearance), or None when undeterminable
//!   spawn_notifier(tx) -> best-effort event source; may legitimately do nothing
//!   park()             -> block the main thread forever
//!
//! `try_get_current` returning None is a first-class answer meaning "this host
//! has no OS appearance to report" — headless, containerised, or a desktop we
//! do not know how to ask. Callers keep their previous value instead of
//! guessing, and on those hosts the terminal drives the theme instead.

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::{name, park, spawn_notifier, try_get_current};

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
pub use linux::{name, park, spawn_notifier, try_get_current};

#[cfg(not(any(target_os = "macos", target_os = "linux")))]
mod unsupported;
#[cfg(not(any(target_os = "macos", target_os = "linux")))]
pub use unsupported::{name, park, spawn_notifier, try_get_current};
