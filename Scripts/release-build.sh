#!/bin/bash
#
# Copyright ©2026 Syd Polk. All Rights Reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# Makes a release. **main always carries the version of the next release**, so
# from a clean main this:
#
#   1. builds a Release MarkdownPreview.app that can be handed to another
#      person: signed with Developer ID, notarized, stapled, and wrapped with
#      CHANGELOG.md in a DMG that is signed, notarized and stapled in turn;
#   2. tags the commit it built release-<version>-build-<build>.
#
# **It does not bump.** A release may take several candidates before one ships,
# so bump-version.sh stays separate: run it with no options for the next
# candidate, which needs a new build number (this refuses a tag already taken),
# and with --minor once a release has shipped, so main moves on to the next one.
#
# Nothing is pushed. With --no-notarize it only builds and packages, from any
# branch, and does not tag. It never starts from a dirty repo.
#
# Syd's to run, not an agent's: it uploads the build to Apple's notary service,
# and it tags.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO/MarkdownPreview.xcodeproj"
TEAM_ID="R5PQPZARC5"
DERIVED_DATA="${MDP_BUILD_ROOT:-$HOME/Library/Developer/Xcode/DerivedData/MarkdownPreview-scripts}"
BUILD_DIR="$DERIVED_DATA/release"
RELEASES_DIR="$HOME/iCloud/dev/MarkdownPreview Releases"
PROFILE="pgr-notary"
NOTARIZE=1

usage() {
    cat <<'HELPTEXT'
Releases MarkdownPreview: a Developer ID signed, notarized DMG, and a tag on
the commit it was built from. It does not bump; bump-version.sh does that.

USAGE
  ./Scripts/release-build.sh [options]

OPTIONS
  --output <dir>              Where to build. Default:
                              ~/Library/Developer/Xcode/DerivedData/MarkdownPreview-scripts/release
                              or $MDP_BUILD_ROOT/release. Never the repository.
  --releases <dir>            Where the finished DMG is copied. Default:
                              ~/iCloud/dev/MarkdownPreview Releases
  --keychain-profile <name>   The notarytool credentials to submit with.
                              Default: pgr-notary, shared by the team's apps.
  --no-notarize               Sign and package, but upload nothing to Apple,
                              copy nothing to the releases folder, and do not
                              tag. Works from any branch, but still only
                              from a clean repo.
  -h, --help                  This.

NEEDS, ONCE PER MAC
  A Developer ID Application certificate for team R5PQPZARC5, and:

    xcrun notarytool store-credentials "pgr-notary" \
        --apple-id "sydvicious@mac.com" --team-id "R5PQPZARC5"

  Both belong to the team, not to this app, so a Mac already set up to release
  any of the team's apps needs nothing more.

NEEDS, EVERY RELEASE
  A clean main (no changes, and no untracked files that are not ignored), and a
  "### <version>" heading in CHANGELOG.md for the release.

RESULT
  <releases>/MarkdownPreview <version> (<build>).dmg, holding the stapled app
  and CHANGELOG.md, and the tag release-<version>-build-<build>. The build
  products stay in <output>. Nothing is pushed.

AFTERWARDS
  Another candidate:          ./Scripts/bump-version.sh
  It shipped:                 ./Scripts/bump-version.sh --minor
HELPTEXT
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) BUILD_DIR="$2"; shift 2 ;;
        --releases) RELEASES_DIR="$2"; shift 2 ;;
        --keychain-profile) PROFILE="$2"; shift 2 ;;
        --no-notarize) NOTARIZE=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$BUILD_DIR" in
    "$REPO"|"$REPO"/*) echo "refusing to build inside the repository: $BUILD_DIR" >&2; exit 2 ;;
esac

git() { command git -C "$REPO" "$@"; }
read_setting() { sed -n "s/^$1 = //p" "$REPO/Version.xcconfig" | tr -d '[:space:]'; }

# **Never from a dirty repo**, in any mode: what is built has to be a commit
# anyone can check out. Untracked files count too, because Xcode compiles
# whatever is in a synchronized folder whether git knows about it or not.
# Ignored files do not.
if [[ -n "$(git status --porcelain)" ]]; then
    echo "the repo is dirty; commit or remove these first:" >&2
    git status --short >&2
    exit 1
fi

# Everything else that would stop a release, found before anything is built.
# The tag belongs on main; the DMG carries CHANGELOG.md, which should say what
# is in it.
if [[ $NOTARIZE -eq 1 ]]; then
    VERSION="$(read_setting MARKETING_VERSION)"
    BUILD="$(read_setting CURRENT_PROJECT_VERSION)"
    TAG="release-$VERSION-build-$BUILD"
    COMMIT="$(git rev-parse HEAD)"
    problems=()
    [[ "$(git branch --show-current)" == "main" ]] || problems+=("not on main: $(git branch --show-current)")
    git show-ref --verify --quiet "refs/tags/$TAG" && problems+=("tag $TAG already exists")
    grep -qx "### $VERSION" "$REPO/CHANGELOG.md" || problems+=("no \"### $VERSION\" heading in CHANGELOG.md")
    if (( ${#problems[@]} > 0 )); then
        echo "cannot release $VERSION ($BUILD):" >&2
        printf '  %s\n' "${problems[@]}" >&2
        exit 1
    fi
fi

IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\"/\1/p" | head -1)"
if [[ -z "$IDENTITY" ]]; then
    echo "no Developer ID Application certificate for team $TEAM_ID in the keychain." >&2
    echo "Create one in Xcode -> Settings -> Accounts -> Manage Certificates." >&2
    exit 1
fi

ARCHIVE="$BUILD_DIR/MarkdownPreview.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_DIR="$BUILD_DIR/dmg"
APP="$EXPORT_DIR/MarkdownPreview.app"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$DMG_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving Release"
xcodebuild archive -project "$PROJECT" -scheme "MarkdownPreview" \
    -configuration Release -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR/DerivedData" -archivePath "$ARCHIVE" -quiet

echo "==> Exporting with Developer ID"
OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates -quiet

# Notarization refuses anything without the hardened runtime, and a build
# without the sandbox would write its sample document to the real ~/Documents
# instead of the container. Check all three here, where the answer is a line of
# output rather than a rejection from Apple or a surprise on somebody else's Mac.
# `-dvv`, because `-dv` prints no Authority lines.
echo "==> Checking the signature"
codesign --verify --deep --strict "$APP"
info="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$info" \
    || { echo "not signed with Developer ID: $APP" >&2; exit 1; }
grep -q "flags=.*runtime" <<<"$info" \
    || { echo "no hardened runtime: $APP" >&2; exit 1; }
codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | grep -q "com.apple.security.app-sandbox" \
    || { echo "not sandboxed: $APP" >&2; exit 1; }

notarize() {
    local file="$1" result status id
    echo "==> Notarizing $(basename "$file")"
    result="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" \
        --wait --output-format json)"
    status="$(plutil -extract status raw - <<<"$result")"
    id="$(plutil -extract id raw - <<<"$result")"
    if [[ "$status" != "Accepted" ]]; then
        echo "notarization $status for $(basename "$file"):" >&2
        xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
        exit 1
    fi
}

if [[ $NOTARIZE -eq 1 ]]; then
    ZIP="$BUILD_DIR/MarkdownPreview.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    rm -f "$ZIP"
    xcrun stapler staple "$APP"
fi

# **From the app, not from Version.xcconfig**, so the image can never be named
# differently from the build inside it. The build number is in the name because
# it moves on every upload, and one version can have more than one build.
VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
BUILD="$(defaults read "$APP/Contents/Info.plist" CFBundleVersion)"
if [[ $NOTARIZE -eq 1 && "$TAG" != "release-$VERSION-build-$BUILD" ]]; then
    echo "the app is $VERSION ($BUILD), but Version.xcconfig named $TAG" >&2
    exit 1
fi
TITLE="MarkdownPreview $VERSION ($BUILD)"
DMG="$DMG_DIR/$TITLE.dmg"
echo "==> Packaging $(basename "$DMG")"
STAGE="$DMG_DIR/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MarkdownPreview.app"
cp "$REPO/CHANGELOG.md" "$STAGE/CHANGELOG.md"
hdiutil create -volname "$TITLE" -srcfolder "$STAGE" -format ULFO -quiet "$DMG"
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ $NOTARIZE -eq 0 ]]; then
    echo "$DMG"
    exit 0
fi

notarize "$DMG"
xcrun stapler staple "$DMG"
echo "==> Gatekeeper"
spctl --assess --type execute -vv "$APP"
spctl --assess --type open --context context:primary-signature -vv "$DMG"

FINAL="$RELEASES_DIR/$(basename "$DMG")"
if [[ -e "$FINAL" ]]; then
    echo "$FINAL already exists; the new image is at $DMG" >&2
    exit 1
fi
mkdir -p "$RELEASES_DIR"
cp "$DMG" "$FINAL"

# The tag goes on the commit the build started from, and only once the image is
# in the releases folder. Advice goes to stderr, so the last line on stdout is
# the image, for the Release DMG target.
echo "==> Tagging $TAG"
git tag -a "$TAG" "$COMMIT" -m "MarkdownPreview $VERSION ($BUILD)"
echo "the tag goes to origin with the next bump, or now: git push origin $TAG" >&2
echo "another candidate: Scripts/bump-version.sh" >&2
echo "it shipped:        Scripts/bump-version.sh --minor" >&2
echo "$FINAL"
