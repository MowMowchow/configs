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
