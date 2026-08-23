#!/bin/bash
#
# Copyright ©2026 Syd Polk. All Rights Reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds a release disk image containing the app and CHANGELOG.md, matching the
# layout of the images already in ~/iCloud/dev/MarkdownPreview Releases.
#
# Usage:
#   Scripts/make-release-dmg.sh <path-to-MarkdownPreview.app> [output-directory]
#
# The .app must be the signed, notarized build exported from an Xcode Archive —
# this script only packages what it is given, it does not build or sign.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <path-to-MarkdownPreview.app> [output-directory]" >&2
    exit 64
fi

APP_PATH="$1"
OUTPUT_DIRECTORY="${2:-$HOME/iCloud/dev/MarkdownPreview Releases}"

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(dirname "$SCRIPT_DIRECTORY")"
CHANGELOG_PATH="$PROJECT_DIRECTORY/CHANGELOG.md"
VERSION_CONFIG="$PROJECT_DIRECTORY/Version.xcconfig"

if [ ! -d "$APP_PATH" ]; then
    echo "error: no app at $APP_PATH" >&2
    exit 66
fi
if [ ! -f "$CHANGELOG_PATH" ]; then
    echo "error: no CHANGELOG.md at $CHANGELOG_PATH" >&2
    exit 66
fi

# Take the version from the app itself rather than the config, so the image can
# never be labelled differently from the build inside it.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"

CONFIG_VERSION="$(sed -n 's/^MARKETING_VERSION = //p' "$VERSION_CONFIG" | tr -d '[:space:]')"
if [ "$VERSION" != "$CONFIG_VERSION" ]; then
    echo "warning: app is $VERSION but Version.xcconfig says $CONFIG_VERSION" >&2
fi

VOLUME_NAME="MarkdownPreview $VERSION"
IMAGE_PATH="$OUTPUT_DIRECTORY/MarkdownPreview $VERSION.dmg"

if [ -e "$IMAGE_PATH" ]; then
    echo "error: $IMAGE_PATH already exists; move it aside first" >&2
    exit 73
fi

STAGING_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT

ditto "$APP_PATH" "$STAGING_DIRECTORY/MarkdownPreview.app"
cp "$CHANGELOG_PATH" "$STAGING_DIRECTORY/CHANGELOG.md"

mkdir -p "$OUTPUT_DIRECTORY"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIRECTORY" \
    -format ULFO \
    -quiet \
    "$IMAGE_PATH"

echo "created: $IMAGE_PATH"
echo "         MarkdownPreview $VERSION (build $BUILD)"

if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
    if spctl --assess --type execute "$APP_PATH" >/dev/null 2>&1; then
        echo "         signature and notarization: accepted"
    else
        echo "warning: signed, but Gatekeeper did not accept it — notarized?" >&2
    fi
else
    echo "warning: the app is not signed; this image is not distributable" >&2
fi
