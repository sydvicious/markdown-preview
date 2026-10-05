<!-- Copyright @2026 Syd Polk. All Rights Reserved -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# AGENTS.md

This file provides working guidance for the `MarkdownPreviewApp` project.

## Project Scope

These instructions apply to the entire directory tree under this folder.

## Working Notes

- The pending task list lives in `TODO.md`. Check it before starting new work and update it when appropriate.
- The log of shipped or notable changes lives in `CHANGELOG.md`. Add entries there when work should be recorded.
- Prefer preserving the app's existing structure and conventions unless a task explicitly calls for a broader refactor.
- When making changes, keep edits focused and avoid touching unrelated files.
- `Scripts/release-build.sh`, `Scripts/bump-version.sh` and the `Release DMG` scheme are Syd's to run: they upload to Apple's notary service, commit, tag and push. An agent may run `--help`, and `bump-version.sh --dry-run`.

## Project Context

- This is an Xcode/macOS app project.
- The main app code lives under `MarkdownPreview/`.
- The markdown engine — parser, HTML builder, and the visible-text mapping find and selection use — is the `MarkdownCore` Swift package, under `MarkdownCore/`. It builds and tests from the command line with `swift test`, and stays free of SwiftUI, UIKit and AppKit.
