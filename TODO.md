# TODO

This document tracks planned work for MarkdownPreviewApp.

### Bug fixes
- Paragraph spacing collapsed everywhere. (fixed 2026-07-26) Blank lines between paragraphs rendered with no visible gap, which is why the sample document leaned on `&nbsp;` spacer lines to force space. Root cause: each top-level block is wrapped in its own `<div class="md-block">`, so a paragraph is `<div class="md-block"><p>…</p></div>` and the `<p>` is always the sole/last child of its wrapper. The stylesheet's `p:last-child, ul:last-child, … { margin-bottom: 0 }` rule — meant to trim only the trailing margin at the document's end — therefore matched every paragraph and zeroed all bottom margins. Fixed in `MarkdownHTMLBuilder`'s CSS by scoping the trim to blocks that actually sit against a container edge: `.md-block:last-child > :last-child, blockquote > :last-child, li > :last-child { margin-bottom: 0 }`. Paragraphs now keep their `1rem` bottom margin (a real gap), while within-paragraph line breaks stay tight because they use `<br>` (no margin) — so the two spacing levels read distinctly. `&nbsp;` spacer lines should no longer be needed anywhere. Not unit-testable (CSS layout); verify by eye in the app.
- On Mac and iPad, search box should have a minimum width, but should fill the title bar otherwise. Mac, of course, has the filename, and it should be full. Priority is full file name, then expand Search Bar.
- On Mac, the remove-from-list toolbar button lands in a weird place: it ends up at the far trailing edge after the toolbar overflow (`»`) chevron, detached from the file list, and renders with an odd blue highlight. Revisit placement/grouping (likely resolved by the document-based redesign).

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

### Claim `.md` as our app's file type on iOS. (investigate)
  - On macOS the app already registers as an `Owner` for `net.daringfireball.markdown` (`LSHandlerRank = Owner`) and the user can make it the default through Finder's Get Info → Open With → Change All. iOS has no equivalent user-facing "default app for this type" control, even though the same document-type declarations already ship (the `INFOPLIST_KEY_CFBundleDocumentTypes` / `UTImportedTypeDeclarations` build settings, shared with macOS).
  - Investigate what actually makes iOS route a `.md` file to this app: how iOS picks a default handler among apps that claim a type, whether `LSHandlerRank` / `CFBundleTypeRole` carry any weight there, the roles of `LSSupportsOpeningDocumentsInPlace` and the document-browser APIs, and whether "open in place" vs. "copy to app" changes Share-sheet placement. Goal: a `.md` opened from Files, Mail, or another app reliably offers — and ideally defaults to — MarkdownPreview.
  - Observed example (behavior only): Indeed's "Job Search" app claims `.doc` for resume uploads and wins that association aggressively — proof the behavior we want for `.md` is achievable. Do **not** reference Indeed's proprietary sources or Info.plist for this; work from Apple's public documentation on document-type declarations, exported/imported UTIs, and handler rank. Syd is investigating over the next few days (as of 2026-07-26).

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
    - File menu: Open (Cmd-O), Open Recent, Close (Cmd-W), Print (Cmd-P). Printing is a future feature and is not implemented yet — see "Share sheet (iOS) and printing" for the macOS `NSPrintOperation` path. Export… for converting to HTML or RTF is a 2.0 feature (see "Export documents to HTML and RTF").
    - Edit menu: Copy (Cmd-C), Select All (Cmd-A), and the Find commands. Read-only operations only, so the menu stays honest about what the app does.
    - Window menu: the standard document-window entries that `DocumentGroup` provides.
    - Help menu: reopening the welcome document belongs here. Because the container copy persists and stays updated, "reopen" means re-adding that copy to the list (the iPhone equivalent is a gesture — see "Ship a welcome document"). A "Show Release Notes" item also belongs here: the sample is not a changelog, and a user who has removed it from the list won't see its updates until they re-add it, so release notes are the reliable place to surface what changed in a build.
    - "New from clipboard" is a 2.0 feature, so File → New and File → Save stay out of the menus for now. When it lands, revisit how it fits the read-only principle: creating a document from the clipboard is not editing an existing file, but Save does write, and it may belong as Export or Save As on a document that was never a file to begin with.
  - Menus apply to iPad, not only macOS. iPadOS 26 has a full system menu bar, populated from the same SwiftUI `Commands`, and the app already vends Find/View/Search command menus that surface there. Design the iPad menu bar deliberately as part of the iOS-package interface — mirror the Mac's read-only-honest structure (File/Edit/View/Help as they apply; still no Save/Undo/Cut/Paste) rather than shipping only whatever the shared `Commands` happen to expose. The File menu items in particular apply to iPad as well as macOS.

### New from clipboard. (2.0)
  - Deferred to 2.0. Until then the app stays a pure viewer, and File and Edit carry no operations that create or write documents.
  - File -> New (Cmd-N): if clipboard has text, create a new unsaved document with that content.
  - File -> Save (Cmd-S): prompt to save as `.md`.

### Share sheet (iOS) and printing.
  - **iOS/iPadOS: add a share sheet.** Wire a `ShareLink` / `UIActivityViewController` on the current document so the standard system share sheet is available. This earns its keep beyond sharing: the iOS share sheet carries the system **Print** activity for free, so printing on iOS comes along without a bespoke print path, and the sheet is the natural home for future "send a copy" / export actions. Decide what gets shared — the source `.md` file URL (simplest; shares the original document as-is) versus rendered output (HTML/RTF/PDF), which overlaps with "Export documents to HTML and RTF" and should reuse that path rather than growing a second one.
  - **macOS: printing is a separate, future feature.** The Mac has no share-sheet Print activity, so printing there is its own path: an `NSPrintOperation` over the preview `WKWebView` (`WKWebView` vends a print operation), wired to a File → Print (Cmd-P) command as part of the document-based redesign (see the File menu under "macOS redesign as a document-based app"). Not implemented yet — the app currently has no print path or share sheet on either platform. Whatever it prints should match what the preview shows, so it likely renders from the same HTML the preview already builds.

### Export documents to HTML and RTF. (2.0)
  - Deferred to 2.0, along with everything else that writes files. Until then the app only reads.
  - File -> Export… : write the current document as HTML or RTF.
  - Share the conversion with the command-line converter (see "Command-line converter for markdown to HTML and RTF") rather than writing it twice. HTML comes straight from `MarkdownCore`; RTF goes through `NSAttributedString` and is currently buried in `MarkdownSelectionClipboard.renderedRTF(for:)`, which wants extracting either way.
  - Decide whether HTML export emits the full styled document that the preview uses or a bare fragment, and whether the stylesheet is inlined.
  - Images need embedding as `data:` URIs for both formats. The preview's `mdimage://` scheme only works inside the app's own web view, so an exported file or an RTF built through `NSAttributedString` would show broken images without it. A `MarkdownImageInliner` doing exactly this was written and then removed on 2026-07-19 for having no caller — reinstate it here rather than designing it again. It can reuse `MarkdownImageURL.resolveFile`, `.rewritingImageSources`, and `.mimeType`, which are still in `MarkdownCore` for the preview path.

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
  - Consider the other output paths too: RTF (via `NSAttributedString`) and any future HTML export would each need to handle — or deliberately re-escape — the same raw HTML, so the policy has to be defined in `MarkdownCore`, not just at the preview.

### Honor source line breaks (soft break as hard break). (done 2026-07-26)
  - The real grievance behind "Support inline HTML": both markdown and the HTML it compiles to collapse a single newline into a space, so a carriage return in the source has no effect on the rendering. `<br>` only papers over that. This is the more principled fix — a newline in the source now means a line break in the output, so what the author typed is what they see.
  - Standard, well-trodden behavior: this is exactly GitHub Flavored Markdown's rendering of comments and issues ("soft break as hard break," historically the `nl2br` option) — a known rendering mode with established semantics, not a bespoke idea.
  - How it shipped: `MarkdownHTMLBuilder.SoftBreak` (`.newline` | `.lineBreak`), a parameter on `document(for:contentScale:softBreak:)` threaded down to `tokenizeInline`. The default is `.newline`, so `MarkdownCore` stays CommonMark-conformant and the whole `CommonMarkConformanceTests` suite (and a future CLI converter) is unaffected. The app selects `.lineBreak` at every rendering site — preview (`MarkdownPreviewView.swift`), rich-text copy (`MarkdownSelectionClipboard.swift`), and the web-view `#Preview` — so users see no toggle; it is hardwired, not a config surface. Purely a rendering choice in the builder: no parser change, and it never touches the escaping or nonce machinery. This delivers the `<br>` value from "Support inline HTML" on its own.
  - Blank-line paragraph breaks are unchanged; only the *within-paragraph* single newline changed meaning. A double newline still starts a new paragraph.
  - Covered in `MarkdownHTMLBuilderTests` (`lineBreakOption*` tests): a two-line paragraph emits `<br />` between the lines under `.lineBreak`; a blank line still emits two `<p>` blocks; single-trailing-space and two-trailing-space breaks still resolve correctly; blockquotes get the same treatment; and `softBreakDefaultsToNewlineNotABreakTag` guards the CommonMark default.
  - Still to verify at runtime (best done in the app, not a unit test): the preview's text-offset mappings drive search-result selection by aligning source offsets to rendered-HTML offsets. Soft breaks now emit `<br />` where they used to emit a bare newline. Hard breaks already emitted `<br />` and the mappings handle them, so this should just route more cases through the same path — but confirm find/selection still lands correctly on a multi-line paragraph.

### Support image references. (done 2026-07-19)
  - Working and verified on macOS, a physical iPhone, the iPhone simulator, and the iPad simulator, for both local files and remote `https` URLs. `![alt](path "title")` renders the picture, with relative paths resolved against the document's directory, including documents on iCloud Drive.
  - How it works, because the obvious approach does not: `WKWebView.loadHTMLString(_:baseURL:)` gives the web content process no read access to the file system, so a relative `<img src>` never loads however correct the base URL is. `MarkdownImageURL` rewrites those references to `mdimage://` URLs and `MarkdownImageSchemeHandler` reads the file in the app process and hands WebKit the bytes. Do not "simplify" this back to a plain relative path. Firefox for iOS serves its own internal pages the same way.
  - Guards on what can be served, all deliberate:
    - The path extension must name a known image type — governs what may be requested.
    - The file's leading bytes must identify an image — governs what is served, so a file merely named `.png` is refused.
    - Every `mdimage://` URL carries a nonce minted at launch, and the handler refuses URLs without it. Raw HTML is currently escaped, so a document cannot forge such a URL anyway; the nonce keeps that guarantee if raw HTML is ever supported.
  - On a sandboxed system the app is granted the document, not its neighbours. When an image fails to resolve the preview offers a folder picker, and `DirectoryAccessStore` persists the grant. This applies on iOS now and will apply on macOS once it is sandboxed for the App Store.
  - Hard-won details, each of which cost real time and is easy to reintroduce:
    - Resolving an image checks the file is readable, which is itself a privileged read, so it must run inside the granted scope or the reference is never rewritten and the handler is never asked.
    - A directory does not contain itself. `DirectoryContainment.directory(covering:from:)` counts the directory itself; `directory(containing:from:)` does not. The grant is usually the document's own folder.
    - Existence is not readability. A sandboxed app can see a path through a file provider while being refused its contents, so the check reads a byte rather than calling `fileExists`.
    - A file in iCloud that is not yet downloaded is unreadable but still servable — the handler materialises it. Treating that as a permission problem raises a prompt that granting cannot fix.
    - On iOS, `withSecurityScope` is unavailable for both bookmark creation and resolution (`API_UNAVAILABLE(ios)` in the SDK), and resolving a bookmark *starts accessing* its implicit ephemeral scope unless `.withoutImplicitStartAccessing` is passed. Omitting it leaked one open scope per restore until the system refused further access. Do not remove it.
    - That implicit scope is documented as "valid until reboot at the latest", so an iOS folder grant cannot survive a device restart. Accepted as an iOS limitation, not a bug to solve.
    - Grants carry a format version so bookmarks written by an older build are discarded at launch. Before that, a bad build's leftovers wedged the store and only deleting the app recovered it.
  - **iOS filesystems are case-sensitive; macOS's default APFS is not.** A document written on a Mac that refers to `photo.jpg` while the file is `Photo.JPG` renders on macOS and fails on iOS. Considered adding a case-insensitive fallback and decided against it — the only observed instance came from exporting an image through Photos, not from ordinary use. Revisit if it comes up for real.
  - Unresolved images are reported by cause: a file that is present but unopenable, or a folder that cannot be listed, offers the folder picker; a file simply absent from a readable folder says so instead, because offering permission would promise a fix that granting cannot deliver. The directory listing is the deciding evidence, since a sandboxed app refused a folder sees its files as absent.
  - Remote `http(s)` images are passed through untouched for the web view to fetch. `Samples/SAMPLE.md` shows the same photograph both locally and over https, so the two paths can be compared at a glance.
  - Images are still missing from copied rich text — see "Images are lost when copying rich text."

### Make the image permission prompt harder to miss.
  - The "Allow…" prompt is a `safeAreaInset` bar above the preview (`MarkdownPreview/Views/MarkdownPreviewView.swift`, `imageAccessPrompt`). It was missed entirely during the first sandboxed run on macOS: the document itself renders normally, so the eye goes to the content and the bar reads as chrome. The images looked simply broken, with no visible way to fix them.
  - Convert it to a modal alert, so granting the folder is a decision the user is actually asked to make rather than an offer they can scroll past.
  - Decide what "once" means before building it, because a modal that reappears is worse than a banner that is ignored. A grant covers a folder, so the natural unit is one prompt per folder per document opened — not per image, and not on every preview update, which `imageProblem` is currently evaluated on.
  - Keep the distinction the banner already makes: only the unreadable case is worth a modal, because granting fixes it. A file that is simply absent must stay a passive notice — see the `.missing` case — since a modal offering a fix that cannot work is worse than saying nothing.
  - Consider what happens when the user declines. There is currently no persisted "asked and refused" state, so a naive modal would ask again on the next open of the same document.
  - This is macOS-specific in urgency: on iOS the same bar sits in a much smaller viewport and is correspondingly harder to overlook. Check whether the modal is wanted there too, or whether the banner should stay on iOS.

### Open images and links in their natural app on click.
  - Clicking a rendered image should hand the file (or link) off to the system to open in whatever app naturally handles it: an image file opens in the default app for that image type; a link opens in the browser.
  - Route this through the system open handler (`NSWorkspace.open` on macOS, `UIApplication.open`/`openURL` on iOS) so the app is not choosing the target app itself.

### Ship a welcome document in the app bundle.
  - **Partly shipped (2026-07-26 build; see the 2026-07-25 changelog), via a different approach than the bundle-resource design sketched below.** What ships copies `SAMPLE.md` into the app's *private* Documents container on first launch — not the user's real `~/Documents` — guarded by the persisted `bundledSampleSeededKey` flag. Writing only inside its own container keeps the app essentially read-only on the user's file system (on Mac especially: nothing lands in `~/Documents`), and the copy is not surfaced to the user — it does not appear in the Files app. (The `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace` keys that would expose the container were tried and removed on 2026-07-26; a clean install still showed nothing, and exposing the container was not wanted anyway.) Consequences: the on-disk copy is kept current on version/build bumps independent of list membership (`refreshSeededSampleIfNeeded`), so it is effectively always present and always updated; removing it from the list only hides it. Because the file is not user-reachable, there are no delete-from-disk instructions — the welcome document just tells the user how to remove it from the list. So the bundle-resource bullets below are superseded for the *mechanics*; what remains genuinely open is the *content* (About-box text, feedback/support links) and the re-add affordance below.
  - Re-adding after removal: since the container copy persists, "reopen the welcome document" means re-adding that copy to the list. Provide a Mac/iPad **menu item** and an **iPhone gesture** that do exactly this (see the Help-menu note under "macOS redesign as a document-based app"). The app never re-adds it automatically; this is the user-initiated way back.
  - Contingency: if keeping even a private container copy draws negative feedback, stop writing the file and instead surface the content through an in-app bottom sheet (modal). Two content sources, not mutually exclusive: fetch release notes from a remote source (GitLab, or wherever the notes live), and/or render the welcome document straight from the app bundle read-only — never written to disk. Either way the app shows the same information without leaving a file behind, and it subsumes the "Show Release Notes" Help-menu item.
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

### Generate screenshots for README and App Store Connect. (next — not tonight)
  - Two audiences from overlapping captures: `README.md` wants a few representative shots of the app in use (see "Improve project documentation and samples"), and App Store Connect requires them per device family for the store listing.
  - App Store Connect specifics: screenshots at Apple's required pixel sizes for each family the app ships on — iPhone, iPad, and Mac — in the right orientation, at least one per family, and eventually a localized set once localization lands. Confirm the current required sizes against App Store Connect at submission time; Apple changes them.
  - Content: open the bundled `SAMPLE.md` — it exists partly so a first launch (and a screenshot) lands on a rendered document instead of an empty window, and it exercises headings, lists, tables, code, images, and quotes in one view, which makes a good hero shot. Capture both light and dark appearance.
  - Tooling: macOS is a straightforward window capture. iOS/iPadOS come from the simulator — mind the Xcode 27 simulator changes (Simulator.app replaced by DeviceHub.app; file import is awkward, and getting `SAMPLE.md` in place may need the File Provider Storage app-group copy trick). `xcrun simctl io <udid> screenshot` is likely the least-friction capture. This is release-prep-adjacent (see "Get ready for TestFlight").

### Marketing and support website (`sydpolk.com`).
  - `sydpolk.com` is already owned but has no site yet; it will cover both the software and the music work. Structure by subdomain per project: marketing at `https://markdownpreview.sydpolk.com`, support at `https://markdownpreview.sydpolk.com/support`. The support URL is required by App Store Connect and gates the first submission (see "Get ready for TestFlight"); the marketing URL is optional but expected. Still needs to be built and deployed.
  - The support URL is also where the welcome document's and About-box feedback/support links should point once they exist (see "Ship a welcome document in the app bundle"), superseding the current `support@sydpolk.com` mailto in `SAMPLE.md`. Keep it to plain support/feedback — off-app transaction links (donations, purchases, subscriptions) are a common App Review rejection trigger.
  - Hosting decision (deciding): Squarespace vs. a mostly-static site on Cloudflare Pages / Netlify / AWS S3+CloudFront.
    - The deciding factor is the music side, not MarkdownPreview — the app needs only a landing page and `/support`, trivial as static HTML. If the music work will want galleries, audio/store embeds, a blog, and frequent visual updates that shouldn't be hand-built, that favors Squarespace's templates (≈$16–23/mo). If music is mostly a landing page linking out to streaming platforms, static wins.
    - For a mostly-static site, raw AWS S3+CloudFront+Route 53+ACM is more ops than needed; Cloudflare Pages or Netlify give git-based deploys, free TLS, and easy custom-domain + subdomain routing at ≈$0. Raw AWS is fine if keeping everything under one roof is preferred. Subdomain-per-project is trivial on any static host via DNS; on Squarespace it is doable but more constrained — verify before committing.
    - Support-form handling nudges toward Squarespace: it can host a support *form* that emails submissions with no backend. A static site can match that but needs a form handler — Netlify Forms is the closest low-effort equivalent (built in, emails submissions on the free tier); otherwise Formspree/Basin, or AWS SES + a Lambda/API Gateway, or a Cloudflare Pages Function calling an email API. If a plain support page (a support `mailto` + FAQ) is enough to satisfy the required support URL, no backend is needed and static stays trivial — the form is the thing that pulls toward Squarespace or Netlify.
    - Lean: static on Cloudflare Pages/Netlify (Netlify if the built-in support form matters) unless the music side turns out media-heavy enough to justify Squarespace.
  - The content is small and portable: build the marketing page + `/support` page once as self-contained, theme-aware HTML and it drops into S3, Cloudflare Pages, Netlify, or even a Squarespace code block unchanged — so the host can be chosen later without redoing the pages.

### Pricing and distribution.
  - Decision for now (2026-07-26): a single **$1.99 one-time purchase**, Universal Purchase across macOS/iOS/iPadOS — option A below. One app record, one price, App Store auto-updates, sandboxed on every platform. A one-time purchase, not a subscription or IAP, and keep it that way for a simple viewer.
  - Known tension with a single price (Syd, 2026-07-26): $1.99 is simultaneously *too expensive* for the iOS market — where this class of app trends free/$0.99 and competes with free markdown viewers, so any price is friction — and *too cheap* for a macOS utility, which can command more (Mac utilities in this space commonly sit ≈$4.99–$14.99). A universal price fits neither market. This is the strongest pull toward **B** (per-platform pricing) before release; weigh it against B's doubled store overhead and loss of Universal Purchase.
  - Not locked until release; before shipping this may switch to one of:
    - **A (current) — one universal app record:** one price for all platforms; simplest; Universal Purchase (buy once, get every platform).
    - **B — two App Store records** (separate Mac and iOS apps, distinct bundle IDs): allows per-platform pricing, still sandboxed and App-Store-updated, but doubles store maintenance and drops Universal Purchase (a both-platforms buyer pays twice).
    - **C — direct Mac distribution** (off the App Store): full pricing freedom and independence from Apple's cut/review, but then Sparkle for updates (extra XPC/entitlement setup when sandboxed), notarization, own payments/licensing/support, and a container reconsideration — dropping the sandbox would send the seeded `SAMPLE.md` to the real `~/Documents` and trip the Documents TCC prompt (see "Ship a welcome document in the app bundle").
  - Key point for revisiting: per-platform pricing does **not** require leaving the App Store — that's B (two records), which keeps the sandbox and App Store auto-updates. C is only worth it for independence from Apple, which is a post-launch strategic call, not a pricing one.

### Get ready for TestFlight.
  - Remaining prep before the first submission: the screenshots (see "Generate screenshots for README and App Store Connect") and the marketing/support website (see "Marketing and support website (`sydpolk.com`)"). Sandboxing, entitlements, the privacy manifest, and the build-number scheme already landed in 0.7.
  - Wire the support URL (required) and marketing URL (optional but expected) into App Store Connect once the site is up — see "Marketing and support website (`sydpolk.com`)" for the URLs and hosting decision.
  - Investigate how to submit to App Store as an individual.
  - Submit app to App Store.
  - Set up TestFlight.
  - Capture and prepare App Store screenshots for iPhone, iPad, and Mac.
  - Automate `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` bumps in CI/CD. Both are centralized in `Version.xcconfig`, but they are no longer bumped in lock step: `MARKETING_VERSION` moves on the first commit after a release, while `CURRENT_PROJECT_VERSION` is a build number bumped on every upload and never reset, because App Store Connect requires a unique increasing build number per upload within a marketing version. Any automation has to bump them on those two different triggers rather than together.
  - Both platforms share the one build number, so uploading only iOS or only macOS still consumes a number for both. Deliberate — a shared counter is simpler than per-platform ones and only costs some gaps in the sequence.

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
  - Done 2026-07-19 for the renderer: `MarkdownCore/Tests/MarkdownCoreConformanceTests` covers the block and inline features against CommonMark 0.31.2, runs headlessly via `swift test`, and passes. It exposed 44 failing cases when it landed; all are now fixed. Still to do: the offset-mapping round trips below, and the audit of the remaining Xcode-hosted suites.
  - Audit what the existing suites actually cover. The gaps found so far were large: before the nested-list work there were no tests at all for list parsing or list HTML, despite lists being a core feature. Assume other features are in the same state until checked, and write down what is covered and what is not.
  - Add a unit test per individual markdown feature: generate a small `.md` fragment exercising exactly that feature, render it, and assert the generated HTML is correct.
    - Cover at least: headings (ATX and setext), paragraphs, bulleted lists, numbered lists, nested and mixed lists, checklists, blockquotes, fenced code, inline code, emphasis and strong, links, images, horizontal rules, and tables (including alignment, inline code in cells, and explicit line breaks).
    - Include the inline/intraword cases that are easy to get wrong — the intraword-underscore `snake_case` case is covered and passing, and is worth keeping as a regression guard.
    - Assert on exact HTML where it is stable. The preview builds display offsets by walking text nodes, so incidental whitespace between tags is a real bug, not a formatting detail — keep asserting that lists emit no whitespace between tags, and extend that check to other block types.
  - Test the offset mappings alongside the HTML: `.md` source to display text, display text back to source, and source to rendered HTML, round-tripping in both directions.
  - Land any future suite complete and runnable even where it exposes bugs. Do not gate landing the tests on fixing what they find, and do not delete or weaken a test to make the suite green.
    - Let the known-failing cases fail the test run (`Cmd-U` / `swift test`). A failing run is the honest signal that the app does not yet behave correctly; do not skip, disable, or wrap them in `withKnownIssue` to get a clean run. The suite goes green when the bugs are fixed, not before. There is no CI yet — if one is added later (see "Get ready for TestFlight"), the same rule applies to it.
    - Updating a test because the intended behavior changed is a different thing and is expected — four expectations were corrected this way while fixing the conformance failures. What is not allowed is softening an assertion to hide a defect.
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
