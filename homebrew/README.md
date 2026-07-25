# johnfoland/homebrew-tap

Homebrew tap for my macOS apps.

```bash
brew tap johnfoland/tap
brew install --cask claudebar
```

## ClaudeBar

A menu bar app that monitors AI coding assistant usage quotas — Claude, Codex,
Gemini, Copilot and others. This is a build of
[my fork](https://github.com/johnfoland/ClaudeBar) of
[tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar).

### If the app won't open

Unless the release was signed with a Developer ID and notarized, macOS
Gatekeeper will block it, because Homebrew quarantines what it installs.
Install it without the quarantine flag:

```bash
brew install --cask --no-quarantine claudebar
```

If you already installed it and macOS says the app "is damaged" or "cannot be
opened", clear the flag in place:

```bash
xattr -dr com.apple.quarantine /Applications/ClaudeBar.app
```

### Updating

```bash
brew upgrade --cask claudebar
```

Sparkle's built-in updater is switched off in fork builds — the bundled appcast
points at upstream's releases and would otherwise replace the fork build with a
stock one. Homebrew is the update path.

### Uninstalling

```bash
brew uninstall --cask claudebar          # remove the app
brew uninstall --zap --cask claudebar    # also remove settings, logs and caches
```

## How this tap stays current

`.github/workflows/update-cask.yml` checks hourly for a new `fork-v*` release in
`johnfoland/ClaudeBar`, downloads the asset, hashes it, and commits the new
`version` and `sha256`. It needs no secrets — polling from this side means the
built-in `GITHUB_TOKEN` is enough.
