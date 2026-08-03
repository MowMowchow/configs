use crate::appearance::Appearance;
use crate::cmd::run_with_timeout;
use crate::config::{expand_tilde, PathsConfig};
use crate::theme::{get_palette, CatppuccinFlavor, Contrast, Palette, ThemeFamily};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

const TMUX_TIMEOUT: Duration = Duration::from_secs(5);

/// Resolve the tmux binary. Delegates to cmd::resolve_bin so the candidate
/// directories are platform-aware — the old hardcoded Homebrew paths never
/// matched on Linux, where tmux lives in /usr/bin.
fn tmux_bin() -> String {
    crate::cmd::resolve_bin("tmux")
}

/// Apply theme to tmux. Idempotent: safe to call repeatedly.
///
/// Sources the generated `*-theme.auto.conf` — the same artifact a remote host
/// sources via theme-apply.sh. One mechanism, not two: the local and remote
/// paths cannot drift because they execute identical bytes.
///
/// This replaced 34 individual `tmux set` subprocesses (measured ~150 ms) with
/// a single `source-file` (~6 ms). The conf carries the catppuccin `@thm_*`
/// unsets and the plugin invocation too, so both families take this one path.
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

    let conf = theme_conf_path(paths, appearance);
    if !conf.exists() {
        // main::apply_appearance regenerates these before calling us, so this
        // only fires if that write failed. Self-heal rather than render a
        // stale theme (same posture as kitty's auto.conf self-heal).
        write_theme_confs(family, variant, paths)?;
    }

    source_file(&conf)
}

fn tmux_running() -> bool {
    let mut cmd = Command::new(tmux_bin());
    cmd.args(["list-sessions"]);
    run_with_timeout(cmd, TMUX_TIMEOUT)
        .map(|o| o.status.success())
        .unwrap_or(false)
}

fn source_file(conf: &Path) -> Result<(), String> {
    let mut cmd = Command::new(tmux_bin());
    cmd.args(["source-file", &conf.to_string_lossy()]);
    let output =
        run_with_timeout(cmd, TMUX_TIMEOUT).map_err(|e| format!("tmux source-file: {}", e))?;

    if !output.status.success() {
        return Err(format!(
            "tmux source-file {} failed: {}",
            conf.display(),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(())
}

// ─────────────────────────────────────────────────────────────────
// Theme definition — the single source of truth
// ─────────────────────────────────────────────────────────────────

/// All catppuccin `@thm_*` variables, cleared before applying any theme so
/// stale format strings cannot bleed through into the status bar.
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

/// The complete set of tmux options that define a gruvbox-family theme.
///
/// Pure function, and the only place these option/value pairs exist. Everything
/// that renders a tmux theme goes through here.
fn theme_options(palette: &Palette) -> Vec<(&'static str, String)> {
    vec![
        ("status-style", format!("bg={},fg={}", palette.bg1, palette.fg)),
        ("message-style", format!("bg={},fg={}", palette.bg1, palette.fg)),
        ("status-left", String::new()),
        (
            "status-right",
            format!("#[fg={},bg={}] session: #S ", palette.bg, palette.aqua),
        ),
        // Window status — reset catppuccin format strings that embed #{@thm_*}
        // colors. Use inline #[fg/bg] so the format is self-contained with
        // gruvbox palette colors. Shows: [index] [name]
        (
            "window-status-format",
            format!(
                "#[fg={},bg={}] #I #[fg={},bg={}] #W ",
                palette.bg1, palette.fg_dim,
                palette.fg_dim, palette.bg1,
            ),
        ),
        (
            "window-status-current-format",
            format!(
                "#[fg={},bg={},bold] #I #[fg={},bg={}] #W ",
                palette.bg, palette.blue,
                palette.fg, palette.bg,
            ),
        ),
        ("pane-border-style", format!("fg={}", palette.bg2)),
        ("pane-active-border-style", format!("fg={}", palette.blue)),
    ]
}

// ─────────────────────────────────────────────────────────────────
// Generated confs
// ─────────────────────────────────────────────────────────────────

fn theme_conf_path(paths: &PathsConfig, appearance: Appearance) -> PathBuf {
    let name = match appearance {
        Appearance::Dark => "dark-theme.auto.conf",
        Appearance::Light => "light-theme.auto.conf",
    };
    expand_tilde(&paths.tmux_config).join(name)
}

/// FNV-1a. Chosen over DefaultHasher because the digest is part of an on-disk
/// artifact compared across machines and across Rust versions; this one is
/// specified, so it cannot silently change under us.
fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        hash ^= *b as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    hash
}

/// The executable part of a theme conf, without the header.
fn theme_body(
    family: ThemeFamily,
    variant: &str,
    appearance: Appearance,
    paths: &PathsConfig,
) -> String {
    let mut out = String::new();

    for var in CATPPUCCIN_VARS {
        out.push_str(&format!("set -gu {}\n", var));
    }
    out.push('\n');

    match family {
        ThemeFamily::Catppuccin => {
            let flavor = CatppuccinFlavor::for_appearance(variant, appearance);
            out.push_str(&format!(
                "set -g @catppuccin_flavor \"{}\"\n",
                flavor.tmux_name()
            ));
            // Left unexpanded: the remote's $HOME differs from ours, and both
            // if-shell and run-shell go through sh, which expands the tilde.
            // Guarded so a host without the plugin no-ops instead of erroring.
            out.push_str(&format!(
                "if-shell \"[ -f {p} ]\" \"run-shell {p}\"\n",
                p = paths.catppuccin_tmux_plugin
            ));
        }
        _ => {
            let contrast = Contrast::parse(variant);
            let palette = get_palette(family, contrast, appearance);
            for (option, value) in theme_options(&palette) {
                out.push_str(&format!("set -g {} \"{}\"\n", option, value));
            }
        }
    }

    out
}

/// Render one appearance's theme as a sourceable tmux config.
///
/// The `# theme-id:` header is the remote's cache key (theme-apply.sh compares
/// it against `@theme_state`). It ends in a digest of the body, not just
/// family-variant-appearance: editing a palette in theme.rs changes the
/// rendered output without changing the family or variant, and a purely
/// nominal key would let that edit be silently ignored on every remote host.
fn generate_conf(
    family: ThemeFamily,
    variant: &str,
    appearance: Appearance,
    paths: &PathsConfig,
) -> String {
    let body = theme_body(family, variant, appearance, paths);
    let digest = format!("{:016x}", fnv1a64(body.as_bytes()));

    format!(
        "# Auto-generated by theme-manager — do not edit manually\n\
         # theme-id: {}-{}-{}-{}\n\n{}",
        family,
        variant,
        appearance,
        &digest[..8],
        body
    )
}

/// Write dark-theme.auto.conf and light-theme.auto.conf into the tmux config
/// dir. A remote tmux has no theme-manager binary, so theme-apply.sh sources
/// one of these instead — same palette, no second copy of the hex values.
///
/// Writes are atomic (temp + rename) because a reader may be sourcing the file
/// concurrently: a tmux hook on one side, this daemon on the other.
pub fn write_theme_confs(
    family: ThemeFamily,
    variant: &str,
    paths: &PathsConfig,
) -> Result<(), String> {
    let dir = expand_tilde(&paths.tmux_config);
    if !dir.exists() {
        return Err(format!("tmux config dir not found: {}", dir.display()));
    }

    for (appearance, name) in [
        (Appearance::Dark, "dark-theme.auto.conf"),
        (Appearance::Light, "light-theme.auto.conf"),
    ] {
        let dst = dir.join(name);
        let tmp = dir.join(format!(".{}.tmp", name));
        fs::write(&tmp, generate_conf(family, variant, appearance, paths))
            .map_err(|e| format!("write {}: {}", tmp.display(), e))?;
        fs::rename(&tmp, &dst)
            .map_err(|e| format!("rename {} -> {}: {}", tmp.display(), dst.display(), e))?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn paths() -> PathsConfig {
        PathsConfig::default()
    }

    /// Parse `set -g <option> "<value>"` lines back out of a rendered conf.
    fn parse_set_g(conf: &str) -> Vec<(String, String)> {
        conf.lines()
            .filter_map(|l| l.strip_prefix("set -g "))
            .filter(|l| !l.starts_with('@'))
            .filter_map(|rest| {
                let (opt, val) = rest.split_once(' ')?;
                let val = val.strip_prefix('"')?.strip_suffix('"')?;
                Some((opt.to_string(), val.to_string()))
            })
            .collect()
    }

    /// THE load-bearing invariant of this design: what the local adapter would
    /// apply and what a remote host sources must be the same option/value set.
    /// Both now render from theme_options(), and this proves it stays that way.
    #[test]
    fn generated_conf_matches_theme_options_exactly() {
        for family in [ThemeFamily::Gruvbox, ThemeFamily::GruvboxMaterial] {
            for variant in ["hard", "medium", "soft"] {
                for appearance in [Appearance::Dark, Appearance::Light] {
                    let palette =
                        get_palette(family, Contrast::parse(variant), appearance);
                    let expected: Vec<(String, String)> = theme_options(&palette)
                        .into_iter()
                        .map(|(o, v)| (o.to_string(), v))
                        .collect();

                    let conf = generate_conf(family, variant, appearance, &paths());
                    assert_eq!(
                        parse_set_g(&conf),
                        expected,
                        "drift for {} {} {}",
                        family,
                        variant,
                        appearance
                    );
                }
            }
        }
    }

    #[test]
    fn every_conf_clears_all_catppuccin_vars() {
        let conf = generate_conf(ThemeFamily::GruvboxMaterial, "medium", Appearance::Dark, &paths());
        for var in CATPPUCCIN_VARS {
            assert!(
                conf.contains(&format!("set -gu {}\n", var)),
                "conf does not clear {}",
                var
            );
        }
    }

    #[test]
    fn theme_id_is_content_addressed() {
        let id = |f, v, a| {
            generate_conf(f, v, a, &paths())
                .lines()
                .find_map(|l| l.strip_prefix("# theme-id: ").map(str::to_string))
                .expect("conf must carry a theme-id")
        };

        let base = id(ThemeFamily::GruvboxMaterial, "medium", Appearance::Dark);

        // Deterministic across calls — otherwise the remote re-applies forever.
        assert_eq!(base, id(ThemeFamily::GruvboxMaterial, "medium", Appearance::Dark));

        // Every axis that changes rendered output must change the id.
        assert_ne!(base, id(ThemeFamily::GruvboxMaterial, "medium", Appearance::Light));
        assert_ne!(base, id(ThemeFamily::GruvboxMaterial, "hard", Appearance::Dark));
        assert_ne!(base, id(ThemeFamily::Gruvbox, "medium", Appearance::Dark));
    }

    /// A palette edit must invalidate the cache key even though family,
    /// variant and appearance are unchanged. Simulated by hashing two bodies
    /// that differ only in a colour.
    #[test]
    fn theme_id_changes_when_only_a_colour_changes() {
        let a = "set -g status-style \"bg=#32302f,fg=#d4be98\"\n";
        let b = "set -g status-style \"bg=#32302f,fg=#d4be99\"\n";
        assert_ne!(fnv1a64(a.as_bytes()), fnv1a64(b.as_bytes()));
    }

    #[test]
    fn conf_values_never_contain_characters_tmux_would_mis_parse() {
        for family in [ThemeFamily::Gruvbox, ThemeFamily::GruvboxMaterial] {
            for variant in ["hard", "medium", "soft"] {
                for appearance in [Appearance::Dark, Appearance::Light] {
                    let palette = get_palette(family, Contrast::parse(variant), appearance);
                    for (opt, val) in theme_options(&palette) {
                        assert!(
                            !val.contains('"') && !val.contains('\\') && !val.contains('\n'),
                            "{} value would break the quoted conf: {:?}",
                            opt,
                            val
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn palettes_are_well_formed() {
        let is_hex = |s: &str| {
            s.len() == 7
                && s.starts_with('#')
                && s[1..].chars().all(|c| c.is_ascii_hexdigit())
        };
        for family in [ThemeFamily::Gruvbox, ThemeFamily::GruvboxMaterial] {
            for variant in ["hard", "medium", "soft"] {
                let dark = get_palette(family, Contrast::parse(variant), Appearance::Dark);
                let light = get_palette(family, Contrast::parse(variant), Appearance::Light);
                for p in [&dark, &light] {
                    for c in [p.bg, p.bg1, p.bg2, p.fg, p.fg_dim, p.blue, p.aqua] {
                        assert!(is_hex(c), "{} {} bad colour {:?}", family, variant, c);
                    }
                    assert_eq!(p.terminal.len(), 16);
                    assert!(p.terminal.iter().all(|c| is_hex(c)));
                }
                // Dark and light must actually differ, or the whole feature is a no-op.
                assert_ne!(dark.bg, light.bg, "{} {} dark==light", family, variant);
            }
        }
    }
}
