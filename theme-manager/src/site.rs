//! Site plugin discovery and invocation.
//!
//! A site plugin carries employer- or network-specific behaviour that must not
//! live in this repository. The seam is a process boundary: we exec a hook and
//! read its exit status. Nothing from a plugin is linked, imported or parsed as
//! code, so a plugin can live in a separate private repository and be developed
//! without touching this project.
//!
//! See `site/README.md` for the contract this implements.

use crate::appearance::Appearance;
use crate::cmd::run_with_timeout;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

/// Contract version this core speaks. A plugin declaring anything else is
/// skipped loudly rather than half-supported.
pub const API_VERSION: u32 = 1;

/// Hooks run on the interactive theme-switch path, so the budget is tight.
/// A plugin needing longer must background its own work.
const HOOK_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug)]
pub struct Plugin {
    pub name: String,
    pub dir: PathBuf,
}

/// Reject anything writable by other users. The hook runs with our privileges,
/// so this is accident-prevention (a stray chmod, a shared directory), not a
/// sandbox. Nothing here defends against a plugin you installed yourself.
#[cfg(unix)]
fn is_safe(path: &Path) -> Result<(), String> {
    use std::os::unix::fs::MetadataExt;
    let md = std::fs::metadata(path).map_err(|e| format!("stat {}: {}", path.display(), e))?;
    let uid = unsafe { libc_getuid() };
    if md.uid() != uid {
        return Err(format!("{} is not owned by uid {}", path.display(), uid));
    }
    if md.mode() & 0o022 != 0 {
        return Err(format!(
            "{} is group- or world-writable (mode {:o})",
            path.display(),
            md.mode() & 0o7777
        ));
    }
    Ok(())
}

#[cfg(unix)]
extern "C" {
    #[link_name = "getuid"]
    fn libc_getuid() -> u32;
}

#[cfg(not(unix))]
fn is_safe(_path: &Path) -> Result<(), String> {
    Ok(())
}

/// Read `api_version` out of a plugin.toml without a TOML dependency on the
/// hot path — the file is three lines and we only need one integer.
fn declared_api_version(manifest: &Path) -> Option<u32> {
    let text = std::fs::read_to_string(manifest).ok()?;
    for line in text.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("api_version") {
            let rest = rest.trim_start().strip_prefix('=')?;
            return rest.trim().parse().ok();
        }
    }
    None
}

/// Find usable plugins under `<config_root>/site/*/`, in lexical order.
pub fn discover(config_root: &Path) -> Vec<Plugin> {
    let site_dir = config_root.join("site");
    let Ok(entries) = std::fs::read_dir(&site_dir) else {
        return Vec::new();
    };

    let mut dirs: Vec<PathBuf> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();
    dirs.sort();

    let mut plugins = Vec::new();
    for dir in dirs {
        let manifest = dir.join("plugin.toml");
        if !manifest.is_file() {
            continue; // not a plugin — e.g. the tracked example, or scratch
        }
        let name = dir
            .file_name()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_else(|| dir.display().to_string());

        match declared_api_version(&manifest) {
            Some(v) if v == API_VERSION => {}
            Some(v) => {
                eprintln!(
                    "[theme-manager] site '{}' declares api_version {} but this core speaks {} — skipping",
                    name, v, API_VERSION
                );
                continue;
            }
            None => {
                eprintln!(
                    "[theme-manager] site '{}' has no api_version in plugin.toml — skipping",
                    name
                );
                continue;
            }
        }

        if let Err(e) = is_safe(&dir) {
            eprintln!("[theme-manager] site '{}' skipped: {}", name, e);
            continue;
        }

        plugins.push(Plugin { name, dir });
    }
    plugins
}

/// Run every plugin's `theme-hook`. Bulkheaded: one plugin's failure neither
/// stops the others nor fails the overall apply, exactly like an adapter.
pub fn run_theme_hooks(
    config_root: &Path,
    appearance: Appearance,
    family: &str,
    variant: &str,
    conf: &Path,
) -> Vec<(String, Result<(), String>)> {
    let mut results = Vec::new();

    for plugin in discover(config_root) {
        let hook = plugin.dir.join("theme-hook");
        if !hook.is_file() {
            continue; // plugins need not implement every hook
        }
        if let Err(e) = is_safe(&hook) {
            results.push((plugin.name, Err(e)));
            continue;
        }

        let mut cmd = Command::new(&hook);
        cmd.arg(appearance.to_string())
            .arg(family)
            .arg(variant)
            .env("THEME_MANAGER_API", API_VERSION.to_string())
            .env("THEME_MANAGER_CONF", conf)
            .env("THEME_MANAGER_DIR", config_root);

        let outcome = match run_with_timeout(cmd, HOOK_TIMEOUT) {
            Ok(out) if out.status.success() => Ok(()),
            Ok(out) => Err(format!(
                "exit {}: {}",
                out.status.code().unwrap_or(-1),
                String::from_utf8_lossy(&out.stderr).trim()
            )),
            Err(e) => Err(e),
        };
        results.push((plugin.name, outcome));
    }

    results
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tmpdir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("tm-site-{}-{}", tag, std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn make_plugin(root: &Path, name: &str, api: &str) -> PathBuf {
        let dir = root.join("site").join(name);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("plugin.toml"), format!("api_version = {}\n", api)).unwrap();
        dir
    }

    #[test]
    fn discovers_only_valid_plugins() {
        let root = tmpdir("discover");
        make_plugin(&root, "good", "1");
        make_plugin(&root, "future", "99");
        // A directory with no manifest is not a plugin.
        fs::create_dir_all(root.join("site").join("notaplugin")).unwrap();

        let names: Vec<String> = discover(&root).into_iter().map(|p| p.name).collect();
        assert_eq!(names, vec!["good"]);
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn missing_site_dir_is_not_an_error() {
        let root = tmpdir("empty");
        assert!(discover(&root).is_empty());
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn hook_receives_arguments_and_environment() {
        let root = tmpdir("hookargs");
        let dir = make_plugin(&root, "probe", "1");
        let out_file = root.join("out.txt");
        fs::write(
            dir.join("theme-hook"),
            format!(
                "#!/bin/sh\nprintf '%s %s %s %s' \"$1\" \"$2\" \"$3\" \"$THEME_MANAGER_API\" > {}\n",
                out_file.display()
            ),
        )
        .unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(dir.join("theme-hook"), fs::Permissions::from_mode(0o755)).unwrap();
        }

        let results = run_theme_hooks(
            &root,
            Appearance::Light,
            "gruvbox-material",
            "medium",
            Path::new("/tmp/x.conf"),
        );
        assert_eq!(results.len(), 1);
        assert!(results[0].1.is_ok(), "hook failed: {:?}", results[0].1);
        assert_eq!(
            fs::read_to_string(&out_file).unwrap(),
            "light gruvbox-material medium 1"
        );
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_failing_hook_is_reported_but_contained() {
        let root = tmpdir("hookfail");
        let dir = make_plugin(&root, "bad", "1");
        fs::write(dir.join("theme-hook"), "#!/bin/sh\necho boom >&2\nexit 3\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(dir.join("theme-hook"), fs::Permissions::from_mode(0o755)).unwrap();
        }

        let results =
            run_theme_hooks(&root, Appearance::Dark, "gruvbox", "hard", Path::new("/tmp/x"));
        assert_eq!(results.len(), 1);
        let err = results[0].1.as_ref().unwrap_err();
        assert!(err.contains("exit 3"), "unexpected: {}", err);
        assert!(err.contains("boom"), "stderr not captured: {}", err);
        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn a_hanging_hook_is_killed_at_the_deadline() {
        let root = tmpdir("hookhang");
        let dir = make_plugin(&root, "slow", "1");
        fs::write(dir.join("theme-hook"), "#!/bin/sh\nsleep 30\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(dir.join("theme-hook"), fs::Permissions::from_mode(0o755)).unwrap();
        }

        let start = std::time::Instant::now();
        let results =
            run_theme_hooks(&root, Appearance::Dark, "gruvbox", "hard", Path::new("/tmp/x"));
        let elapsed = start.elapsed();

        assert!(results[0].1.is_err());
        assert!(
            elapsed < HOOK_TIMEOUT + Duration::from_secs(2),
            "hook was not bounded: {:?}",
            elapsed
        );
        fs::remove_dir_all(&root).ok();
    }
}
