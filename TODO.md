# TODO

This document tracks planned work for MarkdownPreviewApp.

### Bug fixes
- On Mac and iPad, search box should have a minimum width, but should fill the title bar otherwise. Mac, of course, has the filename, and it should be full. Priority is full file name, then expand Search Bar.
- On Mac, the remove (trash) toolbar button lands in a weird place: it ends up at the far trailing edge after the toolbar overflow (`»`) chevron, detached from the file list, and renders with an odd blue highlight. Revisit placement/grouping (likely resolved by the document-based redesign).

### Investigate using Liquid Glass controls.

### Expand search and indexing
  - Sync selection between Preview and Source views while search results move between rendered and source representations.
  - `Command-Shift-F` should go to project-wide source search.
  - On iOS/iPadOS, investigate whether keyboard-level search suggestions can be populated for the existing search fields.
  - Add backend indexing optimizations now that the GUI/search interaction is stable.
  - Maintain a disk-backed word index mapping terms to files and source offsets.
  - Update the index incrementally as files are added, removed, or changed.
  - Use the index to accelerate file-list and in-document search across larger document sets.
  - Optimize search-field typing performance on macOS (still not perfectly smooth; more work needed).
    - Current state (2026-07-03): both search fields bind to one shared `searchText` in `SearchViewModel`. On macOS the in-document search (which rebuilds the whole-document text-offset mapping and applies the match selection through a WKWebView JS round trip) and the system find-pasteboard write are both debounced ~200ms off the keystroke path. This helped but did not fully fix macOS typing lag; iOS is smooth.
    - Idea (Syd; low confidence — "I doubt that will help, but still"): split the currently-unified shared `searchText` back out into a separate backing store per search field (list vs. detail), and reconcile them to the shared search string on the same debounce as the pasteboard. The hope is that a keystroke would update only the focused field's local state instead of driving the whole shared-state re-render.
    - Idea: extract the search field(s) + results into a small subview so typing re-renders only that view, not the entire `ContentView`/`NavigationSplitView` (which currently re-runs the file-list filter and calls `updateNSView` on the preview WKWebView every keystroke).
    - Idea: cache the `MarkdownTextOffsetMapping` per document instead of rebuilding it over the whole document on every search.
    - Tune / make the 200ms debounce adaptive.

### Generate a spotlight index for content

### macOS redesign as a document-based app.
  - Use `DocumentGroup` (or `NSDocument`) so each document opens in its own window.
  - Replace in-app file list with system Recents.
  - Opening a file (for example, double-click in Finder) opens a new window for that doc.
  - Build a sensible menu structure for the document-based app.
  - File menu (macOS and iPad).
    - Open (Cmd-O): present a file picker filtering for `.md`.
    - Print (Cmd-P): show system print panel and print current document/preview.
    - Quit (Cmd-Q): quit the app (macOS only).

### New from clipboard.
  - File -> New (Cmd-N): if clipboard has text, create a new unsaved document with that content.
  - File -> Save (Cmd-S): prompt to save as `.md`.

### Open remote URLs without downloading.
  - If `.onOpenURL` receives an `http(s)` link to a markdown file, fetch into memory and open in a new window.
  - Provide "Save as..." to persist locally if desired.

### Support side-by-side Preview and Source on Mac and iPad.
  - Add a layout mode that shows rendered preview and source simultaneously.
  - Ensure the mode works in regular-width environments on macOS and iPadOS.

### Support image references.

### Improve project documentation and samples.
  - Make a good `SAMPLE.md` file displaying features.
  - Make a better, more consumer-based `README.md` with screenshots displaying features.
  - Split out developer instructions to `CONTRIBUTING.md`.

### Revisit app icon text.
  - Consider changing the icon text from `MD` to `.md` so it more clearly suggests opening markdown files directly.

### Get ready for TestFlight.
  - Investigate how to submit to App Store as an individual.
  - Submit app to App Store.
  - Set up TestFlight.
  - Capture and prepare App Store screenshots for iPhone, iPad, and Mac.
  - Automate `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` bumps in CI/CD (currently a manual convention: both are centralized in `Version.xcconfig` and bumped in lock step on the first commit after a release).

### Rename and simplify `ContentView.swift`.
  - Consider renaming `ContentView.swift` to a clearer top-level container name.
  - Consider combining this cleanup with YMMV-related work.

### Hardening for production use.
  - Improve handling/performance for very large markdown files.
    - Profile and handle really large files end to end: parsing/rendering, the offset mappings (`MarkdownTextOffsetMapping`/`HTMLTextOffsetMapping` currently rebuild over the whole document), in-document search, and WKWebView load/selection. Expect this to be significant work.
    - Consider incremental/virtualized rendering or chunking so opening, scrolling, and searching stay responsive; guard against pathological inputs (huge single lines/tables, deeply nested structures).
    - Relates to the search-field performance work under "Expand search and indexing."
  - Add robustness for markdown edge cases and malformed input across parser/renderer paths.
  - Please write a test suite which generates .md snippets based on everything we support. Test the generated HTML page and make sure that the HTML is correct. Test the mapping from .md to source and source to HTML and back again.

### Internationalization (i18n) and localization (l10n).
  - Localize all user-facing strings across iOS, iPadOS, and macOS.
  - Verify layout/text behavior for longer localized strings and right-to-left languages.

### Accessibility testing.
  - Run VoiceOver, Dynamic Type, contrast, and keyboard navigation checks on all platforms.
  - Fix accessibility labels/traits/focus order issues and add regression checks.

### Add a small XCUITest suite for key flows.
  - Cover a few high-value end-to-end flows using existing accessibility identifiers (open file → appears in list, list search filters the list, remove from list, Preview⇄Source switch). Keep it compact; AI to author and maintain. Skip brittle targets (WKWebView selection, find-pasteboard sync, native context menus).
  - Wait until BOTH: (1) the document-based macOS app redesign has landed (the UI is changing), and (2) iOS simulators work under Xcode 27 — on-device-only iteration is too slow for a GUI suite right now.
  - The `MarkdownPreviewUITests` target (auto-generated boilerplate) was removed entirely on 2026-07-03 because an empty UI-test target fails to launch and broke `Cmd-U`. Recreate a fresh UI Testing Bundle target (File → New → Target) when adding these.

### Async file loading off `@Main`.
  - Read source files in a separate task, not on `@Main`.
  - If loading takes longer than 0.5 seconds, show a spinner with "Loading...".
  - Investigate checking file existence and polling in a separate `Task` as well.
  - Schedule this work after the YMMV-related refactor work.

### Adopt Swift 6 "MainActor by default" concurrency.
  - Move the targets to the Swift 6 language mode and enable Default Actor Isolation = MainActor (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`). Currently on Swift 5 mode with no default actor isolation.
  - Resolve the concurrency diagnostics this surfaces (Combine `objectWillChange` bridges in `ContentViewModel`, the file-monitor/focus `Task`s, `DispatchQueue.main.async` paths, and the AppKit `AppDelegate`).
  - Remove now-redundant explicit `@MainActor` annotations once the default covers them.
  - Note: audited 2026-07-03 — all `@Published` mutations already run on the main thread, so nothing currently *requires* `@MainActor` beyond what is annotated (`FileOpenState` is the only non-`@MainActor` observable and is only mutated from the main-thread open paths).
  - Do this as its own pass, not bundled with a release build.

### Add list toolbar menu.
  - Add a hamburger menu next to the `+` button.
  - Include a menu entry that says `©2026 Syd Polk`.

### Investigate a native visionOS (Vision Pro) app.
  - Only pursue if visionOS / Vision Pro is still a relevant, shipping platform by the time there is something to ship on it.

### Cross-platform widgets (instead of a first-class Apple Watch app).
  - Ship a single WidgetKit widget bundle that renders on macOS, iOS/iPadOS, and watchOS (accessory / complication families) — chosen over a bespoke watchOS companion app because one shared codebase covers the watch essentially for free.
  - Decide what the widgets surface: recent/pinned documents (tap to open), quick actions (open, new from clipboard), and maybe a small rendered snippet or title of a pinned document.
  - Expose recent/pinned documents to the widget extension via an App Group / shared container. The app currently persists documents in its own `UserDefaults` + security-scoped bookmarks, so the extension needs a shared read path (bookmark access from an extension needs care).
  - Deep-link from a widget into the app to open the tapped document (`widgetURL` → `.onOpenURL`; reuse or extend the existing file-open handling).
  - Provide the standard widget families per platform (systemSmall/Medium on iOS/macOS; accessory/rectangular/circular for watchOS and the Lock Screen).
  - Sequencing: this pairs naturally with the document-based macOS redesign (both treat recent documents as first-class), so the App Group / shared-container data layer overlaps — build them together or share the layer.
  - Prototype the shared-container / bookmark data path first; that is the genuinely fiddly part, while the widget UI itself is straightforward.

*Copyright ©2026 Syd Polk. All Rights Reserved.*
