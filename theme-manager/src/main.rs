use clap::{Parser, Subcommand};

mod adapters;
mod appearance;
pub mod cmd;
mod config;
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
}

fn apply_appearance(config: &Config, app: appearance::Appearance) {
    let family = ThemeFamily::parse(&config.theme.family);
    let variant = &config.theme.variant;

    eprintln!(
        "[theme-manager] applying {} {} ({})",
        family, variant, app
    );

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

    let mut errors = 0;
    for (name, result) in &results {
        match result {
            Ok(()) => eprintln!("[theme-manager] {} ok", name),
            Err(e) => {
                eprintln!("[theme-manager] {} error: {}", name, e);
                errors += 1;
            }
        }
    }

    if errors > 0 {
        eprintln!(
            "[theme-manager] {} of {} adapters failed",
            errors,
            results.len()
        );
    }
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

            let mut config = Config::load(&config_path).unwrap_or_default();
            config.theme.family = f.to_string();
            config.theme.variant = v.clone();

            if let Err(e) = config.save(&config_path) {
                eprintln!("Failed to save config: {}", e);
                std::process::exit(1);
            }

            // Write kitty auto.conf files for both appearances
            if let Err(e) = adapters::kitty::write_auto_confs(f, &v, &config.paths) {
                eprintln!("[theme-manager] kitty write error: {}", e);
            }

            // Apply to current system appearance
            let app = appearance::get_current();
            apply_appearance(&config, app);

            println!("Theme set to {} ({})", f, v);
        }
        Commands::Get => {
            let config = Config::load(&config_path).unwrap_or_default();
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
            let config = Config::load(&config_path).unwrap_or_default();
            apply_appearance(&config, app);
        }
        Commands::Watch => {
            eprintln!("[theme-manager] starting daemon...");
            let config_path = config_path.clone();
            appearance::watch(move |app| {
                eprintln!("[theme-manager] appearance changed: {}", app);
                match Config::load(&config_path) {
                    Ok(config) => apply_appearance(&config, app),
                    Err(e) => eprintln!("[theme-manager] config load error: {}", e),
                }
            });
        }
    }
}

fn capitalize(s: &str) -> String {
    let mut c = s.chars();
    match c.next() {
        None => String::new(),
        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
    }
}
