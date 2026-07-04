# TODO

This document tracks planned work for MarkdownPreviewApp.

### Bug fixes
- On Mac and iPad, search box should have a minimum width, but should fill the title bar otherwise. Mac, of course, has the filename, and it should be full. Priority is full file name, then expand Search Bar.

### Refactor
- MarkdownAppCommandCenter should be in its own file.
- MarkdownPreviewTextOffsetMapping and HTMLTextOffsetMapping should be in their own files.

### Investigate using Liquid Glass controls.

### Expand search and indexing
  - Sync selection between Preview and Source views while search results move between rendered and source representations.
  - `Command-Shift-F` should go to project-wide source search.
  - On iOS/iPadOS, investigate whether keyboard-level search suggestions can be populated for the existing search fields.
  - Add backend indexing optimizations now that the GUI/search interaction is stable.
  - Maintain a disk-backed word index mapping terms to files and source offsets.
  - Update the index incrementally as files are added, removed, or changed.
  - Use the index to accelerate file-list and in-document search across larger document sets.

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

### Refactor using YMMV

### Investigate iPad multi-window mode.
  - Evaluate scene/window behavior when opening multiple markdown files in Split View/Stage Manager.
  - Decide whether to keep single-window split navigation or support multiple app windows on iPadOS.

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
  - Add robustness for markdown edge cases and malformed input across parser/renderer paths.
  - Please write a test suite which generates .md snippets based on everything we support. Test the generated HTML page and make sure that the HTML is correct. Test the mapping from .md to source and source to HTML and back again.

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

### Add list toolbar menu.
  - Add a hamburger menu next to the `+` button.
  - Include a menu entry that says `©2026 Syd Polk`.

### Investigate a native visionOS (Vision Pro) app.

### BUG: Investigate why macOS sometimes opens a second list window when a file is double-clicked.
  - Verify whether this still reproduces after the startup/open-flow changes that now restore the previous session and append the Finder-opened file in the main window.

### BUG: Investigate intermittent detail-view flashing/redraw on macOS.
  - Reproduce cases where the currently displayed file flashes even when the file contents have not changed.
  - Verify whether the flash is tied to WKWebView navigation/reload, selection updates, focus changes, or file-monitor polling.

*Copyright ©2026 Syd Polk. All Rights Reserved.*
