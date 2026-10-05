<!-- Copyright @2026 Syd Polk. All Rights Reserved -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# Markdown Preview

A native SwiftUI Markdown viewer for macOS, iOS, and iPadOS.

This app is designed to feel like a lightweight Preview-style reader for `.md` files:
- Open files from the file picker or via file association
- Keep a persistent list of opened files
- Render a readable Markdown preview
- Toggle between rendered preview and raw source
- Find text in a document, or across every document in the list

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
  - Sorted by file name; on macOS, grouped by the folder each file is in
  - Deletable rows
  - macOS row tooltip shows full path (`~` for home directory)
- File opening:
  - `+` button (`accessibilityIdentifier`: `Open`)
  - Opens when list is empty via placeholder action
  - Supports `.md` and plain text imports
- Detail behavior:
  - Defaults to rendered preview
  - Toolbar control switches Preview/Source (`accessibilityIdentifier`: `DetailModePicker`)
  - A selection made in one view carries over to the other
  - Text size is set per document
- Search:
  - A search field over the file list narrows it to the documents containing the text
  - A search field in the document finds matches there, with next and previous
  - Search runs on the document's visible text, so it finds what the preview shows and not the markup
  - macOS shares the system find buffer with other apps
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
- Preview rendering:
  - The whole preview is HTML in a `WKWebView` (macOS + iOS/iPadOS)
  - Local images, read from beside the document, and remote ones over `http`/`https`
  - A Copy button on code, quote and table blocks
  - Horizontal scrolling for wide tables
  - Inline markup in table cells and headers: code, emphasis, links
  - Files with Unix, Windows or classic Mac line endings, or a mixture

## Changelog

- See `CHANGELOG.md` for changes, one section per release.

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
- `MarkdownPreview/Web/`: the preview's page template (`document.html`), stylesheet
  (`preview.css`) and scripts (`*.js`), as real files rather than Swift string literals. The
  folder is kept out of the app target: `MarkdownCore` bundles it, through a link, so that the
  engine can build a complete page on its own.
- `MarkdownPreview/Utilities/`: app-level supporting types
  - `DisplayTextMappings.swift`, `MarkdownPreviewTextOffsetMapping.swift`: the two views of a document's visible text that the app uses — one for search, one for the preview's selection — each a thin wrapper over the engine's `MarkdownVisibleText`
  - `MarkdownFile.swift`: file loading and supported content types
  - `DocumentSessionStore.swift`: the opened-file list, selection, and persistence
- `MarkdownCore/`: the markdown engine, as a local Swift package the app depends on. It is
  deliberately free of SwiftUI, UIKit, and AppKit so it can be built and tested from the command
  line without an app host.
  - `Sources/MarkdownCore/MarkdownBlockParser.swift`: parses markdown source into blocks
  - `Sources/MarkdownCore/MarkdownHTMLBuilder.swift`: renders those blocks as an HTML document
  - `Sources/MarkdownCore/MarkdownVisibleText.swift`: a document's text as the reader sees it, and
    which characters of the source each part came from. Find and selection are built on it. It
    takes its answers from the parser and from the pass that writes the HTML, so it cannot
    disagree with what is rendered.
  - `Sources/MarkdownCore/MarkdownSourceLineTable.swift`, `MarkdownSelectionRange.swift`: source
    offset bookkeeping the preview's selection mapping depends on
  - `Sources/MarkdownCore/Web`: a link to `MarkdownPreview/Web`, above, which is how the package
    takes those files into its resource bundle. They are read through `MarkdownWebResources.swift`.
  - `Tests/MarkdownCoreTests/`: the engine's tests, which are expected to pass
  - `Tests/MarkdownCoreConformanceTests/`: per-feature tests written against the CommonMark
    specification, which fail wherever the renderer is not there yet
  - `Tests/WebTests/`: tests for the preview's scripts, written in JavaScript

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

## Releases

Mac releases are disk images, Developer ID signed and notarized, so they open on any Mac. `Scripts/release-build.sh`, or the `Release DMG` scheme in Xcode, builds one from a clean `main`, puts it in the releases folder, and tags the commit `release-<version>-build-<build>`. `Scripts/bump-version.sh` moves the version and build number in `Version.xcconfig`; `--help` on either script says more. The iOS and iPadOS app is distributed only through TestFlight.

## Using as Default App for `.md` on macOS

1. Install the app from a release disk image by dragging it to `/Applications`, or build it and place it where you keep apps.
2. In Finder, select a `.md` file and choose **Get Info**.
3. Under **Open with**, choose **Markdown Preview**.
4. Click **Change All…**.

After this, double-clicking `.md` files should open them in this app.

## Notes and Limitations

- Rendering is intentionally lightweight and block-oriented.
- It supports common Markdown structures (headings, paragraphs, lists, ordered lists, blockquotes, fenced code, rules, and tables), plus the GitHub task-list and table extensions.
- Table rendering is HTML/CSS-based via `WKWebView` for fidelity and scrolling behavior.
- It is not yet a complete CommonMark implementation. [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/) is the reference the renderer is measured against. The places it currently falls short are covered by failing tests in `MarkdownCoreConformanceTests` and tracked under "Bugs" in `TODO.md`: a list item of more than one line, indented code blocks, autolinks, and reference-style links.
- Raw HTML in a document is shown as text, not rendered. That is deliberate.

## Tests

There are four test suites:

- `MarkdownCoreTests` and `MarkdownCoreConformanceTests`: tests for the markdown engine. Both
  run from the command line with no app host:

```bash
swift test --package-path MarkdownCore
```

  `MarkdownCoreTests` is expected to pass. `MarkdownCoreConformanceTests` is one small case per
  markdown feature, written against [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/).
  Its expectations follow the specification rather than current behavior, so it documents what
  the renderer *should* do. Cases fail where the renderer is not there yet; each failure is
  tracked under "Bugs" in `TODO.md`. A failing run is expected until those are fixed.

- `MarkdownPreviewTests`: tests for the app layer (view models, file state, selection handling).
  It also checks find and selection one markdown feature at a time, loading the real page and
  scripts in WebKit, without a window, and carrying a selection from the source to the page and
  back. These need the app target, and its test plan runs the two engine suites as well:

```bash
xcodebuild test -project MarkdownPreview.xcodeproj -scheme MarkdownPreview -destination 'platform=macOS'
```

- `MarkdownCore/Tests/WebTests`: tests for the preview's scripts in `MarkdownPreview/Web`,
  written in JavaScript and run under [Node](https://nodejs.org) against a DOM
  ([jsdom](https://github.com/jsdom/jsdom)). They load the same files the app ships. Node is
  needed only for this suite, never to build or run the app. Once, to fetch jsdom:

```bash
npm install
```

  Then, from the repository root:

```bash
npm test
```


*Copyright ©2026 Syd Polk. All Rights Reserved.*
