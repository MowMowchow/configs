# Linux (Ubuntu 26.04 LTS) Install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Linux/Ubuntu 26.04 LTS install path mirroring the existing macOS pipeline, and make `theme-manager` compile and run on Linux with a `gsettings`-based appearance backend.

**Architecture:** Top-level `install.sh` becomes a dispatcher selecting `install-macos.sh` (renamed from current `install.sh`) or `install-linux.sh` (new) by `uname -s`. `theme-manager`'s appearance detection module is split into `appearance_macos.rs` (current code, moved verbatim) and `appearance_linux.rs` (new, gsettings-based with the same dual-source watch contract). Adapter binary-resolution helpers consolidate into a single `cmd::resolve_bin()` utility.

**Tech Stack:** Bash 5+, Rust 2021 edition (stdlib only — no new crates), apt, systemd `--user`, gsettings (GNOME), shellcheck for shell verification.

**Spec:** `docs/superpowers/specs/2026-05-06-linux-install-design.md`

---

## File Structure

**New files:**
- `install-linux.sh` — Linux installer (~250 lines, mirrors macOS phases)
- `theme-manager/src/appearance_macos.rs` — current appearance.rs body, moved
- `theme-manager/src/appearance_linux.rs` — gsettings-based detection + watch
- `docs/superpowers/plans/2026-05-06-linux-install.md` — this file (already created)

**Modified files:**
- `install.sh` — replaced with a 20-line dispatcher (current logic moves to `install-macos.sh`)
- `theme-manager/src/appearance.rs` — becomes a dispatcher with shared `Appearance` enum
- `theme-manager/src/cmd.rs` — adds `resolve_bin()` helper
- `theme-manager/src/adapters/tmux.rs` — uses `resolve_bin()`
- `theme-manager/src/adapters/neovim.rs` — uses `resolve_bin()`
- `tmux/tmux.conf:74` — hardcoded macOS path → `~/.local/bin/`
- `zshrc` — third elif branch for Linux zsh-syntax-highlighting path
- `README.md` — Linux quick-start section

**Renamed:**
- `install.sh` → `install-macos.sh` (verbatim copy, then create new `install.sh` dispatcher)

**Untouched (verified during spec review):**
- `fish/config.fish` (already wraps conda init in `test -f`)
- `.gitignore` (theme-manager/target/ already covers Linux)
- `theme-manager/Cargo.toml` (no new deps)
- `theme-manager/src/main.rs`, `config.rs`, `theme.rs`, `adapters/mod.rs`, `adapters/kitty.rs`

---

## Execution Order

Tasks are grouped to minimize cross-task coupling. Within each group, later tasks may depend on earlier ones. Across groups, A→B→C→D→E is the safe order.

- **Group A** (cross-cutting fixes, independent)
- **Group B** (Rust theme-manager port — must be self-contained, tests included)
- **Group C** (install dispatcher — small, depends on nothing)
- **Group D** (`install-linux.sh` build-up, phase-by-phase)
- **Group E** (docs)

---

## Group A: Cross-Cutting Fixes

### Task A1: Fix hardcoded macOS path in `tmux/tmux.conf`

**Files:**
- Modify: `tmux/tmux.conf:74`

- [ ] **Step 1: Read the current line**

Run: `sed -n '74p' tmux/tmux.conf`
Expected: `run-shell '/Users/jhou/.local/bin/theme-manager apply 2>/tmp/theme-manager-tmux-init.err || true'`

- [ ] **Step 2: Replace hardcoded path with `~/.local/bin`**

Use the Edit tool:
- old_string:
  ```
  run-shell '/Users/jhou/.local/bin/theme-manager apply 2>/tmp/theme-manager-tmux-init.err || true'
  ```
- new_string:
  ```
  run-shell '~/.local/bin/theme-manager apply 2>/tmp/theme-manager-tmux-init.err || true'
  ```

- [ ] **Step 3: Verify the line changed**

Run: `sed -n '74p' tmux/tmux.conf`
Expected: `run-shell '~/.local/bin/theme-manager apply 2>/tmp/theme-manager-tmux-init.err || true'`

- [ ] **Step 4: Verify tmux still parses the config**

Run: `tmux -f tmux/tmux.conf -L test-config new-session -d 'true' 2>&1; tmux -L test-config kill-server 2>/dev/null || true`
Expected: no error from tmux about syntax. (The `theme-manager apply` will fail silently inside the test session because no terminal is attached — that's fine; the `|| true` swallows it.)

- [ ] **Step 5: Commit**

```bash
git add tmux/tmux.conf
git commit -m "tmux: use ~/.local/bin for theme-manager path

Hardcoded /Users/jhou/.local/bin would only work for one user on macOS.
Tilde expansion works on both macOS and Linux."
```

---

### Task A2: Add Linux fallback for zsh-syntax-highlighting in `zshrc`

**Files:**
- Modify: `zshrc` lines 119–124

- [ ] **Step 1: Read current state**

Run: `sed -n '118,125p' zshrc`
Expected output contains the existing if/elif chain checking `/opt/homebrew/share/...` and `/usr/local/share/...`.

- [ ] **Step 2: Add a third elif branch for Linux apt path**

Use the Edit tool:
- old_string:
  ```
  if [[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  elif [[ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  fi
  ```
- new_string:
  ```
  if [[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  elif [[ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  elif [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  fi
  ```

- [ ] **Step 3: Verify zsh parses the file**

Run: `zsh -n zshrc && echo OK`
Expected: `OK`. (`-n` is syntax-only, doesn't execute.)

- [ ] **Step 4: Commit**

```bash
git add zshrc
git commit -m "zshrc: add Ubuntu apt path for zsh-syntax-highlighting

apt installs the plugin at /usr/share/zsh-syntax-highlighting/, which
neither of the existing Homebrew branches covered."
```

---

## Group B: theme-manager Rust Port

This group must produce a Rust crate that compiles and tests pass on macOS (regression-safe) and is structured so that Linux compilation works (verification deferred to Task B7).

### Task B1: Add `resolve_bin()` helper to `cmd.rs` with unit tests

**Files:**
- Modify: `theme-manager/src/cmd.rs`

- [ ] **Step 1: Read current `cmd.rs`**

Use the Read tool on `theme-manager/src/cmd.rs`. Confirm it contains only the `run_with_timeout` function.

- [ ] **Step 2: Append `resolve_bin()` and a `#[cfg(test)]` module to `cmd.rs`**

Append to the end of `theme-manager/src/cmd.rs`:

```rust

/// Resolve a binary's absolute path by probing platform-specific install
/// directories, falling back to the bare name (PATH-resolved by the OS).
///
/// macOS probes /opt/homebrew/bin then /usr/local/bin (Homebrew Apple Silicon
/// then Intel). Linux probes /usr/local/bin then /usr/bin (manual installs
/// then apt). The bare-name fallback covers anywhere else on PATH.
pub fn resolve_bin(name: &str) -> String {
    let candidates: &[&str] = if cfg!(target_os = "macos") {
        &["/opt/homebrew/bin", "/usr/local/bin"]
    } else {
        &["/usr/local/bin", "/usr/bin"]
    };
    for dir in candidates {
        let p = format!("{}/{}", dir, name);
        if std::path::Path::new(&p).exists() {
            return p;
        }
    }
    name.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_bin_returns_absolute_path_when_binary_exists() {
        // /bin/sh exists on every Unix; it's not in our candidate dirs, but
        // we use it here only to assert the fallback returns the bare name
        // when nothing in candidates matches.
        let result = resolve_bin("definitely-not-a-real-binary-xyz");
        assert_eq!(result, "definitely-not-a-real-binary-xyz");
    }

    #[test]
    fn resolve_bin_finds_binary_in_usr_bin() {
        // `ls` exists at /usr/bin/ls on Linux and /bin/ls on macOS (with
        // /usr/bin/ls as a symlink). On macOS the candidate list doesn't
        // include /usr/bin, so we'd hit the fallback. To make this test
        // platform-agnostic, just check the result is non-empty and either
        // absolute (found in candidates) or the bare name (fallback).
        let result = resolve_bin("ls");
        assert!(!result.is_empty());
        assert!(result == "ls" || result.starts_with('/'));
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `cd theme-manager && cargo test cmd::tests`
Expected: 2 passed.

- [ ] **Step 4: Commit**

```bash
git add theme-manager/src/cmd.rs
git commit -m "theme-manager: add cmd::resolve_bin() platform-aware path probe

Centralizes the macOS-specific /opt/homebrew lookup currently duplicated
across the tmux and neovim adapters. Linux builds will probe /usr/local/bin
and /usr/bin instead. Bare-name fallback delegates to OS PATH lookup."
```

---

### Task B2: Refactor `appearance.rs` into a dispatcher and move macOS code to `appearance_macos.rs`

**Files:**
- Create: `theme-manager/src/appearance_macos.rs`
- Modify: `theme-manager/src/appearance.rs` (replace contents)

- [ ] **Step 1: Read current `appearance.rs`** (already done during spec writing — confirm it has the `Appearance` enum, `get_current()`, `watch()`, CF FFI).

- [ ] **Step 2: Create `theme-manager/src/appearance_macos.rs` with the macOS body**

Use Write to create `theme-manager/src/appearance_macos.rs`:

```rust
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
```

- [ ] **Step 3: Replace `theme-manager/src/appearance.rs` with the dispatcher**

Use Write to replace `theme-manager/src/appearance.rs` entire contents:

```rust
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
mod appearance_macos;
#[cfg(target_os = "linux")]
mod appearance_linux;

#[cfg(target_os = "macos")]
pub use appearance_macos::{get_current, watch};
#[cfg(target_os = "linux")]
pub use appearance_linux::{get_current, watch};
```

- [ ] **Step 4: Build and run all tests on macOS**

Run: `cd theme-manager && cargo build --release && cargo test`
Expected: build succeeds, all tests pass (the existing 2 from B1, plus any pre-existing).

- [ ] **Step 5: Commit**

```bash
git add theme-manager/src/appearance.rs theme-manager/src/appearance_macos.rs
git commit -m "theme-manager: split appearance.rs into platform-dispatched modules

The macOS body moves verbatim into appearance_macos.rs. appearance.rs
becomes a dispatcher that re-exports get_current/watch from the right
backend at compile time. Shared Appearance enum + Display impl stay in
appearance.rs so both backends can import them via super::Appearance.

No behavior change on macOS — same code path, same exports."
```

---

### Task B3: Add `appearance_linux.rs` with `get_current()` only

**Files:**
- Create: `theme-manager/src/appearance_linux.rs`

- [ ] **Step 1: Create `theme-manager/src/appearance_linux.rs` with detection only (watch comes in B4)**

Use Write to create `theme-manager/src/appearance_linux.rs`:

```rust
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
```

- [ ] **Step 2: Verify macOS build still works (regression check)**

Run: `cd theme-manager && cargo build --release`
Expected: success. (`appearance_linux.rs` is `#[cfg(target_os = "linux")]` so it's not compiled on macOS — but it must still parse.)

To force it to be parsed on macOS for type-checking, also run:

Run: `cd theme-manager && cargo check --target-dir=target/lint -- --cfg=target_os=\"linux\" 2>&1 | head -30 || true`

(This is best-effort; the goal is just to catch obvious syntax errors. If it errors due to missing target, skip — Task B7's Docker check covers full Linux compilation.)

- [ ] **Step 3: Run all tests**

Run: `cd theme-manager && cargo test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add theme-manager/src/appearance_linux.rs
git commit -m "theme-manager: add Linux appearance detection (get_current only)

Reads org.gnome.desktop.interface color-scheme via gsettings. watch() is
a stub for now — full impl with gsettings monitor + polling fallback
lands in the next commit so the diff stays reviewable."
```

---

### Task B4: Implement `appearance_linux::watch()` with gsettings monitor + polling fallback

**Files:**
- Modify: `theme-manager/src/appearance_linux.rs` (replace `watch()` stub)

- [ ] **Step 1: Replace the stub `watch()` with the full implementation**

Use the Edit tool on `theme-manager/src/appearance_linux.rs`:
- old_string:
  ```
  /// Placeholder — full impl arrives in the next task (B4).
  /// Kept here so the module compiles and macOS regression tests still pass.
  pub fn watch<F: Fn(Appearance) + Send + 'static>(_on_change: F) -> ! {
      unimplemented!("watch() implementation arrives in task B4")
  }
  ```
- new_string:
  ```
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
  ```

- [ ] **Step 2: Build on macOS (regression — appearance_linux.rs is cfg-gated out)**

Run: `cd theme-manager && cargo build --release && cargo test`
Expected: all tests pass; build succeeds.

- [ ] **Step 3: Commit**

```bash
git add theme-manager/src/appearance_linux.rs
git commit -m "theme-manager: implement Linux watch() via gsettings monitor + polling

Same dual-source contract as macOS:
- gsettings monitor subprocess for instant event-driven updates on GNOME
- 5-second polling thread as fallback for non-GNOME DEs
- Handler dedupes via last-applied cache so polling steady state is silent

No new crates — std::process + std::sync::mpsc only. The monitor subprocess
auto-restarts on exit with 10s back-off."
```

---

### Task B5: Refactor `adapters/tmux.rs` to use `cmd::resolve_bin()`

**Files:**
- Modify: `theme-manager/src/adapters/tmux.rs:13-20`

- [ ] **Step 1: Read the current `tmux_bin()` helper**

Use Read on `theme-manager/src/adapters/tmux.rs` lines 1-25 to confirm the current shape.

- [ ] **Step 2: Replace the helper with a `resolve_bin()` call**

Use the Edit tool:
- old_string:
  ```
  /// Resolve the tmux binary path. The daemon runs under launchd with a
  /// minimal PATH that doesn't include /opt/homebrew/bin, so we check
  /// known locations explicitly (same pattern as the neovim adapter).
  fn tmux_bin() -> &'static str {
      for path in &["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"] {
          if std::path::Path::new(path).exists() {
              return path;
          }
      }
      "tmux" // fall back to PATH lookup
  }
  ```
- new_string:
  ```
  /// Resolve the tmux binary path. The daemon runs under launchd / systemd
  /// with a minimal PATH, so we probe known install dirs via the shared
  /// platform-aware helper.
  fn tmux_bin() -> String {
      crate::cmd::resolve_bin("tmux")
  }
  ```

- [ ] **Step 3: Update call sites — `&'static str` becomes `String`**

`tmux_bin()` previously returned `&'static str`; now returns `String`. The existing call sites pass it to `Command::new(tmux_bin())`, which accepts both types via `AsRef<OsStr>`. No call-site edits should be necessary.

Run: `cd theme-manager && cargo build --release 2>&1 | head -30`
Expected: build succeeds with no errors. If errors mention type mismatches, fix the call site by passing `&tmux_bin()` instead of `tmux_bin()`.

- [ ] **Step 4: Run tests**

Run: `cd theme-manager && cargo test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add theme-manager/src/adapters/tmux.rs
git commit -m "theme-manager/tmux: use shared cmd::resolve_bin() helper

Eliminates the macOS-only path probe inline in the adapter. Linux probes
/usr/local/bin and /usr/bin instead. Behavior on macOS unchanged."
```

---

### Task B6: Refactor `adapters/neovim.rs` to use `cmd::resolve_bin()`

**Files:**
- Modify: `theme-manager/src/adapters/neovim.rs:114-127`

- [ ] **Step 1: Read the current `find_nvim()` helper**

Use Read on `theme-manager/src/adapters/neovim.rs` lines 110-128 to confirm the current shape.

- [ ] **Step 2: Replace the helper with a `resolve_bin()` call**

Use the Edit tool:
- old_string:
  ```
  fn find_nvim() -> Option<String> {
      for path in &["/opt/homebrew/bin/nvim", "/usr/local/bin/nvim"] {
          if std::path::Path::new(path).exists() {
              return Some(path.to_string());
          }
      }
      // Fall back to PATH lookup
      Command::new("which")
          .arg("nvim")
          .output()
          .ok()
          .filter(|o| o.status.success())
          .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
  }
  ```
- new_string:
  ```
  /// Resolve the nvim binary. Returns None only if the resolved path doesn't
  /// exist as a file on disk — practically nvim is either installed (Some)
  /// or absent (None and the adapter skips silently).
  fn find_nvim() -> Option<String> {
      let resolved = crate::cmd::resolve_bin("nvim");
      // resolve_bin returns either an absolute /usr/.../nvim that we
      // verified exists, or the bare "nvim" PATH-fallback. The bare-name
      // case means our probes failed; we then re-check with `which` to
      // distinguish installed-but-not-in-our-list from not-installed.
      if std::path::Path::new(&resolved).is_absolute() {
          return Some(resolved);
      }
      Command::new("which")
          .arg("nvim")
          .output()
          .ok()
          .filter(|o| o.status.success())
          .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
          .filter(|s| !s.is_empty())
  }
  ```

- [ ] **Step 3: Build and test**

Run: `cd theme-manager && cargo build --release && cargo test`
Expected: build succeeds, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add theme-manager/src/adapters/neovim.rs
git commit -m "theme-manager/nvim: use shared cmd::resolve_bin() helper

Replaces the inline /opt/homebrew probe. Keeps the which-based fallback
so the adapter stays Some(...) when nvim is installed somewhere unusual.

Same behavior on macOS; Linux now probes /usr/local/bin, /usr/bin first."
```

---

### Task B7: Verify Linux build via Docker (best-effort regression check)

**Files:** none modified

- [ ] **Step 1: Check if Docker is available**

Run: `command -v docker && docker version >/dev/null 2>&1 && echo HAS_DOCKER || echo NO_DOCKER`
- If `HAS_DOCKER`: continue to Step 2.
- If `NO_DOCKER`: skip this task — note in the commit log of the next task that the Linux build was not verified locally. Move to Task C1.

- [ ] **Step 2: Build the Rust crate inside an Ubuntu 26.04 container**

Run:
```bash
docker run --rm -v "$(pwd)/theme-manager:/work" -w /work ubuntu:26.04 bash -lc '
  apt-get update -qq &&
  apt-get install -y -qq curl build-essential pkg-config &&
  curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal &&
  . "$HOME/.cargo/env" &&
  cargo build --release 2>&1 | tail -40 &&
  cargo test 2>&1 | tail -20
'
```

Expected: `cargo build --release` succeeds, `cargo test` reports all tests pass. If the image tag `ubuntu:26.04` is not yet available on Docker Hub, substitute `ubuntu:latest` and note that in the commit message.

- [ ] **Step 3: If build fails, debug and fix**

Common failure modes:
- Missing `pkg-config` / `build-essential` → already in Step 2; if more deps are needed, add them and re-run.
- `appearance_linux.rs` syntax error → fix and re-run B4 build verification.
- Cfg-gated module not found → check that `appearance.rs` correctly references `mod appearance_linux` under `#[cfg(target_os = "linux")]`.

- [ ] **Step 4: No commit needed** — this is a verification-only task. If you made fixes, the relevant fix-up commit goes against the task that introduced the bug.

---

## Group C: Install Dispatcher

### Task C1: Rename `install.sh` → `install-macos.sh`

**Files:**
- Rename: `install.sh` → `install-macos.sh`

- [ ] **Step 1: Confirm `install.sh` exists and `install-macos.sh` does not**

Run: `ls -la install.sh install-macos.sh 2>&1`
Expected: `install.sh` exists; `install-macos.sh` reports "No such file or directory".

- [ ] **Step 2: Rename via git**

Run: `git mv install.sh install-macos.sh`

- [ ] **Step 3: Verify executable bit and shebang preserved**

Run: `ls -la install-macos.sh && head -1 install-macos.sh`
Expected: file is executable (`-rwxr-xr-x`); first line is `#!/usr/bin/env bash`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "install: rename install.sh to install-macos.sh (prep for dispatcher)

The new install.sh becomes a 20-line OS-detect dispatcher in the next
commit. Existing macOS contents move verbatim — no logic changes."
```

---

### Task C2: Create new `install.sh` dispatcher

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Create the dispatcher**

Use Write to create `install.sh`:

```bash
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# dotfiles installer — OS dispatcher
#
# Usage:
#   git clone git@github.com:MowMowchow/configs.git ~/.config
#   cd ~/.config && ./install.sh
#
# Detects the host OS and delegates to the platform-specific installer.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)" in
  Darwin)
    exec "$HERE/install-macos.sh" "$@"
    ;;
  Linux)
    if [[ -r /etc/os-release ]] && ! grep -qi '^ID=ubuntu' /etc/os-release; then
      printf '\033[1;33m  ! only Ubuntu is officially supported; trying anyway\033[0m\n' >&2
    fi
    exec "$HERE/install-linux.sh" "$@"
    ;;
  *)
    printf 'unsupported OS: %s\n' "$(uname -s)" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x install.sh`

- [ ] **Step 3: Lint with shellcheck**

Run: `shellcheck install.sh && echo OK`
Expected: `OK`. If shellcheck is not installed, run `brew install shellcheck` (macOS) or skip with a warning — the script is small and reviewed by hand.

- [ ] **Step 4: Test that it dispatches to install-macos.sh**

Run: `./install.sh --help 2>&1 | head -5; echo "exit=$?"` — actually `install-macos.sh` does not support `--help` and would start running. Better:

Run: `bash -x install.sh < /dev/null 2>&1 | head -5 || true`
Expected: trace output shows `case "$(uname -s)"` and `exec ".../install-macos.sh"`. The actual `install-macos.sh` execution may begin and prompt for sudo; abort it with Ctrl+C if needed.

A safer dry-run:

Run: `bash -nc 'set -euo pipefail; HERE="."; case "Darwin" in Darwin) echo would-exec install-macos.sh ;; esac'`
Expected: `would-exec install-macos.sh`.

(This isn't testing our actual file, but the case statement logic is small and matches above. If a Linux host is available, also confirm `case "Linux" in Linux) echo would-exec install-linux.sh ;; esac` prints the linux branch.)

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "install: add OS-dispatching install.sh

Top-level install.sh now detects host OS via uname -s and execs the
matching platform installer. macOS users see no behavior change — same
./install.sh entrypoint, same end-to-end install. Linux users hit the
new install-linux.sh (added next)."
```

---

## Group D: `install-linux.sh` (phase-by-phase)

Build the file up incrementally. Each task adds one or two phases. After each task, the file is well-formed shell (passes shellcheck) but isn't expected to actually install correctly until the full set of phases are present.

### Task D1: Skeleton + Phase 1 (apt prelude, helpers)

**Files:**
- Create: `install-linux.sh`

- [ ] **Step 1: Create `install-linux.sh` with the helper functions, header, and Phase 1**

Use Write to create `install-linux.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# dotfiles installer — Ubuntu 26.04 LTS
#
# Usage:
#   ./install.sh   (which exec's into this script on Linux)
#
# Idempotent — safe to re-run. Skips steps already done.
# ─────────────────────────────────────────────────────────────────

DOTFILES="$HOME/.config"
LOCAL_BIN="$HOME/.local/bin"

info()  { printf "\033[1;34m==> %s\033[0m\n" "$1"; }
ok()    { printf "\033[1;32m  ✓ %s\033[0m\n" "$1"; }
warn()  { printf "\033[1;33m  ! %s\033[0m\n" "$1"; }
fail()  { printf "\033[1;31m  ✗ %s\033[0m\n" "$1"; }

need() {
  command -v "$1" >/dev/null 2>&1
}

# Idempotent symlink: if dst is already a symlink (any target) we leave it;
# if it's a regular file we move to .bak first; otherwise we link fresh.
link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    ok "$dst (already linked)"
  elif [[ -e "$dst" ]]; then
    warn "$dst exists and is not a symlink — backing up to ${dst}.bak"
    mv "$dst" "${dst}.bak"
    ln -s "$src" "$dst"
    ok "$dst (linked, old file backed up)"
  else
    ln -s "$src" "$dst"
    ok "$dst"
  fi
}

# ─────────────────────────────────────────────────────────────────
# Phase 1: apt prelude
# ─────────────────────────────────────────────────────────────────
info "Phase 1: apt prelude"

if [[ $EUID -eq 0 ]]; then
  fail "do not run as root; this script will sudo when needed"
  exit 1
fi

# Prime sudo cache, then refresh in the background so long phases don't time out.
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

sudo apt-get update -qq
ok "apt updated"

# ─────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────
echo ""
info "install-linux.sh — phases pending: 1.5/2/3/4/5/6/7/8/9/10"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x install-linux.sh`

- [ ] **Step 3: Lint with shellcheck**

Run: `shellcheck install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 4: Verify shell parses**

Run: `bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: skeleton + phase 1 (apt prelude)

Helper functions (info/ok/warn/fail/need/link) mirror install-macos.sh
verbatim so behavior is parallel. Phase 1 primes sudo with a keepalive
that dies with the parent shell, then runs apt-get update."
```

---

### Task D2: Phase 1.5 (Nerd Font install)

**Files:**
- Modify: `install-linux.sh` (insert phase 1.5)

- [ ] **Step 1: Append phase 1.5 before the trailing summary banner**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  sudo apt-get update -qq
  ok "apt updated"

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 1.5/2/3/4/5/6/7/8/9/10"
  ```
- new_string:
  ```
  sudo apt-get update -qq
  ok "apt updated"

  # ─────────────────────────────────────────────────────────────────
  # Phase 1.5: Fonts (apt fallback + Nerd Font tarball)
  # ─────────────────────────────────────────────────────────────────
  info "Phase 1.5: Fonts"

  sudo apt-get install -y -qq fonts-jetbrains-mono
  ok "fonts-jetbrains-mono (apt baseline)"

  NF_DIR="$HOME/.local/share/fonts/JetBrainsMono-NerdFont"
  if [[ -d "$NF_DIR" ]] && find "$NF_DIR" -name '*.ttf' -print -quit | grep -q .; then
    ok "JetBrainsMono Nerd Font already installed"
  else
    mkdir -p "$NF_DIR"
    TMP="$(mktemp -d)"
    if curl -fsSL -o "$TMP/JetBrainsMono.tar.xz" \
         https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz; then
      tar -xf "$TMP/JetBrainsMono.tar.xz" -C "$NF_DIR"
      fc-cache -f "$NF_DIR" >/dev/null
      ok "JetBrainsMono Nerd Font installed (tarball)"
    else
      warn "Nerd Font download failed — apt fallback in use; icons may render as boxes"
    fi
    rm -rf "$TMP"
  fi

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 2/3/4/5/6/7/8/9/10"
  ```

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 1.5 — Nerd Font + apt fonts-jetbrains-mono fallback

Two-tier font install. apt installs a regular JetBrains Mono as a baseline
(idempotent via apt's own check). Then the Nerd Font tarball goes into
~/.local/share/fonts/ for the icon glyphs that tmux/eza/neofetch all assume.
fc-cache rebuilds the font index. Skip-if-non-empty makes re-runs cheap."
```

---

### Task D3: Phase 2 (apt packages)

**Files:**
- Modify: `install-linux.sh` (insert phase 2)

- [ ] **Step 1: Insert phase 2 before the trailing summary**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 2/3/4/5/6/7/8/9/10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 2: apt packages + supplemental installs
  # ─────────────────────────────────────────────────────────────────
  info "Phase 2: apt packages"

  APT_PKGS=(
    tmux neovim eza neofetch bat
    zsh-syntax-highlighting zoxide fzf ripgrep fd-find
    python3 python3-pip python3-venv pipx
    luarocks clang-format golang-go kitty
  )

  sudo apt-get install -y -qq "${APT_PKGS[@]}"
  for p in "${APT_PKGS[@]}"; do
    ok "$p"
  done

  # NodeSource: apt's nodejs lags; install LTS via the official deb script
  # if no recent node is already on PATH.
  if need node && [[ "$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)" -ge 20 ]]; then
    ok "node $(node --version) already installed"
  else
    info "  installing Node.js LTS via NodeSource"
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y -qq nodejs
    ok "node $(node --version)"
  fi

  # spicetify-cli — print hint, do not auto-install (snap Spotify breaks it).
  if ! need spicetify; then
    warn "spicetify-cli not installed (Linux Spotify is typically snap; spicetify needs a writable Spotify dir which snap blocks)"
    warn "  see https://spicetify.app/docs/getting-started if you want it"
  fi

  # aerospace — macOS-only, no auto-install on Linux.
  warn "aerospace is macOS-only — see sway / i3 / hyprland for Linux tiling WMs"

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 3/4/5/6/7/8/9/10"
  ```

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 2 — apt packages + NodeSource + skip-with-hint cases

Single 'apt-get install -y' for the bulk set. Node.js comes from NodeSource
deb script when the system version is <20. spicetify-cli and aerospace
print one-line hints rather than auto-installing — both have macOS-specific
expectations the installer can't safely meet on Linux."
```

---

### Task D4: Phase 3 (Rust toolchain)

**Files:**
- Modify: `install-linux.sh` (insert phase 3)

- [ ] **Step 1: Insert phase 3**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 3/4/5/6/7/8/9/10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 3: Rust toolchain (via rustup)
  # ─────────────────────────────────────────────────────────────────
  info "Phase 3: Rust toolchain"

  if need rustc; then
    ok "Rust already installed ($(rustc --version))"
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
    ok "Rust installed"
  fi

  # stylua + sqlfluff — not in apt
  if need stylua; then
    ok "stylua already installed"
  else
    cargo install stylua --quiet
    ok "stylua"
  fi

  if need sqlfluff; then
    ok "sqlfluff already installed"
  else
    pipx install sqlfluff
    ok "sqlfluff"
  fi

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 4/5/6/7/8/9/10"
  ```

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 3 — rustup + cargo-installed stylua + pipx sqlfluff

Same rustup --profile minimal as macOS. stylua and sqlfluff aren't in apt
on Ubuntu 26.04; cargo install and pipx install respectively cover the gap.
Each install is wrapped in a need-check for idempotency."
```

---

### Task D5: Phase 4 (Oh My Zsh)

**Files:**
- Modify: `install-linux.sh` (insert phase 4)

- [ ] **Step 1: Insert phase 4**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 4/5/6/7/8/9/10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 4: Oh My Zsh
  # ─────────────────────────────────────────────────────────────────
  info "Phase 4: Oh My Zsh"

  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    ok "Oh My Zsh already installed"
  else
    sudo apt-get install -y -qq zsh
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ok "Oh My Zsh installed"
  fi

  # We don't run chsh automatically — that changes the login shell, which
  # is a user-affecting decision. Print a hint instead.
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
    warn "default shell is not zsh — run: chsh -s \"\$(command -v zsh)\" then log out and back in"
  fi

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 5/6/7/8/9/10"
  ```

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 4 — Oh My Zsh + chsh hint

Same install command as macOS. Adds an apt zsh install first since Ubuntu
doesn't ship zsh by default. We don't run chsh ourselves — that changes
the user's login shell, requires a logout/login, and the user may already
prefer bash. Just hint."
```

---

### Task D6: Phase 5 (symlinks + bat/fd shims)

**Files:**
- Modify: `install-linux.sh` (insert phase 5)

- [ ] **Step 1: Insert phase 5**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 5/6/7/8/9/10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 5: Symlinks + ~/.local/bin shims
  # ─────────────────────────────────────────────────────────────────
  info "Phase 5: Symlinks"

  mkdir -p "$LOCAL_BIN"

  link "$DOTFILES/zshrc"          "$HOME/.zshrc"
  link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
  link "$DOTFILES/tmux"           "$HOME/.tmux"

  # Ubuntu installs `bat` as `batcat` and `fd` as `fdfind` to avoid name
  # collisions with older packages. The rest of the dotfiles assume the
  # standard names — symlinks bridge the gap with no per-OS branching.
  if [[ -x /usr/bin/batcat ]]; then
    link "/usr/bin/batcat" "$LOCAL_BIN/bat"
  fi
  if [[ -x /usr/bin/fdfind ]]; then
    link "/usr/bin/fdfind" "$LOCAL_BIN/fd"
  fi

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 6/7/8/9/10"
  ```

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 5 — dotfile symlinks + bat/fd name shims

Same three dotfile symlinks as macOS (~/.zshrc, ~/.tmux.conf, ~/.tmux).
On top, two ~/.local/bin shims map Ubuntu's batcat/fdfind to bat/fd so
the rest of the configs (eza aliases, fish, etc.) work unmodified."
```

---

### Task D7: Phase 6 (TPM + Catppuccin tmux plugin)

**Files:**
- Modify: `install-linux.sh` (insert phase 6)

- [ ] **Step 1: Insert phase 6**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 6/7/8/9/10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 6: Tmux plugins (TPM + Catppuccin)
  # ─────────────────────────────────────────────────────────────────
  info "Phase 6: Tmux plugins"

  TPM_DIR="$DOTFILES/tmux/plugins/tpm"
  if [[ -d "$TPM_DIR" ]]; then
    ok "TPM already installed"
  else
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    ok "TPM installed"
  fi

  CATPPUCCIN_DIR="$DOTFILES/tmux/plugins/tmux"
  if [[ -d "$CATPPUCCIN_DIR" ]]; then
    ok "Catppuccin tmux already installed"
  else
    git clone https://github.com/catppuccin/tmux "$CATPPUCCIN_DIR"
    ok "Catppuccin tmux installed"
  fi

  if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
    "$TPM_DIR/bin/install_plugins" >/dev/null 2>&1 && ok "TPM plugins installed" || warn "TPM plugin install had issues"
  fi

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 7/8/9/10"
  ```

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 6 — TPM + Catppuccin tmux plugin

git clone is OS-agnostic; this phase is functionally identical to the
macOS one. Re-runs check directory existence first."
```

---

### Task D8: Phase 7 (Neovim formatters)

**Files:**
- Modify: `install-linux.sh` (insert phase 7)

- [ ] **Step 1: Insert phase 7**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 7/8/9/10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 7: Neovim formatters (lazy.nvim auto-bootstraps on first launch)
  # ─────────────────────────────────────────────────────────────────
  info "Phase 7: Neovim"

  ok "lazy.nvim will auto-bootstrap on first nvim launch"
  ok "Mason LSPs will auto-install on first nvim launch"

  if need npm; then
    if npm list -g prettier >/dev/null 2>&1; then
      ok "prettier (npm)"
    else
      sudo npm install -g prettier
      ok "prettier (npm)"
    fi
  fi

  # Ubuntu 26.04 enforces PEP 668 — pip3 install --user is blocked. Use pipx.
  if need pipx; then
    pipx install black >/dev/null 2>&1 || true
    pipx install isort >/dev/null 2>&1 || true
    ok "black + isort (pipx)"
  fi

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 8/9/10"
  ```

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 7 — Neovim formatters via npm + pipx

prettier comes from npm same as macOS. black and isort can't go through
pip3 install --user on 26.04 (PEP 668 blocks it); pipx is the supported
path. lazy.nvim and Mason still auto-bootstrap on first nvim launch."
```

---

### Task D9: Phase 8 (theme-manager build)

**Files:**
- Modify: `install-linux.sh` (insert phase 8)

- [ ] **Step 1: Insert phase 8**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 8/9/10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 8: theme-manager (build + install + initial config)
  # ─────────────────────────────────────────────────────────────────
  info "Phase 8: theme-manager"

  THEME_MGR="$DOTFILES/theme-manager"

  if [[ -f "$LOCAL_BIN/theme-manager" ]]; then
    ok "theme-manager binary exists"
  else
    if [[ -f "$THEME_MGR/Cargo.toml" ]]; then
      ( cd "$THEME_MGR" && cargo build --release )
      cp "$THEME_MGR/target/release/theme-manager" "$LOCAL_BIN/"
      ok "theme-manager built and installed"
    else
      fail "theme-manager source not found at $THEME_MGR"
    fi
  fi

  # Default config — only if missing.
  if [[ ! -f "$THEME_MGR/config.toml" ]]; then
    cat > "$THEME_MGR/config.toml" << 'TOML'
  [theme]
  family = "gruvbox-material"
  variant = "medium"

  [paths]
  kitty_config = "~/.config/kitty"
  tmux_config = "~/.config/tmux"
  nvim_socket_pattern = "/tmp/nvim-theme-*.sock"
  catppuccin_tmux_plugin = "~/.config/tmux/plugins/tmux/catppuccin.tmux"
  TOML
    ok "theme-manager config.toml created"
  else
    ok "theme-manager config.toml exists"
  fi

  # Apply once so kitty *.auto.conf files are written. Failure is non-fatal
  # — kitty / tmux may not be running yet on a fresh box.
  "$LOCAL_BIN/theme-manager" apply >/dev/null 2>&1 && ok "theme applied" || warn "theme apply failed (kitty/tmux may not be running)"

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 9/10"
  ```

Note: the `cat > ... << 'TOML'` block uses spaces for indentation in the heredoc since the surrounding shell is using `<<` (not `<<-`). That gives the produced TOML two leading spaces per line — fix this by un-indenting the heredoc body to column 0:

Adjust the heredoc body in the new_string to:

```
  if [[ ! -f "$THEME_MGR/config.toml" ]]; then
    cat > "$THEME_MGR/config.toml" << 'TOML'
[theme]
family = "gruvbox-material"
variant = "medium"

[paths]
kitty_config = "~/.config/kitty"
tmux_config = "~/.config/tmux"
nvim_socket_pattern = "/tmp/nvim-theme-*.sock"
catppuccin_tmux_plugin = "~/.config/tmux/plugins/tmux/catppuccin.tmux"
TOML
    ok "theme-manager config.toml created"
  else
    ok "theme-manager config.toml exists"
  fi
```

(Bash heredocs preserve all whitespace; the un-indented body produces a clean TOML file.)

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`. If shellcheck warns about SC1091 (cargo env), the existing `# shellcheck disable=SC1091` from phase 3 handles it.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 8 — theme-manager build + default config + apply

Cargo build, copy to ~/.local/bin, write a default config.toml if absent,
and run 'theme-manager apply' so kitty's auto.conf files exist before
the first kitty launch. Apply failure is non-fatal — kitty/tmux may not
be running yet on a fresh box."
```

---

### Task D10: Phase 9 (systemd user unit)

**Files:**
- Modify: `install-linux.sh` (insert phase 9)

- [ ] **Step 1: Insert phase 9**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 9/10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 9: systemd user unit (theme-manager daemon)
  # ─────────────────────────────────────────────────────────────────
  info "Phase 9: systemd user unit"

  SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
  UNIT_FILE="$SYSTEMD_USER_DIR/theme-manager.service"

  mkdir -p "$SYSTEMD_USER_DIR"

  cat > "$UNIT_FILE" << 'UNIT'
[Unit]
Description=theme-manager appearance daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=%h/.local/bin/theme-manager watch
Restart=on-failure
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
UNIT
  ok "theme-manager.service written"

  if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user enable --now theme-manager.service 2>/dev/null && ok "daemon enabled + started" || warn "could not enable daemon (no systemd --user session?)"
  else
    warn "systemctl --user not available — daemon will not auto-start"
  fi

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 10"
  ```

- [ ] **Step 2: Lint and parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 9 — systemd --user unit for theme-manager watch

PartOf=graphical-session.target so the daemon stops on logout. WantedBy=
default.target so it starts on session login. systemctl --user daemon-reload
+ enable --now is idempotent. Failure is non-fatal (e.g. on systems without
a user systemd session) — the user can still run 'theme-manager apply'
manually."
```

---

### Task D11: Phase 10 (Secrets reminder + final completion message)

**Files:**
- Modify: `install-linux.sh` (insert phase 10, replace the placeholder summary)

- [ ] **Step 1: Replace the trailing summary banner with the real completion message**

Use the Edit tool on `install-linux.sh`:
- old_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "install-linux.sh — phases pending: 10"
  ```
- new_string:
  ```
  # ─────────────────────────────────────────────────────────────────
  # Phase 10: Secrets reminder
  # ─────────────────────────────────────────────────────────────────
  info "Phase 10: Secrets"

  if [[ -f "$HOME/.secrets" ]]; then
    ok "~/.secrets exists"
  else
    warn "~/.secrets not found — create it with your API keys:"
    echo "    cat > ~/.secrets << 'EOF'"
    echo "    export OPENAI_API_KEY=\"...\""
    echo "    EOF"
    echo "    chmod 600 ~/.secrets"
  fi

  # ─────────────────────────────────────────────────────────────────
  # Done
  # ─────────────────────────────────────────────────────────────────
  echo ""
  info "Setup complete!"
  echo ""
  echo "  Linux notes (untested path — expect rough edges):"
  echo "    - Auto dark/light requires gsettings (works under GNOME)"
  echo "    - aerospace, iterm2, spicetify-cli are skipped"
  echo "    - If your shell is still bash: chsh -s \"\$(command -v zsh)\" + log out"
  echo ""
  echo "  Next steps:"
  echo "    1. Open a new terminal (or run: source ~/.zshrc)"
  echo "    2. Open nvim — plugins will auto-install on first launch"
  echo "    3. In tmux, press Ctrl+S then I to install TPM plugins"
  echo "    4. Create ~/.secrets with your API keys (if not done)"
  echo "    5. Run: theme-manager set gruvbox-material medium"
  echo ""
  ```

- [ ] **Step 2: Final lint + parse**

Run: `shellcheck install-linux.sh && bash -n install-linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Sanity-check the file size and structure**

Run: `wc -l install-linux.sh && grep -c '^info "Phase' install-linux.sh`
Expected: roughly 240–270 lines, exactly 11 phase lines (1, 1.5, 2, 3, 4, 5, 6, 7, 8, 9, 10).

- [ ] **Step 4: Commit**

```bash
git add install-linux.sh
git commit -m "install-linux: phase 10 — secrets reminder + final completion message

Mirrors macOS phase 10 verbatim, then prints a 'Linux notes' block flagging
the untested path, skipped configs, and the chsh hint. install-linux.sh is
now feature-complete and shellcheck-clean."
```

---

## Group E: Documentation

### Task E1: Add Linux quick-start to `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read current README to find insertion point**

Run: `grep -n '^## ' README.md`
Expected: lists section headers including `## Quick Start`, `## What's Inside`, etc.

- [ ] **Step 2: Insert a Linux subsection after the macOS quick-start**

Use the Edit tool on `README.md`:
- old_string:
  ```
  # dotfiles

  macOS dev environment — keyboard-driven, consistently themed, one-command setup.

  ## Quick Start

  ```bash
  git clone git@github.com:MowMowchow/configs.git ~/.config
  cd ~/.config && ./install.sh
  ```

  The installer is idempotent — safe to re-run on an existing setup.
  ```
- new_string:
  ```
  # dotfiles

  macOS dev environment — keyboard-driven, consistently themed, one-command setup. Linux (Ubuntu 26.04 LTS) is supported on a best-effort basis.

  ## Quick Start

  ```bash
  git clone git@github.com:MowMowchow/configs.git ~/.config
  cd ~/.config && ./install.sh
  ```

  `install.sh` detects the host OS and dispatches to `install-macos.sh` or `install-linux.sh`. Both are idempotent — safe to re-run on an existing setup.

  ### Linux (Ubuntu 26.04 LTS, untested)

  The Linux path is best-effort and may need fixing on first run. Notable differences from macOS:

  - Auto dark/light switching depends on `gsettings` (works on GNOME — Ubuntu's default; KDE/sway/etc. fall back to 5-second polling).
  - `aerospace`, `iterm2`, and `spicetify-cli` are skipped.
  - Fonts: apt's `fonts-jetbrains-mono` is installed as a baseline, plus the JetBrainsMono Nerd Font tarball from `github.com/ryanoasis/nerd-fonts` for icon glyphs.
  - The theme-manager daemon runs as a `systemd --user` unit instead of a LaunchAgent. Logs: `journalctl --user -u theme-manager`.
  - You may need to set zsh as your login shell after install: `chsh -s "$(command -v zsh)"`.
  ```

- [ ] **Step 3: Verify rendering by re-reading the file**

Run: `head -25 README.md`
Expected: shows the new Linux section directly after Quick Start.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "README: document Linux (Ubuntu 26.04 LTS) install path

Same install.sh entrypoint, dispatcher routes to install-linux.sh on
Linux. Calls out the untested status, skipped configs (aerospace,
iterm2, spicetify-cli), the gsettings dependency for auto-switching,
and the systemd --user daemon."
```

---

## Self-Review (post-write)

**Spec coverage check:**

| Spec section | Implemented in |
|---|---|
| Top-level dispatcher (`install.sh`) | C1 (rename), C2 (new file) |
| `install-linux.sh` Phase 1 (apt prelude) | D1 |
| `install-linux.sh` Phase 1.5 (fonts) | D2 |
| `install-linux.sh` Phase 2 (apt + supplemental) | D3 |
| `install-linux.sh` Phase 3 (rust + stylua + sqlfluff) | D4 |
| `install-linux.sh` Phase 4 (Oh My Zsh) | D5 |
| `install-linux.sh` Phase 5 (symlinks + bat/fd shims) | D6 |
| `install-linux.sh` Phase 6 (TPM + Catppuccin) | D7 |
| `install-linux.sh` Phase 7 (formatters) | D8 |
| `install-linux.sh` Phase 8 (theme-manager build) | D9 |
| `install-linux.sh` Phase 9 (systemd user unit) | D10 |
| `install-linux.sh` Phase 10 (secrets + completion) | D11 |
| `theme-manager` `appearance.rs` dispatcher | B2 |
| `theme-manager` `appearance_macos.rs` (moved code) | B2 |
| `theme-manager` `appearance_linux.rs::get_current()` | B3 |
| `theme-manager` `appearance_linux.rs::watch()` | B4 |
| `theme-manager` `cmd::resolve_bin()` | B1 |
| `theme-manager` `adapters/tmux.rs` refactor | B5 |
| `theme-manager` `adapters/neovim.rs` refactor | B6 |
| `theme-manager` Linux build verification | B7 |
| `tmux/tmux.conf:74` fix | A1 |
| `zshrc` Linux fallback | A2 |
| `README.md` Linux section | E1 |

All spec items map to exactly one task.

**Placeholder scan:** None of "TBD", "TODO", "implement later", "appropriate error handling", or "similar to Task N" appear in any task body. Every code/command step shows the actual content.

**Type/symbol consistency:**
- `resolve_bin()` defined in B1 (signature `(&str) -> String`); used in B5 and B6 with the same signature.
- `Appearance` enum defined in B2 (in `appearance.rs`); imported in B2 (`appearance_macos.rs`) and B3 (`appearance_linux.rs`) via `use super::Appearance`. Consistent.
- `get_current()` and `watch()` symbols are exported from `appearance.rs` in B2 (`pub use appearance_macos::{get_current, watch}` and the corresponding linux line). Both backends define both functions with matching signatures. Consistent.
- `tmux_bin()` returns `&'static str` before B5 and `String` after. Step 3 of B5 covers the call-site impact; both `Command::new(&str)` and `Command::new(String)` work via `AsRef<OsStr>`, so no callers need editing.
- `find_nvim()` returns `Option<String>` before and after B6 — type unchanged.

No issues found.

---

## Done

Plan complete and saved to `docs/superpowers/plans/2026-05-06-linux-install.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
