//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore

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
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

        viewModel.setSearchText("alpha")
        viewModel.flushPendingSearch()

        #expect(viewModel.resultCount == 2)
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 0, length: 5)])
        #expect(viewModel.detailSearchStatusText == "1 of 2")
    }

    @Test func noMatchClearsTheSelection() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

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
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

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
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

        viewModel.setSearchText("alpha")
        viewModel.flushPendingSearch()
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 0, length: 5)])

        #expect(viewModel.moveToAdjacentMatch(.forward) == true)
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 11, length: 5)])
    }

    @Test func moveToAdjacentMatchReturnsFalseWithNoActiveQuery() {
        let store = makeStore([("doc.md", "alpha")])
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())
        #expect(viewModel.moveToAdjacentMatch(.forward) == false)
    }

    @Test func documentMatchesSearchFiltersByContent() throws {
        let store = makeStore([
            ("alpha.md", "content mentioning alpha"),
            ("beta.md", "content mentioning beta")
        ])
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())
        viewModel.setSearchText("alpha")

        let alpha = try #require(store.openedDocuments.first { $0.file.fileName == "alpha.md" })
        let beta = try #require(store.openedDocuments.first { $0.file.fileName == "beta.md" })
        #expect(viewModel.documentMatchesSearch(alpha))
        #expect(!viewModel.documentMatchesSearch(beta))
    }

    @Test func selectionSearchTextUsesSourceSelectionInSourceMode() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())
        store.setSelections([MarkdownSelectionRange(location: 6, length: 4)], for: id, text: "alpha beta alpha")

        #expect(viewModel.selectionSearchText(detailMode: .source) == "beta")
    }

    @Test func selectionSearchTextPrefersPreviewSelectionInPreviewMode() {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())
        viewModel.previewSelectedText = "rendered selection"

        #expect(viewModel.selectionSearchText(detailMode: .preview) == "rendered selection")
    }

    @Test func searchForSelectionNormalizesNewlinesAndSetsQuery() {
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

        viewModel.searchForSelection("  alpha\nbeta  ")
        #expect(viewModel.searchText == "alpha beta")
    }

    @Test func trimmedAndHasSearchTextIgnoreWhitespace() {
        let store = makeStore([("doc.md", "alpha")])
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

        viewModel.setSearchText("   ")
        #expect(viewModel.trimmedSearchText.isEmpty)
        #expect(viewModel.hasSearchText == false)

        viewModel.setSearchText("  hi  ")
        #expect(viewModel.trimmedSearchText == "hi")
        #expect(viewModel.hasSearchText)
    }

    // MARK: - Suggestions under the two search fields

    /// Two documents, with `a.md` on screen.
    private func makeSuggestionStore() -> DocumentSessionStore {
        makeStore([
            ("a.md", "alphabet soup and alpine air"),
            ("b.md", "an alpaca"),
        ])
    }

    /// The field over a document offers words from that document, and the
    /// field over the list offers them from every document.
    @Test func theDocumentsSearchFieldSuggestsFromTheDocumentOnScreenOnly() {
        let store = makeSuggestionStore()
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

        viewModel.setSearchText("al", origin: .passive)
        viewModel.flushPendingSearch()

        #expect(viewModel.detailSearchSuggestions == ["alphabet", "alpine"])
        #expect(viewModel.listSearchSuggestions == ["alphabet", "alpine", "alpaca"])
    }

    @Test func theDocumentsSearchFieldSuggestsFromWhicheverDocumentIsOnScreen() throws {
        let store = makeSuggestionStore()
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())
        viewModel.setSearchText("al", origin: .passive)
        viewModel.flushPendingSearch()

        store.selectedDocumentID = try #require(store.openedDocuments.first { $0.file.fileName == "b.md" }).id

        #expect(viewModel.detailSearchSuggestions == ["alpaca"])
    }

    @Test func theDocumentsSearchFieldSuggestsNothingWithNoDocumentOnScreen() {
        let store = makeSuggestionStore()
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())
        viewModel.setSearchText("al", origin: .passive)
        viewModel.flushPendingSearch()

        store.selectedDocumentID = nil

        #expect(viewModel.detailSearchSuggestions.isEmpty)
        // The list is still there to search.
        #expect(viewModel.listSearchSuggestions == ["alphabet", "alpine", "alpaca"])
    }

    @Test func neitherFieldSuggestsAnythingForOneCharacter() {
        let store = makeSuggestionStore()
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

        viewModel.setSearchText("a", origin: .passive)
        viewModel.flushPendingSearch()

        #expect(viewModel.detailSearchSuggestions.isEmpty)
        #expect(viewModel.listSearchSuggestions.isEmpty)
    }

    @Test func clearingTheSearchClearsTheSuggestions() {
        let store = makeSuggestionStore()
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())
        viewModel.setSearchText("al", origin: .passive)
        viewModel.flushPendingSearch()

        viewModel.setSearchText("", origin: .passive)
        viewModel.flushPendingSearch()

        #expect(viewModel.detailSearchSuggestions.isEmpty)
        #expect(viewModel.listSearchSuggestions.isEmpty)
    }

    @Test func listSearchSuggestionsCompleteFromIndexedContent() {
        let store = makeStore([("doc.md", "alphabetical ordering")])
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

        viewModel.setSearchText("alph")
        #expect(viewModel.listSearchSuggestions.contains("alphabetical"))
    }

    @Test func refreshDetailSearchAppliesToTheCurrentDocument() throws {
        let store = makeStore([
            ("a.md", "alpha in a"),
            ("b.md", "alpha alpha in b")
        ])
        let viewModel = SearchViewModel(store: store, findPasteboard: InMemoryFindPasteboard())

        viewModel.setSearchText("alpha")
        viewModel.flushPendingSearch()
        #expect(viewModel.resultCount == 1)

        store.selectedDocumentID = try #require(store.openedDocuments.first { $0.file.fileName == "b.md" }).id
        viewModel.refreshDetailSearch()
        #expect(viewModel.resultCount == 2)
    }

    // MARK: - The find pasteboard it is given

    /// What the reader types goes to the find pasteboard the view model was
    /// made with, and to no other.
    @Test func aTypedTermIsPublishedToTheFindPasteboardItWasGiven() async throws {
        let findPasteboard = InMemoryFindPasteboard()
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)

        viewModel.setSearchText("alpha")
        #if os(macOS)
        // On the Mac the write waits for a pause in the typing.
        let write = try #require(viewModel.pasteboardWriteTask, "typing should have called for a write")
        await write.value
        #endif

        #expect(findPasteboard.currentQuery() == "alpha")
    }

    @Test func anEmptySearchIsSeededFromTheFindPasteboardItWasGiven() {
        let findPasteboard = InMemoryFindPasteboard()
        findPasteboard.setQuery("beta")
        let store = makeStore([("doc.md", "alpha beta")])
        let viewModel = SearchViewModel(store: store, findPasteboard: findPasteboard)

        viewModel.seedFromPasteboardIfEmpty()

        #expect(viewModel.searchText == "beta")
    }
}
