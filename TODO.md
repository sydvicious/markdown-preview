# TODO

This document tracks planned work for MarkdownPreviewApp.

### Bug fixes
- On Mac and iPad, search box should have a minimum width, but should fill the title bar otherwise. Mac, of course, has the filename, and it should be full. Priority is full file name, then expand Search Bar.
- On Mac, the remove-from-list toolbar button lands in a weird place: it ends up at the far trailing edge after the toolbar overflow (`»`) chevron, detached from the file list, and renders with an odd blue highlight. Revisit placement/grouping (likely resolved by the document-based redesign).
- Markdown rendering gaps found by the CommonMark conformance suite (`Tests/MarkdownCoreTests`, added 2026-07-19). Each bullet names the failing test; run `swift test` to see them. 44 of 92 cases fail today.
  - Inline text
    - Backslash escapes are not implemented at all, so `\*`, `\_`, `` \` ``, and `\[` render literally with the backslash and do not suppress the construct they escape (`escapedAsteriskIsNotEmphasis`, `escapedUnderscoreIsLiteral`, `escapedBacktickIsLiteral`, `escapedBracketIsNotALink`).
    - HTML entities in the source are double-escaped: `&amp;` renders as `&amp;amp;` (`namedEntityIsDecoded`).
    - Emphasis has no flanking rules, so `* foo *` emphasizes where the spec leaves it literal (`whitespaceAfterOpeningDelimiterIsNotEmphasis`); see also the intraword-underscore entry below.
    - `***foo***` does not produce strong inside emphasis, and emphasis does not nest (`tripleDelimiterIsStrongInsideEmphasis`, `emphasisNests`).
    - Code spans do not support double-backtick fencing, and do not strip one leading/trailing space (`doubleBackticksCanContainASingleBacktick`, `oneLeadingAndTrailingSpaceIsStripped`).
    - Link and image titles (`[a](/u "t")`) are not parsed and end up inside the URL; angle-bracket destinations are not unwrapped (`linkTitleBecomesATitleAttribute`, `imageTitleBecomesATitleAttribute`, `angleBracketDestinationIsUnwrapped`).
    - Image alt text keeps its markup instead of reducing to plain text (`altTextIsPlainTextNotMarkup`).
  - Blocks
    - `#foo` with no space is treated as a heading; ATX closing sequences (`## foo ##`) are not stripped; a bare `#` is not an empty heading (`hashWithoutFollowingSpaceIsNotAHeading`, `closingSequenceIsStripped`, `closingSequenceNeedNotMatchOpeningLength`, `emptyHeadingIsAllowed`).
    - Setext underlines shorter than three characters are rejected, and setext content cannot span multiple lines (`underlineOfAnyLengthIsAccepted`, `multiLineContentIsJoined`).
    - Soft line breaks inside a paragraph collapse to a space instead of a newline, and neither hard-break form is supported (`softLineBreakIsANewlineNotABreakTag`, `twoTrailingSpacesMakeAHardBreak`, `trailingBackslashMakesAHardBreak`).
    - Thematic breaks reject spaces between the characters, so `* * *` is not a rule (`spacesBetweenCharactersAreAllowed`).
    - Fenced code ignores the info string (no `language-` class), rejects `~~~` fences, and requires the fence at column 0 (`infoStringBecomesALanguageClass`, `tildeFenceRendersPreCode`, `fenceMayBeIndentedUpToThreeSpaces`).
    - Block quotes flatten to a single paragraph joined with `<br>`, cannot nest, and cannot contain other blocks (`continuationLinesJoinAsSoftBreaks`, `quotesNest`, `quotesContainOtherBlocks`).
    - Ordered lists put the number on each `<li value="N">` rather than `<ol start="N">`, do not accept the `)` delimiter, and have no loose/tight distinction (`orderedListRenders`, `orderedListStartingAtOneHasNoStartAttribute`, `orderedListStartNumberIsCarriedOnTheList`, `changingMarkerTypeStartsANewList`, `mixedNestingKeepsEachLevelsOwnMarkerType`, `parenthesisDelimiterIsAccepted`, `looseListItemsWrapContentInParagraphs`). Decide deliberately whether to move to `start=`; the current `value=` output renders correctly and may be worth keeping, in which case fix the tests instead.
    - Tables reject single-column tables, `:-:` centering, and single-dash delimiter cells, and do not pad short rows (`cellContentIsInlineRendered`, `alignmentMarkersSetCellClasses`, `shortAlignmentMarkersAreAccepted`, `rowsShorterThanTheHeaderArePadded`).
  - Cosmetic: unchecked task items emit `<input type="checkbox" disabled  />` with a doubled space (`uncheckedItem`).
- Render snake_case correctly: intraword underscores (e.g. `foo_bar_blamph`) should stay literal, not italicize the middle segment. CommonMark/GitLab forbid intraword `_` emphasis (to protect identifiers); the app currently emphasizes it like older Markdown.pl. Check the parser's intraword-underscore / `no_intra_emphasis` flag, and check for more differences in parsing between what is currently in the app and CommonMark.

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
  - Restructure the project around Swift packages while doing this, since the platforms are diverging anyway.
    - Put the view models in their own Swift package, so they are testable without an app host like `MarkdownCore` already is.
    - Separate packages for the Mac interface and the iOS interface. The document-based Mac design and the iPhone/iPad navigation stack have little left in common, and separating them stops each platform's `#if os(...)` branches from cluttering the other.
    - The Mac interface is essentially a fresh start, not a port. Going document-based changes enough that the existing views are a reference at most; expect to write the Mac package rather than move code into it. The current views carry over to the iOS package and keep evolving there.
    - So the two interface packages are not two copies of the same thing, and there is no shared UI package. Whatever overlap survives is incidental — do not factor it back out.
    - **Each platform gets the interface that is right for it; sharing view code is not a goal and must not constrain either one.** If the Mac wants a structure that would break the iOS views, that is fine and expected.
    - **Models and view models, on the other hand, should be shared** — that is the point of putting them in their own package. Both interfaces sit on the same view models and the same `MarkdownCore`, and only the views differ. Where a platform needs something the shared view models cannot express, prefer extending them over forking; the split is meant to fall at the view boundary, not lower.
    - One top-level application file per platform — a Mac one and an iOS one — each in its own directory, rather than a single shared entry point with conditional compilation inside it.
    - Two `Info.plist` files, one per platform. The project already half does this: `GENERATE_INFOPLIST_FILE` is off for macOS with `INFOPLIST_FILE[sdk=macosx*] = Info-macOS.plist`, while iOS still uses a generated one. Make both explicit and give each its own directory alongside its app file.
    - Attach every new package to the project as a **navigator folder**, not via Add Package Dependency, or its tests will not be visible to Xcode — see "How the `MarkdownCore` package is attached to the project."
  - Use `DocumentGroup` (or `NSDocument`) so each document opens in its own window.
  - Replace in-app file list with system Recents.
  - Opening a file (for example, double-click in Finder) opens a new window for that doc.
  - Build a sensible menu structure for the document-based app. A standard Mac app has an About box and File and Edit menus, and has since 1984; Window and Help joined them in Mac OS X. This is the baseline users expect, not a checklist to trim because the app is a simple viewer — a Mac app without them reads as unfinished.
    - The app is a viewer, not an editor. File and Edit carry only operations that do not imply changing the document's content — no Save, no Undo, no Cut or Paste, and no editing affordances that would suggest the file can be modified in place. "Export…" is the intended way to write anything out, and it is a 2.0 feature.
    - App menu: About (same content as the bundled welcome document — see "Ship a welcome document in the app bundle"), and Quit (Cmd-Q).
    - File menu: Open (Cmd-O), Open Recent, Close (Cmd-W), Print (Cmd-P). Export… for converting to HTML or RTF is a 2.0 feature (see "Export documents to HTML and RTF").
    - Edit menu: Copy (Cmd-C), Select All (Cmd-A), and the Find commands. Read-only operations only, so the menu stays honest about what the app does.
    - Window menu: the standard document-window entries that `DocumentGroup` provides.
    - Help menu: reopening the welcome document belongs here.
    - "New from clipboard" is a 2.0 feature, so File → New and File → Save stay out of the menus for now. When it lands, revisit how it fits the read-only principle: creating a document from the clipboard is not editing an existing file, but Save does write, and it may belong as Export or Save As on a document that was never a file to begin with.
  - The File menu items apply to iPad as well as macOS.

### New from clipboard. (2.0)
  - Deferred to 2.0. Until then the app stays a pure viewer, and File and Edit carry no operations that create or write documents.
  - File -> New (Cmd-N): if clipboard has text, create a new unsaved document with that content.
  - File -> Save (Cmd-S): prompt to save as `.md`.

### Export documents to HTML and RTF. (2.0)
  - Deferred to 2.0, along with everything else that writes files. Until then the app only reads.
  - File -> Export… : write the current document as HTML or RTF.
  - Share the conversion with the command-line converter (see "Command-line converter for markdown to HTML and RTF") rather than writing it twice. HTML comes straight from `MarkdownCore`; RTF goes through `NSAttributedString` and is currently buried in `MarkdownSelectionClipboard.renderedRTF(for:)`, which wants extracting either way.
  - Decide whether HTML export emits the full styled document that the preview uses or a bare fragment, and whether the stylesheet is inlined.

### Open remote URLs without downloading.
  - If `.onOpenURL` receives an `http(s)` link to a markdown file, fetch into memory and open in a new window.
  - Provide "Save as..." to persist locally if desired.

### Support side-by-side Preview and Source on Mac and iPad.
  - Add a layout mode that shows rendered preview and source simultaneously.
  - Ensure the mode works in regular-width environments on macOS and iPadOS.

### Support image references.

### Ship a welcome document in the app bundle.
  - Include a `Welcome.md` in the app bundle and add it to the file list on the very first launch, so a new user is met with a rendered document instead of an empty window.
  - Once the user removes it from the list, remember that and never add it back. From then on the app behaves exactly as it does today: `ContentViewModel.initialOpenPresentation` (`MarkdownPreview/View Models/ContentViewModel.swift:213`) presents the file picker on macOS when a restore finds no documents, and the empty list offers its placeholder open action.
    - This is a persisted "welcome document has been dismissed" flag, separate from the file list itself. It has to survive the list going empty by other means, so that emptying the list for unrelated reasons does not bring the welcome document back.
    - It is a first-launch affordance, not a fallback for an empty list — so it is added once, not every time the list happens to be empty.
  - The document is a bundle resource rather than a user file, which the file list is not currently built for.
    - The list persists security-scoped bookmarks (`DocumentSessionStore`), and a bundle resource has none. Expect this to need a distinct case rather than a bookmark, with a stable identity so it is not duplicated across launches.
    - It is read-only inside the bundle, so anything keyed to a writable user file — text size preferences keyed by path, the search index — needs to tolerate it.
  - This is about-box content: what the app is and does, how to open files, copyright, and where to send feedback and get support. Keep it short. It is not a feature showcase.
    - Leave a clear place for the feedback and support links to land once those exist, rather than shipping dead links.
    - Vet those links against App Review before shipping them. Anything that reads as taking the user outside the app to transact — donations, purchases, subscriptions — is the usual rejection trigger; a plain support or feedback address is not. Keep it to what the app needs.
    - Localization is the real cost here: this is prose in a bundled file, so every supported language needs its own copy kept in sync, which is worse than localizing a string table. Factor that into how long the document is, and see "Internationalization (i18n) and localization (l10n)".
    - It is still the first rendered markdown a user sees, so keep it to constructs that currently render correctly (see "Bug fixes").
  - On macOS the same contents also back the About box, from the same file — one source of truth, so the two cannot drift. **Sequencing: the About box work waits for the document-based redesign**, which is where the macOS menu structure gets built; the bundled welcome document itself does not have to wait.
    - Decide between the standard AppKit About panel and a custom window. `orderFrontStandardAboutPanel` takes attributed-string credits and shows the version and copyright from `Info.plist` for free; a custom window would instead render the markdown through the app's own preview, which keeps one rendering path but means building the window.
    - If the standard panel is used, the markdown has to become an `NSAttributedString`. The HTML-to-attributed-string conversion in `MarkdownSelectionClipboard.renderedRTF(for:)` (`MarkdownPreview/Utilities/MarkdownSelectionClipboard.swift:57`) already does exactly this and is worth reusing rather than reimplementing.
    - iOS and iPadOS have no About box and nowhere else to put this content, so the document in the list on first launch is the whole mechanism there, not a supplement to something else. The alternatives considered were a bottom sheet on first launch — explicitly not wanted — or doing nothing at all. If the bundled document does not work out, doing nothing is the fallback; do not reach for the sheet.
    - Supersedes the `©2026 Syd Polk` menu entry under "Add list toolbar menu" if that entry was standing in for an about box; decide which of the two is wanted.
  - Consider a Help menu item to reopen the document, so dismissing it is not irreversible.

### Improve project documentation and samples.
  - Make a good `SAMPLE.md` file displaying features. This is a separate thing from the bundled welcome document, which is deliberately not a feature showcase.
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
  - See "Audit the test suites and cover every markdown feature" for the parser/renderer test work this depends on.

### Internationalization (i18n) and localization (l10n).
  - Standing design principle: expose as little visible text in the GUI as possible, so there is less to localize. The Mac menu bar unavoidably needs it; nearly everything else can avoid it.
    - The larger saving is layout, not translation. Visible strings are what force layouts to reflow for longer translations and to be re-verified per language; a GUI without them largely sidesteps that, and the menu bar is laid out by the system anyway. This is also why concentrating the strings in accessibility labels and placeholders works: labels never affect layout at all, and a field's placeholder does not resize the field.
    - Prefer icons to text labels, and prefer standard system controls and commands, whose strings Apple already localizes, over hand-rolled equivalents with custom wording.
    - Treat any new user-visible string as a cost to be justified, not a default. This applies to empty states, confirmation copy, and error messages as much as to labels.
    - Accessibility labels and field placeholders are where the strings will unavoidably live, and that is accepted: an icon-only interface leans harder on them, and both are user-facing text that must be localized. Budget for localizing them even though they are not visible clutter — see "Accessibility testing."
  - Localize all user-facing strings across iOS, iPadOS, and macOS.
  - The bundled welcome document is prose in a file rather than a string table, so it needs a localized copy per language, kept in sync by hand. Keep it short for this reason (see "Ship a welcome document in the app bundle").
  - Verify layout/text behavior for longer localized strings. Scope this to wherever visible text survived the principle above — the fewer such places, the cheaper this step gets.
  - Right-to-left languages need a real pass eventually, since RTL affects layout direction and icon mirroring rather than just string length. **Low priority** given the expected number of RTL users for this app. Accessibility comes first.

### Accessibility testing.
  - Higher priority than right-to-left localization, and higher than i18n generally. It reaches far more users, and the deliberately icon-heavy design (see "Internationalization (i18n) and localization (l10n)") makes it load-bearing rather than optional: with few visible labels, a VoiceOver user is navigating almost entirely by accessibility labels, so a missing or wrong one makes a control unusable rather than merely unpolished.
  - Run VoiceOver, Dynamic Type, contrast, and keyboard navigation checks on all platforms.
  - Fix accessibility labels/traits/focus order issues and add regression checks.
  - Audit that every icon-only control has an accurate label and the right traits, and that the labels are localized. These are the strings the design deliberately concentrates text into, so they are the ones that most need to be right.

### How the `MarkdownCore` package is attached to the project. (solved 2026-07-19 — do not undo)
  - `MarkdownCore` must be attached to the project as a **folder in the project navigator**, not via Add Package Dependency → Add Local…. This is the difference between Xcode exposing the package's test targets and hiding them, and it cost most of a day to find.
    - Attached as an `XCLocalSwiftPackageReference` (the Add Local… route), Xcode offers only the package's *library* product. `MarkdownCoreTests` and `MarkdownCoreConformanceTests` never appear in Product → Scheme → New Scheme… or in a test plan's target picker, and a hand-written plan entry for them is silently ignored.
    - Attached as a navigator folder, the same plan entry works. In `project.pbxproj` the package is then a `PBXFileReference` with `lastKnownFileType = wrapper`, and the product is an `XCSwiftPackageProductDependency` with no `package =` field.
    - The published consensus says this is impossible — [that only root packages can be tested](https://forums.swift.org/t/cant-add-swiftpm-testtarget-to-xcode-test-plan/71260), with related reports at [Apple Developer Forums](https://developer.apple.com/forums/thread/764589) and an [earlier thread](https://developer.apple.com/forums/thread/133495). That is wrong, or at least out of date: this project now does it with no workspace, opening the `.xcodeproj` directly.
  - When re-attaching a package this way, link it explicitly. A navigator package can end up a target *dependency* (so it builds) with an empty Frameworks build phase (so it never links), which fails only at link time with "Undefined symbol: ...MarkdownCore...". Add the library under the target's Frameworks, Libraries, and Embedded Content.
  - The test plan entry for a package test target looks like this — `containerPath` is the package directory, `identifier` is just the target name:
    - `{"containerPath": "container:MarkdownCore", "identifier": "MarkdownCoreTests", "name": "MarkdownCoreTests"}`
  - Verify any test plan change by its executed-test count, never by its exit status. A plan referencing an unresolvable target reports `** TEST SUCCEEDED **` while running nothing, and a plan file the scheme cannot read fails the same quiet way.

### Audit the test suites and cover every markdown feature.
  - Started 2026-07-19: `Tests/MarkdownCoreTests/CommonMarkConformanceTests.swift` covers the block and inline features against CommonMark 0.31.2 and runs headlessly via `swift test`. Still to do: the offset-mapping round trips below, and the audit of the remaining Xcode-hosted suites.
  - Audit what the existing suites actually cover. The gaps found so far were large: before the nested-list work there were no tests at all for list parsing or list HTML, despite lists being a core feature. Assume other features are in the same state until checked, and write down what is covered and what is not.
  - Add a unit test per individual markdown feature: generate a small `.md` fragment exercising exactly that feature, render it, and assert the generated HTML is correct.
    - Cover at least: headings (ATX and setext), paragraphs, bulleted lists, numbered lists, nested and mixed lists, checklists, blockquotes, fenced code, inline code, emphasis and strong, links, images, horizontal rules, and tables (including alignment, inline code in cells, and explicit line breaks).
    - Include the inline/intraword cases that are known or suspected to be wrong, such as the intraword-underscore `snake_case` bug under "Bug fixes".
    - Assert on exact HTML where it is stable. The preview builds display offsets by walking text nodes, so incidental whitespace between tags is a real bug, not a formatting detail — keep asserting that lists emit no whitespace between tags, and extend that check to other block types.
  - Test the offset mappings alongside the HTML: `.md` source to display text, display text back to source, and source to rendered HTML, round-tripping in both directions.
  - Land the suite complete and runnable even where it exposes bugs. Do not gate landing the tests on fixing what they find, and do not delete or weaken a test to make the suite green.
    - Let the known-failing cases fail the test run (`Cmd-U` / `xcodebuild test`). A failing run is the honest signal that the app does not yet render these correctly; do not skip, disable, or wrap them in `withKnownIssue` to get a clean run. The suite goes green when the bugs are fixed, not before. There is no CI yet — if one is added later (see "Get ready for TestFlight"), the same rule applies to it.
    - File each exposed bug as its own entry under "Bug fixes" so the failing test and the bug are linked.

### Command-line converter for markdown to HTML and RTF.
  - Now that the engine builds as the `MarkdownCore` library (`Package.swift`, 2026-07-19), add an executable target that converts `.md` files without going near the app. Useful for batch conversion, scripting, and inspecting renderer output directly.
  - HTML is the easy half: `MarkdownHTMLBuilder.document(for:contentScale:)` already produces a standalone document and needs nothing beyond `MarkdownCore`.
    - Add a body-only mode as well as the full document. `document(for:)` embeds the whole stylesheet, which is what the preview wants but not what a caller piping into another tool wants.
  - RTF needs a decision first. The conversion lives in `MarkdownSelectionClipboard.renderedRTF(for:)` (`MarkdownPreview/Utilities/MarkdownSelectionClipboard.swift:57`) and works by handing the generated HTML to `NSAttributedString` and asking for RTF back, so it depends on AppKit/UIKit.
    - AppKit links fine in a command-line tool on macOS, so this works — but it must not be folded into `MarkdownCore`, which is deliberately free of UI frameworks so it stays command-line testable. Put the RTF path in its own target that depends on `MarkdownCore`.
    - It also makes RTF output macOS-only, while HTML output would work anywhere Swift runs.
    - Extract the conversion out of `MarkdownSelectionClipboard` so the app and the tool share one implementation rather than diverging.
  - Sketch of the interface: read from a file or stdin, write to a file or stdout, `--format html|rtf`, `--fragment` for body-only HTML, and accept several input files for batch conversion.
  - Worth doing early for its own sake: it gives a fast way to see exactly what the renderer produces for a given input, which is how the conformance-suite failures were diagnosed.

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
