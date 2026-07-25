#!/usr/bin/env bash
# Package a ClaudeBar build for distribution via GitHub Releases + Homebrew.
#
# Usage:
#   ./scripts/fork-release.sh <version> [extra dev-build.sh flags...]
#
# Example:
#   ./scripts/fork-release.sh 0.4.73-fork.1 --universal
#
# Produces .build/ClaudeBar-<version>.zip and prints the two values a cask
# needs — the version and the sha256. Under GitHub Actions it also appends
# them to $GITHUB_OUTPUT as `version`, `zip`, `sha256` and `notarized`.
#
# Signing is secrets-gated, so this same script covers both worlds:
#
#   CLAUDEBAR_SIGN_IDENTITY unset  ->  ad-hoc signature. Gatekeeper would block
#                                      it, but the cask's preflight clears the
#                                      quarantine attribute on install.
#   CLAUDEBAR_SIGN_IDENTITY set    ->  Developer ID + hardened runtime, and if
#                                      the App Store Connect key is also
#                                      present, notarized and stapled. Installs
#                                      with no warning and no extra flags.
#
# Notarization needs all three of:
#   APP_STORE_CONNECT_API_KEY_P8    the .p8 private key, as text
#   APP_STORE_CONNECT_KEY_ID
#   APP_STORE_CONNECT_ISSUER_ID
#
# The version is stamped into the bundle rather than into Sources/App/Info.plist
# on purpose: that file is rewritten on every upstream release, and keeping the
# fork's diff empty there is what keeps upstream syncs conflict-free.

set -euo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "Usage: $0 <version> [dev-build.sh flags...]" >&2; exit 2; }
shift

cd "$(git rev-parse --show-toplevel)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Releases have to be built on a Mac."

# --- Build ------------------------------------------------------------------

# --stage leaves a signed .build/ClaudeBar.app without archiving it. Stapling
# below rewrites the bundle, so the zip has to come after notarization.
info "Building ClaudeBar $VERSION"
CLAUDEBAR_VERSION="$VERSION" ./scripts/dev-build.sh --stage "$@"

APP="$PWD/.build/ClaudeBar.app"
[ -d "$APP" ] || die "dev-build.sh --stage did not leave $APP behind."

# --- Notarize ---------------------------------------------------------------

NOTARIZED="false"
KEY_P8="${APP_STORE_CONNECT_API_KEY_P8:-}"
KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"

if [ -n "$KEY_P8" ] && [ -n "$KEY_ID" ] && [ -n "$ISSUER_ID" ]; then
    if [ "${CLAUDEBAR_SIGN_IDENTITY:--}" = "-" ]; then
        die "Notarization credentials are set but CLAUDEBAR_SIGN_IDENTITY is not.
    Apple rejects ad-hoc signatures — set a Developer ID identity too, or unset
    the App Store Connect variables to build an ad-hoc release."
    fi

    KEY_FILE="$(mktemp -t claudebar-notary-XXXXXX).p8"
    # The key is a credential: keep it out of the repo, and delete it on every
    # exit path including failure.
    trap 'rm -f "$KEY_FILE"' EXIT
    printf '%s' "$KEY_P8" > "$KEY_FILE"

    # notarytool only accepts an archive, never a bare .app, so this is a
    # throwaway zip — the distributable one is built after stapling.
    SUBMIT_ZIP="$(mktemp -d)/ClaudeBar-notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMIT_ZIP"

    info "Submitting to Apple for notarization (this usually takes 1-5 minutes)"
    xcrun notarytool submit "$SUBMIT_ZIP" \
        --key "$KEY_FILE" \
        --key-id "$KEY_ID" \
        --issuer "$ISSUER_ID" \
        --wait \
        --timeout 30m

    # Staple the ticket into the bundle so Gatekeeper clears it offline, on a
    # machine that has never contacted Apple about this build.
    info "Stapling the notarization ticket"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP" || die "Stapling reported success but validation failed."

    rm -f "$KEY_FILE"
    trap - EXIT
    NOTARIZED="true"
else
    info "No App Store Connect credentials — skipping notarization"
fi

# --- Archive ----------------------------------------------------------------

ZIP="$PWD/.build/ClaudeBar-$VERSION.zip"
rm -f "$ZIP"
# ditto --sequesterRsrc --keepParent is the archiver Apple expects for .app
# bundles; plain `zip` loses symlinks and breaks the signature.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

SHA256="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

info "Wrote $ZIP"
echo "    version:    $VERSION"
echo "    sha256:     $SHA256"
echo "    size:       $(du -h "$ZIP" | cut -f1)"
echo "    notarized:  $NOTARIZED"

if [ "$NOTARIZED" != "true" ]; then
    echo
    echo "    This build is ad-hoc signed. Gatekeeper would block it, but the cask's"
    echo "    preflight clears the quarantine attribute, so installing it is just:"
    echo "        brew install --cask johnfoland/tap/claudebar"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "version=$VERSION"
        echo "zip=$ZIP"
        echo "sha256=$SHA256"
        echo "notarized=$NOTARIZED"
    } >> "$GITHUB_OUTPUT"
fi
