# Fork Workflow

How to keep this fork (`johnfoland/ClaudeBar`) current with upstream
(`tddworks/ClaudeBar`) while carrying your own edits, and how to build the app
after changing it.

Upstream is active — roughly a release a week, dozens of merged PRs a month —
so "sync occasionally and hope" turns into a painful merge fast. The setup
below keeps each sync boring.

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

`.github/workflows/sync-upstream.yml` fast-forwards `main` daily at 06:00 UTC
(and on demand from the Actions tab), so the mirror is current before you sit
down. It never touches `mine` — merging upstream into your work belongs on a
machine where you can build and test the result.

The workflow file lives on `mine`, and the schedule only runs if `mine` is your
default branch (see §1). Until then, trigger it manually from the Actions tab.

GitHub also offers a **Sync fork** button on the repo page, and `gh repo sync
johnfoland/ClaudeBar --branch main` from the CLI. Both do the same
fast-forward; the workflow just removes the need to remember.

### How often

Sync **before** you start a change, not after. Merging a week of upstream into
a clean tree is trivial; merging it into three days of your own half-finished
work is not. Weekly is a good rhythm for this repo.

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
# plus Xcode from the App Store (macOS 15+ deployment target, Swift 6.2)
```

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
./scripts/sync-upstream.sh        # weekly, or before starting work
./scripts/dev-build.sh --open     # then ⌘R / ⌘U inside Xcode
```

Xcode is the better inner loop once the project is generated; the script is for
after a sync, after a `Project.swift` change, or when you want a clean
verification from the terminal.

### Installing your own build

`--install` builds Release, copies the app to `/Applications`, and:

- **stamps the version** as `<upstream-version>-fork.<sha>` so you can tell your
  build apart from an official one in the About box;
- **turns off Sparkle's automatic update check** in the installed bundle.

That second one matters. ClaudeBar ships with Sparkle pointed at
`tddworks.github.io/ClaudeBar/appcast.xml`, and the version in
`Sources/App/Info.plist` is only bumped by the release workflow — so a local
build reports `1.0.0`, sees an official release as "newer", and offers to
replace your fork with stock ClaudeBar. The script patches the *built bundle*
rather than `Info.plist` so your diff against upstream stays empty there.

If you'd rather keep official updates and lose your changes on each one, delete
the `SUEnableAutomaticChecks` line from `scripts/dev-build.sh`.

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
# Sync
./scripts/sync-upstream.sh                 # mirror main, merge into mine
./scripts/sync-upstream.sh --mirror-only   # update main only

# Inspect your fork
git log --oneline main..mine               # your commits
git diff --stat main..mine                 # your changed files
git log --oneline mine..main               # upstream commits you haven't merged

# Build
./scripts/dev-build.sh --open              # work in Xcode
./scripts/dev-build.sh --test              # verify
./scripts/dev-build.sh --install           # ship it to /Applications

# Escape hatches
git merge --abort                          # back out an in-progress merge
git checkout main -- <file>                # take upstream's version of a file
git reset --hard upstream/main             # (on main only) restore the mirror
```
