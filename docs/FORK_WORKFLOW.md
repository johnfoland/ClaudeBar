# Fork Workflow

How to keep this fork (`johnfoland/ClaudeBar`) current with upstream
(`tddworks/ClaudeBar`) while carrying your own edits, and how to build the app
after changing it.

Upstream is active — roughly a release a week, dozens of merged PRs a month —
so "sync occasionally and hope" turns into a painful merge fast. The setup
below keeps each sync boring.

## What runs by itself

Most of this is automated. In the normal case upstream lands on `mine`
overnight and you never touch it.

| When | What happens | Where |
|------|--------------|-------|
| Daily, 06:00 UTC | `main` fast-forwards to upstream | `sync-upstream.yml` (job 1) |
| ...then | `main` merges into `mine`, gets built and tested, and is pushed **only if green** | `sync-upstream.yml` (job 2) |
| ...if it conflicts or fails | A pull request opens instead; `mine` is left alone | `sync-upstream.yml` |
| Push / PR to `mine` | Build + test on macOS | `fork-ci.yml` |
| After a merge or checkout | Warns you when Tuist inputs changed and your Xcode project is stale | `scripts/hooks/` |

What is deliberately *not* automated: resolving conflicts, and pushing a merge
that fails to build. Both mean an upstream change collided with something of
yours, and both want eyes on them.

You get a GitHub notification when the sync opens a PR. If you'd rather be
notified on every run, watch the repo's Actions.

---

## 1. The branch model

The single idea that prevents big merges: **never edit the branch that tracks
upstream.**

| Branch | Contents | Rule |
|--------|----------|------|
| `main` | Byte-for-byte mirror of `upstream/main` | Never commit here. It only ever fast-forwards, so it can never conflict. |
| `mine` | Your customizations, branched from `main` | All your work goes here. Upstream lands here via merge. |

Because `main` is untouched, `git diff main..mine` is *exactly* your fork's
patch set — at any moment you can see the complete list of things you've
changed. Keeping that list small is the whole game.

"Never edit `main`" includes fork *tooling* — this document, the scripts, and
the sync workflow all live on `mine`, not on `main`. Anything committed to
`main` breaks the fast-forward and the sync script will refuse to run (with
instructions for recovering).

### One-time setup

```bash
git remote add upstream https://github.com/tddworks/ClaudeBar.git
git fetch upstream main

# Park your work on its own branch
git checkout -b mine main
git push -u origin mine

# Remember conflict resolutions so repeated syncs stop re-asking
git config rerere.enabled true
git config rerere.autoupdate true

# Install the repo's git hooks (once per clone)
./scripts/install-hooks.sh
```

Then **set `mine` as the default branch** in GitHub → Settings → General →
Default branch. This isn't cosmetic: GitHub only runs scheduled workflows from
the default branch, so `sync-upstream.yml` will never fire on its own unless
`mine` is the default. It also makes the repo home page show your version, and
points new clones and PRs at the right branch.

---

## 2. Syncing

### The command

```bash
./scripts/sync-upstream.sh
```

That script does the whole dance:

1. fetches `upstream`,
2. fast-forwards `main` and pushes it,
3. merges `main` into `mine`,
4. prints your patch set (`git diff --stat main..mine`).

Useful flags:

| Flag | Effect |
|------|--------|
| `-b <branch>` | Use a different work branch (default `mine`) |
| `--mirror-only` | Update `main` only; don't touch your work branch |
| `--rebase` | Replay your commits on top of upstream instead of merging |
| `--no-push` | Do everything locally, push nothing |

### By hand, if you prefer

```bash
git fetch upstream main
git checkout main && git merge --ff-only upstream/main && git push origin main
git checkout mine && git merge main
```

### Automatically

`.github/workflows/sync-upstream.yml` does the whole thing nightly, in two
jobs:

**Job 1 — `mirror`** (Linux, ~20s) fast-forwards `main` to upstream. It is
fast-forward-only: if `main` has somehow acquired commits of its own it fails
loudly rather than rewriting anything.

**Job 2 — `integrate`** (macOS, ~15 min) runs only when job 1 actually moved.
It merges `main` into `mine`, then:

| Outcome | Result |
|---------|--------|
| Merges clean, builds, tests pass | Pushed straight to `mine`. Nothing for you to do. |
| Merge conflicts | Nothing pushed. Opens a PR `main` → `mine` listing the conflicting files. |
| Merges clean but build/tests fail | Nothing pushed. Opens a PR explaining that upstream collided with your changes semantically. |

That third case is why the macOS job exists at all. A merge that produces no
conflict markers can still be broken — upstream renames a protocol method your
custom provider implements, git merges both sides happily, and the result
doesn't compile. Only a build catches that.

The PR is reused rather than duplicated: if the sync fails two nights running,
the same PR is updated.

Run it on demand from **Actions → Sync Fork with Upstream → Run workflow**,
which also offers two options:

- **force_integrate** — run the merge/test job even when upstream had nothing
  new (useful right after you push your own changes to `mine`).
- **skip_tests** — push a clean merge without building. Faster, less safe.

The workflow file lives on `mine`, and the nightly schedule runs only because
`mine` is the default branch (see §1) — GitHub schedules workflows from the
default branch only.

GitHub also offers a **Sync fork** button on the repo page, and `gh repo sync
johnfoland/ClaudeBar --branch main` from the CLI. Both do the same
fast-forward as job 1, without the merge into `mine`.

### How often

The nightly job mostly answers this for you. When you do sync by hand, sync
**before** you start a change, not after: merging a week of upstream into a
clean tree is trivial, merging it into three days of your own half-finished
work is not.

---

## 3. Keeping conflicts small

Git conflicts only where two sides changed the *same lines*. So the goal is to
touch as few upstream lines as possible.

### Prefer adding files over editing them

ClaudeBar is unusually friendly here — it has real extension points, and using
them turns a "modify a shared file" change into a "new file plus one line"
change:

| Want to... | Additive approach | Upstream lines touched |
|-----------|-------------------|------------------------|
| New theme | New `Sources/App/Theme/Themes/MyTheme.swift` | 2 (registry + `ThemeMode` enum) |
| New provider | New probe + provider class | 1 (providers array in `ClaudeBarApp.init()`) |
| New report card | Follow the `DailyUsage` pattern | 1–2 |
| Change a setting's default | Edit `~/.claudebar/settings.json` at runtime | 0 |

The `.claude/skills/` in this repo (`add-provider`, `add-report`,
`implement-feature`) walk through each of those.

### Know the hot files

Most-changed files upstream over the last 200 commits — every line you add to
one of these is a line likely to conflict:

```
CHANGELOG.md            33   ← never edit this in a fork
SettingsView.swift      12
MenuContentView.swift   12
ClaudeBarApp.swift      12
ClaudeAPIUsageProbe     11
UsageQuota.swift         8
AppSettings.swift        8
README.md                7
```

`Sources/App/Info.plist` is rewritten on every upstream release (the version
bump), so avoid editing it too — see the Sparkle note in §4 for the one thing
you'd be tempted to change there.

### Habits that pay off

- **One commit per customization**, with a recognizable prefix:
  `fork: dark theme accent`, `fork: hide Bedrock card`. You can then list your
  fork's contents with `git log --oneline main..mine`, and drop a change
  upstream later adopted with a single `git revert`.
- **Never reformat, reorder, or rename** upstream code. A whitespace pass
  across a file conflicts with every future upstream edit to that file.
- **Append, don't insert.** Adding at the end of an array or enum conflicts far
  less often than adding in the middle.
- **Delete nothing you don't have to.** Hiding a provider via its
  `isEnabled` setting beats deleting its code.
- **Drop customizations that upstream absorbs.** If a feature you patched in
  arrives upstream, revert your commit rather than merging around it forever.
- **Consider upstreaming.** Anything not personal to you is worth a PR to
  `tddworks/ClaudeBar` — merged upstream means zero maintenance for you.

### When a conflict does happen

```bash
git status                     # which files
git diff                       # <<<<<<< HEAD is yours, >>>>>>> main is upstream
# edit, keeping upstream's change plus your intent
git add <file>
git commit                     # or: git merge --abort to back out entirely
```

Nothing is lost while a merge is in progress, and `git merge --abort` always
returns you to where you started. With `rerere` enabled (the setup above), the
next sync replays the same resolution automatically.

After resolving, always build and run the tests before pushing — a merge that
compiles cleanly can still be semantically wrong.

---

## 4. Building your fork

The Xcode project is **generated by Tuist and git-ignored**, so a fresh clone
has no `.xcodeproj`/`.xcworkspace`. It must be regenerated after any sync that
touches `Project.swift` or `Tuist/Package.swift` — which is the usual cause of
"it built yesterday and doesn't today".

### Prerequisites

```bash
brew install --cask tuist      # project generation
brew install xcodesorg/made/xcodes  # optional: manage Xcode from the CLI
xcodes install --latest        # or install Xcode from the App Store
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
```

Xcode.app has to be installed even if you never open it — the Command Line
Tools alone don't provide the macOS SDK, the Swift macro toolchain, or
`xcodebuild archive`. `dev-build.sh` checks this up front and tells you if
`xcode-select` is pointing at the wrong place, rather than failing halfway
through a build.

Everything below is command line only. `--open` is there if you ever want the
GUI, and nothing else needs it.

### The command

```bash
./scripts/dev-build.sh            # generate + Debug build (quick sanity check)
./scripts/dev-build.sh --open     # generate + open the workspace in Xcode
./scripts/dev-build.sh --test     # generate + run the full test suite
./scripts/dev-build.sh --install  # Release build -> /Applications/ClaudeBar.app
./scripts/dev-build.sh --clean …  # wipe generated project + derived data first
```

Underneath it is just the sequence CI runs:

```bash
tuist install                    # resolve SPM dependencies
tuist generate --no-open         # write ClaudeBar.xcworkspace
./scripts/fix-swiftterm-metal.sh # workaround for tuist/tuist#9111
xcodebuild build -scheme ClaudeBar -workspace ClaudeBar.xcworkspace \
  -destination 'platform=macOS,arch=arm64'
```

The `fix-swiftterm-metal.sh` step is not optional — without it the build fails
with "Unexpected duplicate tasks" on SwiftTerm's `Shaders.metal`.

### Day-to-day loop

```bash
git pull                          # the nightly sync already merged upstream
./scripts/dev-build.sh --open     # then ⌘R / ⌘U inside Xcode
```

Xcode is the better inner loop once the project is generated; the script is for
after a sync, after a `Project.swift` change, or when you want a clean
verification from the terminal.

### The stale-project trap (and the hook that catches it)

The single most confusing failure in a Tuist project: you pull, the build
breaks, and nothing you changed is at fault. What happened is that upstream
edited `Project.swift` or `Tuist/Package.swift` — added a target, bumped a
dependency — and your generated `.xcworkspace` still describes the old shape.

`./scripts/install-hooks.sh` (once per clone) installs `post-merge` and
`post-checkout` hooks that notice exactly this and tell you:

```
┌──────────────────────────────────────────────────────────────┐
│ Tuist inputs changed — your Xcode project is stale.          │
└──────────────────────────────────────────────────────────────┘
```

To skip the message and just have it regenerate, put this in your shell
profile:

```bash
export CLAUDEBAR_AUTO_GENERATE=1
```

The hooks live in `scripts/hooks/` and are wired up with `core.hooksPath`, so
they're version-controlled rather than hidden in `.git/hooks`. That does mean
any hooks you already had in `.git/hooks` stop running — `install-hooks.sh`
warns you if it finds some, and `--remove` puts things back.

### Verification on GitHub

`fork-ci.yml` runs the test suite and a Release build on every push and PR to
`mine`. Upstream's `build.yml`/`tests.yml` only trigger on `main` and
`develop`, so without it your branch would have no CI. It's deliberately thin —
it just calls `scripts/dev-build.sh`, so CI and your Mac build the app the same
way, and upstream changing its workflow files can't conflict with yours.

### Installing your own build

The whole thing, from nothing to a running menu bar app:

```bash
git clone https://github.com/johnfoland/ClaudeBar.git
cd ClaudeBar
./scripts/install-hooks.sh
./scripts/dev-build.sh --install
```

Roughly 10 minutes the first time (most of it dependency resolution and the
Release compile), a couple of minutes after that. It ends with the app running
in your menu bar.

If you already have the official cask installed, remove it first — its
`/Applications/ClaudeBar.app` is root-owned and can't be overwritten:

```bash
brew uninstall --cask claudebar
```

**Why it archives instead of just building.** The app target sets
`ENABLE_DEBUG_DYLIB=YES` for SwiftUI previews, which makes an ordinary
`xcodebuild build` split the binary and leave a `ClaudeBar.debug.dylib` inside
the bundle. That runs from Xcode but isn't a real app bundle. `--install` uses
`xcodebuild archive` — an install-action build, which drops the preview
scaffolding — and mirrors the invocation in upstream's `release.yml`. The
script asserts the debug dylib is gone before installing.

It then:

- **stamps the version** as `<upstream-version>-fork.<sha>`, so `About` tells
  you exactly which commit you're running;
- **turns off Sparkle's automatic update check** in the installed bundle;
- **signs ad-hoc** — nested code first, then the top level with the app's
  entitlements, and verifies with `codesign --verify --strict`.

The Sparkle part matters. ClaudeBar ships pointed at
`tddworks.github.io/ClaudeBar/appcast.xml`, and the version in
`Sources/App/Info.plist` is only bumped by the release workflow — so an
unpatched local build reports `1.0.0`, sees any official release as "newer",
and offers to replace your fork with stock ClaudeBar. The script patches the
*built bundle* rather than `Info.plist`, so your diff against upstream stays
empty there.

To update later:

```bash
git pull && ./scripts/dev-build.sh --install
```

**Ad-hoc signing caveat:** Gatekeeper is fine with this — the app was built
locally, never downloaded, so there's no quarantine flag to clear. The one
thing that may not work is *Launch at Login*: it uses `SMAppService`, which
sometimes rejects ad-hoc signatures. If that toggle doesn't stick, this is why,
and the fix is a real Developer ID certificate rather than anything in the
code.

### Getting a build without building

`fork-ci.yml` packages the app on every push to `mine` and uploads it as a
workflow artifact:

```bash
gh run download --repo johnfoland/ClaudeBar --name "ClaudeBar-<sha>"
unzip ClaudeBar-*.zip -d /Applications/
```

Useful from a Mac without the toolchain installed. Artifacts are kept 14 days.

Note that a *downloaded* zip does carry the quarantine flag, so you'd need
`xattr -dr com.apple.quarantine /Applications/ClaudeBar.app` — which
`--install` handles for you on a local build.

### Toward a Homebrew tap

`./scripts/dev-build.sh --zip` produces exactly what a cask consumes — a
`ditto`-archived bundle plus its sha256:

```bash
./scripts/dev-build.sh --zip --universal
# .build/ClaudeBar-0.4.73-fork.abc1234.zip
#     sha256: 9f2c...
```

`--universal` builds arm64 + x86_64, which only matters if you'd install on an
Intel Mac as well.

What's still missing for a working tap is a stable download URL, which means
GitHub Releases on this fork: a workflow that tags, archives, and uploads the
zip, and a `homebrew-tap` repo whose cask points at the release asset with
`version` and `sha256`. That's a self-contained piece of work — none of it
changes anything above.

### Inherited CI

Your fork also inherited upstream's workflows. `build.yml` and `tests.yml` run
fine on pushes and are worth keeping — free verification on macOS runners.
`release.yml` and `appstore-release.yml` will fail without upstream's signing
certificate, notarization API key, and Sparkle private key; disable them under
**Actions → workflow → ⋯ → Disable workflow** unless you're setting up your own
signing identity.

---

## 5. Quick reference

```bash
# Once per clone
./scripts/install-hooks.sh                 # stale-project warnings

# Sync (the nightly workflow usually does this for you)
./scripts/sync-upstream.sh                 # mirror main, merge into mine
./scripts/sync-upstream.sh --mirror-only   # update main only

# Inspect your fork
git log --oneline main..mine               # your commits
git diff --stat main..mine                 # your changed files
git log --oneline mine..main               # upstream commits you haven't merged

# Build
./scripts/dev-build.sh                     # quick Debug build
./scripts/dev-build.sh --test              # verify
./scripts/dev-build.sh --install           # archive + install to /Applications
./scripts/dev-build.sh --zip --universal   # archive -> zip + sha256 (for a cask)
./scripts/dev-build.sh --open              # ...if you do want Xcode

# Escape hatches
git merge --abort                          # back out an in-progress merge
git checkout main -- <file>                # take upstream's version of a file
git reset --hard upstream/main             # (on main only) restore the mirror
```

## 6. Files this fork owns

Everything the fork adds is a new file, so the diff against upstream stays
additive and nothing here can conflict on a sync:

```
docs/FORK_WORKFLOW.md               this document
scripts/sync-upstream.sh            manual sync
scripts/dev-build.sh                generate / build / test / install
scripts/install-hooks.sh            hook installer
scripts/hooks/                      post-merge, post-checkout, drift check
.github/workflows/sync-upstream.yml nightly mirror + integrate
.github/workflows/fork-ci.yml       CI for the mine branch
```

The one exception is a short **Fork Maintenance** section appended to
`CLAUDE.md`, so Claude Code sessions in this repo know the branch model. That
file changes upstream about once every 75 commits, and the section is at the
end, so the conflict risk is small — but it is the one file to watch.
