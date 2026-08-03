//! macOS appearance backend.
//!
//! Two event sources feed the shared watch loop in `appearance.rs`:
//! a CoreFoundation distributed notification (instant) and, from the shared
//! loop, a periodic poll (catches anything the notification misses).

use crate::appearance::Appearance;
use std::ffi::CString;
use std::os::raw::{c_long, c_void};
use std::process::Command;
use std::sync::mpsc::Sender;
use std::sync::OnceLock;

pub fn name() -> &'static str {
    "macos"
}

/// Read the current appearance, distinguishing "light" from "don't know".
///
/// `defaults read -g AppleInterfaceStyle` exits non-zero when the key is
/// absent, and absent genuinely means light mode. A failure to *run* `defaults`
/// is a different thing and must not be reported as light — otherwise a
/// transient fork failure flips the whole system to light.
pub fn try_get_current() -> Option<Appearance> {
    match Command::new("defaults")
        .args(["read", "-g", "AppleInterfaceStyle"])
        .output()
    {
        Ok(o) if o.status.success() => {
            if String::from_utf8_lossy(&o.stdout).trim() == "Dark" {
                Some(Appearance::Dark)
            } else {
                Some(Appearance::Light)
            }
        }
        // Key absent — documented macOS behaviour for light mode.
        Ok(_) => Some(Appearance::Light),
        // Could not execute `defaults`. Unknown, so do not guess.
        Err(_) => None,
    }
}

// ─────────────────────────────────────────────────────────────────
// CoreFoundation distributed notification centre
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

static NOTIFY_TX: OnceLock<Sender<()>> = OnceLock::new();

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

/// Register for `AppleInterfaceThemeChangedNotification`. Best effort: the
/// shared poll still runs, so a failure here degrades latency, not correctness.
pub fn spawn_notifier(tx: Sender<()>) {
    if NOTIFY_TX.set(tx).is_err() {
        eprintln!("[theme-manager] notifier already registered");
        return;
    }

    unsafe {
        let center = CFNotificationCenterGetDistributedCenter();
        let name_cstr = CString::new("AppleInterfaceThemeChangedNotification")
            .expect("static string has no interior nul");
        let cf_name = CFStringCreateWithCString(
            std::ptr::null(),
            name_cstr.as_ptr(),
            K_CF_STRING_ENCODING_UTF8,
        );

        CFNotificationCenterAddObserver(
            center,
            std::ptr::null(),
            on_appearance_changed,
            cf_name,
            std::ptr::null(),
            CF_NOTIFICATION_DELIVER_IMMEDIATELY,
        );
    }
}

/// Block the calling thread forever. Must be the main thread: the CF run loop
/// is what actually delivers the notifications registered above.
pub fn park() -> ! {
    unsafe { CFRunLoopRun() };
    unreachable!("CFRunLoopRun should never return")
}
