use std::io::Read;
use std::process::{Command, Output, Stdio};
use std::time::{Duration, Instant};

/// How often to check whether the child has exited. These commands finish in
/// single-digit milliseconds, so this bounds added latency, not cost.
const POLL_INTERVAL: Duration = Duration::from_millis(1);

/// Run a command with a timeout, capturing its output.
///
/// On timeout the child is killed and reaped, so a hung target cannot leave an
/// orphan process behind. stdout/stderr are piped rather than inherited for two
/// reasons: callers format `output.stderr` into their error messages, and
/// inherited output would otherwise land in the daemon's log.
///
/// Ownership note: the child is waited on *here* rather than in a helper
/// thread. A thread calling `wait_with_output()` would have to own the `Child`,
/// which is precisely what would make it unkillable from this side.
pub fn run_with_timeout(mut cmd: Command, timeout: Duration) -> Result<Output, String> {
    cmd.stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let mut child = cmd.spawn().map_err(|e| format!("spawn: {}", e))?;

    // Drain both pipes concurrently. A child that fills a pipe buffer while we
    // are waiting would otherwise block forever and always hit the timeout.
    let mut stdout_pipe = child.stdout.take().expect("stdout was piped");
    let mut stderr_pipe = child.stderr.take().expect("stderr was piped");
    let stdout_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = stdout_pipe.read_to_end(&mut buf);
        buf
    });
    let stderr_reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = stderr_pipe.read_to_end(&mut buf);
        buf
    });

    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {
                if Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait(); // reap; without this we leave a zombie
                    return Err(format!("timed out after {:?} (child killed)", timeout));
                }
                std::thread::sleep(POLL_INTERVAL);
            }
            Err(e) => return Err(format!("wait: {}", e)),
        }
    };

    // The child has exited, so both pipes are at EOF and these joins are prompt.
    let stdout = stdout_reader.join().unwrap_or_default();
    let stderr = stderr_reader.join().unwrap_or_default();

    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

/// Resolve a binary to an absolute path, preferring the locations a package
/// manager uses on this platform.
///
/// The daemon runs under launchd (or systemd) with a minimal PATH that does
/// not include /opt/homebrew/bin, so a bare name would not resolve. Falls back
/// to the bare name so the OS can still do a normal PATH lookup.
pub fn resolve_bin(name: &str) -> String {
    let candidates: &[&str] = if cfg!(target_os = "macos") {
        &["/opt/homebrew/bin", "/usr/local/bin"]
    } else {
        // ~/.local/bin first: the Linux installer puts newer kitty/sapling
        // shims there deliberately to override older system copies.
        &["/usr/local/bin", "/usr/bin", "/snap/bin"]
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
    fn resolve_bin_falls_back_to_the_bare_name() {
        // Not in any candidate dir, so it must come back unchanged for the OS
        // to resolve via PATH.
        assert_eq!(
            resolve_bin("definitely-not-a-real-binary-xyz"),
            "definitely-not-a-real-binary-xyz"
        );
    }

    #[test]
    fn resolve_bin_returns_something_usable_for_a_real_binary() {
        // `ls` lives in different places per platform, and on macOS /usr/bin
        // is not a candidate, so assert the shape rather than an exact path.
        let r = resolve_bin("ls");
        assert!(!r.is_empty());
        assert!(r == "ls" || r.starts_with('/'), "unexpected: {}", r);
    }

    #[test]
    fn captures_stdout_and_stderr() {
        let mut cmd = Command::new("sh");
        cmd.args(["-c", "printf out; printf err >&2; exit 3"]);
        let out = run_with_timeout(cmd, Duration::from_secs(5)).expect("should complete");
        assert_eq!(out.stdout, b"out");
        assert_eq!(out.stderr, b"err");
        assert_eq!(out.status.code(), Some(3));
    }

    #[test]
    fn times_out_and_kills_the_child() {
        let marker = std::env::temp_dir()
            .join(format!("theme-manager-timeout-test-{}", std::process::id()));
        let _ = std::fs::remove_file(&marker);

        let mut cmd = Command::new("sh");
        cmd.args(["-c", &format!("sleep 2; touch {}", marker.to_string_lossy())]);
        let err =
            run_with_timeout(cmd, Duration::from_millis(100)).expect_err("should time out");
        assert!(err.contains("timed out"), "unexpected error: {}", err);

        // If the child survived the timeout it would go on to create the marker.
        std::thread::sleep(Duration::from_millis(2500));
        assert!(
            !marker.exists(),
            "child outlived the timeout and ran to completion"
        );
    }

    #[test]
    fn survives_a_child_that_writes_more_than_a_pipe_buffer() {
        let mut cmd = Command::new("sh");
        cmd.args(["-c", "yes 0123456789 | head -c 500000"]);
        let out = run_with_timeout(cmd, Duration::from_secs(10)).expect("should not deadlock");
        assert_eq!(out.stdout.len(), 500_000);
    }
}
