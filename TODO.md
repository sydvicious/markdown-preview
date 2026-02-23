# TODO

This document tracks planned work for MarkdownPreviewApp.

## 1) Support Image References

## 2) [COMPLETED] Investigate why Mac does not know this opens .md files.

## 3) Allow editing of the text in the Source view.
- On iPad and Mac, investigate showing both preview and source at the same time.

## 4) File menu (macOS and iPad)
- Open (Cmd-O): Present a file picker filtering for .md files
- Print (Cmd-P): Show system print panel and print current document/preview
- Quit (Cmd-Q): Quit the app (macOS only)

## 5) macOS startup behavior
- If there are no valid files after restore, automatically present the file picker

## 6) [COMPLETED] iPhone/iPad document associations
- Configure Info.plist CFBundleDocumentTypes to open .md files
- Support opening in place and handle security-scoped URLs

## 7) Adopt MVVM
- Introduce a ViewModel to manage open/restore/persist, selection, and errors
- Keep MarkdownFile as the model; keep SwiftUI views focused on rendering

## 8) macOS redesign as a document-based app
- Use DocumentGroup (or NSDocument) so each document opens in its own window
- Replace in-app file list with system Recents
- Opening a file (e.g., double-click in Finder) opens a new window for that doc

## 9) New from clipboard
- File -> New (Cmd-N): If clipboard has text, create a new unsaved document with that content
- File -> Save (Cmd-S): Prompt to save as .md

## 10) Open remote URLs without downloading
- If .onOpenURL receives an http(s) link to a markdown file, fetch into memory and open in a new window
- Provide Save to persist locally if desired

## 11) Investigate iPad multi-window mode
- Evaluate scene/window behavior when opening multiple markdown files in Split View/Stage Manager.
- Decide whether to keep single-window split navigation or support multiple app windows on iPadOS.

## 12) Support side-by-side Preview and Source on Mac and iPad
- Add a layout mode that shows rendered preview and source simultaneously.
- Ensure the mode works in regular-width environments on macOS and iPadOS.

## 13) Add text size controls with per-file persistence
- Add controls to increase/decrease text size for markdown preview content.
- Persist text size settings per file and restore the value when that file is reopened.

## 14) Support remote URIs to `.md` files
- Open `http(s)` URIs that point to markdown files directly in the app.
- Handle redirects, content-type mismatches, and network failures with user-visible errors.

## 15) Add clipboard support
- Add actions to paste/open markdown text directly from the clipboard.
- Define copy behavior for source text and rendered preview content on each platform.

## 16) Improve project documentation and samples
- Make a good `SAMPLE.md` file displaying features.
- Make a better, more consumer-based `README.md` with screenshots displaying features.
- Split out developer instructions to `CONTRIBUTING.md`.

## 17) Get ready for TestFlight
- Investigate how to submit to AppStore as an individual.
- Submit apps to app store.
- Setup TestFlight.
- Capture and prepare App Store screenshots for iPhone, iPad, and Mac.

## 18) Break up and rename `ContentView.swift`
- Split `ContentView.swift` into smaller, focused files with clearer names.
- Consider combining this refactor with the YMMV-related work.

## 19) Hardening for production use
- Improve handling/performance for very large markdown files.
- Add robustness for markdown edge cases and malformed input across parser/renderer paths.

## 20) Internationalization (i18n) and localization (l10n)
- Localize all user-facing strings across iOS, iPadOS, and macOS.
- Verify layout/text behavior for longer localized strings and right-to-left languages.

## 21) Accessibility testing
- Run VoiceOver, Dynamic Type, contrast, and keyboard navigation checks on all platforms.
- Fix accessibility labels/traits/focus order issues and add regression checks.

## 22) Async file loading off `@Main`
- Read source files in a separate task, not on `@Main`.
- If loading takes longer than 0.5 seconds, show a spinner with "Loading...".
- Investigate checking file existence and polling in a separate `Task` as well.
- Schedule this work after the YMMV-related refactor work.

## 23) Add list title
- Add the title `Markdown Preview` to the list panel.

## 24) Add list toolbar menu
- Add a hamburger menu next to the `+` button.
- Include a menu entry that says `©2026 Syd Polk`.

## BUGS

- Investigate why macOS sometimes opens a second list window when a file is double-clicked.

Notes:
- Printing will require platform-specific integration (NSPrintOperation on macOS, UIPrintInteractionController on iPadOS)
- Keep iOS/iPadOS on the split-view design while macOS migrates to document-based
- Info.plist updates are required for document types and opening-in-place

*Copyright ©2026 Syd Polk. All Rights Reserved.*
