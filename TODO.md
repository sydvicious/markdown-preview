# TODO

This document tracks planned work for MarkdownPreviewApp.

## 1) Investigate why Mac does not know this opens .md files.

## 2) Update when the file changes while the app is open.
- If the currently displayed file disappears:
  - Present a modal alert.
  - When the user presses OK, remove that file from the list.
  - On iPhone, if currently in detail view, navigate back to the list view.
- If a file that is not currently displayed disappears:
  - Remove it from the list without showing an alert.
- If the file moves, update the reference.
- Detection strategy:
  - Long-term: move to filesystem notifications.
  - Initial implementation: poll the active file every 1 second and all files every 10 seconds.

## 3) Allow editing of the text in the Source view.
- On iPad and Mac, investigate showing both preview and source at the same time.

## 4) File menu (macOS and iPad)
- Open (Cmd-O): Present a file picker filtering for .md files
- Print (Cmd-P): Show system print panel and print current document/preview
- Quit (Cmd-Q): Quit the app (macOS only)

## 5) macOS startup behavior
- If there are no valid files after restore, automatically present the file picker

## 6) iPhone/iPad document associations
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

## 11) Support Image Referenes

Notes:
- Printing will require platform-specific integration (NSPrintOperation on macOS, UIPrintInteractionController on iPadOS)
- Keep iOS/iPadOS on the split-view design while macOS migrates to document-based
- Info.plist updates are required for document types and opening-in-place

## Completed (2026-02-22)

- Replaced SwiftUI table rendering with an embedded `WKWebView` table renderer.
- Added horizontal scrolling for wide tables and auto-height reporting back to SwiftUI.
- Added inline backtick rendering in table cells/headers.
- Tuned iOS table typography and disabled text inflation for consistent sizing.

*Copyright ©2026 Syd Polk. All Rights Reserved.*
