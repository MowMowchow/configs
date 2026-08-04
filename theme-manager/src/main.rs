use clap::{Parser, Subcommand};

mod adapters;
mod appearance;
pub mod cmd;
mod config;
mod platform;
mod site;
mod theme;

use config::Config;
use theme::ThemeFamily;

#[derive(Parser)]
#[command(name = "theme-manager", about = "Unified macOS theme manager")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Set the active theme family and variant
    Set {
        /// Theme family: catppuccin, gruvbox, gruvbox-material
        family: String,
        /// Variant (optional, family-dependent):
        ///   catppuccin: mocha, macchiato, frappe (dark flavor; light is always latte)
        ///   gruvbox:    hard, medium, soft (contrast)
        variant: Option<String>,
    },
    /// Show current theme configuration
    Get,
    /// List available themes and their options
    List,
    /// Apply theme for current or specified appearance (without changing theme family)
    Apply {
        /// dark, light, or omit to auto-detect from system
        mode: Option<String>,
    },
    /// Watch for system appearance changes (daemon mode)
    Watch,
    /// Report what the theme system can see and whether it is healthy
    Doctor,
}

/// One-shot health check. Everything a "the bar is the wrong colour" question
/// needs, in one command, so nobody has to remember five separate probes.
fn doctor(config_path: &std::path::Path) -> i32 {
    let mut problems = 0;
    let mut note = |ok: bool, label: &str, detail: String| {
        println!("  {} {:<22} {}", if ok { "ok  " } else { "FAIL" }, label, detail);
        if !ok {
            problems += 1;
        }
    };

    println!("platform");
    note(true, "backend", appearance::backend().to_string());
    match appearance::try_get_current() {
        Some(a) => note(true, "appearance", format!("{}", a)),
        None => note(
            false,
            "appearance",
            "undeterminable — no OS appearance on this host".into(),
        ),
    }

    println!("config");
    let config = match Config::load(config_path) {
        Ok(c) => {
            note(true, "config.toml", format!("{}", config_path.display()));
            c
        }
        Err(e) => {
            note(false, "config.toml", e);
            return 1;
        }
    };
    let family = ThemeFamily::parse(&config.theme.family);
    note(
        family.is_valid_variant(&config.theme.variant),
        "theme",
        format!("{} / {}", family, config.theme.variant),
    );

    println!("artifacts");
    let tmux_dir = config::expand_tilde(&config.paths.tmux_config);
    for name in ["dark-theme.auto.conf", "light-theme.auto.conf"] {
        let p = tmux_dir.join(name);
        match std::fs::read_to_string(&p) {
            Ok(body) => {
                let id = body
                    .lines()
                    .find_map(|l| l.strip_prefix("# theme-id: "))
                    .unwrap_or("<no theme-id>");
                note(true, name, id.to_string());
            }
            Err(e) => note(false, name, format!("{}: {}", p.display(), e)),
        }
    }

    println!("site plugins");
    let plugins = site::discover(&config_dir());
    if plugins.is_empty() {
        println!("  ---- {:<22} none installed", "");
    }
    for p in &plugins {
        let hook = p.dir.join("theme-hook");
        note(
            true,
            &p.name,
            format!(
                "api v{}{}",
                site::API_VERSION,
                if hook.is_file() { ", theme-hook" } else { "" }
            ),
        );
    }

    println!();
    if problems == 0 {
        println!("healthy");
        0
    } else {
        println!("{} problem(s) found", problems);
        1
    }
}

/// Apply the configured theme for `app`. Returns true if every adapter
/// succeeded, so the daemon can retry a partial apply instead of latching it.
fn apply_appearance(config: &Config, app: appearance::Appearance) -> bool {
    let family = ThemeFamily::parse(&config.theme.family);
    let variant = &config.theme.variant;

    eprintln!(
        "[theme-manager] applying {} {} ({})",
        family, variant, app
    );

    // Regenerate both sets of theme artifacts unconditionally, so an edit to
    // theme.rs propagates on the next rebuild without needing
    // `theme-manager set`. These writes are ~1 ms combined.
    //
    // Kitty used to regenerate only when the files were missing while tmux
    // regenerated always — which meant a palette edit reached tmux but not
    // kitty. Same policy for both is the point.
    let mut errors = 0;
    for (name, result) in [
        (
            "kitty conf",
            adapters::kitty::write_auto_confs(family, variant, &config.paths),
        ),
        (
            "tmux conf",
            adapters::tmux::write_theme_confs(family, variant, &config.paths),
        ),
    ] {
        if let Err(e) = result {
            eprintln!("[theme-manager] {} write error: {}", name, e);
            errors += 1;
        }
    }

    // Record the resolved appearance where anything without an OS to ask can
    // read it.
    //
    // Only tmux/theme-apply.sh wrote this before, and that runs on remote hosts
    // only — so on a machine driven by this binary the file was whatever a sync
    // last seeded and then never moved again. Neovim's startup path reads it to
    // pick `background`, so a stale pointer means every freshly launched editor
    // gets the wrong one until something re-applies. Writing it here makes the
    // binary the single writer on every platform it runs on.
    //
    // Best-effort and atomic: a concurrent reader must never see a half-written
    // value, and failing to record state must not fail the apply.
    if let Err(e) = write_appearance_pointer(app) {
        eprintln!("[theme-manager] appearance pointer: {}", e);
    }

    // Run each adapter independently — one failure must not block others.
    // This follows the bulkhead pattern: isolate failure domains.
    let results: [(&str, Result<(), String>); 3] = [
        ("kitty", adapters::kitty::reload()),
        (
            "tmux",
            adapters::tmux::apply(family, variant, app, &config.paths),
        ),
        (
            "neovim",
            adapters::neovim::apply(family, variant, app, &config.paths),
        ),
    ];

    for (name, result) in &results {
        match result {
            Ok(()) => eprintln!("[theme-manager] {} ok", name),
            Err(e) => {
                eprintln!("[theme-manager] {} error: {}", name, e);
                errors += 1;
            }
        }
    }

    // Site plugins last: they may want to act on the result, and anything
    // employer-specific must never be able to delay the local adapters.
    // Bulkheaded the same way — a failing hook is reported, not fatal.
    let config_root = config_dir();
    let conf = config::expand_tilde(&config.paths.tmux_config).join(match app {
        appearance::Appearance::Dark => "dark-theme.auto.conf",
        appearance::Appearance::Light => "light-theme.auto.conf",
    });
    let hooks = site::run_theme_hooks(&config_root, app, &family.to_string(), variant, &conf);
    let hook_count = hooks.len();
    for (name, result) in &hooks {
        match result {
            Ok(()) => eprintln!("[theme-manager] site:{} ok", name),
            Err(e) => {
                eprintln!("[theme-manager] site:{} error: {}", name, e);
                errors += 1;
            }
        }
    }

    if errors > 0 {
        eprintln!(
            "[theme-manager] {} of {} steps failed",
            errors,
            results.len() + hook_count + 2
        );
    }

    errors == 0
}

/// Root of the dotfiles tree — the parent of theme-manager's own config dir.
fn config_dir() -> std::path::PathBuf {
    dirs::home_dir()
        .map(|h| h.join(".config"))
        .unwrap_or_else(|| std::path::PathBuf::from(".config"))
}

fn main() {
    let cli = Cli::parse();
    let config_path = Config::default_path();

    match cli.command {
        Commands::Set { family, variant } => {
            let f = ThemeFamily::parse(&family);
            let v = variant.unwrap_or_else(|| f.default_variant().to_string());

            if !f.is_valid_variant(&v) {
                eprintln!(
                    "Invalid {} '{}' for {}. Valid options:",
                    f.variant_label(),
                    v,
                    f
                );
                for opt in f.valid_variants() {
                    let marker = if *opt == f.default_variant() {
                        " (default)"
                    } else {
                        ""
                    };
                    eprintln!("  {}{}", opt, marker);
                }
                std::process::exit(1);
            }

            let mut config = load_config(&config_path);
            config.theme.family = f.to_string();
            config.theme.variant = v.clone();

            if let Err(e) = config.save(&config_path) {
                eprintln!("Failed to save config: {}", e);
                std::process::exit(1);
            }

            // apply_appearance regenerates both sets of theme artifacts, so
            // there is nothing to write here.
            let app = appearance::get_current();
            apply_appearance(&config, app);

            println!("Theme set to {} ({})", f, v);
        }
        Commands::Get => {
            let config = load_config(&config_path);
            let family = ThemeFamily::parse(&config.theme.family);
            let app = appearance::get_current();

            println!("Family:     {}", config.theme.family);
            println!(
                "{}:   {}",
                capitalize(family.variant_label()),
                config.theme.variant
            );
            if family == ThemeFamily::Catppuccin {
                let flavor = theme::CatppuccinFlavor::for_appearance(
                    &config.theme.variant,
                    app,
                );
                println!("Active:     {} (resolved for {} mode)", flavor, app);
            }
            println!("Appearance: {} (system)", app);
        }
        Commands::List => {
            let active = Config::load(&config_path).ok();

            println!("Available themes:\n");
            for (name, label, variants, default) in [
                ("catppuccin", "flavor", vec!["mocha", "macchiato", "frappe"], "mocha"),
                ("gruvbox", "contrast", vec!["hard", "medium", "soft"], "medium"),
                ("gruvbox-material", "contrast", vec!["hard", "medium", "soft"], "medium"),
            ] {
                let is_active = active
                    .as_ref()
                    .map_or(false, |c| c.theme.family == name);
                let marker = if is_active { " *" } else { "" };
                println!("  {}{}", name, marker);

                let options: Vec<String> = variants
                    .iter()
                    .map(|v| {
                        let active_marker = if is_active
                            && active.as_ref().map_or(false, |c| c.theme.variant == *v)
                        {
                            " [active]"
                        } else if *v == default {
                            " (default)"
                        } else {
                            ""
                        };
                        format!("{}{}", v, active_marker)
                    })
                    .collect();
                println!("    {}: {}", label, options.join(", "));

                if name == "catppuccin" {
                    println!("    light: latte (auto-selected by system appearance)");
                }
                println!();
            }
        }
        Commands::Apply { mode } => {
            let app = match mode.as_deref() {
                Some("dark") => appearance::Appearance::Dark,
                Some("light") => appearance::Appearance::Light,
                None => appearance::get_current(),
                Some(other) => {
                    eprintln!("Invalid mode '{}'. Use 'dark', 'light', or omit to auto-detect.", other);
                    std::process::exit(1);
                }
            };
            let config = load_config(&config_path);
            apply_appearance(&config, app);
        }
        Commands::Doctor => {
            std::process::exit(doctor(&config_path));
        }
        Commands::Watch => {
            eprintln!("[theme-manager] starting daemon...");
            let config_path = config_path.clone();
            appearance::watch(move |app| {
                eprintln!("[theme-manager] appearance changed: {}", app);
                match Config::load(&config_path) {
                    Ok(config) => apply_appearance(&config, app),
                    Err(e) => {
                        // Do not fall back to defaults here: that would apply
                        // the wrong theme and then overwrite the generated
                        // artifacts with it. Report false so the tick is
                        // retried once the config is readable again.
                        eprintln!("[theme-manager] config load error: {}", e);
                        false
                    }
                }
            });
        }
    }
}

/// Load the config for a one-shot command, refusing to guess.
///
/// A missing config is fine — first run, use defaults. A config that exists but
/// does not parse is not: `unwrap_or_default()` silently switched the user to
/// catppuccin *and* discarded their `[paths]`, and the very next step
/// regenerates the theme artifacts from that wrong theme. Fail fast instead.
fn load_config(path: &std::path::Path) -> Config {
    if !path.exists() {
        eprintln!(
            "[theme-manager] no config at {}, using defaults",
            path.display()
        );
        return Config::default();
    }
    Config::load(path).unwrap_or_else(|e| {
        eprintln!("[theme-manager] {} exists but could not be loaded", path.display());
        eprintln!("[theme-manager]   {}", e);
        eprintln!("[theme-manager]   fix it, or delete it to fall back to defaults");
        std::process::exit(1);
    })
}

fn capitalize(s: &str) -> String {
    let mut c = s.chars();
    match c.next() {
        None => String::new(),
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
    }
}

/// Persist the active appearance to `~/.local/state/theme-manager/appearance`.
///
/// Consumers have no OS appearance API of their own: Neovim's startup path, and
/// tmux on builds older than 3.6 which lack `#{client_theme}`.
///
/// Written via a temp file and renamed, because a reader that catches a
/// partially written file sees neither "dark" nor "light" and silently falls
/// back to a default.
fn write_appearance_pointer(app: appearance::Appearance) -> Result<(), String> {
    let dir = dirs_state_dir();
    std::fs::create_dir_all(&dir).map_err(|e| format!("create {}: {}", dir.display(), e))?;
    let final_path = dir.join("appearance");
    let tmp = dir.join("appearance.tmp");
    std::fs::write(&tmp, app.to_string()).map_err(|e| format!("write temp: {}", e))?;
    std::fs::rename(&tmp, &final_path).map_err(|e| format!("rename: {}", e))?;
    Ok(())
}

/// `$XDG_STATE_HOME/theme-manager`, falling back to `~/.local/state`.
fn dirs_state_dir() -> std::path::PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
                .join(".local")
                .join("state")
        })
        .join("theme-manager")
}
