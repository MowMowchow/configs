//! macOS-specific appearance detection.
//!
//! Uses CoreFoundation distributed notifications for instant change events,
//! plus a 5-second polling fallback to catch any missed notifications.

use super::Appearance;
use std::ffi::CString;
use std::os::raw::{c_long, c_void};
use std::process::Command;
use std::sync::{mpsc, OnceLock};
use std::time::Duration;

/// Detect current macOS appearance via `defaults read`.
pub fn get_current() -> Appearance {
    let output = Command::new("defaults")
        .args(["read", "-g", "AppleInterfaceStyle"])
        .output();

    match output {
        Ok(o) if o.status.success() => {
            if String::from_utf8_lossy(&o.stdout).trim() == "Dark" {
                Appearance::Dark
            } else {
                Appearance::Light
            }
        }
        // When key doesn't exist, system is in light mode
        _ => Appearance::Light,
    }
}

// ─────────────────────────────────────────────────────────────────
// Core Foundation FFI for distributed notification center
// ─────────────────────────────────────────────────────────────────
#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFNotificationCenterGetDistributedCenter() -> *mut c_void;
    fn CFNotificationCenterAddObserver(
        center: *mut c_void,
        observer: *const c_void,
        callBack: unsafe extern "C" fn(
            center: *mut c_void,
            observer: *mut c_void,
            name: *const c_void,
            object: *const c_void,
            user_info: *const c_void,
        ),
        name: *const c_void,
        object: *const c_void,
        suspensionBehavior: c_long,
    );
    fn CFRunLoopRun();
    fn CFStringCreateWithCString(
        alloc: *const c_void,
        cStr: *const i8,
        encoding: u32,
    ) -> *const c_void;
}

const K_CF_STRING_ENCODING_UTF8: u32 = 0x0800_0100;
const CF_NOTIFICATION_DELIVER_IMMEDIATELY: c_long = 4;

static NOTIFY_TX: OnceLock<mpsc::Sender<()>> = OnceLock::new();

unsafe extern "C" fn on_appearance_changed(
    _center: *mut c_void,
    _observer: *mut c_void,
    _name: *const c_void,
    _object: *const c_void,
    _user_info: *const c_void,
) {
    if let Some(tx) = NOTIFY_TX.get() {
        let _ = tx.send(());
    }
}

/// Watch for macOS appearance changes. Blocks the calling thread.
///
/// Uses a dual-source strategy for maximum reliability:
/// 1. Core Foundation distributed notifications (instant, event-driven)
/// 2. Polling fallback every 5 seconds (catches any missed notifications)
pub fn watch<F: Fn(Appearance) + Send + 'static>(on_change: F) -> ! {
    let (tx, rx) = mpsc::channel();

    // Send initial trigger
    tx.send(()).unwrap();

    // Clone for polling thread before moving into OnceLock
    let poll_tx = tx.clone();

    // Store sender for CF notification callback
    NOTIFY_TX
        .set(tx)
        .expect("watch() can only be called once");

    // Polling fallback thread - catches any missed CF notifications
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(5));
        let _ = poll_tx.send(());
    });

    // Handler thread - processes appearance changes from either source
    std::thread::spawn(move || {
        let mut last: Option<Appearance> = None;
        while rx.recv().is_ok() {
            let current = get_current();
            if last.map_or(true, |l| l != current) {
                on_change(current);
                last = Some(current);
            }
        }
    });

    // Register for CF notifications and block on run loop
    unsafe {
        let center = CFNotificationCenterGetDistributedCenter();
        let name_cstr =
            CString::new("AppleInterfaceThemeChangedNotification").unwrap();
        let name = CFStringCreateWithCString(
            std::ptr::null(),
            name_cstr.as_ptr(),
            K_CF_STRING_ENCODING_UTF8,
        );

        CFNotificationCenterAddObserver(
            center,
            std::ptr::null(),
            on_appearance_changed,
            name,
            std::ptr::null(),
            CF_NOTIFICATION_DELIVER_IMMEDIATELY,
        );

        eprintln!("[theme-manager] watching (CF notifications + 5s polling fallback)");
        CFRunLoopRun();
    }

    unreachable!("CFRunLoopRun should never return")
}
