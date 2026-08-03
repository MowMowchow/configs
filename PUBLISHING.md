# Publishing

```sh
./publish.sh              # stage + commit into a clone, stop for review
./publish.sh --push       # ...and push
```

## Why not just `git push` from here?

This directory is the **private working repo**. Its working tree is clean — `make check-public`
enforces that — but its *history* is not: the initial snapshot commit contains older versions of
`zshrc` and the nvim modules from before that content moved into `site/`.

A push publishes history, not the working tree. So `publish.sh` copies exactly the files git tracks
here into a clone of the public repo and commits that. The public repo's history therefore only
ever contains sanitized content.

A `pre-push` hook in `.git/hooks/` refuses direct pushes from this repo to make the mistake hard.

## What gets published

Exactly `git ls-files` — which by construction excludes everything gitignored, i.e. all of
`site/<private>/`. Of the `site/` tree only `README.md` and `example/` are tracked.

`publish.sh` will not commit if any of these fail:

1. `make check-public` on the source tree
2. a second scan of the *staged clone* — the thing actually being published, not the source
3. no private site plugin present in the publish tree
4. the new commit must be a fast-forward from the remote tip

That last one matters: an earlier version of this script created an orphan commit when the remote's
default branch could not be detected, which would have replaced the public history rather than
adding to it. The script now discovers the default branch three ways and refuses if it cannot.

## First-time setup

The repo is private, so pushing needs credentials — a one-time step.

```sh
# credential.helper is already set to osxkeychain. GitHub does not accept
# passwords, so create a token (classic, scope: repo) at
# https://github.com/settings/tokens and paste it at the Password prompt on
# the first clone — the keychain remembers it afterwards.
#
# Alternative, if you prefer a browser flow:
gh auth login                                    # needs: brew install gh
```

SSH to github.com is blocked from this machine's network; HTTPS through the corp proxy works.

## Adding to the denylist

`make check-public` merges the patterns in `.denylist` (gitignored) with a small builtin set. Add
any new internal hostname, tool name or path prefix there. It greps the tracked tree only — it
cannot see git history, so use `git log -S<marker>` for that.
