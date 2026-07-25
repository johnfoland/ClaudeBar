#!/usr/bin/env bash
# Point git at this repo's version-controlled hooks.
#
#   ./scripts/install-hooks.sh          # install
#   ./scripts/install-hooks.sh --remove # uninstall
#
# Uses core.hooksPath rather than copying into .git/hooks, so the hooks stay
# under version control and survive a fresh clone (run this once per clone).
#
# Note: core.hooksPath replaces .git/hooks entirely — any hooks you already have
# there stop running. `--remove` restores the default.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

if [ "${1:-}" = "--remove" ]; then
    git config --unset core.hooksPath 2>/dev/null || true
    info "Hooks uninstalled — git is back to .git/hooks"
    exit 0
fi

existing="$(git config --get core.hooksPath || true)"
if [ -n "$existing" ] && [ "$existing" != "scripts/hooks" ]; then
    printf '\033[1;33m!!\033[0m  core.hooksPath was %s; overwriting.\n' "$existing" >&2
fi

if [ -d .git/hooks ] && [ -n "$(find .git/hooks -type f ! -name '*.sample' 2>/dev/null)" ]; then
    printf '\033[1;33m!!\033[0m  .git/hooks contains hooks that will stop running:\n' >&2
    find .git/hooks -type f ! -name '*.sample' | sed 's/^/      /' >&2
fi

chmod +x scripts/hooks/*
git config core.hooksPath scripts/hooks

info "Installed hooks from scripts/hooks/"
echo "    post-merge     — warns when a sync makes your Xcode project stale"
echo "    post-checkout  — same, on branch switches"
echo
echo "Set CLAUDEBAR_AUTO_GENERATE=1 in your shell profile to regenerate automatically."
