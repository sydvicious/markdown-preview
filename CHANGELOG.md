# Changelog

Format:
- One top-level entry per date in `YYYY-MM-DD` format.
- Bullets describe user-visible behavior changes, platform updates, or notable implementation changes.

## 2026-07-03

- Bumped the app marketing version to `0.5` and build number to `5` (both in `Version.xcconfig`), adopting the convention of bumping the version on the first commit after a release.
- Unified search into a single shared query string across all platforms: the file-list search box and the in-document search box now always show the same text, and that one string drives both file-list filtering and in-document find. This removes the separate list/detail search states and the list→detail handoff, so the search text no longer goes blank when moving between the file list and a document (notably on iPhone). The in-memory/system find buffer still seeds an empty field on focus (and from selection-for-find).
- Made the macOS search two-way shared with the system find pasteboard: the shared search string is written to the find pasteboard as it changes, and when the app becomes active it adopts a find term set by another app (or a native find bar) if it changed since the app last saw it (guarded by the pasteboard change count so the app never re-adopts its own writes or undoes a manual clear).
- Fixed in-document search so that once a query stops matching, the previously highlighted match is cleared and no selection is shown while there are no matches; the pre-search selection is still restored when the search is cleared.
- Added a "Search" action to the text-selection menu so a selection can be sent straight to the shared search: on iOS/iPadOS it appears in the selection edit menu (callout) for both the source and preview, and on macOS it appears in the right-click context menu for both. Choosing it runs the in-document search for the selected text without stealing keyboard focus.

## 2026-06-30

- Bumped the app marketing version to `0.4` and build number to `4` for this release, with both values now centralized in `Version.xcconfig`.
- Fixed Preview-mode copy so copying a text selection writes only the selected rendered text's corresponding markdown source, instead of expanding to the whole rendered block.
- Fixed Preview-to-Source selection handoff so selections made in the `WKWebView` preview are retained when switching back to Source mode.
- Tightened Preview `WKWebView` selection handling by using typed bridge payload parsing, display-to-source range mapping, and guarded replay of preview-originated selections so native WebKit selection behavior is not immediately overwritten.
- Preserved native macOS word selection behavior in Preview by avoiding immediate re-application of selections that originated inside the preview WebView.
- Added focused unit coverage for preview selection bridge payload validation, copy-block message validation, rendered display range mapping, inline markdown selections, multi-block selections, list/table selections, and out-of-bounds payload handling.
- Stopped the UI launch test from running across alternate target application UI configurations so it no longer flips the Mac appearance setting to Dark after test runs.
- Improved iPhone Preview-to-Source selection handoff by explicitly flushing the current `WKWebView` selection before switching modes and retaining the last non-empty preview selection when WebKit collapses selection during focus handoff.
- Fixed iOS so a selection carried from Preview to Source is a real, copyable selection rather than an invisible range: the source text view now claims first responder and applies the range, so it renders on arrival and works with Cmd-C and the edit menu (macOS unchanged). Added unit coverage for the empty-vs-non-empty selection resolution, including clamping and out-of-bounds handling.

## 2026-06-28

- Added file-list and in-document search UI on macOS, iPhone, and iPad, including compact search controls in the toolbar/detail chrome, match counts, next/previous navigation, search suggestions, and keyboard shortcuts for find navigation.
- Added cross-pane search handoff so choosing a file from list-search results opens that file, seeds the detail search, and lets `Esc` back out through the handoff state in order.
- Updated find command behavior so `Command-F` targets detail search when a document is selected, falls back to list search when only the file list is available, and `Command-Shift-F` focuses the file-list search.
- Shared macOS find behavior with the system find pasteboard, including populating searches from the shared buffer and supporting `Command-E` from the current selection.
- Reworked search/index plumbing around stripped-text mappings so file-list search and detail search operate on source-derived text while preview selections still map back into the rendered `WKWebView`.
- Fixed iPhone file-list search after session restore by migrating restored document IDs to their resolved bookmark paths before restoring selection, text-size preferences, and the search index.
- Added the `MarkdownPreview` title to the iPhone list view and kept search filtering active only while the app is foregrounded so external system searches do not unexpectedly hide files.

## 2026-06-27

- On macOS, the app now automatically presents the file picker on direct launch when restore finds no valid files, while Finder/Open With launches keep any restored session files open, add the requested file to the list, and suppress the automatic picker.
- Restored the last selected file on relaunch when it is still available, including reopening directly into the detail pane on iPhone; if that file no longer restores, the app now leaves the selection empty instead of choosing a different document.
- Added per-file text size controls on macOS, iPhone, and iPad, with sizes persisted by file path and cleaned up automatically when files are removed from the app list or disappear from disk.
- Added keyboard shortcuts for text sizing, including `Command--` to decrease text size and both `Command-=` and `Command-+` to increase it when a hardware keyboard is present.
- Extended iPhone and iPad text sizing to the full Dynamic Type range, including the larger accessibility sizes exposed by the iOS/iPadOS Accessibility settings.
- Fixed macOS detail-pane sizing so reducing source text size no longer causes the source view to collapse horizontally.
- Updated the `WKWebView` preview renderer to scale typography without shrinking the rendered page width, and removed the centered max-width reading column so preview content stays pinned to the available detail width as text size changes.
- Simplified the generated UI launch smoke test so it only launches the app, avoiding the extra screenshot-capture work in the macOS launch-template test.

## 2026-04-27

- Sorted the sidebar document list alphabetically by filename instead of most-recently opened order.
- Added explicit file-list removal actions on macOS and iOS so opened files can be removed from the app’s list without deleting them from disk.

## 2026-06-25

- Replaced the custom SwiftUI preview renderer with a full-document `WKWebView` preview backed by generated HTML/CSS, simplifying native text selection and unifying table rendering with the rest of the preview surface.
- Removed the temporary legacy preview comparison mode now that the `WKWebView` renderer is the preferred preview path on macOS and iOS.
- Kept macOS support compatible with macOS 26 Tahoe while continuing the iOS 27 move.
- Updated the macOS file-drop handler to use `NSItemProvider.loadObject` instead of the deprecated `loadItem` API for macOS 27.

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
