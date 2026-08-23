//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

@MainActor
struct SearchViewModelTests {

    private func makeStore(_ files: [(name: String, contents: String)]) -> DocumentSessionStore {
        let markdownFiles = files.map {
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/\($0.name)"), contents: $0.contents)
        }
        return DocumentSessionStore(previewFiles: markdownFiles, disablePersistenceRestore: true)
    }


    @Test func inDocumentSearchSelectsFirstMatchAndCountsAll() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store)

        viewModel.setSearchText("alpha")
        viewModel.flushPendingSearch()

        #expect(viewModel.resultCount == 2)
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 0, length: 5)])
        #expect(viewModel.detailSearchStatusText == "1 of 2")
    }

    @Test func noMatchClearsTheSelection() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store)

        viewModel.setSearchText("alpha")
        viewModel.flushPendingSearch()
        #expect(!store.selections(for: id).isEmpty)

        viewModel.setSearchText("zzz")
        viewModel.flushPendingSearch()
        #expect(viewModel.resultCount == 0)
        #expect(store.selections(for: id).isEmpty)
        #expect(viewModel.detailSearchStatusText == "0 results")
    }

    @Test func clearingSearchRestoresThePreSearchSelection() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store)

        let preSearchSelection = [MarkdownSelectionRange(location: 6, length: 4)] // "beta"
        store.setSelections(preSearchSelection, for: id, text: "alpha beta alpha")

        viewModel.setSearchText("alpha")
        viewModel.flushPendingSearch()
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 0, length: 5)])

        viewModel.clearSearch()
        viewModel.flushPendingSearch()
        #expect(store.selections(for: id) == preSearchSelection)
    }

    @Test func moveToAdjacentMatchAdvancesToNextMatch() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store)

        viewModel.setSearchText("alpha")
        viewModel.flushPendingSearch()
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 0, length: 5)])

        #expect(viewModel.moveToAdjacentMatch(.forward) == true)
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 11, length: 5)])
    }

    @Test func moveToAdjacentMatchReturnsFalseWithNoActiveQuery() {
        let store = makeStore([("doc.md", "alpha")])
        let viewModel = SearchViewModel(store: store)
        #expect(viewModel.moveToAdjacentMatch(.forward) == false)
    }

    @Test func documentMatchesSearchFiltersByContent() throws {
        let store = makeStore([
            ("alpha.md", "content mentioning alpha"),
            ("beta.md", "content mentioning beta")
        ])
        let viewModel = SearchViewModel(store: store)
        viewModel.setSearchText("alpha")

        let alpha = try #require(store.openedDocuments.first { $0.file.fileName == "alpha.md" })
        let beta = try #require(store.openedDocuments.first { $0.file.fileName == "beta.md" })
        #expect(viewModel.documentMatchesSearch(alpha))
        #expect(!viewModel.documentMatchesSearch(beta))
    }

    @Test func selectionSearchTextUsesSourceSelectionInSourceMode() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store)
        store.setSelections([MarkdownSelectionRange(location: 6, length: 4)], for: id, text: "alpha beta alpha")

        #expect(viewModel.selectionSearchText(detailMode: .source) == "beta")
    }

    @Test func selectionSearchTextPrefersPreviewSelectionInPreviewMode() {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let viewModel = SearchViewModel(store: store)
        viewModel.previewSelectedText = "rendered selection"

        #expect(viewModel.selectionSearchText(detailMode: .preview) == "rendered selection")
    }

    @Test func searchForSelectionNormalizesNewlinesAndSetsQuery() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store)

        viewModel.searchForSelection("  alpha\nbeta  ")
        #expect(viewModel.searchText == "alpha beta")
    }

    @Test func trimmedAndHasSearchTextIgnoreWhitespace() {
        let store = makeStore([("doc.md", "alpha")])
        let viewModel = SearchViewModel(store: store)

        viewModel.setSearchText("   ")
        #expect(viewModel.trimmedSearchText.isEmpty)
        #expect(viewModel.hasSearchText == false)

        viewModel.setSearchText("  hi  ")
        #expect(viewModel.trimmedSearchText == "hi")
        #expect(viewModel.hasSearchText)
    }

    @Test func listSearchSuggestionsCompleteFromIndexedContent() {
        let store = makeStore([("doc.md", "alphabetical ordering")])
        let viewModel = SearchViewModel(store: store)

        viewModel.setSearchText("alph")
        #expect(viewModel.listSearchSuggestions.contains("alphabetical"))
    }

    @Test func refreshDetailSearchAppliesToTheCurrentDocument() throws {
        let store = makeStore([
            ("a.md", "alpha in a"),
            ("b.md", "alpha alpha in b")
        ])
        let viewModel = SearchViewModel(store: store)

        viewModel.setSearchText("alpha")
        viewModel.flushPendingSearch()
        #expect(viewModel.resultCount == 1)

        store.selectedDocumentID = try #require(store.openedDocuments.first { $0.file.fileName == "b.md" }).id
        viewModel.refreshDetailSearch()
        #expect(viewModel.resultCount == 2)
    }
}

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
        let previous = SystemFindPasteboard.currentQuery()
        SystemFindPasteboard.setQuery(query)
        body()
        if let previous {
            SystemFindPasteboard.setQuery(previous)
        }
    }

    /// The bug this scoping exists for: switching back from another app that had
    /// published a find term used to replace the query and re-filter the file
    /// list, without the user ever asking to search.
    @Test func findQueryIsNotAdoptedWhileNoFieldIsFocused() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store)
        viewModel.establishFindPasteboardBaseline()

        withFindPasteboard("beta") {
            viewModel.adoptSystemFindQueryIfChanged()
        }

        #expect(viewModel.searchText == "")
    }

    @Test func findQueryIsAdoptedOnceAFieldIsFocused() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store)
        viewModel.establishFindPasteboardBaseline()
        viewModel.focusedField = .list

        withFindPasteboard("beta") {
            viewModel.adoptSystemFindQueryIfChanged()
        }

        #expect(viewModel.searchText == "beta")
    }

    /// A term already on the shared buffer when the app launched is not the
    /// user's request either, so the baseline swallows the first observation.
    @Test func findQueryPresentBeforeLaunchIsNotAdopted() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store)
        viewModel.focusedField = .list

        withFindPasteboard("beta") {
            viewModel.establishFindPasteboardBaseline()
            viewModel.adoptSystemFindQueryIfChanged()
        }

        #expect(viewModel.searchText == "")
    }

    /// The write path, which the read path's tests do not cover: typing in a
    /// focused field has to reach the shared buffer even though the in-document
    /// field's focus goes transiently nil as SwiftUI re-hosts the toolbar item.
    /// The write path. Typing must reach the shared buffer regardless of what
    /// `@FocusState` reports, which is why the gate is the origin and not focus.
    @Test func userInputIsPublishedToTheFindPasteboard() async {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store)
        let previous = SystemFindPasteboard.currentQuery()
        defer { if let previous { SystemFindPasteboard.setQuery(previous) } }

        viewModel.setSearchText("alpha")
        // Outlast the 250ms write debounce.
        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(SystemFindPasteboard.currentQuery() == "alpha")
    }

    /// A search the user did not type — the selection's Search menu action —
    /// stays out of a buffer the whole machine shares.
    @Test func passiveSearchIsNotPublishedToTheFindPasteboard() async {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store)
        let previous = SystemFindPasteboard.currentQuery()
        defer { if let previous { SystemFindPasteboard.setQuery(previous) } }
        let sentinel = "markdownpreview-passive-sentinel"

        // Set directly rather than through `withFindPasteboard`, which restores
        // the previous term before the assertion could see what was left.
        SystemFindPasteboard.setQuery(sentinel)
        viewModel.searchForSelection("alpha")
        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(SystemFindPasteboard.currentQuery() == sentinel)
    }

    /// Adopting a term must not turn around and write it back. The value would
    /// be identical either way, so this watches the change count: a needless
    /// write still bumps it, and still counts as touching a shared resource.
    @Test func adoptedQueryIsNotRepublished() async {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store)
        let previous = SystemFindPasteboard.currentQuery()
        defer { if let previous { SystemFindPasteboard.setQuery(previous) } }

        viewModel.establishFindPasteboardBaseline()
        viewModel.focusedField = .list
        SystemFindPasteboard.setQuery("beta")
        let changeCountAfterSeeding = SystemFindPasteboard.changeCount()

        viewModel.adoptSystemFindQueryIfChanged()
        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(viewModel.searchText == "beta")
        #expect(SystemFindPasteboard.changeCount() == changeCountAfterSeeding)
    }
}
#endif
