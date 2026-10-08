<!-- Copyright @2026 Syd Polk. All Rights Reserved -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# TODO

This document tracks planned work for MarkdownPreviewApp.

## Bugs

### (macOS) Search field focus and Find Next across files.
  - `Command-F` should put focus on the detail view's Search field.
  - Tab should take focus to the file list's Search field, and Tab again should take it back.
  - When the detail view's Search field has focus, Return, the next/previous arrows, `Command-G` and `Shift-Command-G` should send focus back to the detail view — and the navigation should still work.
  - When focus is in the file list's Search field, `Command-G` should search in the current file. When it reaches the bottom of that file, it should open the next file in the list and highlight the search text there.
  - When focus is in either Search field, Esc should put focus back in the detail view. It should still clear the search text too, as it does today.

### Proposed performance fixes.
  - Decide whether the engine's scanner is worth making faster. A 505 KB document builds in 83 ms, and its text is read for searching in 91 ms, in a release build; a debug build takes two to three times as long. What is left is the tokenizer comparing a whole `Character` at a time as it scans, and the parsing of table rows. Having the scanner work on bytes would be a large change to the tokenizer.
  - Take the read off the main actor. It is 3 ms as a rule, but `MarkdownFile.load` waits up to 30 seconds, sleeping the thread between tries, for an iCloud file that has not downloaded.
  - Take the image checks off the main actor: 29 ms for a 505 KB document. They need the folders the app has been granted, which are the main actor's.
  - Shorten setting a long document's text into the source pane, or show the pane before it is done. It is on the main actor, the first time the document is shown in Source: 148 ms for 1.4 MB, in a debug build on an iPad simulator.
  - Take the first placing of a selection in a document off the main actor, or have it use what building the page already read. The whole document is read to find the blocks the selection touches: about 220 ms for 1.4 MB, in the same build. It is kept after that, so only the first one costs.
  - Find out why a page in a web view taken from the spare says it has loaded some 300 to 400 ms after it has painted: a short page painted at 43 to 122 ms and loaded at 308 to 422 ms, where in a web view made for it the same page loaded at 23 ms. The app waits for that before it puts back a selection or the reader's place.

### The source pane lands near a place far down a long document, and not on it.
  - When the source pane has to follow the preview to a place far down a long document, it lands close to the place and not on it. That is after the reader scrolls Preview by hand and switches to Source, and on iPhone on coming back from the list, where both panes are made again.
  - The pane is scrolled to a character offset. That far down, the text above has not been laid out, so where the line is is an estimate. Asking twice, a turn apart, does not settle it.
  - Find a way to put a line at the top of the source pane that is right that far down. Scrolling a range into view, which is how the selection has always been shown there, may already be right where asking for the line's rectangle is not.
  - Within one long block, a long list or code block, the place is taken by proportion, in both directions. Decide whether that is close enough.

### A line selected by triple-click in the preview does not stay a line.
  - Clicking three times on a line in the preview highlights the line and a strip below it, into the block after. Switching to Source and back highlights the line's words alone. The highlight should be the line alone from the click.
  - After that trip through Source, a copy from the preview is expected to be the words and not the line: no `#` or list marker, and no line ending. Confirm it with a paste.
  - When the mouse comes up on a selection that runs into the next block, or the next item of a list, and takes nothing from it, draw its end back to the last text it takes.
  - Have the page remember that this exact selection is whole lines, so that a copy of it is still the line as it is written.
  - When the app puts a whole-line selection into the page, as it does on the way back from Source, pass the same note with it.
  - This changes the selection under WebKit, which only running the app can check: try a triple-click and drag, and touch selection on iPad.

### Open every file dropped from the Finder, not only one.
  - Several files dragged from the Finder and dropped on the window should all be opened.
  - This may have worked once. Find out whether it did, and what stopped it.

## Features

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
    - Current state: both search fields bind to one shared `searchText` in `SearchViewModel`. On macOS the in-document search (which rebuilds the whole-document text-offset mapping and applies the match selection through a WKWebView JS round trip) and the system find-pasteboard write are both debounced ~200ms off the keystroke path. Typing on macOS still lags; iOS is smooth.
    - Idea (Syd; low confidence — "I doubt that will help, but still"): split the currently-unified shared `searchText` back out into a separate backing store per search field (list vs. detail), and reconcile them to the shared search string on the same debounce as the pasteboard. The hope is that a keystroke would update only the focused field's local state instead of driving the whole shared-state re-render.
    - Idea: extract the search field(s) + results into a small subview so typing re-renders only that view, not the entire `ContentView`/`NavigationSplitView` (which currently re-runs the file-list filter and calls `updateNSView` on the preview WKWebView every keystroke).
    - Idea: cache the `MarkdownTextOffsetMapping` per document instead of rebuilding it over the whole document on every search.
    - Tune / make the 200ms debounce adaptive.

### Generate a spotlight index for content

### Claim `.md` as our app's file type on iOS. (investigate)
  - On macOS the app already registers as an `Owner` for `net.daringfireball.markdown` (`LSHandlerRank = Owner`) and the user can make it the default through Finder's Get Info → Open With → Change All. iOS has no equivalent user-facing "default app for this type" control, even though the same document-type declarations already ship (the `INFOPLIST_KEY_CFBundleDocumentTypes` / `UTImportedTypeDeclarations` build settings, shared with macOS).
  - Investigate what actually makes iOS route a `.md` file to this app: how iOS picks a default handler among apps that claim a type, whether `LSHandlerRank` / `CFBundleTypeRole` carry any weight there, the roles of `LSSupportsOpeningDocumentsInPlace` and the document-browser APIs, and whether "open in place" vs. "copy to app" changes Share-sheet placement. Goal: a `.md` opened from Files, Mail, or another app reliably offers — and ideally defaults to — MarkdownPreview.
  - Observed example (behavior only): Indeed's "Job Search" app claims `.doc` for resume uploads and wins that association aggressively — proof the behavior we want for `.md` is achievable. Do **not** reference Indeed's proprietary sources or Info.plist for this; work from Apple's public documentation on document-type declarations, exported/imported UTIs, and handler rank.

### Share sheet (iOS) and printing.
  - **iOS/iPadOS: add a share sheet.** Wire a `ShareLink` / `UIActivityViewController` on the current document so the standard system share sheet is available. This earns its keep beyond sharing: the iOS share sheet carries the system **Print** activity for free, so printing on iOS comes along without a bespoke print path. What gets shared is the source `.md` file URL: the original document, as-is.
  - **macOS: printing is a separate path, but the iOS work may carry most of it.** The Mac has no share-sheet Print activity, so it needs its own trigger: an `NSPrintOperation` over the preview `WKWebView` (`WKWebView` vends a print operation), wired to a File → Print (Cmd-P) command. What the iOS work should get for free is everything behind that trigger — deciding what a printed page contains and rendering it, which both platforms want to match the preview and so likely comes from the same HTML the preview already builds. Do the iOS side first and see how much of the Mac path is left; the expectation is that only the command wiring is genuinely Mac-specific.
    - **1.0 needs an interim printing solution on the Mac — approach TBD.** The File → Print menu item was originally scoped as part of the document-based redesign, which is now deferred to a later version (see the File menu under "macOS redesign as a document-based app"). 1.0 ships the current Mac UI, so printing needs some path that works in the menus as they stand today, without waiting for the redesign to give it a permanent home. Decide what that interim path is; expect the redesign to replace it rather than inherit it.
    - Not implemented yet — the app currently has no print path or share sheet on either platform.

### Export.
  - Writes the document out as it was read. That is the entire feature.
  - 1.0 needs it two ways: an Export… item in the File menu on Mac and iPad, and the share sheet on iOS and iPadOS (see "Share sheet (iOS) and printing").

### Open remote URLs without downloading.
  - If `.onOpenURL` receives an `http(s)` link to a markdown file, fetch into memory and open in a new window.
  - Provide "Save as..." to persist locally if desired.

### Support side-by-side Preview and Source on Mac and iPad.
  - Add a layout mode that shows rendered preview and source simultaneously.
  - Ensure the mode works in regular-width environments on macOS and iPadOS.

### Support inline HTML.
  - Raw HTML in the source is currently escaped rather than rendered — `MarkdownHTMLBuilder` emits the literal `&lt;br&gt;` for a `<br>`, so tricks like `<br>` or `&nbsp;` for a blank line, or any inline markup, show as text instead of taking effect. Passing it through would let CommonMark documents that mix in HTML render as authors intend.
  - This is a security decision before it is a feature. The escaping is load-bearing: `MarkdownImageURL` (`MarkdownCore/Sources/MarkdownCore/MarkdownImageURL.swift:27`) notes that escaping raw HTML is what stops a document forging an `mdimage://` URL, and the per-launch nonce exists precisely to hold that guarantee "if raw HTML is ever supported." So enabling passthrough means the nonce becomes the real defense and a document can otherwise inject arbitrary markup into the preview `WKWebView`.
  - Chosen direction: a curated allow-list of safe inline tags, with everything else still escaped exactly as today. This is the conservative first step — it covers the common reasons documents reach for HTML (a `<br>`, a `<sub>`/`<sup>`) without opening the door to full-document passthrough. Full passthrough behind a general HTML sanitizer stays out of scope until there is a reason for it; do not ship unfiltered passthrough into the web view.
    - `<br>` is the driving case and the minimum bar for calling this done. It is the one people reach for constantly — an intentional in-paragraph line break that markdown can only express with trailing double-spaces, which are invisible and easy to strip. If the first cut only un-escapes `<br>` and nothing else, that already delivers most of the value; the rest of the tag set is a follow-on.
    - Candidate tag set: `<br>` first, then the inline formatting tags `<b>`, `<strong>`, `<i>`, `<em>`, `<u>`, `<s>`/`<del>`/`<ins>`, `<sub>`, `<sup>`, `<mark>`, `<small>`, `<kbd>`, `<samp>`, `<var>`, `<abbr>`, `<cite>`, `<q>`. Note that markdown already produces most of these; the value here is the ones it cannot express — line breaks, subscript/superscript, highlight.
    - Deliberately excluded: `<a>` (its `href` can be `javascript:`), `<img>` (goes through the `mdimage://` path, not raw HTML), `<span>`/`<div>` (a styling hook with no semantics worth the attribute surface), and every block/script/embed tag.
    - Attributes are the real risk, not the tag names. An allowed tag with `onclick`, `onmouseover`, `style`, or an `id`/`href` is still an injection vector. Strip all attributes on allowed tags to start — none of the tags above need one to be useful except `<abbr title>`, so decide whether that single attribute is worth a value-sanitized exception or whether `<abbr>` renders bare.
    - Keep the nonce guarantee intact: even with these tags allowed, no allowed tag can emit an `mdimage://` URL, so a document still cannot forge one. Verify this holds for whatever exception `<abbr title>` gets.

### Support a subset of raw HTML tags: `<br>` and `<img>`.
  - Scope is deliberately just these two tags to start — the concrete cases Syd wants — carved out of the broader "Support inline HTML" allow-list rather than shipping that whole set at once. Everything not on the list stays escaped exactly as today. This shares that section's machinery and security model; read it first.
  - **`<br>`** is the easy half and the minimum bar. Un-escape a bare `<br>` (and `<br/>` / `<br />`) into a real line break; keep escaping everything else. Note this is distinct from "Honor source line breaks" — that made a *source newline* render as a break, which delivers most of the day-to-day value. This adds the case where the author literally typed the `<br>` tag and today sees the literal text `<br>` instead. `<br>` takes no attributes, so there is nothing to sanitize on it.
  - **`<img>`** reverses the exclusion recorded under "Support inline HTML" ("`<img>` goes through the `mdimage://` path, not raw HTML"). The point of allowing it is that a document can use the familiar HTML form, and — unlike markdown's `![alt](src "title")` — get sizing via `width`/`height`. It must reuse the existing image pipeline, not grow a second one: rewrite the `src` through `MarkdownImageURL` → `mdimage://` and let `MarkdownImageSchemeHandler` serve the bytes, exactly as `![]()` already does, so local/relative/iCloud/remote-`https` resolution and the sandbox folder-grant flow all come for free.
  - **`<img>` is the exact forge vector the launch nonce was built for.** The nonce and the "escape all raw HTML" rule exist together precisely so a document *cannot* hand the scheme handler a `mdimage://` URL it minted itself; allowing a raw `<img>` is the first time a document gets to put a `src` in front of that handler, so the nonce stops being a latent guarantee and becomes the live defense. The handler already refuses any `mdimage://` URL without the current-launch nonce — verify that still holds when the URL originates from a raw `<img src>` and that the document can only ever reach the handler through the rewrite (which stamps the nonce), never by writing an `mdimage://` literal itself.
  - Attributes are the whole risk. Allow only a safe set on `<img>` — `src`, `alt`, `title`, `width`, `height` — and strip everything else. `onerror`/`onload` (and every other `on*`) and `style` must be dropped: `<img src=x onerror=…>` is the textbook injection and is the reason `<img>` was excluded in the first place. `src` is not passed through verbatim — it goes through the same resolve-and-rewrite as markdown images, so `javascript:`/`data:`/arbitrary schemes never reach the web view; a `src` that does not resolve to a real, readable image file (or an allowed remote `http(s)` URL) is refused the same way an unresolved `![]()` is.
  - Testable in `MarkdownCore` without the app: a raw `<br>` becomes a break tag while `<br onclick=…>`-style noise stays escaped; a raw `<img src="photo.jpg">` rewrites to a nonced `mdimage://` URL with the same resolution rules as `![]()`; `onerror`/`style`/unknown attributes are stripped; a forged `mdimage://` literal in the source stays escaped and never reaches the handler.

### Open images in their natural app on click.
  - Clicking a rendered image should hand the file off to the system to open in the default app for that image type.
  - Route this through the system open handler (`NSWorkspace.open` on macOS, `UIApplication.open`/`openURL` on iOS), as links already are, so the app is not choosing the target app itself.

### Ship a welcome document in the app bundle.
  - How it works, for what follows: on first launch the app copies `SAMPLE.md` into its own private Documents container, not the user's `~/Documents`, and adds it to the list. The copy is kept current with each build whether or not it is in the list, and the user cannot reach it — it is deliberately not shown in the Files app. Removing it from the list only hides it.
  - Vet the feedback and support links against App Review before shipping them. Anything that reads as taking the user outside the app to transact — donations, purchases, subscriptions — is the usual rejection trigger; a plain support or feedback address is not. Keep it to what the app needs.
  - Localization is the real cost here: this is prose in a bundled file, so every supported language needs its own copy kept in sync, which is worse than localizing a string table. See "Internationalization (i18n) and localization (l10n)".
  - Open: re-adding after removal. Since the container copy persists, "reopen the welcome document" means re-adding that copy to the list. Provide a Mac/iPad **menu item** and an **iPhone gesture** that do exactly this (see the Help-menu note under "macOS redesign as a document-based app"). The app never re-adds it automatically; this is the user-initiated way back.
  - iOS and iPadOS have no About box and nowhere else to put this content, so the document in the list on first launch is the whole mechanism there, not a supplement to something else. The alternatives considered were a bottom sheet on first launch — explicitly not wanted — or doing nothing at all. If the bundled document does not work out, doing nothing is the fallback; do not reach for the sheet.
  - On macOS the About box is to be simple, with a button that opens the welcome document. That work lives with the document-based redesign, which is where the macOS menu structure gets built (see the App menu under "macOS redesign as a document-based app"); the bundled welcome document itself does not wait on it.

### Investigate menus.
  - iPadOS generates a menu bar automatically from the app's commands, and it comes out wrong: there are **two View menus**, plus other problems worth cataloguing once looked at properly.
  - The duplication is the obvious lead. The app defines a `CommandMenu("View")` in `MarkdownPreviewCommands` (`MarkdownPreview/MarkdownPreviewApp.swift`) for the text-size commands, while iPadOS also synthesizes its own standard View menu — so both appear. The same likely applies to the `Find` and `Search` menus, which may duplicate or displace system equivalents; `Search` in particular exists only to host Escape as Cancel Search, which is not really a menu-worthy command.
  - Prefer the standard command groups where they exist (`CommandGroupPlacement.textEditing`, `.toolbar`, `.sidebar`, and the built-in Find group) over bespoke `CommandMenu`s, which is what stops iPadOS synthesizing a second copy.
  - **Open question: can that generated menu bar be made to appear on the Mac?** Worth investigating — the Mac's menus are currently hand-built by the same `Commands` block, so if the platforms can share one definition that renders correctly on both, that is strictly less to maintain. Find out what iPadOS is generating from and whether macOS can be driven the same way.

### Add list toolbar menu.
  - Add a hamburger menu next to the `+` button.
  - Include a menu entry that says `©2026 Syd Polk`.

### Internationalization (i18n) and localization (l10n).
  - Standing design principle: expose as little visible text in the GUI as possible, so there is less to localize. The Mac menu bar unavoidably needs it; nearly everything else can avoid it.
    - The larger saving is layout, not translation. Visible strings are what force layouts to reflow for longer translations and to be re-verified per language; a GUI without them largely sidesteps that, and the menu bar is laid out by the system anyway. This is also why concentrating the strings in accessibility labels and placeholders works: labels never affect layout at all, and a field's placeholder does not resize the field.
    - Prefer icons to text labels, and prefer standard system controls and commands, whose strings Apple already localizes, over hand-rolled equivalents with custom wording.
    - Treat any new user-visible string as a cost to be justified, not a default. This applies to empty states, confirmation copy, and error messages as much as to labels.
    - Accessibility labels and field placeholders are where the strings will unavoidably live, and that is accepted: an icon-only interface leans harder on them, and both are user-facing text that must be localized. Budget for localizing them even though they are not visible clutter — see "Accessibility testing."
  - Localize all user-facing strings across iOS, iPadOS, and macOS.
  - Fully localize `SAMPLE.md`, the welcome document. It is prose in a bundled file, not a string table, so every supported language needs its own complete copy, and the app has to seed the copy for the user's language.
  - Verify layout/text behavior for longer localized strings. Scope this to wherever visible text survived the principle above — the fewer such places, the cheaper this step gets.
  - Right-to-left languages need a real pass eventually, since RTL affects layout direction and icon mirroring rather than just string length. **Low priority** given the expected number of RTL users for this app. Accessibility comes first.

### Accessibility testing.
  - Higher priority than right-to-left localization, and higher than i18n generally. It reaches far more users, and the deliberately icon-heavy design (see "Internationalization (i18n) and localization (l10n)") makes it load-bearing rather than optional: with few visible labels, a VoiceOver user is navigating almost entirely by accessibility labels, so a missing or wrong one makes a control unusable rather than merely unpolished.
  - Run VoiceOver, Dynamic Type, contrast, and keyboard navigation checks on all platforms.
  - Fix accessibility labels/traits/focus order issues and add regression checks.
  - Audit that every icon-only control has an accurate label and the right traits, and that the labels are localized. These are the strings the design deliberately concentrates text into, so they are the ones that most need to be right.

## Tech Debt

### Rename and simplify `ContentView.swift`.
  - Consider renaming `ContentView.swift` to a clearer top-level container name.
  - Consider combining this cleanup with YMMV-related work.

### Hardening for production use.
  - Improve handling/performance for very large markdown files.
    - Profile and handle really large files end to end: parsing/rendering, the offset mappings (`MarkdownTextOffsetMapping` currently rebuilds over the whole document), in-document search, and WKWebView load/selection. Expect this to be significant work.
    - Consider incremental/virtualized rendering or chunking so opening, scrolling, and searching stay responsive; guard against pathological inputs (huge single lines/tables, deeply nested structures).
    - Relates to the search-field performance work under "Expand search and indexing."
  - Add robustness for markdown edge cases and malformed input across parser/renderer paths.

### Turn content JavaScript off in the preview. (investigate)
  - Why: clicking a `javascript:` link runs its script in the preview's page. WebKit does not call `decidePolicyFor` for one, so the app's link handling never sees it. Script in the page can read the key `MarkdownImageURL` puts on image URLs, and so ask the scheme handler for other image files the app can read, and can post to the app's message handlers.
  - The renderer is one layer: it writes a link or autolink whose destination is `javascript:` or `vbscript:` without its `href`. The second would be `allowsContentJavaScript = false` on the preview's `WKWebpagePreferences` — it is set to `true` in both platforms' `makeUIView`/`makeNSView` in `MarkdownPreviewWebView.swift`. Apple documents that setting as stopping script the *content* brings, `javascript:` URLs included, while user scripts and `evaluateJavaScript` still run. If that holds, nothing a document contains could run script even if the renderer let something through, and it is the right default before raw HTML is allowed in ("Support inline HTML").
  - To check before changing it: that the app's own scripts still work with it off — the Copy button, selection reporting and applying, the image-access button, scroll reporting and restoring. The WebKit tests build their own configuration, so they do not exercise the app's; they would need to share it, or this wants checking in the running app.

### Close the gaps the test audit found.
  - No UI tests. Syd is not willing to write or maintain any more of them than there already are, particularly since the Mac app is going to have a complete redesign at some point. The one exception is a specific GUI bug that has to be verified and cannot easily be reproduced by hand. In their place, working previews to play with: both need mocks and discipline, but a preview adapts as the interface changes, where GUI tests are much harder to maintain.
  - Working previews in place of tests, for `MarkdownPreviewView.swift`:
    - The image decision: one preview each for a document whose images load, are missing, and are unreadable.
    - `PreviewSelectionSynchronizer`: a preview showing the preview and the source together, to select in by hand.
  - Markdown features with nothing to assert yet, to cover when they exist: a line break inside a table cell (there is no way to write one until `<br>` is supported), strikethrough, and bare-URL autolinks.
  - Land any future suite complete and runnable even where it exposes bugs. Do not gate landing the tests on fixing what they find, and do not delete or weaken a test to make the suite green.
    - A release, and a feature called complete, have no failing tests. While work is under way an intermediate commit may have them, and a failure that goes on for a while is converted to an expected failure. A test that shows a known bug, or a feature left unbuilt on purpose, is marked an expected failure (`withKnownIssue`): it does not fail the run, and it does fail the run once it starts passing, which is the signal to take the marking off.
    - A test that fails while the code is behaving correctly is not a valid test; change or remove it.
    - Updating a test because the intended behavior changed is a different thing and is expected. What is not allowed is softening an assertion to hide a defect.
    - File each exposed bug as its own entry under "Bugs" so the failing test and the bug are linked.

### Test everything before a release.
  - `Scripts/release-build.sh` runs `Scripts/run-tests-release.sh` before it archives, and that step has never been run. Watch it at the next release: from Terminal, and from the `Release DMG` target, which finds Homebrew's Node where Terminal finds nvm's.
  - Not yet seen: a failing Mac or simulator test stopping a release, or what `Scripts/run-tests-release.sh` prints for one, and for a build that fails.

### Set up CI/CD on the new Mac mini.
  - Run a build server on the M5 Pro Mac mini, and set up a CI/CD system on it. Probably Jenkins; not decided.
  - What it would run: `Scripts/run-tests-mac.sh`.

### Adopt Swift 6 "MainActor by default" concurrency.
  - Move the targets to the Swift 6 language mode and enable Default Actor Isolation = MainActor (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`). Currently on Swift 5 mode with no default actor isolation.
  - Resolve the concurrency diagnostics this surfaces (Combine `objectWillChange` bridges in `ContentViewModel`, the file-monitor/focus `Task`s, `DispatchQueue.main.async` paths, and the AppKit `AppDelegate`).
  - Remove now-redundant explicit `@MainActor` annotations once the default covers them.
  - Do this as its own pass, not bundled with a release build.

### Move the build and release scripts to a shared repo. (investigate)
  - Syd: "we might need to make a separate repo for build/release scripts." `Scripts/release-build.sh` and `Scripts/bump-version.sh` are adapted copies of the same scripts in `photos-go-round`, and every new app gets another copy (the global `app-release` skill), so each fix has to be made once per app.
  - Decide how an app consumes the shared scripts — a git submodule, a checkout at a known path beside the apps, or copies kept in sync from one source — and what stays per app: the app name, project and scheme, the version-config path, the releases folder, and the post-export checks (this app's sandbox; `photos-go-round`'s helpers, extensions and Photos entitlement, and its Finder-laid-out DMG).
  - The same item is in `photos-go-round`'s `TODO.md`; do it once for both.

## Later versions

### macOS redesign as a document-based app.
  - Restructure the project around Swift packages while doing this, since the platforms are diverging anyway.
    - Put the view models in their own Swift package, so they are testable without an app host like `MarkdownCore` already is.
    - Separate packages for the Mac interface and the iOS interface. The document-based Mac design and the iPhone/iPad navigation stack have little left in common, and separating them stops each platform's `#if os(...)` branches from cluttering the other.
    - The Mac interface is essentially a fresh start, not a port. Going document-based changes enough that the existing views are a reference at most; expect to write the Mac package rather than move code into it. The current views carry over to the iOS package and keep evolving there.
    - So the two interface packages are not two copies of the same thing, and there is no shared UI package. Whatever overlap survives is incidental — do not factor it back out.
    - **Each platform gets the interface that is right for it; sharing view code is not a goal and must not constrain either one.** If the Mac wants a structure that would break the iOS views, that is fine and expected.
    - **Models and view models, on the other hand, should be shared** — that is the point of putting them in their own package. Both interfaces sit on the same view models and the same `MarkdownCore`, and only the views differ. Where a platform needs something the shared view models cannot express, prefer extending them over forking; the split is meant to fall at the view boundary, not lower.
    - One top-level application file per platform — a Mac one and an iOS one — each in its own directory, rather than a single shared entry point with conditional compilation inside it.
    - Two `Info.plist` files, one per platform. The project already half does this: `GENERATE_INFOPLIST_FILE` is off for macOS with `INFOPLIST_FILE[sdk=macosx*] = Info-macOS.plist`, while iOS still uses a generated one. Make both explicit and give each its own directory alongside its app file.
    - Attach every new package to the project as a **navigator folder**, not via Add Package Dependency, or its tests will not be visible to Xcode.
  - Use `DocumentGroup` (or `NSDocument`) so each document opens in its own window.
  - Replace in-app file list with system Recents.
  - Opening a file (for example, double-click in Finder) opens a new window for that doc.
  - Build a sensible menu structure for the document-based app. A standard Mac app has an About box and File and Edit menus, and has since 1984; Window and Help joined them in Mac OS X. This is the baseline users expect, not a checklist to trim because the app is a simple viewer — a Mac app without them reads as unfinished.
    - The app is a viewer, not an editor. File and Edit carry only operations that do not imply changing the document's content — no Save, no Undo, no Cut or Paste, and no editing affordances that would suggest the file can be modified in place. "Export…" is the intended way to write anything out.
    - App menu: About — a simple About box with a button that opens the welcome document (see "Ship a welcome document in the app bundle") — and Quit (Cmd-Q).
      - The About box work sits here rather than with the welcome document because it needs the macOS menu structure this redesign builds. The bundled document itself ships independently of this section.
      - Supersedes the `©2026 Syd Polk` menu entry under "Add list toolbar menu" if that entry was standing in for an about box; decide which of the two is wanted.
    - File menu: Open (Cmd-O), Open Recent, Close (Cmd-W), Print (Cmd-P). Printing is a future feature and is not implemented yet — see "Share sheet (iOS) and printing" for the macOS `NSPrintOperation` path. Export… writes the document out as it was read (see "Export").
    - Edit menu: Copy (Cmd-C), Select All (Cmd-A), and the Find commands. Read-only operations only, so the menu stays honest about what the app does.
    - Window menu: the standard document-window entries that `DocumentGroup` provides.
    - Help menu: reopening the welcome document belongs here. Because the container copy persists and stays updated, "reopen" means re-adding that copy to the list (the iPhone equivalent is a gesture — see "Ship a welcome document"). A "Show Release Notes" item also belongs here: the sample is not a changelog, and a user who has removed it from the list won't see its updates until they re-add it, so release notes are the reliable place to surface what changed in a build.
    - "New from clipboard" is a 2.0 feature, so File → New and File → Save stay out of the menus for now. When it lands, revisit how it fits the read-only principle: creating a document from the clipboard is not editing an existing file, but Save does write, and it may belong as Export or Save As on a document that was never a file to begin with.
  - Menus apply to iPad, not only macOS. iPadOS 26 has a full system menu bar, populated from the same SwiftUI `Commands`, and the app already vends Find/View/Search command menus that surface there. Design the iPad menu bar deliberately as part of the iOS-package interface — mirror the Mac's read-only-honest structure (File/Edit/View/Help as they apply; still no Save/Undo/Cut/Paste) rather than shipping only whatever the shared `Commands` happen to expose. The File menu items in particular apply to iPad as well as macOS.

### New from clipboard. (2.0)
  - Deferred to 2.0. Until then the app stays a viewer: File and Edit carry no operations that create documents, and the only one that writes is Export, which writes a document out as it was read.
  - File -> New (Cmd-N): if clipboard has text, create a new unsaved document with that content.
  - File -> Save (Cmd-S): prompt to save as `.md`.

## Admin and App Store Connect

### Improve project documentation and samples.
  - Make a better, more consumer-based `README.md` with screenshots displaying features.
  - Split out developer instructions to `CONTRIBUTING.md`.

### Generate screenshots for README and App Store Connect. (next — not tonight)
  - Two audiences from overlapping captures: `README.md` wants a few representative shots of the app in use (see "Improve project documentation and samples"), and App Store Connect requires them per device family for the store listing.
  - App Store Connect specifics: screenshots at Apple's required pixel sizes for each family the app ships on — iPhone, iPad, and Mac — in the right orientation, at least one per family, and eventually a localized set once localization lands. Confirm the current required sizes against App Store Connect at submission time; Apple changes them.
  - Content: open the bundled `SAMPLE.md` — it exists partly so a first launch (and a screenshot) lands on a rendered document instead of an empty window, and it exercises headings, lists, tables, code, images, and quotes in one view, which makes a good hero shot. Capture both light and dark appearance.
  - Tooling: macOS is a straightforward window capture. iOS/iPadOS come from the simulator — mind the Xcode 27 simulator changes (Simulator.app replaced by DeviceHub.app; file import is awkward, and getting `SAMPLE.md` in place may need the File Provider Storage app-group copy trick). `xcrun simctl io <udid> screenshot` is likely the least-friction capture. This is release-prep-adjacent (see "Get ready for TestFlight").

### Marketing and support website (`sydpolk.com`).
  - MarkdownPreview's marketing, support and privacy pages at `markdownpreview.sydpolk.com` are planned in `../sydpolk-com/sydpolk.com.md`. The support and privacy policy URLs gate the first submission (see "Get ready for TestFlight").
  - The support URL is also where the welcome document's and About-box feedback/support links should point once they exist (see "Ship a welcome document in the app bundle"), superseding the current `support@sydpolk.com` mailto in `SAMPLE.md`. Keep it to plain support/feedback — off-app transaction links (donations, purchases, subscriptions) are a common App Review rejection trigger.

### Pricing and distribution.
  - Decision for now: a single **$1.99 one-time purchase**, Universal Purchase across macOS/iOS/iPadOS — option A below. One app record, one price, App Store auto-updates, sandboxed on every platform. A one-time purchase, not a subscription or IAP, and keep it that way for a simple viewer.
  - Known tension with a single price (Syd): $1.99 is simultaneously *too expensive* for the iOS market — where this class of app trends free/$0.99 and competes with free markdown viewers, so any price is friction — and *too cheap* for a macOS utility, which can command more (Mac utilities in this space commonly sit ≈$4.99–$14.99). A universal price fits neither market. This is the strongest pull toward **B** (per-platform pricing) before release; weigh it against B's doubled store overhead and loss of Universal Purchase.
  - Not locked until release; before shipping this may switch to one of:
    - **A (current) — one universal app record:** one price for all platforms; simplest; Universal Purchase (buy once, get every platform).
    - **B — two App Store records** (separate Mac and iOS apps, distinct bundle IDs): allows per-platform pricing, still sandboxed and App-Store-updated, but doubles store maintenance and drops Universal Purchase (a both-platforms buyer pays twice).
    - **C — direct Mac distribution** (off the App Store): full pricing freedom and independence from Apple's cut/review, but then Sparkle for updates (extra XPC/entitlement setup when sandboxed), own payments/licensing/support, and a container reconsideration — dropping the sandbox would send the seeded `SAMPLE.md` to the real `~/Documents` and trip the Documents TCC prompt (see "Ship a welcome document in the app bundle").
  - Key point for revisiting: per-platform pricing does **not** require leaving the App Store — that's B (two records), which keeps the sandbox and App Store auto-updates. C is only worth it for independence from Apple, which is a post-launch strategic call, not a pricing one.

### Confirm the notarized DMG on another Mac.
  - `MarkdownPreview 0.9 (3).dmg` is notarized and stapled, and Gatekeeper accepts it here. Confirm it on a Mac that has never seen the app — the work Mac (macOS 26.x), downloaded through Dropbox's website so it carries the quarantine attribute: it should open with only the "downloaded from the internet" prompt, and `spctl --assess -vv` on the installed app should say `source=Notarized Developer ID`.

### Get ready for TestFlight.
  - Distribution split (Syd): the DMG that `Scripts/release-build.sh` makes is the **Mac build only**. The iOS/iPadOS app reaches anyone outside this machine **only through TestFlight builds**.
  - Eventually, a script that makes both builds and uploads them to App Store Connect. A separate effort from the DMG release script, not an extension of it.
  - Remaining prep before the first submission: the screenshots (see "Generate screenshots for README and App Store Connect") and the marketing/support website (see "Marketing and support website (`sydpolk.com`)").
  - Wire the support URL (required) and marketing URL (optional but expected) into App Store Connect once the site is up — see "Marketing and support website (`sydpolk.com`)" for the URLs and hosting decision.
  - Investigate how to submit to App Store as an individual.
  - Submit app to App Store.
  - Set up TestFlight.

*Copyright ©2026 Syd Polk. All Rights Reserved.*
