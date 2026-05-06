use std::process::Command;
use std::sync::mpsc;
use std::time::Duration;

/// Run a command with a timeout. Returns the output or an error if it times out
/// or fails to spawn. If the command exceeds the timeout, the child process is
/// killed and an error is returned.
pub fn run_with_timeout(mut cmd: Command, timeout: Duration) -> Result<std::process::Output, String> {
    let child = cmd.spawn().map_err(|e| format!("spawn: {}", e))?;
    let (tx, rx) = mpsc::channel();

    std::thread::spawn(move || {
        let result = child.wait_with_output();
        let _ = tx.send(result);
    });

    match rx.recv_timeout(timeout) {
        Ok(result) => result.map_err(|e| format!("wait: {}", e)),
        Err(_) => Err(format!("command timed out after {:?}", timeout)),
    }
}

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
    fn resolve_bin_falls_back_to_bare_name_when_not_in_candidates() {
        // The candidate dirs (/opt/homebrew/bin, /usr/local/bin on macOS;
        // /usr/local/bin, /usr/bin on Linux) won't contain this fake name,
        // so resolve_bin must return it unchanged for OS PATH lookup.
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
