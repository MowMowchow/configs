# Site plugins

A **site plugin** carries configuration that belongs to one employer, machine, or network and
must not live in this repository — internal hostnames, proxy endpoints, certificate paths,
internal tooling, private bootstrap steps.

The boundary is a **process boundary, not a code boundary**. The core never imports, links, or
compiles anything from a plugin; it executes well-known files if they exist and ignores them if
they don't. A plugin can therefore live in a completely separate private repository, be developed
independently, and never mix its source with this project's.

Everything under `site/` is gitignored except this file and `site/example/`.

## Layout

```
site/
├── README.md          # this file (tracked)
├── example/           # reference implementation (tracked, INACTIVE)
└── <name>/            # your plugin (ignored — e.g. site/acme/)
    ├── plugin.toml    # required: declares the API version
    ├── env.sh         # optional: sourced by the shell at startup
    ├── bootstrap.sh   # optional: run once per machine by install.sh
    └── theme-hook     # optional: executable, run after each theme change
```

Discovery is `~/.config/site/*/` — any directory containing a `plugin.toml`. Plugins load in
lexical order. There is no registry and no enable/disable flag: a plugin is active because its
directory is present and has a manifest, which makes "why is this happening" answerable with `ls`.

That is also why `site/example/` ships its manifest as `plugin.toml.template` — a reference
implementation that executed on every theme switch would be a trap. To start from it:

```sh
cp -r site/example site/acme
mv site/acme/plugin.toml.template site/acme/plugin.toml
```

## plugin.toml

```toml
api_version = 1        # required; the core refuses a version it does not speak
name        = "acme"   # required; used in log lines
description = "ACME Corp internal environment"
```

The core speaks `api_version = 1`. A plugin declaring a version the core does not know is skipped
with a warning rather than silently ignored — an old plugin against a new core must fail loudly.

## Hooks

### `env.sh` — shell environment

Sourced by `zshrc` in the interactive shell, early, before Oh My Zsh. Use it for proxy variables,
company shell init, private aliases, and `PATH` entries.

Runs in the shell's own process: it can export variables and define functions, and a syntax error
will break the user's shell. Keep it defensive and fast.

### `bootstrap.sh` — one-time machine setup

Executed by `install.sh` after the platform layer has run. Use it for anything a fresh machine on
your network needs: proxy configuration for package managers, certificate trust, internal
repositories, private tool installation.

Must be idempotent — it may be re-run at any time.

### `theme-hook` — after an appearance change

Executable (not sourced). Invoked by `theme-manager` after the built-in adapters have run:

```
theme-hook <appearance> <family> <variant>
#          dark|light   e.g. gruvbox-material, medium
```

Environment:

| Variable | Meaning |
|---|---|
| `THEME_MANAGER_API` | contract version the core is speaking (`1`) |
| `THEME_MANAGER_CONF` | absolute path to the generated tmux conf for this appearance |
| `THEME_MANAGER_DIR` | the config root (normally `~/.config`) |

Contract:

- **Budget: 2 seconds.** The core kills the hook after that and logs a timeout. This runs on every
  theme switch, on an interactive path — do slow or network-bound work in the background.
- Exit `0` for success. Any other status is logged with the hook's stderr and counted as a failed
  step, but never blocks the other adapters (bulkhead).
- stdout is ignored; stderr is surfaced in the core's log. Log to stderr.
- The hook must be idempotent: it can be called repeatedly with the same arguments.

A typical use is pushing the appearance to remote hosts you are logged into.

## Security

The core executes these files. Before running any of them it checks that the plugin directory and
the file are owned by the current user and are not group- or world-writable, and skips them with a
warning otherwise. This is accident-prevention — the hook runs with your privileges and is not
sandboxed. Do not put a plugin directory somewhere other people can write.

## Keeping a plugin private

Two options:

1. **Plain ignored directory** (recommended). `site/<name>/` is gitignored. Keep it as its own git
   repository if you want history: a nested repo inside an ignored directory is invisible to the
   outer one.
2. **Git submodule** — *not* recommended here. `.gitmodules` is tracked and records the remote
   URL, so the existence and location of your private repo leaks even though its contents do not.

There is a `make check-public` target that greps the tracked tree for a configurable denylist of
internal markers. Run it before pushing; wire it to a pre-commit hook if you want it enforced.
