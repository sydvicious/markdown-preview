# Changelog

Format:
- One top-level entry per date in `YYYY-MM-DD` format.
- Where a date spans a release, a `###` subheading names the version the bullets under it belong to.
- Bullets describe user-visible behavior changes, platform updates, or notable implementation changes.

## 2026-07-19

### 0.7

- Bumped the app marketing version to `0.7` (in `Version.xcconfig`), following the convention of bumping the version on the first commit after a release.
- Enabled App Sandbox on macOS, which the App Store requires and which the app had never run under before. The document you open, and any folder you grant, are now reached through security-scoped bookmarks on macOS exactly as they already were on iOS. The entitlements are App Sandbox, user-selected file access, app-scoped bookmarks, and outgoing network connections for `http(s)` images.
  - **User-selected access has to be read-write, although the app never writes a document.** Read-only is enough to open and read a file the user picked, but not to create a security-scoped bookmark from it: `bookmarkData(.withSecurityScope)` fails with `NSCocoaErrorDomain` code 256 even with the scope held open. Without a bookmark nothing reopens after a relaunch, so narrowing this back to read-only makes every Open fail with a message claiming the file could not be opened. The reason is recorded in `MarkdownPreview.entitlements`; do not "tidy" it to read-only on the grounds that the app only reads.
  - Folder grants written by earlier builds are discarded at launch, because a bookmark made before the app was sandboxed cannot be resolved by it afterwards. Granting the folder again is the recovery, and costs one trip through the picker.
- Fixed the file-access defects that only appear once the app is sandboxed. Each of these was harmless on an unsandboxed system, where a privileged read tends to succeed anyway, and each fails silently rather than loudly once it is not.
  - A failure to create a security-scoped bookmark is now reported instead of quietly falling back to a bookmark without a scope. The fallback resolved perfectly well and then produced a URL the sandbox refused, so a document opened normally and then vanished from the list on the next launch, far from the cause. Opening now fails at the point the permission cannot be captured, and the reason is written to the log.
  - Reading a document's modification date now holds the file's security scope. Without it the read returns nothing under the sandbox, which defeated the "unchanged, so skip" check and silently re-read and re-indexed every open document on every polling tick — once a second for the active document.
  - Deciding *why* an image failed now happens inside the granted folder scope, as the rewrite beside it already did. Outside it the directory listing fails even when the folder has been granted, so every unresolved image was classed as unreadable and the app offered to fix missing files by granting permission — a fix that cannot work, and the exact promise that distinction exists to avoid making.
  - A file dropped on the window is bookmarked at the moment the drop hands it over, rather than two asynchronous hops later. The sandbox extension a drop carries belongs to the drag session, so by the time the URL reached the main actor there could be nothing left to record, and the dropped document would not survive a relaunch.
  - Paths in the sidebar and tooltips abbreviate to `~` again. Under the sandbox `NSHomeDirectory()` returns the app's container rather than the user's home directory, so nothing matched and full absolute paths were displayed; the home directory is now read from the account record, which the sandbox does not rewrite.
  - On iOS, resolving a stored bookmark no longer leaks a security scope each time. Resolution implicitly starts the scope unless told not to, and the system permits only so many open at once; this runs once per document at launch and again on every polling tick.
- Added a privacy manifest declaring the two required-reason APIs the app uses: file timestamps, for reloading a document when it changes on disk, and user defaults, for the document list and folder grants. `MarkdownCore` has no third-party dependencies, so nothing else is inherited. Also declared that the app uses no non-exempt encryption, which otherwise stalls every upload on the export-compliance question.
- Split the build number from the marketing version. `CURRENT_PROJECT_VERSION` restarts at `1` and is bumped on every upload without ever resetting, while `MARKETING_VERSION` continues to move on the first commit after a release. App Store Connect requires a unique increasing build number for each upload within a marketing version, and a release takes more than one upload whenever a build is rejected or replaced, so keeping the two in lock step burned a marketing version on every retry. Both platforms share the one counter.
- Removed a reference to the deleted `MarkdownPreviewUITests` target from the shared scheme, where it had remained as a test target with no matching definition in the project. Harmless so far because the test plans name their targets explicitly, but the kind of dangling reference that surfaces during an archive.

### 0.6

- Released version `0.6` (build `6`).
- Images in markdown documents now display on macOS, iOS, and iPadOS. `![alt](photo.jpg "title")` renders the picture, with relative paths resolved against the document's own directory, including documents stored on iCloud Drive.
  - This needed more than a correct path. A `WKWebView` loaded from an HTML string gives its web content process no read access to the file system, so a relative image reference never loaded however right the base URL was — which is why only alt text appeared. Image references are now rewritten to a private `mdimage://` URL scheme and served by a handler running in the app process, which can read the file. The alternative of embedding each image as a `data:` URI was rejected because the document is re-rendered on every preview update, and base64 would mean re-encoding every image each time, inflated by a third.
  - A sandboxed app is granted the document you opened, not the files beside it, so an image may be unreadable even when the path is right. When that happens the preview offers to open the enclosing folder, and the permission is remembered across launches. The locations tested on iOS so far did not require it, but the same mechanism covers macOS once the app is sandboxed for the App Store.
  - Images that live in iCloud Drive are downloaded on demand and read under file coordination, matching how the markdown document itself is already loaded.
  - Only files whose extension names a known image type are requested, and the handler additionally checks that the file's leading bytes really are an image before serving it. A file merely named `.png` is refused rather than handed to the web view. Each generated image URL also carries a key minted at launch, so nothing but this app's own rendering can ask for a file.
  - When an image cannot be shown, the reason is now distinguished: a file that is there but unreadable offers to open the enclosing folder, while a file that is simply absent says so plainly instead of offering a permission it cannot use.
  - Images referenced by `http` or `https` URL are fetched over the network as usual.
- Added `Samples/SAMPLE.md`, a document exercising every supported feature — headings, line breaks, emphasis, code, lists of every shape, block quotes, links, images, tables, thematic breaks, and escapes — with a closing section listing what is not supported. Useful for seeing the renderer's behavior at a glance.
- Fixed every failure the CommonMark conformance suite exposed. All 44 failing cases now pass, and the renderer follows [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/) across the features the app supports. User-visible changes:
  - Backslash escapes work, so `\*not emphasized\*` renders literally instead of showing the backslashes, and an escaped character can no longer open or close a construct.
  - HTML entities are decoded rather than double-escaped: `&amp;` in the source now renders as an ampersand instead of the literal text `&amp;`.
  - Emphasis follows the specification's flanking rules. Intraword underscores stay literal, so `snake_case_names` and `foo__bar__baz` survive intact, while `foo*bar*baz` still emphasizes. `***foo***` renders as strong inside emphasis, and emphasis nests correctly.
  - Line breaks behave properly. A line ending inside a paragraph is a soft break rendered as a newline rather than collapsing to a space, and both hard-break forms — two trailing spaces, or a trailing backslash — now produce a line break instead of being silently discarded.
  - Block quotes hold real block structure. They can nest, and can contain headings, lists, and code rather than flattening into a single paragraph.
  - Headings accept the full syntax: `#foo` without a space is correctly not a heading, closing sequences like `## foo ##` are stripped, a bare `#` is an empty heading, and a setext underline may be any length and may underline a multi-line paragraph.
  - Fenced code accepts `~~~` fences and fences indented up to three spaces, and the info string becomes a `language-` class on the `<code>` element, which makes syntax highlighting possible later.
  - Code spans support double-backtick fencing, so a span can contain a literal backtick, and strip one leading and trailing space.
  - Links and images accept titles and angle-bracket destinations, and image alt text is reduced to plain text rather than carrying markup into the attribute.
  - Thematic breaks accept spaces between the characters, so `* * *` is a rule, and take precedence over list markers so `- - -` is a rule rather than a list.
  - Lists accept the `)` delimiter, and a blank line between items now makes the list loose rather than ending it, wrapping each item's content in a paragraph.
  - Tables accept single-column tables, `:-:` centering, single-dash delimiter cells, and rows shorter than the header, which are padded instead of ending the table.
  - Ordered lists keep their existing behavior of numbering each item with `value` rather than putting `start` on the list. This is a deliberate departure from the specification, kept because it reproduces non-sequential numbering exactly as written.
- Raised the deployment targets back to `IPHONEOS_DEPLOYMENT_TARGET = 26.0` and `MACOSX_DEPLOYMENT_TARGET = 26.0` across all build configurations, reversing the 2026-07-05 change that had lowered them to `18.0` and `15.0` to widen device support. The app and the `MarkdownCore` package both build cleanly for macOS and iOS at the raised targets. `README.md` had continued to advertise 26.0+ throughout, and now matches the project again.
- Added a per-feature markdown conformance test suite written against CommonMark 0.31.2, covering headings, paragraphs and line breaks, thematic breaks, fenced code, block quotes, lists, task lists, code spans, emphasis, links, images, escapes, and tables. Expectations follow the specification rather than what the renderer happened to do, so the suite documents intended behavior; it exposed 44 failing cases when it landed, all of which are fixed above.
- Extracted the markdown engine into `MarkdownCore`, a local Swift package the app depends on, so it can be built and tested from the command line with no app host and no GUI session. `swift test --package-path MarkdownCore` runs the engine's tests in about a second, instead of building and launching the app under `xcodebuild test`. `MarkdownBlockParser`, `MarkdownHTMLBuilder`, `MarkdownSourceLineTable`, and `MarkdownSelectionRange` moved into the package and their API became `public`; the app files that use them now `import MarkdownCore`. The package is deliberately free of SwiftUI, UIKit, and AppKit — a UI-framework import there is what would push its tests back into an app host.
  - The parser and HTML builder test suites moved into the package alongside the code they cover, so they run headlessly too.
  - Split the package's tests into two targets so each can be run on its own: `MarkdownCoreTests` for the parser, HTML builder, and image URL handling, and `MarkdownCoreConformanceTests` for the CommonMark suite.
  - Added three test plans, all selectable from Xcode's Tests panel. The default `MarkdownPreview` plan runs everything — the app tests plus both engine suites, 232 tests — while `MarkdownCoreTests` and `MarkdownCoreConformanceTests` run each engine suite alone for focused work.
  - Attached `MarkdownCore` to the project as a navigator folder rather than as a package dependency. Xcode only exposes a package's test targets when the package is attached that way; as a dependency it offers the library alone, which is why the engine tests could not be added to a scheme or test plan at first. See `TODO.md` for the details.
  - `MarkdownHTMLBuilder.document(for:)` now takes a plain `contentScale` number instead of a SwiftUI `DynamicTypeSize`, which is what let the engine drop its last UI-framework dependency. Call sites pass `textSize.scaleFactor`.
- Fixed nested list rendering to follow CommonMark. Nesting depth is now measured relative to the parent item's content column instead of by dividing the absolute indent width, so two spaces, four spaces, or a tab each nest exactly one level and a list can no longer jump two levels at once. Previously a four-space indent was read as depth two and a tab as depth two, neither of which matches the standard.
  - Numbered lists nest on the same rules, and the two marker types can now nest inside each other (a numbered list under a bulleted item, or the reverse). Previously hitting the other marker type ended the list and started a separate block, so mixed nesting was impossible. Switching marker type at the top level still starts a new list, as CommonMark specifies.
  - Lists now render as structurally nested `<ul>`/`<ol>` elements rather than one flat list whose items were pushed right with `depth-N` CSS margins. As a side effect, nested checklist items are now indented — the old `li.task` rule zeroed their margin, so they had been rendering flat regardless of depth.
- Changed the "Remove from List" affordances from a trash can to an X-in-a-circle (`xmark.circle`) so they no longer imply the file will be deleted from disk — removal only takes the file out of the app's list. Covers the macOS list context menu and sidebar toolbar button, and the iOS/iPadOS row context menu and swipe action.
  - Made those same remove affordances visually neutral by dropping their destructive button role, so they no longer render in red; the iOS swipe action is explicitly tinted gray (without a role it would otherwise pick up the accent color).

## 2026-07-08

- Bumped the app marketing version to `0.6` and build number to `6` (both in `Version.xcconfig`), adopting the convention of bumping the version on the first commit after a release.
- Released version `0.5` (build `5`).

## 2026-07-05

- Lowered the deployment targets across all build configurations to widen device support ahead of TestFlight: `IPHONEOS_DEPLOYMENT_TARGET` from `27.0` to `18.0` and `MACOSX_DEPLOYMENT_TARGET` from `26.0` to `15.0`. The project builds cleanly against the lowered targets on macOS with no API availability gaps to resolve.

## 2026-07-03

- Bumped the app marketing version to `0.5` and build number to `5` (both in `Version.xcconfig`), adopting the convention of bumping the version on the first commit after a release.
- Let the macOS file-open dialog (the `+` button and the startup prompt when the list is empty) select multiple `.md` files at once; all selected files are opened instead of only the first.
- Fixed macOS so opening multiple `.md` files at once (for example selecting several in Finder) opens all of them instead of only one: a batch Open is now handled by the AppKit app delegate's `application(_:open:)`, which receives every URL together, and incoming URLs are queued and drained rather than overwriting a single slot. (SwiftUI's `.onOpenURL` only surfaced one file from a multi-file open.)
- Fixed macOS list removal, which had no working affordance: replaced the unreliable per-row context menu with the List's `.contextMenu(forSelectionType:)` (right-click → "Remove from List"), and added an always-present trash button to the file-list (sidebar) toolbar (disabled when nothing is selected) so removal is discoverable next to the list.
- Added a "Remove from List" menu command (⌘⌦) that removes the selected file. As a menu command it works regardless of which pane holds focus, so removal no longer depends on the file list being first responder.
- Fixed the Delete key on macOS not removing the selected file: because selecting a file parks first responder on a hidden focus sink (to keep the search field from grabbing focus), the file list was no longer first responder and `onDeleteCommand` never fired. The sink now also handles Delete / Forward Delete to remove the selected document.
- Unified search into a single shared query string across all platforms: the file-list search box and the in-document search box now always show the same text, and that one string drives both file-list filtering and in-document find. This removes the separate list/detail search states and the list→detail handoff, so the search text no longer goes blank when moving between the file list and a document (notably on iPhone). The in-memory/system find buffer still seeds an empty field on focus (and from selection-for-find).
- Made the macOS search two-way shared with the system find pasteboard: the shared search string is written to the find pasteboard as it changes, and when the app becomes active it adopts a find term set by another app (or a native find bar) if it changed since the app last saw it (guarded by the pasteboard change count so the app never re-adopts its own writes or undoes a manual clear).
- Fixed in-document search so that once a query stops matching, the previously highlighted match is cleared and no selection is shown while there are no matches; the pre-search selection is still restored when the search is cleared.
- Gave rendered headings more space above them so a heading following a paragraph reads as a new section instead of sitting as tightly as normal paragraph spacing (the first block's top margin is still zeroed so the title is not pushed down).
- Added a "Search" action to the text-selection menu so a selection can be sent straight to the shared search: on iOS/iPadOS it appears in the selection edit menu (callout) for both the source and preview, and on macOS it appears in the right-click context menu for both. Choosing it runs the in-document search for the selected text without stealing keyboard focus.
- Split several types into their own files (`MarkdownAppCommandCenter`, `MarkdownPreviewTextOffsetMapping`, `HTMLTextOffsetMapping`) and grouped the view models (`ContentViewModel`, `SearchViewModel`) under a `View Models` folder.
- Restructured `ContentView` toward MVVM (no user-facing behavior change beyond the typing-performance fix below): moved the search state and data logic into a dedicated `SearchViewModel`, and moved the command capabilities, the find / text-size / remove commands, the file-open/drop/startup-importer orchestration, and the file-list search filtering into `ContentViewModel`. Keyboard focus (`@FocusState`) stays in the view but is driven by the view model via a focus request; the size class and app-foreground state are mirrored into the view model. `ContentView` shrank from ~1,350 to ~1,065 lines, and `ContentView`/`ContentViewModel`/`SearchViewModel` logic is now covered by view-model unit tests.
- Reduced search-field typing latency (most noticeable on macOS) by moving per-keystroke work off the keystroke path: the in-document search (which rebuilds a whole-document text-offset mapping and applies the match selection through a `WKWebView` round trip) and the macOS system find-pasteboard write are now debounced (~200ms), while the search field and the file-list filter stay live. In-document match count and highlighting settle a beat after you stop typing.
- Added unit tests for the models and view models and reorganized the test target so each test file mirrors its source file's folder (`View Models/`, `Utilities/`, `Views/`). Removed the auto-generated `MarkdownPreviewUITests` target entirely (its empty UI-test bundle failed to launch and broke `Cmd-U`); a fresh UI Testing Bundle target will be created when a real GUI-test suite is added.

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
