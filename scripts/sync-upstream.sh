#!/usr/bin/env bash
# Sync this fork with the upstream repository it was forked from.
#
# Model:
#   main  — a pristine mirror of upstream/main. Never edited locally, so it can
#           always fast-forward and can never conflict.
#   mine  — your long-lived branch holding your customizations. Upstream lands
#           here via a merge (or rebase), so conflicts are limited to the files
#           you actually changed.
#
# Usage:
#   ./scripts/sync-upstream.sh                 # mirror main, then merge it into "mine"
#   ./scripts/sync-upstream.sh -b my-branch    # ...into a different work branch
#   ./scripts/sync-upstream.sh --rebase        # replay your commits on top instead
#   ./scripts/sync-upstream.sh --mirror-only   # just update main, leave work branch alone
#   ./scripts/sync-upstream.sh --no-push       # don't push anything to origin
#
# Environment overrides:
#   UPSTREAM_URL, UPSTREAM_BRANCH, MIRROR_BRANCH, WORK_BRANCH

set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/tddworks/ClaudeBar.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
MIRROR_BRANCH="${MIRROR_BRANCH:-main}"
WORK_BRANCH="${WORK_BRANCH:-mine}"
MODE="merge"
MIRROR_ONLY="no"
PUSH="yes"

while [ $# -gt 0 ]; do
    case "$1" in
        -b|--branch)   WORK_BRANCH="$2"; shift 2 ;;
        --rebase)      MODE="rebase"; shift ;;
        --merge)       MODE="merge"; shift ;;
        --mirror-only) MIRROR_ONLY="yes"; shift ;;
        --no-push)     PUSH="no"; shift ;;
        -h|--help)     sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)             echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$(git rev-parse --show-toplevel)"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$1" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$1" >&2; exit 1; }

# --- Preconditions ----------------------------------------------------------

if ! git diff --quiet || ! git diff --cached --quiet; then
    die "You have uncommitted changes. Commit or stash them first (git stash)."
fi

if [ -n "$(git ls-files --unmerged)" ]; then
    die "A merge/rebase is already in progress. Finish or abort it first."
fi

# --- Remote setup -----------------------------------------------------------

if git remote get-url upstream >/dev/null 2>&1; then
    have="$(git remote get-url upstream)"
    [ "$have" = "$UPSTREAM_URL" ] || warn "Remote 'upstream' is $have (expected $UPSTREAM_URL)"
else
    info "Adding remote 'upstream' -> $UPSTREAM_URL"
    git remote add upstream "$UPSTREAM_URL"
fi

# Remember conflict resolutions so repeated syncs don't re-ask the same questions.
git config rerere.enabled true
git config rerere.autoupdate true

info "Fetching upstream"
git fetch --prune upstream "$UPSTREAM_BRANCH"

# --- Step 1: fast-forward the mirror branch ---------------------------------

start_branch="$(git rev-parse --abbrev-ref HEAD)"

if git show-ref --verify --quiet "refs/heads/$MIRROR_BRANCH"; then
    git checkout "$MIRROR_BRANCH"
else
    git checkout -b "$MIRROR_BRANCH" "upstream/$UPSTREAM_BRANCH"
fi

before="$(git rev-parse HEAD)"

if ! git merge --ff-only "upstream/$UPSTREAM_BRANCH"; then
    cat >&2 <<EOF

$MIRROR_BRANCH could not fast-forward, which means it has commits of its own.
The mirror branch must stay a byte-for-byte copy of upstream. To fix:

    git branch rescue-$MIRROR_BRANCH          # keep your commits somewhere safe
    git reset --hard upstream/$UPSTREAM_BRANCH
    git push --force-with-lease origin $MIRROR_BRANCH

then cherry-pick anything you needed from rescue-$MIRROR_BRANCH onto $WORK_BRANCH.
EOF
    git checkout "$start_branch"
    exit 1
fi

after="$(git rev-parse HEAD)"
if [ "$before" = "$after" ]; then
    info "$MIRROR_BRANCH already up to date ($(git rev-parse --short HEAD))"
else
    info "$MIRROR_BRANCH: ${before:0:7} -> ${after:0:7} ($(git rev-list --count "$before..$after") new commits)"
    git --no-pager log --oneline "$before..$after" | head -20
fi

if [ "$PUSH" = "yes" ]; then
    info "Pushing $MIRROR_BRANCH to origin"
    git push -u origin "$MIRROR_BRANCH"
fi

if [ "$MIRROR_ONLY" = "yes" ]; then
    git checkout "$start_branch"
    exit 0
fi

# --- Step 2: bring upstream into the work branch ----------------------------

if git show-ref --verify --quiet "refs/heads/$WORK_BRANCH"; then
    git checkout "$WORK_BRANCH"
else
    info "Creating work branch '$WORK_BRANCH' from $MIRROR_BRANCH"
    git checkout -b "$WORK_BRANCH" "$MIRROR_BRANCH"
fi

if git merge-base --is-ancestor "$MIRROR_BRANCH" HEAD; then
    info "$WORK_BRANCH already contains everything from $MIRROR_BRANCH"
else
    info "Bringing $MIRROR_BRANCH into $WORK_BRANCH via $MODE"
    if [ "$MODE" = "rebase" ]; then
        cmd=(git rebase "$MIRROR_BRANCH")
        resume="git rebase --continue   (or: git rebase --abort)"
    else
        cmd=(git merge --no-edit "$MIRROR_BRANCH")
        resume="git commit             (or: git merge --abort)"
    fi

    if ! "${cmd[@]}"; then
        cat >&2 <<EOF

Conflicts. Nothing is lost — resolve them and continue:

    git status                  # see the conflicting files
    # edit each file, keeping upstream's change plus your intent
    git add <file>
    $resume

Then re-run this script, or just: ./scripts/dev-build.sh --test
EOF
        exit 1
    fi
fi

if [ "$PUSH" = "yes" ]; then
    info "Pushing $WORK_BRANCH to origin"
    if [ "$MODE" = "rebase" ]; then
        git push --force-with-lease -u origin "$WORK_BRANCH"
    else
        git push -u origin "$WORK_BRANCH"
    fi
fi

# --- Summary ----------------------------------------------------------------

echo
info "Your fork's patch set (everything $WORK_BRANCH changes vs upstream):"
if [ -z "$(git diff --stat "$MIRROR_BRANCH..$WORK_BRANCH")" ]; then
    echo "    (none yet — $WORK_BRANCH is identical to upstream)"
else
    git --no-pager diff --stat "$MIRROR_BRANCH..$WORK_BRANCH" | sed 's/^/    /'
fi
echo
info "Next: ./scripts/dev-build.sh --test && ./scripts/dev-build.sh --install"
