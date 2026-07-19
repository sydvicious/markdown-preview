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
- Table rendering:
  - Tables are rendered with an embedded `WKWebView` block (macOS + iOS/iPadOS)
  - Horizontal scrolling for wide tables
  - Preserves explicit line breaks in cells
  - Disables hyphenation/truncation behavior that was clipping table text
  - Supports inline backticks in table cells/headers as styled inline code

## Changelog

- See `CHANGELOG.md` for dated change entries.

## Preview Table Sample

| Area | Status | Notes |
| --- | --- | --- |
| macOS | ✅ | Open With + drag/drop supported |
| iOS | ✅ | Files picker + detail/source toggle |
| iPadOS | ✅ | Split view navigation + toolbar actions |


## Project Structure

- `MarkdownPreview/MarkdownPreviewApp.swift`: app entry, scene setup, `onOpenURL`
- `MarkdownPreview/Views/`: SwiftUI views — `ContentView.swift` (navigation and file list), `MarkdownPreviewView.swift` and `MarkdownPreviewWebView.swift` (rendered preview), `MarkdownSourceView.swift` (raw source)
- `MarkdownPreview/View Models/`: `ContentViewModel.swift` and `SearchViewModel.swift`
- `MarkdownPreview/Utilities/`: app-level supporting types
  - `DisplayTextMappings.swift`, `MarkdownPreviewTextOffsetMapping.swift`: map between source text, displayed text, and rendered HTML
  - `MarkdownFile.swift`: file loading and supported content types
  - `DocumentSessionStore.swift`: the opened-file list, selection, and persistence
- `MarkdownCore/`: the markdown engine, as a local Swift package the app depends on. It is
  deliberately free of SwiftUI, UIKit, and AppKit so it can be built and tested from the command
  line without an app host.
  - `Sources/MarkdownCore/MarkdownBlockParser.swift`: parses markdown source into blocks
  - `Sources/MarkdownCore/MarkdownHTMLBuilder.swift`: renders those blocks as an HTML document
  - `Sources/MarkdownCore/MarkdownSourceLineTable.swift`, `MarkdownSelectionRange.swift`: source
    offset bookkeeping the preview's selection mapping depends on
  - `Tests/MarkdownCoreTests/`: the engine's tests

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
- It supports common Markdown structures (headings, paragraphs, lists, ordered lists, blockquotes, fenced code, rules, and tables), plus the GitHub task-list and table extensions.
- Table rendering is HTML/CSS-based via `WKWebView` for fidelity and scrolling behavior.
- It is not yet a complete CommonMark implementation. [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/) is the reference the renderer is measured against, and the places it currently falls short — backslash escapes, hard line breaks, emphasis flanking rules, and nested block quotes among them — are covered by failing tests in `MarkdownCoreTests` and tracked under "Bug fixes" in `TODO.md`.

## Tests

There are two test suites:

- `MarkdownCoreTests`: tests for the markdown engine, including per-feature conformance tests
  written against [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/). These run from the
  command line with no app host:

```bash
swift test --package-path MarkdownCore
```

  Expectations follow the specification rather than current behavior, so this suite documents
  what the renderer *should* do. Cases fail where the renderer is not there yet; each failure is
  tracked under "Bug fixes" in `TODO.md`. A failing run is expected until those are fixed.

- `MarkdownPreviewTests`: unit tests for the app layer (view models, file state, selection
  handling). These need the app target:

```bash
xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS'
```


*Copyright ©2026 Syd Polk. All Rights Reserved.*
