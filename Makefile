.PHONY: help check check-public test build install

help:
	@echo "make check-public  Fail if the tracked tree mentions anything private"
	@echo "make test          Run the theme-manager test suite"
	@echo "make build         Build theme-manager (release)"
	@echo "make check         check-public + test"
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

test:
	@cd theme-manager && cargo test --release

build:
	@cd theme-manager && cargo build --release

check: check-public test

install:
	@./install.sh
