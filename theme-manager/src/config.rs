use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub theme: ThemeConfig,
    #[serde(default)]
    pub paths: PathsConfig,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ThemeConfig {
    pub family: String,
    /// Universal variant field. Meaning depends on family:
    /// - catppuccin: dark flavor (mocha, macchiato, frappe). Light is always latte.
    /// - gruvbox / gruvbox-material: contrast (hard, medium, soft).
    ///
    /// Accepts the legacy "contrast" key for backward compatibility.
    #[serde(default = "default_variant", alias = "contrast")]
    pub variant: String,
}

fn default_variant() -> String {
    "medium".to_string()
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct PathsConfig {
    #[serde(default = "default_kitty")]
    pub kitty_config: String,
    #[serde(default = "default_tmux")]
    pub tmux_config: String,
    #[serde(default = "default_nvim_socket")]
    pub nvim_socket_pattern: String,
    #[serde(default = "default_catppuccin_tmux")]
    pub catppuccin_tmux_plugin: String,
}

fn default_kitty() -> String {
    "~/.config/kitty".to_string()
}
fn default_tmux() -> String {
    "~/.config/tmux".to_string()
}
fn default_nvim_socket() -> String {
    "/tmp/nvim-theme-*.sock".to_string()
}
fn default_catppuccin_tmux() -> String {
    "~/.config/tmux/plugins/tmux/catppuccin.tmux".to_string()
}

impl Default for Config {
    fn default() -> Self {
        Config {
            theme: ThemeConfig {
                family: "catppuccin".to_string(),
                variant: "mocha".to_string(),
            },
            paths: PathsConfig::default(),
        }
    }
}

impl Default for PathsConfig {
    fn default() -> Self {
        PathsConfig {
            kitty_config: default_kitty(),
            tmux_config: default_tmux(),
            nvim_socket_pattern: default_nvim_socket(),
            catppuccin_tmux_plugin: default_catppuccin_tmux(),
        }
    }
}

impl Config {
    pub fn default_path() -> PathBuf {
        let home = dirs::home_dir().expect("no home directory");
        home.join(".config/theme-manager/config.toml")
    }

    pub fn load(path: &Path) -> Result<Self, String> {
        let content =
            std::fs::read_to_string(path).map_err(|e| format!("read {}: {}", path.display(), e))?;
        let config: Self =
            toml::from_str(&content).map_err(|e| format!("parse {}: {}", path.display(), e))?;

        // Validate loaded config
        config.validate()?;
        Ok(config)
    }

    /// Atomic save: write to a temp file then rename, so a crash mid-write
    /// never leaves a corrupted config.
    pub fn save(&self, path: &Path) -> Result<(), String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("create config dir: {}", e))?;
        }
        let content =
            toml::to_string_pretty(self).map_err(|e| format!("serialize config: {}", e))?;

        let tmp = path.with_extension("toml.tmp");
        std::fs::write(&tmp, &content)
            .map_err(|e| format!("write {}: {}", tmp.display(), e))?;
        std::fs::rename(&tmp, path)
            .map_err(|e| format!("rename {} -> {}: {}", tmp.display(), path.display(), e))?;
        Ok(())
    }

    /// Validate that family and variant are consistent. Corrects silently
    /// for known mismatches (e.g. old config with wrong variant for family).
    fn validate(&self) -> Result<(), String> {
        use crate::theme::ThemeFamily;
        let family = ThemeFamily::parse(&self.theme.family);
        if !family.is_valid_variant(&self.theme.variant) {
            eprintln!(
                "[theme-manager] warning: variant '{}' invalid for {}, using default '{}'",
                self.theme.variant,
                family,
                family.default_variant()
            );
        }
        Ok(())
    }
}

pub fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = dirs::home_dir() {
            return home.join(rest);
        }
    }
    PathBuf::from(path)
}
