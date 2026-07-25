#!/usr/bin/env bash
# Create and populate the Homebrew tap repo from homebrew/ in this repository.
#
# Usage:
#   ./scripts/bootstrap-tap.sh [--dry-run]
#
# A Homebrew tap has to live in a repo named homebrew-<name>: `brew tap
# johnfoland/tap` resolves to github.com/johnfoland/homebrew-tap. This creates
# that repo, copies homebrew/ into it, seeds the cask from the newest published
# release, and pushes.
#
# Safe to re-run. If the repo already exists it updates the working copy in
# place instead of creating anything, so this doubles as "push my local cask
# edits to the tap".
#
# Needs the GitHub CLI, authenticated:  gh auth login

set -euo pipefail

DRY_RUN="no"
[ "${1:-}" = "--dry-run" ] && DRY_RUN="yes"

cd "$(git rev-parse --show-toplevel)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$1" >&2; exit 1; }

# Uses BSD `sed -i ''` and `shasum`, both of which differ on GNU userland.
[ "$(uname -s)" = "Darwin" ] || die "This script assumes a Mac (BSD sed/shasum)."
command -v gh >/dev/null 2>&1 || die "The GitHub CLI is required. Install it with: brew install gh"
gh auth status >/dev/null 2>&1 || die "Not logged in to GitHub. Run: gh auth login"

OWNER="$(gh api user --jq .login)"
TAP_REPO="$OWNER/homebrew-tap"
SOURCE_REPO="$OWNER/ClaudeBar"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Create or clone --------------------------------------------------------

if gh repo view "$TAP_REPO" >/dev/null 2>&1; then
    info "$TAP_REPO already exists — updating it"
    [ "$DRY_RUN" = "yes" ] || gh repo clone "$TAP_REPO" "$WORK/tap" -- --quiet
else
    info "Creating $TAP_REPO"
    if [ "$DRY_RUN" = "yes" ]; then
        echo "    (dry run — would create a public repo and push homebrew/ into it)"
    else
        gh repo create "$TAP_REPO" \
            --public \
            --description "Homebrew tap for $OWNER's macOS apps. brew tap $OWNER/tap"
        git init -q "$WORK/tap"
        git -C "$WORK/tap" remote add origin "https://github.com/$TAP_REPO.git"
    fi
fi

if [ "$DRY_RUN" = "yes" ]; then
    info "Files that would be published to $TAP_REPO:"
    (cd homebrew && find . -type f | sed 's|^\./|    |')
    exit 0
fi

# --- Copy ------------------------------------------------------------------

info "Copying homebrew/ into the tap"
mkdir -p "$WORK/tap"
# -a to carry the dot-directory (.github/) across; a plain glob would skip it.
cp -a homebrew/. "$WORK/tap/"

# --- Seed the cask from the newest release ----------------------------------

CASK="$WORK/tap/Casks/claudebar.rb"

TAG="$(gh release list --repo "$SOURCE_REPO" --limit 20 --json tagName,isDraft,isPrerelease \
    --jq '[.[] | select(.isDraft == false and .isPrerelease == false)
               | select(.tagName | startswith("fork-v"))][0].tagName // ""')"

if [ -z "$TAG" ]; then
    # The placeholder digest in the committed cask is all zeros, so an install
    # attempt fails the checksum rather than silently installing something
    # unverified. Leave it that way until there is a release to point at.
    info "No fork-v* release published yet — leaving the cask's placeholder version in place"
    echo "    Publish one first:  git tag fork-v0.4.73-fork.1 && git push origin fork-v0.4.73-fork.1"
else
    VERSION="${TAG#fork-v}"
    ASSET="ClaudeBar-$VERSION.zip"
    URL="https://github.com/$SOURCE_REPO/releases/download/$TAG/$ASSET"

    info "Seeding the cask from $TAG"
    curl --fail --silent --show-error --location -o "$WORK/$ASSET" "$URL" \
        || die "Release $TAG exists but $ASSET could not be downloaded from it."
    SHA256="$(shasum -a 256 "$WORK/$ASSET" | cut -d' ' -f1)"

    sed -i '' "s|^  version \".*\"$|  version \"$VERSION\"|" "$CASK"
    sed -i '' "s|^  sha256 \".*\"$|  sha256 \"$SHA256\"|" "$CASK"

    echo "    version:  $VERSION"
    echo "    sha256:   $SHA256"
fi

# --- Push -------------------------------------------------------------------

cd "$WORK/tap"
git add -A

if git diff --cached --quiet; then
    info "Tap is already up to date — nothing to push"
    exit 0
fi

git commit -q -m "claudebar: sync cask from ClaudeBar${TAG:+ ($TAG)}"
git branch -M main
git push -u origin main

info "Published $TAP_REPO"
echo
# Fully qualified: upstream ClaudeBar is in homebrew/cask, so a bare
# `claudebar` token resolves to their build rather than this tap's.
echo "    brew install --cask $OWNER/tap/claudebar"
