# Changelog

Format:
- One top-level entry per date in `YYYY-MM-DD` format.
- Bullets describe user-visible behavior changes, platform updates, or notable implementation changes.

## 2026-03-04

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
