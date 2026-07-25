cask "claudebar" do
  # version/sha256 are rewritten by .github/workflows/update-cask.yml whenever a
  # new fork-v* release is published. Editing them by hand is fine too.
  #
  # The seed values below are deliberately not installable: an all-zero digest
  # fails the checksum comparison rather than skipping it, so a tap published
  # before its first release refuses to install instead of installing something
  # unverified. scripts/bootstrap-tap.sh fills in the real values.
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/johnfoland/ClaudeBar/releases/download/fork-v#{version}/ClaudeBar-#{version}.zip",
      verified: "github.com/johnfoland/ClaudeBar/"
  name "ClaudeBar"
  desc "Menu bar app that monitors AI coding assistant usage quotas"
  homepage "https://github.com/johnfoland/ClaudeBar"

  # Releases are tagged fork-v<version> to stay clear of upstream's v* tags, so
  # the default version regex would not match.
  livecheck do
    url :url
    strategy :github_latest
    regex(/^fork[._-]v?(.+)$/i)
  end

  # Project.swift sets a macOS 15.0 deployment target.
  depends_on macos: ">= :sequoia"

  app "ClaudeBar.app"

  # Homebrew quarantines what it installs, and Gatekeeper refuses to open a
  # quarantined app that is not Developer ID signed and notarized. Fork releases
  # are ad-hoc signed, so clear the attribute here rather than making every
  # install carry HOMEBREW_CASK_OPTS=--no-quarantine.
  #
  # `command.run` rather than `system_command`: the latter goes through
  # SystemCommand.run!, which raises on a non-zero exit. `xattr -d` can exit
  # non-zero when the attribute is not there — which is exactly what happens
  # once releases are notarized — and that would turn a no-op into a failed
  # install. `run` defaults to must_succeed: false; stated explicitly here so
  # the tolerance is deliberate rather than incidental.
  postflight do
    command.run "/usr/bin/xattr",
                args:         ["-dr", "com.apple.quarantine", "#{appdir}/ClaudeBar.app"],
                must_succeed: false
  end

  # ~/.claudebar holds settings.json plus imported themes and extensions.
  zap trash: [
    "~/.claudebar",
    "~/Library/Caches/com.tddworks.claudebar",
    "~/Library/HTTPStorages/com.tddworks.claudebar",
    "~/Library/Logs/ClaudeBar",
    "~/Library/Preferences/com.tddworks.claudebar.plist",
  ]

  caveats <<~EOS
    ClaudeBar runs as a menu bar app with no Dock icon — look for its icon in
    the menu bar after launching it.

    Fork builds have Sparkle's automatic update check disabled, because the
    bundled appcast points at upstream tddworks releases and would otherwise
    replace this build with a stock one. Update through Homebrew instead:

      brew upgrade --cask johnfoland/tap/claudebar
  EOS
end
