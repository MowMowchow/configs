//! Portable appearance type and watch loop.
//!
//! Everything OS-specific lives in `platform/`. This module owns the logic that
//! is the same everywhere: deduplication, panic isolation, retry-on-failure,
//! and the polling fallback.

use crate::platform;
use std::fmt;
use std::panic::AssertUnwindSafe;
use std::str::FromStr;
use std::sync::mpsc;
use std::time::Duration;

/// How often to re-read the appearance regardless of notifications. Catches a
/// missed event, a notifier that died, and platforms with no event source.
pub(crate) const POLL_INTERVAL: Duration = Duration::from_secs(5);

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

impl FromStr for Appearance {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.trim().to_lowercase().as_str() {
            "dark" => Ok(Appearance::Dark),
            "light" => Ok(Appearance::Light),
            other => Err(format!("invalid appearance '{}', expected dark or light", other)),
        }
    }
}

/// Current appearance, or None when this host has none to report.
pub fn try_get_current() -> Option<Appearance> {
    platform::try_get_current()
}

/// Current appearance, defaulting to light when undeterminable.
/// Prefer `try_get_current` where "unknown" is actionable.
pub fn get_current() -> Appearance {
    try_get_current().unwrap_or(Appearance::Light)
}

/// Name of the active platform backend, for logs and `doctor`.
pub fn backend() -> &'static str {
    platform::name()
}

/// Watch for appearance changes. Blocks the calling thread forever.
///
/// Two sources: the platform's event notifier (instant, may not exist) and a
/// 5-second poll (catches missed events and covers platforms with no notifier).
/// Both just nudge the handler, which re-reads the authoritative value — so a
/// spurious wake is harmless and a missed one is corrected within 5s.
///
/// `on_change` returns whether the theme applied cleanly. The result is latched
/// only on success, so a failed or panicking apply is retried on the next tick.
pub fn watch<F: Fn(Appearance) -> bool + Send + 'static>(on_change: F) -> ! {
    let (tx, rx) = mpsc::channel();

    // Prime it so we apply once at startup.
    let _ = tx.send(());

    let poll_tx = tx.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(POLL_INTERVAL);
        if poll_tx.send(()).is_err() {
            break; // handler is gone
        }
    });

    platform::spawn_notifier(tx);

    // Handler thread.
    //
    // Nothing supervises this thread: the main thread is parked in
    // platform::park(), so if this thread dies the process stays alive and the
    // service manager keeps reporting it healthy while it silently does nothing
    // forever. Hence catch_unwind — an adapter panic must not be fatal.
    std::thread::spawn(move || {
        let mut last: Option<Appearance> = None;
        while rx.recv().is_ok() {
            let Some(current) = try_get_current() else {
                // No OS appearance on this host. Not an error; the terminal or
                // an explicit `apply` drives the theme instead.
                continue;
            };

            if last == Some(current) {
                continue;
            }

            let applied = std::panic::catch_unwind(AssertUnwindSafe(|| on_change(current)))
                .unwrap_or_else(|_| {
                    eprintln!("[theme-manager] apply panicked; retrying on next tick");
                    false
                });

            if applied {
                last = Some(current);
            }
        }
    });

    eprintln!(
        "[theme-manager] watching via {} (+ {}s poll)",
        platform::name(),
        POLL_INTERVAL.as_secs()
    );
    platform::park()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appearance_round_trips_through_string() {
        for a in [Appearance::Dark, Appearance::Light] {
            assert_eq!(a.to_string().parse::<Appearance>().unwrap(), a);
        }
    }

    #[test]
    fn appearance_parsing_is_forgiving_but_not_reckless() {
        assert_eq!("Dark".parse::<Appearance>().unwrap(), Appearance::Dark);
        assert_eq!("  light\n".parse::<Appearance>().unwrap(), Appearance::Light);
        assert!("".parse::<Appearance>().is_err());
        assert!("prefer-dark".parse::<Appearance>().is_err());
        assert!("0".parse::<Appearance>().is_err());
    }

    /// The host running the tests must have a backend compiled in, and
    /// whichever it is must not panic when asked.
    #[test]
    fn backend_is_queryable() {
        assert!(!backend().is_empty());
        let _ = try_get_current();
    }
}
