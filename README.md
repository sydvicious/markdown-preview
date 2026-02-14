# Markdown Preview

A native SwiftUI Markdown viewer for macOS, iOS, and iPadOS.

This app is designed to feel like a lightweight Preview-style reader for `.md` files:
- Open files from the file picker or via file association
- Keep a persistent, recent-first list of opened files
- Render a readable Markdown preview
- Toggle between rendered preview and raw source

## Platforms

- macOS 26.0+
- iOS 26.0+
- iPadOS 26.0+

## Current Features

- `NavigationSplitView` layout with:
  - Sidebar list of opened files
  - Detail area for content
- Sidebar behavior:
  - Shows every opened file
  - Sorted by most recently opened first
  - Deletable rows
  - macOS row tooltip shows full path (`~` for home directory)
- File opening:
  - `+` button (`accessibilityIdentifier`: `Open`)
  - Opens when list is empty via placeholder action
  - Supports `.md` and plain text imports
- Detail behavior:
  - Defaults to rendered preview
  - Toolbar toggle button switches Preview/Source (`accessibilityIdentifier`: `View`)
- Persistence:
  - Stores opened file list and selection in `UserDefaults`
  - Persists bookmarks for reopening files across launches
  - Validates bookmarks on startup and removes missing/inaccessible files before showing list
- macOS integrations:
  - App registers for Markdown documents (`.md` / `net.daringfireball.markdown`)
  - Supports opening files with `Open With…` and double-click (when selected as default app)
  - Supports drag-and-drop of file URLs into the window
  - Single-window macOS scene
- Accessibility:
  - Dynamic text sizing (`Dynamic Type`) supported across list/preview/source content

## Project Structure

- `MarkdownPreview/MarkdownPreviewApp.swift`: app entry, scene setup, `onOpenURL`
- `MarkdownPreview/ContentView.swift`: navigation, file list, persistence, preview/source UI
- `MarkdownPreview/MarkdownFile.swift`: file loading and supported content types

## Build and Run

### Xcode

1. Open `MarkdownPreview.xcodeproj`.
2. Select the `MarkdownPreview` scheme.
3. Choose a destination (`My Mac`, iPhone simulator, iPad simulator, or device).
4. Build and run.

### Command line

```bash
# iOS
xcodebuild \
  -project /Users/jazzman/dev/github/sydvicious/MarkdownPreviewApp/MarkdownPreview.xcodeproj \
  -scheme MarkdownPreview \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build

# macOS
xcodebuild \
  -project /Users/jazzman/dev/github/sydvicious/MarkdownPreviewApp/MarkdownPreview.xcodeproj \
  -scheme MarkdownPreview \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Using as Default App for `.md` on macOS

1. Build and place the app where you keep apps (for example `/Applications`).
2. In Finder, select a `.md` file and choose **Get Info**.
3. Under **Open with**, choose **Markdown Preview**.
4. Click **Change All…**.

After this, double-clicking `.md` files should open them in this app.

## Notes and Limitations

- Rendering is intentionally lightweight and block-oriented.
- It supports common Markdown structures (headings, paragraphs, lists, ordered lists, blockquotes, fenced code, rules).
- It does not aim to be a full CommonMark/GitHub-Flavored Markdown engine yet.

## Tests

The repository includes unit/UI test targets:
- `MarkdownPreviewTests`
- `MarkdownPreviewUITests`


//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//
