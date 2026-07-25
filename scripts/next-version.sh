#!/usr/bin/env bash
# Print the version the next fork release should carry.
#
# Usage:
#   ./scripts/next-version.sh                      # asks GitHub for existing tags
#   ./scripts/next-version.sh --tags-from FILE     # reads tags from FILE, one per line
#
# The scheme is <upstream-version>-fork.<n>:
#
#   * <upstream-version> comes from the newest `## [x.y.z]` heading in
#     CHANGELOG.md — the same source dev-build.sh stamps local builds from — so
#     a fork release always advertises which upstream release it is built on.
#   * <n> is one higher than the highest existing release for that same upstream
#     version, or 1 if there is none.
#
# The reset falls out for free: when an upstream sync bumps CHANGELOG.md to
# 0.4.74, no fork-v0.4.74-fork.* tags exist yet, so the next release is
# 0.4.74-fork.1 rather than continuing 0.4.73's numbering.
#
# Homebrew orders these correctly. `Version` tokenizes 0.4.73-fork.2 as
# [0, 4, 73, "fork", 2] and compares NumericTokens by integer value, so
# fork.10 sorts above fork.9 rather than below it as a string compare would.
#
# --tags-from exists so this is testable without a network round trip.

set -euo pipefail

TAGS_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --tags-from) TAGS_FILE="${2:-}"; shift 2 ;;
        -h|--help)   sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$(git rev-parse --show-toplevel)"

UPSTREAM="$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' CHANGELOG.md | head -1)"
if [ -z "$UPSTREAM" ]; then
    echo "Could not read an upstream version from CHANGELOG.md." >&2
    exit 1
fi

if [ -n "$TAGS_FILE" ]; then
    TAGS="$(cat "$TAGS_FILE")"
else
    command -v gh >/dev/null 2>&1 || { echo "The GitHub CLI is required." >&2; exit 1; }
    TAGS="$(gh release list \
        --repo "${GITHUB_REPOSITORY:-johnfoland/ClaudeBar}" \
        --limit 100 \
        --json tagName \
        --jq '.[].tagName')"
fi

# The upstream version goes into a regex, and it is full of dots — escape them
# so 0.4.73 cannot also match a tag like 0X4X73.
UPSTREAM_RE="$(printf '%s' "$UPSTREAM" | sed 's/\./\\./g')"

# Only exact `fork-v<upstream>-fork.<digits>` tags count. Anything hand-made in
# another shape is ignored rather than crashing the arithmetic.
#
# The `|| true` is load-bearing: grep exits 1 when nothing matches, and under
# `set -o pipefail` that would abort the script in exactly the case that has to
# work — the first release for a given upstream version, where no tag exists yet.
MATCHES="$(printf '%s\n' "$TAGS" | grep -E "^fork-v${UPSTREAM_RE}-fork\.[0-9]+$" || true)"

LAST="$(printf '%s\n' "$MATCHES" | sed 's/.*-fork\.//' | sort -n | tail -1)"

printf '%s-fork.%d\n' "$UPSTREAM" "$(( ${LAST:-0} + 1 ))"
