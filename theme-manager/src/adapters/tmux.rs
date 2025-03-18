use crate::appearance::Appearance;
use crate::cmd::run_with_timeout;
use crate::config::{expand_tilde, PathsConfig};
use crate::theme::{get_palette, CatppuccinFlavor, Contrast, Palette, ThemeFamily};
use std::process::Command;
use std::time::Duration;

const TMUX_TIMEOUT: Duration = Duration::from_secs(5);

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

/// Apply theme to tmux. Idempotent: safe to call repeatedly.
///
/// - Catppuccin: sets the flavor variable, then re-runs the tmux plugin.
/// - Gruvbox variants: sets all status bar colors directly from the palette.
///
/// Both paths first clear catppuccin @thm_* variables to prevent stale
/// format strings from bleeding through.
pub fn apply(
    family: ThemeFamily,
    variant: &str,
    appearance: Appearance,
    paths: &PathsConfig,
) -> Result<(), String> {
    if !tmux_running() {
        eprintln!("[theme-manager] tmux not detected, skipping");
        return Ok(());
    }

    match family {
        ThemeFamily::Catppuccin => {
            let flavor = CatppuccinFlavor::for_appearance(variant, appearance);
            apply_catppuccin(flavor, paths)
        }
        _ => {
            let contrast = Contrast::parse(variant);
            let palette = get_palette(family, contrast, appearance);
            apply_gruvbox(&palette)
        }
    }
}

fn tmux_running() -> bool {
    let mut cmd = Command::new(tmux_bin());
    cmd.args(["list-sessions"]);
    run_with_timeout(cmd, TMUX_TIMEOUT)
        .map(|o| o.status.success())
        .unwrap_or(false)
}

// ─────────────────────────────────────────────────────────────────
// Catppuccin (via tmux plugin)
// ─────────────────────────────────────────────────────────────────

/// All catppuccin @thm_* variables that must be cleared before re-running
/// the plugin, so it re-initializes cleanly with the new flavor.
const CATPPUCCIN_VARS: &[&str] = &[
    "@thm_bg", "@thm_fg", "@thm_crust", "@thm_mantle",
    "@thm_surface_0", "@thm_surface_1", "@thm_surface_2",
    "@thm_overlay_0", "@thm_overlay_1", "@thm_overlay_2",
    "@thm_subtext_0", "@thm_subtext_1",
    "@thm_blue", "@thm_flamingo", "@thm_green", "@thm_lavender",
    "@thm_maroon", "@thm_mauve", "@thm_peach", "@thm_pink",
    "@thm_red", "@thm_rosewater", "@thm_sapphire", "@thm_sky",
    "@thm_teal", "@thm_yellow",
];

fn apply_catppuccin(flavor: CatppuccinFlavor, paths: &PathsConfig) -> Result<(), String> {
    // Clear all catppuccin variables so the plugin re-initializes cleanly
    for var in CATPPUCCIN_VARS {
        let _ = tmux_set_unset(var);
    }

    tmux_set("@catppuccin_flavor", flavor.tmux_name())?;

    let plugin_path = expand_tilde(&paths.catppuccin_tmux_plugin);
    if !plugin_path.exists() {
        return Err(format!(
            "catppuccin plugin not found: {} — install with TPM or check paths.catppuccin_tmux_plugin in config",
            plugin_path.display()
        ));
    }

    let mut cmd = Command::new(tmux_bin());
    cmd.args(["run-shell", plugin_path.to_str().unwrap_or_default()]);
    let output = run_with_timeout(cmd, TMUX_TIMEOUT)
        .map_err(|e| format!("run catppuccin.tmux: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "catppuccin.tmux failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    Ok(())
}

// ─────────────────────────────────────────────────────────────────
// Gruvbox (direct tmux options)
// ─────────────────────────────────────────────────────────────────

fn apply_gruvbox(palette: &Palette) -> Result<(), String> {
    // Clear catppuccin variables to prevent their format strings from
    // bleeding through into the status bar
    for var in CATPPUCCIN_VARS {
        let _ = tmux_set_unset(var);
    }

    // Status bar
    tmux_set("status-style", &format!("bg={},fg={}", palette.bg1, palette.fg))?;
    tmux_set("message-style", &format!("bg={},fg={}", palette.bg1, palette.fg))?;
    tmux_set("status-left", "")?;
    tmux_set(
        "status-right",
        &format!("#[fg={},bg={}] session: #S ", palette.bg, palette.aqua),
    )?;

    // Window status — reset catppuccin format strings that embed #{@thm_*}
    // colors. Use inline #[fg/bg] so the format is self-contained with
    // gruvbox palette colors. Shows: [index] [name]
    tmux_set(
        "window-status-format",
        &format!(
            "#[fg={},bg={}] #I #[fg={},bg={}] #W ",
            palette.bg1, palette.fg_dim,
            palette.fg_dim, palette.bg1,
        ),
    )?;
    tmux_set(
        "window-status-current-format",
        &format!(
            "#[fg={},bg={},bold] #I #[fg={},bg={}] #W ",
            palette.bg, palette.blue,
            palette.fg, palette.bg,
        ),
    )?;

    // Pane borders
    tmux_set("pane-border-style", &format!("fg={}", palette.bg2))?;
    tmux_set("pane-active-border-style", &format!("fg={}", palette.blue))?;

    Ok(())
}

// ─────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────

fn tmux_set(option: &str, value: &str) -> Result<(), String> {
    let mut cmd = Command::new(tmux_bin());
    cmd.args(["set", "-g", option, value]);
    let output = run_with_timeout(cmd, TMUX_TIMEOUT)
        .map_err(|e| format!("tmux set {}: {}", option, e))?;

    if !output.status.success() {
        Err(format!(
            "tmux set {} failed: {}",
            option,
            String::from_utf8_lossy(&output.stderr)
        ))
    } else {
        Ok(())
    }
}

fn tmux_set_unset(option: &str) -> Result<(), String> {
    let mut cmd = Command::new(tmux_bin());
    cmd.args(["set", "-gu", option]);
    let _ = run_with_timeout(cmd, TMUX_TIMEOUT);
    Ok(())
}
