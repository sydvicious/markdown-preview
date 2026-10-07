//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

#if os(macOS)
/// Tests that touch the macOS system find pasteboard.
///
/// They share one global resource — the machine-wide find buffer — so they are
/// serialized against each other. Run in parallel they clobber each other's
/// terms and fail intermittently, which is a property of the resource, not of
/// the code under test. Each test also restores whatever term it found, since
/// that buffer belongs to every app on the system.
@Suite(.serialized)
@MainActor
struct SearchViewModelFindPasteboardTests {

    /// The machine's own find pasteboard, which is what these tests are about.
    private let findPasteboard = SystemFindPasteboard()

    private func makeStore(_ files: [(name: String, contents: String)]) -> DocumentSessionStore {
    let markdownFiles = files.map {
        MarkdownFile(url: URL(fileURLWithPath: "/tmp/\($0.name)"), contents: $0.contents)
    }
    return DocumentSessionStore(previewFiles: markdownFiles, disablePersistenceRestore: true)
    }

    /// Runs `body` with the system find pasteboard holding `query`, then puts
    /// whatever was there back. The find buffer is shared with every other app
    /// on the machine, so a test must not leave its own term sitting on it.
    private func withFindPasteboard(_ query: String, _ body: () -> Void) {
        let previous = findPasteboard.currentQuery()
        findPasteboard.setQuery(query)
        body()
        if let previous {
            findPasteboard.setQuery(previous)
        }
    }

    /// The bug this scoping exists for: switching back from another app that had
    /// published a find term used to replace the query and re-filter the file
    /// list, without the user ever asking to search.
    @Test func findQueryIsNotAdoptedWhileNoFieldIsFocused() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)

        withFindPasteboard("beta") {
            viewModel.adoptSystemFindQueryIfChanged()
        }

        #expect(viewModel.searchText == "")
    }

    // MARK: - Starting a search from what the machine last searched for

    /// Going to an empty search field starts it with the term on the find
    /// buffer, the way Find does in every other app.
    @Test func anEmptySearchIsSeededFromTheFindBuffer() {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)

        withFindPasteboard("alpha") {
            viewModel.seedFromPasteboardIfEmpty()
        }
        viewModel.flushPendingSearch()

        #expect(viewModel.searchText == "alpha")
        #expect(viewModel.resultCount == 2)
        // The buffer already holds it, so it is not written back there.
        #expect(viewModel.pasteboardWriteTask == nil)
    }

    /// What the reader has typed is theirs. The buffer does not replace it.
    @Test func aSearchAlreadyUnderWayIsNotReplacedFromTheFindBuffer() {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)
        viewModel.setSearchText("beta", origin: .passive)

        withFindPasteboard("alpha") {
            viewModel.seedFromPasteboardIfEmpty()
        }

        #expect(viewModel.searchText == "beta")
    }

    /// A field holding only spaces has nothing in it.
    @Test func aSearchFieldHoldingOnlySpacesIsSeededFromTheFindBuffer() {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)
        viewModel.setSearchText("   ", origin: .passive)

        withFindPasteboard("alpha") {
            viewModel.seedFromPasteboardIfEmpty()
        }

        #expect(viewModel.searchText == "alpha")
    }

    @Test func findQueryIsAdoptedOnceAFieldIsFocused() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)
        viewModel.focusedField = .list

        withFindPasteboard("beta") {
            viewModel.adoptSystemFindQueryIfChanged()
        }

        #expect(viewModel.searchText == "beta")
    }

    /// Clicking into a search field is the user asking to search, so the first
    /// click adopts whatever is on the buffer — including a term published
    /// before this launch, which an earlier baseline used to swallow.
    @Test func findQueryPresentBeforeLaunchIsAdoptedOnFirstFocus() {
        let store = makeStore([("doc.md", "alpha beta")])

        withFindPasteboard("beta") {
            // The term is on the buffer before there is a view model to see it.
            let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)

            // Looked at with no field focused, as when the app comes forward,
            // it is not adopted, and looking must not use it up.
            viewModel.adoptSystemFindQueryIfChanged()
            #expect(viewModel.searchText == "")

            viewModel.focusedField = .list
            viewModel.adoptSystemFindQueryIfChanged()
            #expect(viewModel.searchText == "beta")
        }
    }

    /// The write path, which the read path's tests do not cover: typing in a
    /// focused field has to reach the shared buffer even though the in-document
    /// field's focus goes transiently nil as SwiftUI re-hosts the toolbar item.
    /// The write path. Typing must reach the shared buffer regardless of what
    /// `@FocusState` reports, which is why the gate is the origin and not focus.
    @Test func userInputIsPublishedToTheFindPasteboard() async throws {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)
        let previous = findPasteboard.currentQuery()
        defer { if let previous { findPasteboard.setQuery(previous) } }

        viewModel.setSearchText("alpha")
        // The write waits for a pause in the typing, and then for its turn on
        // the main actor. In a full run that turn can be a long time coming, so
        // this waits for the write and not for a length of time: sleeping 400ms
        // to outlast the 250ms pause read the pasteboard before the write had
        // been made, and found whatever the machine had on it.
        let write = try #require(viewModel.pasteboardWriteTask, "typing should have called for a write")
        await write.value

        #expect(findPasteboard.currentQuery() == "alpha")
    }

    /// A search the user did not type — the selection's Search menu action —
    /// stays out of a buffer the whole machine shares.
    @Test func passiveSearchIsNotPublishedToTheFindPasteboard() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)
        let previous = findPasteboard.currentQuery()
        defer { if let previous { findPasteboard.setQuery(previous) } }
        let sentinel = "markdownpreview-passive-sentinel"

        // Set directly rather than through `withFindPasteboard`, which restores
        // the previous term before the assertion could see what was left.
        findPasteboard.setQuery(sentinel)
        viewModel.searchForSelection("alpha")

        // No write is waiting to be made, so there is nothing to outlast.
        #expect(viewModel.pasteboardWriteTask == nil)
        #expect(findPasteboard.currentQuery() == sentinel)
    }

    /// Adopting a term must not turn around and write it back. The value would
    /// be identical either way, so this watches the change count: a needless
    /// write still bumps it, and still counts as touching a shared resource.
    @Test func adoptedQueryIsNotRepublished() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)
        let previous = findPasteboard.currentQuery()
        defer { if let previous { findPasteboard.setQuery(previous) } }

        viewModel.focusedField = .list
        findPasteboard.setQuery("beta")
        let changeCountAfterSeeding = findPasteboard.changeCount()

        viewModel.adoptSystemFindQueryIfChanged()

        #expect(viewModel.searchText == "beta")
        #expect(viewModel.pasteboardWriteTask == nil)
        #expect(findPasteboard.changeCount() == changeCountAfterSeeding)
    }
}
#endif
