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

  # Homebrew quarantines what it installs, and Gatekeeper answers a quarantined
  # app with no Developer ID signature by offering to move it to the Bin — with
  # "Move to Bin" as the *default* button. Fork releases are ad-hoc signed, so
  # the attribute has to be gone before the app is ever launched, or the first
  # run ends with the app in the Trash.
  #
  # This runs in `preflight`, not `postflight`, and that is the whole point.
  # Homebrew applies quarantine to the *staged* copy in the Caskroom (see
  # Quarantine.propagate, called at the end of Installer#stage), and preflight
  # is the first artifact to run afterwards — before the `app` stanza moves the
  # bundle into /Applications. Clearing it there needs nothing but write access
  # to Homebrew's own cache.
  #
  # Clearing it in postflight, which is what this cask used to do, targets the
  # bundle after it has landed in /Applications. macOS 14+ gates modifying an
  # installed app bundle behind the App Management (TCC) permission, which the
  # calling terminal has usually not been granted — Homebrew documents exactly
  # this in Cask::Staged#set_ownership. So the xattr call failed with
  # "Operation not permitted", `must_succeed: false` swallowed it, and the
  # install reported success while leaving an app macOS would offer to throw
  # away on first launch.
  #
  # `command.run` rather than `system_command`: the latter goes through
  # SystemCommand.run!, which raises on a non-zero exit. `xattr -dr` exits
  # non-zero for any file that does not carry the attribute — symlinks, which
  # Quarantine.propagate skips, and every file at all once releases are
  # notarized or when installing with HOMEBREW_CASK_OPTS=--no-quarantine. That
  # would turn a no-op into a failed install. `run` defaults to
  # must_succeed: false; stated explicitly so the tolerance is deliberate.
  preflight do
    command.run "/usr/bin/xattr",
                args:         ["-dr", "com.apple.quarantine", "#{staged_path}/ClaudeBar.app"],
                must_succeed: false
  end

  # Belt and braces: the launched bundle is the one in /Applications, so verify
  # it there. Gatekeeper keys the launch decision off the attribute on the app
  # bundle itself, so checking the root is the check that matters.
  #
  # If it is somehow still quarantined, try once more (harmless when preflight
  # already did the work) and fail the install with instructions rather than
  # hand over an app whose first run offers to trash it. Preflight has run and
  # the artifacts are installed by this point, so Homebrew unwinds them for us.
  postflight do
    installed_app = "#{appdir}/ClaudeBar.app"

    quarantined = lambda do
      command.run("/usr/bin/xattr",
                  args:         ["-p", "com.apple.quarantine", installed_app],
                  print_stderr: false,
                  must_succeed: false).success?
    end

    next unless quarantined.call

    command.run "/usr/bin/xattr",
                args:         ["-dr", "com.apple.quarantine", installed_app],
                must_succeed: false

    next unless quarantined.call

    raise Cask::CaskError, <<~ERROR
      Could not clear the quarantine attribute from #{installed_app}.

      Fork builds are ad-hoc signed rather than notarized, so macOS would meet
      the first launch with "ClaudeBar is damaged and can't be opened" and a
      default button that moves the app to the Bin.

      This usually means your terminal lacks App Management permission. Grant it
      in System Settings -> Privacy & Security -> App Management, then run:

        brew reinstall --cask johnfoland/tap/claudebar

      Or clear the attribute yourself and skip it on future installs:

        xattr -dr com.apple.quarantine #{installed_app}
        HOMEBREW_CASK_OPTS=--no-quarantine brew reinstall --cask johnfoland/tap/claudebar
    ERROR
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
