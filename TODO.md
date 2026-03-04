# TODO

This document tracks planned work for MarkdownPreviewApp.

### Support image references.

### Allow editing in Source view.
  - On iPad and Mac, investigate showing preview and source at the same time.

### File menu (macOS and iPad).
  - Open (Cmd-O): present a file picker filtering for `.md`.
  - Print (Cmd-P): show system print panel and print current document/preview.
  - Quit (Cmd-Q): quit the app (macOS only).

### macOS startup behavior.
  - If there are no valid files after restore, automatically present the file picker.

### macOS redesign as a document-based app.
  - Use `DocumentGroup` (or `NSDocument`) so each document opens in its own window.
  - Replace in-app file list with system Recents.
  - Opening a file (for example, double-click in Finder) opens a new window for that doc.

### New from clipboard.
  - File -> New (Cmd-N): if clipboard has text, create a new unsaved document with that content.
  - File -> Save (Cmd-S): prompt to save as `.md`.

### Open remote URLs without downloading.
  - If `.onOpenURL` receives an `http(s)` link to a markdown file, fetch into memory and open in a new window.
  - Provide Save to persist locally if desired.

### Investigate iPad multi-window mode.
  - Evaluate scene/window behavior when opening multiple markdown files in Split View/Stage Manager.
  - Decide whether to keep single-window split navigation or support multiple app windows on iPadOS.

### Support side-by-side Preview and Source on Mac and iPad.
  - Add a layout mode that shows rendered preview and source simultaneously.
  - Ensure the mode works in regular-width environments on macOS and iPadOS.

### Add text size controls with per-file persistence.
  - Add controls to increase/decrease text size for markdown preview content.
  - Persist text size settings per file and restore the value when that file is reopened.

### Add clipboard support.
  - Add actions to paste/open markdown text directly from the clipboard.
  - Define copy behavior for source text and rendered preview content on each platform.

### Improve project documentation and samples.
  - Make a good `SAMPLE.md` file displaying features.
  - Make a better, more consumer-based `README.md` with screenshots displaying features.
  - Split out developer instructions to `CONTRIBUTING.md`.

### Get ready for TestFlight.
  - Investigate how to submit to App Store as an individual.
  - Submit app to App Store.
  - Set up TestFlight.
  - Capture and prepare App Store screenshots for iPhone, iPad, and Mac.

### Rename and simplify `ContentView.swift`.
  - Consider renaming `ContentView.swift` to a clearer top-level container name.
  - Consider combining this cleanup with YMMV-related work.

### Hardening for production use.
  - Improve handling/performance for very large markdown files.
  - Add robustness for markdown edge cases and malformed input across parser/renderer paths.

### Internationalization (i18n) and localization (l10n).
  - Localize all user-facing strings across iOS, iPadOS, and macOS.
  - Verify layout/text behavior for longer localized strings and right-to-left languages.

### Accessibility testing.
  - Run VoiceOver, Dynamic Type, contrast, and keyboard navigation checks on all platforms.
  - Fix accessibility labels/traits/focus order issues and add regression checks.

### Async file loading off `@Main`.
  - Read source files in a separate task, not on `@Main`.
  - If loading takes longer than 0.5 seconds, show a spinner with "Loading...".
  - Investigate checking file existence and polling in a separate `Task` as well.
  - Schedule this work after the YMMV-related refactor work.

### Add list title.
  - Add the title `Markdown Preview` to the list panel.

### Add list toolbar menu.
  - Add a hamburger menu next to the `+` button.
  - Include a menu entry that says `©2026 Syd Polk`.

### Implement search.
  - Add in-document search for markdown source and/or rendered preview.
  - Depends on current selection model and final copy behavior details.

### Selection/copy follow-ups.
  - Add multi-range selection in source and preview parity where feasible.
  - Implement copy export in plain text and rich text formats.
  - Define table-granularity selection behavior (whole table/row/column/cell/text).

### Add Copy button to quote and table blocks.
  - Expand the rounded-rect container to include a top strip.
  - In that top strip, add a right-aligned `Copy <icon>` action using the standard web-style copy icon.
  - On tap/click, copy the contents of that quote block or table block.
  - Set the current selection to the corresponding quote/table block in source.
  - Initial behavior: copy the original source block as plain text.
  - Follow-up behavior: also place an attributed version on the clipboard as RTF.

### BUG: Investigate why macOS sometimes opens a second list window when a file is double-clicked.

*Copyright ©2026 Syd Polk. All Rights Reserved.*
