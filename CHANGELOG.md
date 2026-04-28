# Changelog

Format:
- One top-level entry per date in `YYYY-MM-DD` format.
- Bullets describe user-visible behavior changes, platform updates, or notable implementation changes.

## 2026-04-27

- Sorted the sidebar document list alphabetically by filename instead of most-recently opened order.
- Added explicit file-list removal actions on macOS and iOS so opened files can be removed from the app’s list without deleting them from disk.

## 2026-03-19

- Refreshed the app icon artwork around a centered `.md` lockup, improving baseline alignment, small-size readability, and spacing of the accompanying `©SRP` mark across icon variants.
- Brought the same coalesced preview text-segment behavior to macOS so adjacent headings, paragraphs, and list content can be selected across block boundaries there as well.
- Kept quote blocks, fenced code blocks, tables, and rules as explicit preview selection boundaries on macOS and iOS, preserving copy-block behavior and stable table geometry.
- Copy actions for quote, table, and fenced code blocks now place both plain-text markdown source and rendered rich-text (`RTF`) representations on the clipboard.

## 2026-03-18

- Restored iOS preview text selection/copy within individual rendered text blocks using native selectable text views.
- Coalesced adjacent basic preview text blocks on iOS so selection can drag across headings, paragraphs, and list content until a quote, code block, table, or rule boundary.
- Quote and fenced code blocks now host native selectable text content while preserving their existing copy-block chrome.
- Added animated copy feedback for block copy actions, including immediate visual confirmation and iOS haptic feedback.
- Tuned block copy feedback timing so the animation starts immediately on tap and clears more quickly.

## 2026-03-04

- Added reusable copyable block chrome (`Copy` action in a top strip) for quote, table, and fenced code blocks.
- Block copy now copies the original markdown/plain-text source for quote, table, and fenced code blocks to the system clipboard.
- Copy actions now preserve existing user selection state (copy no longer rewrites source selection).
- Source selection behavior updated: tap/click with no selected text now clears the shared selection model.
- Improved copy-block container sizing:
  - width clamps to `min(content width, available width)`,
  - horizontal overflow scrolls inside the rounded container,
  - layout now responds correctly to window/split-view resize in both growth and shrink directions.
- Replaced markdown table rendering with native SwiftUI `Grid`-based layout, using horizontal scrolling for overflow.
- Removed `WKWebView` table rendering path (`MarkdownTableWebView.swift`).
- Removed obsolete table HTML/CSS builder utility (`MarkdownTableHTMLBuilder.swift`).
- Fixed macOS scroll-wheel behavior when moving vertically past table blocks.
- Improved rendering performance; table-heavy documents now scroll and render noticeably faster with the `Grid` implementation.
- Updated preview selection highlight color to use system semantic colors so it better matches Source selection and adapts to appearance/accessibility settings.

## 2026-03-03

- Completed major view/model refactor:
  - split major views into dedicated files (one primary `struct ...: View` per file),
  - extracted markdown parsing into `MarkdownBlockParser`,
  - introduced and integrated `ContentViewModel`,
  - expanded `#Preview` coverage with shared preview fixtures.
- Implemented cross-platform source text selection plumbing and persisted selections in the document session model.
- Synced source selections into preview highlighting, including heading normalization so markdown heading syntax maps to rendered heading text.
- Fixed selection loss when switching between Preview and Source by keeping both panes mounted and toggling visibility instead of recreating views.
- Stabilized selection behavior by ignoring transient empty selection updates emitted during focus/view transitions.

## 2026-02-23

- Fixed iOS/iPadOS open-in-place behavior for iCloud files and restored use of real source URLs (`UIDocumentPicker` with `asCopy: false`).
- Completed iPhone/iPad document association support (`.md`/UTI declaration + open-in-place handling).
- Added a dedicated macOS app `Info.plist` (`Info-macOS.plist`) and build wiring so Finder/Open With recognizes `.md` files.
- Added a markdown table sample to the preview source document (`README.md`) so SwiftUI previews exercise table rendering.
- Fixed preview instability by disabling live file monitoring via dependency injection in preview configurations.
- Improved table rendering polish:
  - Added dark-mode-aware table styling for text, borders, headers, and inline code.
  - Measured table width and height from table content so rounded card bounds fit content.
  - Reduced extra vertical whitespace around table cards.
  - Tightened table cell horizontal padding.
  - Switched markdown block container from `LazyVStack` to `VStack` to avoid first-scroll table hitching.

## 2026-02-22

- Replaced SwiftUI `Grid` table rendering with a `WKWebView`-based table block renderer on macOS, iOS, and iPadOS.
- Added automatic table block height reporting from web content back to SwiftUI.
- Added horizontal scrolling for wide tables in the embedded table renderer.
- Updated table rendering to preserve explicit line breaks in table cells.
- Added inline backtick rendering in table cells and headers (`code` styling).
- Tuned iOS table typography:
  - Reduced inline code font size for better visual balance.
  - Disabled text inflation in the web table renderer so compact and regular presentations match.
- Iterated table width behavior to avoid clipping/truncation artifacts that appeared in the original SwiftUI table approach.
- Added live file change handling for opened documents:
  - Poll active file every 1 second.
  - Poll all opened files every 10 seconds.
  - On iOS/iPadOS, re-check files on launch and when app enters foreground.
- Added missing-file behavior:
  - If the active file disappears, show modal alert and remove file on OK.
  - If a non-active file disappears, remove it silently.
  - On iPhone compact layout, return to file list after removing the active missing file.


*Copyright ©2026 Syd Polk. All Rights Reserved.*
