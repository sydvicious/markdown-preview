#!/bin/bash
#
# Copyright ©2026 Syd Polk. All Rights Reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# Moves the version and the build number in Version.xcconfig, commits that one
# file straight to main, tags the commit, and pushes main and its tags to
# origin. Adapted from ../photos-go-round/Scripts/bump-version.sh.
#
# **main always carries the version of the next release**, and this is how it
# moves. It is separate from release-build.sh because a release may take
# several candidates: with no options it moves the build number only, for the
# next candidate or upload; with --minor, once a release has shipped, it moves
# main on to the next version.
#
# **The build number only ever goes up**, and never resets when the version
# moves: App Store Connect wants a new one for every upload (Version.xcconfig).
#
# **From a clean main, and nowhere else**, so the commit holds the version and
# nothing more.
#
# Syd's to run: it commits, tags and pushes. An agent may run `--dry-run`.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO/Version.xcconfig"
DRY_RUN=0

usage() {
    cat <<'HELPTEXT'
Moves the version and the build number, commits, tags and pushes.

USAGE
  ./Scripts/bump-version.sh [--dry-run]                  build number + 1
  ./Scripts/bump-version.sh [--dry-run] --minor          0.9 -> 0.10, build + 1
  ./Scripts/bump-version.sh [--dry-run] --major          0.9 -> 1.0, build + 1
  ./Scripts/bump-version.sh [--dry-run] --version <x.y>  that version, build + 1

From a clean main, it changes Version.xcconfig, commits it to main, tags the
commit v<x.y>-<build>, and pushes main and its tags to origin. The build number
never resets.

With no options, for another release candidate or upload. With --minor, once a
release has shipped.

  --dry-run   Say what it would do, and change nothing.
HELPTEXT
}

CHANGE=""
VERSION_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --minor|--major) CHANGE="$1"; shift ;;
        --version)
            [[ "${2:-}" =~ ^[0-9]+\.[0-9]+$ ]] || { echo "--version needs x.y" >&2; exit 2; }
            CHANGE="--version"; VERSION_ARG="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

git() { command git -C "$REPO" "$@"; }

read_setting() { sed -n "s/^$1 = //p" "$CONFIG" | tr -d '[:space:]'; }

VERSION="$(read_setting MARKETING_VERSION)"
BUILD="$(read_setting CURRENT_PROJECT_VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || { echo "MARKETING_VERSION is not x.y: $VERSION" >&2; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "CURRENT_PROJECT_VERSION is not a number: $BUILD" >&2; exit 1; }

MAJOR="${VERSION%%.*}"
MINOR="${VERSION#*.}"
case "$CHANGE" in
    "") NEW_VERSION="$VERSION" ;;
    --minor) NEW_VERSION="$MAJOR.$((MINOR + 1))" ;;
    --major) NEW_VERSION="$((MAJOR + 1)).0" ;;
    --version) NEW_VERSION="$VERSION_ARG" ;;
esac
NEW_BUILD="$((BUILD + 1))"
TAG="v$NEW_VERSION-$NEW_BUILD"
TITLE="$NEW_VERSION ($NEW_BUILD)"

# Everything that would stop it, found before anything is changed. Untracked
# files count as dirty, as they do for release-build.sh.
problems=()
[[ "$(git branch --show-current)" == "main" ]] || problems+=("not on main: $(git branch --show-current)")
[[ -z "$(git status --porcelain)" ]] || problems+=("the repo is dirty")
git show-ref --verify --quiet "refs/tags/$TAG" && problems+=("tag $TAG already exists")

echo "$VERSION ($BUILD) -> $TITLE"
echo "  commit \"Version $TITLE\" to main, tag $TAG, push main and tags to origin"

if (( ${#problems[@]} > 0 )); then
    printf '  cannot: %s\n' "${problems[@]}" >&2
    git status --short >&2
    exit 1
fi
if (( DRY_RUN )); then
    echo "dry run — nothing changed"
    exit 0
fi

# If a step fails part way, say where things were left rather than undo them.
trap 'echo "stopped part way. Check git status, git log and git tag." >&2' ERR

sed -i '' \
    -e "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $NEW_VERSION/" \
    -e "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $NEW_BUILD/" \
    "$CONFIG"
git add "$CONFIG"
git commit --quiet -m "Version $TITLE"
git tag -a "$TAG" -m "MarkdownPreview $TITLE"
# --follow-tags also takes any release-… tag made on main since the last push.
git push --quiet --follow-tags origin main

echo "main at $(git rev-parse --short HEAD), tagged $TAG, pushed to origin"
