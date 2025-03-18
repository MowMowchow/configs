use crate::appearance::Appearance;
use std::fmt;

// ─────────────────────────────────────────────────────────────────
// Theme Family
// ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeFamily {
    Catppuccin,
    Gruvbox,
    GruvboxMaterial,
}

impl ThemeFamily {
    pub fn parse(s: &str) -> Self {
        match s.to_lowercase().replace('_', "-").as_str() {
            "catppuccin" => Self::Catppuccin,
            "gruvbox" => Self::Gruvbox,
            "gruvbox-material" => Self::GruvboxMaterial,
            other => {
                eprintln!("Unknown theme family '{}', defaulting to catppuccin", other);
                Self::Catppuccin
            }
        }
    }

    /// Valid variant values for this family.
    ///
    /// - Catppuccin: dark flavors (mocha, macchiato, frappe). Light is always latte.
    /// - Gruvbox / Gruvbox Material: contrast levels (hard, medium, soft).
    pub fn valid_variants(&self) -> &'static [&'static str] {
        match self {
            Self::Catppuccin => &["mocha", "macchiato", "frappe"],
            Self::Gruvbox | Self::GruvboxMaterial => &["hard", "medium", "soft"],
        }
    }

    pub fn default_variant(&self) -> &'static str {
        match self {
            Self::Catppuccin => "mocha",
            Self::Gruvbox | Self::GruvboxMaterial => "medium",
        }
    }

    pub fn is_valid_variant(&self, v: &str) -> bool {
        self.valid_variants().contains(&v.to_lowercase().as_str())
    }

    pub fn variant_label(&self) -> &'static str {
        match self {
            Self::Catppuccin => "flavor",
            Self::Gruvbox | Self::GruvboxMaterial => "contrast",
        }
    }
}

impl fmt::Display for ThemeFamily {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Catppuccin => write!(f, "catppuccin"),
            Self::Gruvbox => write!(f, "gruvbox"),
            Self::GruvboxMaterial => write!(f, "gruvbox-material"),
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// Contrast (Gruvbox / Gruvbox Material)
// ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Contrast {
    Hard,
    Medium,
    Soft,
}

impl Contrast {
    pub fn parse(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "hard" => Self::Hard,
            "medium" => Self::Medium,
            "soft" => Self::Soft,
            other => {
                eprintln!("Unknown contrast '{}', defaulting to medium", other);
                Self::Medium
            }
        }
    }
}

impl fmt::Display for Contrast {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Hard => write!(f, "hard"),
            Self::Medium => write!(f, "medium"),
            Self::Soft => write!(f, "soft"),
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// Catppuccin Flavor
// ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CatppuccinFlavor {
    Mocha,
    Macchiato,
    Frappe,
    Latte,
}

impl CatppuccinFlavor {
    pub fn parse(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "mocha" => Self::Mocha,
            "macchiato" => Self::Macchiato,
            "frappe" | "frappé" => Self::Frappe,
            "latte" => Self::Latte,
            other => {
                eprintln!("Unknown catppuccin flavor '{}', defaulting to mocha", other);
                Self::Mocha
            }
        }
    }

    /// Resolve the flavor based on system appearance.
    /// Dark: user's chosen flavor. Light: always latte (the only light flavor).
    pub fn for_appearance(variant: &str, appearance: Appearance) -> Self {
        match appearance {
            Appearance::Light => Self::Latte,
            Appearance::Dark => Self::parse(variant),
        }
    }

    pub fn tmux_name(&self) -> &'static str {
        match self {
            Self::Mocha => "mocha",
            Self::Macchiato => "macchiato",
            Self::Frappe => "frappe",
            Self::Latte => "latte",
        }
    }

    /// Kitty theme file name in the themes/ directory.
    pub fn kitty_file(&self) -> &'static str {
        match self {
            Self::Mocha => "mocha.conf",
            Self::Macchiato => "macchiato.conf",
            Self::Frappe => "frappe.conf",
            Self::Latte => "latte.conf",
        }
    }

    /// Neovim colorscheme name (catppuccin-<flavor>).
    pub fn nvim_colorscheme(&self) -> &'static str {
        match self {
            Self::Mocha => "catppuccin-mocha",
            Self::Macchiato => "catppuccin-macchiato",
            Self::Frappe => "catppuccin-frappe",
            Self::Latte => "catppuccin-latte",
        }
    }
}

impl fmt::Display for CatppuccinFlavor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.tmux_name())
    }
}

// ─────────────────────────────────────────────────────────────────
// Color Palette (Gruvbox families only)
// ─────────────────────────────────────────────────────────────────

#[allow(dead_code)]
pub struct Palette {
    pub bg: &'static str,
    pub bg_dim: &'static str,
    pub bg1: &'static str,
    pub bg2: &'static str,
    pub fg: &'static str,
    pub fg_dim: &'static str,
    pub gray: &'static str,
    pub blue: &'static str,
    pub aqua: &'static str,
    pub purple: &'static str,
    pub yellow: &'static str,
    pub red: &'static str,
    pub orange: &'static str,
    pub terminal: [&'static str; 16],
}

pub fn get_palette(family: ThemeFamily, contrast: Contrast, appearance: Appearance) -> Palette {
    match (family, appearance) {
        (ThemeFamily::Gruvbox, Appearance::Dark) => gruvbox_dark(contrast),
        (ThemeFamily::Gruvbox, Appearance::Light) => gruvbox_light(contrast),
        (ThemeFamily::GruvboxMaterial, Appearance::Dark) => gruvbox_material_dark(contrast),
        (ThemeFamily::GruvboxMaterial, Appearance::Light) => gruvbox_material_light(contrast),
        (ThemeFamily::Catppuccin, _) => {
            unreachable!("catppuccin uses existing theme files, not generated palettes")
        }
    }
}

// ─────────────────────────────────────────────────────────────────
// Gruvbox Original palettes
// ─────────────────────────────────────────────────────────────────

fn gruvbox_dark(contrast: Contrast) -> Palette {
    let (bg, bg_dim) = match contrast {
        Contrast::Hard => ("#1d2021", "#1d2021"),
        Contrast::Medium => ("#282828", "#1d2021"),
        Contrast::Soft => ("#32302f", "#282828"),
    };
    Palette {
        bg, bg_dim,
        bg1: "#3c3836", bg2: "#504945",
        fg: "#ebdbb2", fg_dim: "#a89984", gray: "#928374",
        blue: "#83a598", aqua: "#689d6a", purple: "#d3869b",
        yellow: "#fabd2f", red: "#fb4934", orange: "#fe8019",
        terminal: [
            "#282828", "#cc241d", "#98971a", "#d79921",
            "#458588", "#b16286", "#689d6a", "#a89984",
            "#928374", "#fb4934", "#b8bb26", "#fabd2f",
            "#83a598", "#d3869b", "#8ec07c", "#ebdbb2",
        ],
    }
}

fn gruvbox_light(contrast: Contrast) -> Palette {
    let (bg, bg_dim) = match contrast {
        Contrast::Hard => ("#f9f5d7", "#ebdbb2"),
        Contrast::Medium => ("#fbf1c7", "#ebdbb2"),
        Contrast::Soft => ("#f2e5bc", "#d5c4a1"),
    };
    Palette {
        bg, bg_dim,
        bg1: "#ebdbb2", bg2: "#d5c4a1",
        fg: "#3c3836", fg_dim: "#7c6f64", gray: "#928374",
        blue: "#076678", aqua: "#427b58", purple: "#8f3f71",
        yellow: "#b57614", red: "#9d0006", orange: "#af3a03",
        terminal: [
            "#fbf1c7", "#cc241d", "#98971a", "#d79921",
            "#458588", "#b16286", "#689d6a", "#7c6f64",
            "#928374", "#9d0006", "#79740e", "#b57614",
            "#076678", "#8f3f71", "#427b58", "#3c3836",
        ],
    }
}

// ─────────────────────────────────────────────────────────────────
// Gruvbox Material palettes
// ─────────────────────────────────────────────────────────────────

fn gruvbox_material_dark(contrast: Contrast) -> Palette {
    let (bg, bg_dim) = match contrast {
        Contrast::Hard => ("#1d2021", "#1d2021"),
        Contrast::Medium => ("#282828", "#1d2021"),
        Contrast::Soft => ("#32302f", "#282828"),
    };
    Palette {
        bg, bg_dim,
        bg1: "#32302f", bg2: "#45403d",
        fg: "#d4be98", fg_dim: "#a89984", gray: "#928374",
        blue: "#7daea3", aqua: "#89b482", purple: "#d3869b",
        yellow: "#d8a657", red: "#ea6962", orange: "#e78a4e",
        terminal: [
            "#282828", "#ea6962", "#a9b665", "#d8a657",
            "#7daea3", "#d3869b", "#89b482", "#d4be98",
            "#928374", "#ea6962", "#a9b665", "#d8a657",
            "#7daea3", "#d3869b", "#89b482", "#d4be98",
        ],
    }
}

fn gruvbox_material_light(contrast: Contrast) -> Palette {
    let (bg, bg_dim) = match contrast {
        Contrast::Hard => ("#f9f5d7", "#e5d5ad"),
        Contrast::Medium => ("#fbf1c7", "#ebdbb2"),
        Contrast::Soft => ("#f2e5bc", "#d5c4a1"),
    };
    Palette {
        bg, bg_dim,
        bg1: "#f4e8be", bg2: "#e5d5ad",
        fg: "#654735", fg_dim: "#a89984", gray: "#928374",
        blue: "#45707a", aqua: "#4c7a5d", purple: "#945e80",
        yellow: "#b47109", red: "#c14a4a", orange: "#c35e0a",
        terminal: [
            "#fbf1c7", "#c14a4a", "#6c782e", "#b47109",
            "#45707a", "#945e80", "#4c7a5d", "#654735",
            "#928374", "#c14a4a", "#6c782e", "#b47109",
            "#45707a", "#945e80", "#4c7a5d", "#654735",
        ],
    }
}
