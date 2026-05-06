use crate::appearance::Appearance;
use crate::cmd::run_with_timeout;
use crate::config::PathsConfig;
use crate::theme::{CatppuccinFlavor, Contrast, ThemeFamily};
use std::process::Command;
use std::time::Duration;

const NVIM_TIMEOUT: Duration = Duration::from_secs(3);

/// Apply theme to all running neovim instances via remote sockets.
///
/// Sends a sequence of key commands to each nvim instance:
///   1. Set background (dark/light)
///   2. Configure family-specific options (contrast, flavor, etc.)
///   3. Apply the colorscheme
///
/// Idempotent: safe to call repeatedly with the same arguments.
pub fn apply(
    family: ThemeFamily,
    variant: &str,
    appearance: Appearance,
    paths: &PathsConfig,
) -> Result<(), String> {
    let nvim_bin = match find_nvim() {
        Some(bin) => bin,
        None => return Ok(()), // nvim not installed, skip silently
    };

    let bg = match appearance {
        Appearance::Dark => "dark",
        Appearance::Light => "light",
    };

    let mut cmd = format!("<Cmd>set background={}<CR>", bg);

    let colorscheme = match family {
        ThemeFamily::Gruvbox => {
            let contrast = Contrast::parse(variant);
            let contrast_str = match contrast {
                Contrast::Hard => "hard",
                Contrast::Medium => "",
                Contrast::Soft => "soft",
            };
            cmd += &format!(
                "<Cmd>lua require('gruvbox').setup({{contrast='{}'}})<CR>",
                contrast_str
            );
            "gruvbox"
        }
        ThemeFamily::GruvboxMaterial => {
            let contrast = Contrast::parse(variant);
            cmd += &format!(
                "<Cmd>let g:gruvbox_material_background='{}'<CR>",
                contrast
            );
            "gruvbox-material"
        }
        ThemeFamily::Catppuccin => {
            let flavor = CatppuccinFlavor::for_appearance(variant, appearance);
            flavor.nvim_colorscheme()
        }
    };

    cmd += &format!("<Cmd>colorscheme {}<CR>", colorscheme);

    // Find all nvim sockets and send the command
    let sockets = glob::glob(&paths.nvim_socket_pattern)
        .map_err(|e| format!("invalid socket pattern: {}", e))?;

    let mut updated = 0;
    let mut cleaned = 0;

    for entry in sockets.flatten() {
        if !entry.exists() {
            continue;
        }

        let mut nvim_cmd = Command::new(&nvim_bin);
        nvim_cmd.args([
            "--server",
            entry.to_str().unwrap_or_default(),
            "--remote-send",
            &cmd,
        ]);
        let result = run_with_timeout(nvim_cmd, NVIM_TIMEOUT);

        match result {
            Ok(output) if output.status.success() => updated += 1,
            Ok(_) => {
                // Socket exists but nvim isn't listening — orphaned socket, clean up
                let _ = std::fs::remove_file(&entry);
                cleaned += 1;
            }
            Err(e) => {
                eprintln!(
                    "[theme-manager] neovim socket {}: {}",
                    entry.display(),
                    e
                );
            }
        }
    }

    if updated > 0 || cleaned > 0 {
        eprintln!(
            "[theme-manager] neovim: {} updated, {} orphaned sockets cleaned",
            updated, cleaned
        );
    }

    Ok(())
}

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
