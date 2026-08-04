#!/usr/bin/env bash
set -uo pipefail

# ─────────────────────────────────────────────────────────────────
# Publish the sanitized tree to the public dotfiles repo.
#
#   ./publish.sh [--push] [remote-url]
#
# Why a separate clone rather than pushing this repo:
#
# This working repo's HISTORY contains employer-internal content in its
# initial snapshot commit (older versions of zshrc and the nvim modules, from
# before they moved into site/). The working TREE is clean, but a push
# publishes history, not the tree. So instead we copy exactly the files git
# tracks here into a clone of the public repo and commit that. The public
# repo's history therefore only ever sees sanitized content.
#
# Refuses to do anything if `make check-public` fails.
# Never force-pushes. Without --push it stops after committing locally so you
# can inspect the result.
# ─────────────────────────────────────────────────────────────────

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${PUBLISH_WORKDIR:-$HOME/.config-publish}"
REMOTE_DEFAULT="https://github.com/MowMowchow/configs.git"

DO_PUSH=0
REMOTE=""
for arg in "$@"; do
  case "$arg" in
    --push) DO_PUSH=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) REMOTE="$arg" ;;
  esac
done
REMOTE="${REMOTE:-$REMOTE_DEFAULT}"

info() { printf "\033[1;34m==> %s\033[0m\n" "$1"; }
ok()   { printf "\033[1;32m  ✓ %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m  ! %s\033[0m\n" "$1"; }
fail() { printf "\033[1;31m  ✗ %s\033[0m\n" "$1"; }

# ── Gate 1: the tree must be clean of private markers ────────────
info "Checking the tracked tree is publishable"
if ! make -C "$DOTFILES" check-public; then
  fail "refusing to publish"
  exit 1
fi

# ── Gate 2: no uncommitted work, so what we publish is reviewable ─
if [ -n "$(git -C "$DOTFILES" status --porcelain)" ]; then
  warn "working tree has uncommitted changes:"
  git -C "$DOTFILES" status --short | sed 's/^/      /'
  warn "they WILL be published (we copy the working tree, not HEAD)"
fi

# ── Prepare the clone ────────────────────────────────────────────
info "Preparing $WORK"

# The remote's default branch, discovered rather than assumed. Getting this
# wrong lands us on an unborn branch and every commit becomes a new root, which
# then either fails to push or, if forced, replaces the repo's history.
remote_default_branch() {
  local b
  # Preferred: the symbolic ref the clone recorded.
  b="$(git -C "$WORK" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  # Next: ask the remote. Prints "(unknown)" if its HEAD dangles.
  [ -z "$b" ] && b="$(git -C "$WORK" remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')"
  [ "$b" = "(unknown)" ] && b=""
  # Last resort: if there is exactly one remote branch, it is unambiguous.
  if [ -z "$b" ]; then
    local n
    n="$(git -C "$WORK" branch -r --format='%(refname:short)' | grep -v 'origin/HEAD' | wc -l | tr -d ' ')"
    if [ "$n" = "1" ]; then
      b="$(git -C "$WORK" branch -r --format='%(refname:short)' | grep -v 'origin/HEAD' | sed 's|^origin/||')"
    fi
  fi
  printf '%s' "$b"
}

if [ -d "$WORK/.git" ]; then
  git -C "$WORK" remote set-url origin "$REMOTE"
  git -C "$WORK" fetch --quiet --prune origin && ok "fetched" || warn "fetch failed (offline? auth?)"
else
  rm -rf "$WORK"
  if ! git clone "$REMOTE" "$WORK"; then
    fail "clone failed — the repo is private, so this needs GitHub credentials"
    echo
    echo "      credential.helper is already set to osxkeychain, so you only"
    echo "      have to do this once. GitHub does not accept passwords:"
    echo
    echo "        1. Create a token at https://github.com/settings/tokens"
    echo "           (classic, scope: repo)"
    echo "        2. Re-run this script. When git prompts:"
    echo "             Username: your github username"
    echo "             Password: paste the token"
    echo "           The keychain stores it and will not ask again."
    echo
    echo "      Alternative: brew install gh && gh auth login  (browser flow)"
    exit 1
  fi
  ok "cloned $REMOTE"
fi

BRANCH="$(remote_default_branch)"
BRANCH="${BRANCH:-main}"
if ! git -C "$WORK" rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
  fail "remote has no branch '$BRANCH' — cannot determine where to publish"
  git -C "$WORK" branch -r | sed 's/^/      /'
  exit 1
fi
git -C "$WORK" checkout -q -B "$BRANCH" "origin/$BRANCH"
git -C "$WORK" reset --hard --quiet "origin/$BRANCH"
ok "on $BRANCH (at $(git -C "$WORK" rev-parse --short HEAD))"

# ── Copy exactly the files git tracks here ───────────────────────
info "Syncing the sanitized tree"
# The file list comes from `git ls-files`, which by construction excludes
# everything gitignored — i.e. all of site/<private>/. --exclude .git so we
# never touch the target's history.
MANIFEST_DIR="$(mktemp -d)"
trap 'rm -rf "$MANIFEST_DIR"' EXIT
git -C "$DOTFILES" ls-files -z > "$MANIFEST_DIR/manifest0"
tr '\0' '\n' < "$MANIFEST_DIR/manifest0" | sort > "$MANIFEST_DIR/wanted"

rsync -a --exclude '.git' --files-from="$MANIFEST_DIR/wanted" "$DOTFILES/" "$WORK/"

# Prune whatever the source no longer tracks.
#
# This used to be `rsync --delete`, which does nothing here: --delete is
# inert when combined with --files-from, because rsync is transferring an
# explicit list and has no directory tree to diff the destination against.
# The comment claimed deletion; no deletion happened. The public repo had
# therefore kept every file ever removed from this one — 17 of them, among
# them both superseded installers, the old theme scripts, dead
# theme-manager sources, and a .DS_Store — while PUBLISHING.md advertised
# "exactly git ls-files".
( cd "$WORK" && find . -type f -not -path './.git/*' | sed 's|^\./||' | sort ) \
  > "$MANIFEST_DIR/actual"
PRUNED=0
while IFS= read -r stale; do
  [ -n "$stale" ] || continue
  rm -f "$WORK/$stale"
  PRUNED=$((PRUNED + 1))
done < <(comm -23 "$MANIFEST_DIR/actual" "$MANIFEST_DIR/wanted")
# Directories git never tracked, only their contents; drop any left empty.
find "$WORK" -mindepth 1 -type d -not -path "$WORK/.git/*" -not -path "$WORK/.git" \
     -empty -delete 2>/dev/null || true

ok "$(wc -l < "$MANIFEST_DIR/wanted" | tr -d ' ') files$([ "$PRUNED" -gt 0 ] && echo ", $PRUNED stale removed")"

# ── Gate 3: re-check the result, not the source ──────────────────
info "Re-checking the published tree"
cd "$WORK"
git add -A
# Run the SAME gate against the staged clone rather than a second copy of the
# patterns. The Makefile is itself published, so the two can never drift — and
# a duplicated pattern list here would match itself anyway. .denylist is
# gitignored (so absent from the clone); pass it through for the check.
[ -f "$DOTFILES/.denylist" ] && cp "$DOTFILES/.denylist" "$WORK/.denylist"
if ! make -C "$WORK" check-public; then
  rm -f "$WORK/.denylist"
  fail "the tree we are about to publish did not pass — NOT committing"
  exit 1
fi
rm -f "$WORK/.denylist"

# ── Show, commit, optionally push ────────────────────────────────
if git diff --cached --quiet; then
  ok "nothing to publish — already up to date"
  exit 0
fi

info "Changes to publish"
git diff --cached --stat | tail -30

git -c user.name="$(git -C "$DOTFILES" config user.name || echo dotfiles)" \
    -c user.email="$(git -C "$DOTFILES" config user.email || echo dotfiles@localhost)" \
    commit -q -m "Sync dotfiles from working tree

Cross-platform (macOS + Ubuntu), site-plugin architecture, theme-manager
performance and correctness fixes. See README.md."
ok "committed in $WORK"

# Never publish something that would not be a fast-forward. If our commit does
# not descend from the remote tip we would be rewriting the public history,
# which is the one thing this script must never do silently.
if ! git merge-base --is-ancestor "origin/$BRANCH" HEAD; then
  fail "HEAD does not descend from origin/$BRANCH — refusing to push"
  echo "      This means the clone was not based on the remote tip."
  echo "      Inspect $WORK before doing anything else."
  exit 1
fi
ok "fast-forward from origin/$BRANCH ($(git rev-list --count "origin/$BRANCH..HEAD") new commit)"

if [ "$DO_PUSH" -eq 1 ]; then
  info "Pushing to $BRANCH"
  git push origin "HEAD:$BRANCH" && ok "published" || { fail "push failed"; exit 1; }
else
  echo
  info "Not pushed (no --push)."
  echo "  Review:  git -C $WORK show --stat"
  echo "  Publish: git -C $WORK push origin HEAD:$BRANCH"
fi
