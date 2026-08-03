.PHONY: help check check-public lint-tmux test build install

help:
	@echo "make check-public  Fail if the tracked tree mentions anything private"
	@echo "make lint-tmux     Fail on tmux format strings tmux would silently drop"
	@echo "make test          Run the theme-manager test suite"
	@echo "make build         Build theme-manager (release)"
	@echo "make check         check-public + lint-tmux + test"
	@echo "make install       Run the installer for this platform"

# Markers that must never appear in a tracked file. Add your employer's
# internal hostnames, tool names and path prefixes to .denylist (ignored),
# which is merged with the always-on patterns below.
#
# This is a guard against accidents, not a security control. Two known limits:
#   - it greps the tracked tree only, so it cannot see what is already in git
#     history (use `git log -S<marker>` for that);
#   - it skips this Makefile, which would otherwise match its own patterns.
DENY_BUILTIN := fwdproxy|internal\.example\.com|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|AKIA[0-9A-Z]{16}

check-public:
	@patterns='$(DENY_BUILTIN)'; \
	if [ -f .denylist ]; then \
	  extra=$$(grep -vE '^[[:space:]]*(#|$$)' .denylist | paste -sd'|' -); \
	  [ -n "$$extra" ] && patterns="$$patterns|$$extra"; \
	fi; \
	echo "checking tracked tree against: $$patterns"; \
	hits=$$(git ls-files -z | xargs -0 grep -nIE --exclude=Makefile "$$patterns" 2>/dev/null || true); \
	if [ -n "$$hits" ]; then \
	  echo "$$hits" | sed 's/^/      /'; \
	  echo "FAIL: the tracked tree contains private markers (above)."; \
	  echo "      Move them into site/<name>/ — see site/README.md"; \
	  exit 1; \
	fi; \
	echo "OK: no private markers in tracked files"
	@leaked=$$(git ls-files site/ | grep -vE '^site/(README\.md|example/)' || true); \
	if [ -n "$$leaked" ]; then \
	  echo "FAIL: a site plugin is tracked. Only site/README.md and site/example/ may be:"; \
	  echo "$$leaked" | sed 's/^/      /'; \
	  exit 1; \
	fi; \
	echo "OK: no site plugin is tracked"

# `#{window_name:0:20}` is *shell* substring syntax. tmux has no such format
# modifier, does not warn, and expands the whole thing to "" — so the status
# bar just renders blank and nothing anywhere says why. That shipped unnoticed
# for a long time. tmux's truncation is `#{=20:window_name}`.
#
# The trailing filter drops comment lines: the fix for this bug documents the
# broken syntax in a comment, which would otherwise trip the lint on itself.
lint-tmux:
	@bad=$$(grep -nE '#\{[a-z_]+:[0-9]+:[0-9]+\}' tmux/*.conf 2>/dev/null \
	        | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' || true); \
	if [ -n "$$bad" ]; then \
	  echo "$$bad" | sed 's/^/      /'; \
	  echo "FAIL: shell substring syntax in a tmux format — tmux expands it to \"\"."; \
	  echo "      Use #{=N:var} to truncate."; \
	  exit 1; \
	fi; \
	echo "OK: no shell-substring syntax in tmux formats"

test:
	@cd theme-manager && cargo test --release

build:
	@cd theme-manager && cargo build --release

check: check-public lint-tmux test

install:
	@./install.sh
