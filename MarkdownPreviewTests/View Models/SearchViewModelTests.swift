//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
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

        #expect(viewModel.resultCount == 2)
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 0, length: 5)])
        #expect(viewModel.detailSearchStatusText == "1 of 2")
    }

    @Test func noMatchClearsTheSelection() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store)

        viewModel.setSearchText("alpha")
        #expect(!store.selections(for: id).isEmpty)

        viewModel.setSearchText("zzz")
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
        #expect(store.selections(for: id) == [MarkdownSelectionRange(location: 0, length: 5)])

        viewModel.clearSearch()
        #expect(store.selections(for: id) == preSearchSelection)
    }

    @Test func moveToAdjacentMatchAdvancesToNextMatch() throws {
        let store = makeStore([("doc.md", "alpha beta alpha")])
        let id = try #require(store.selectedDocumentID)
        let viewModel = SearchViewModel(store: store)

        viewModel.setSearchText("alpha")
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
        #expect(viewModel.resultCount == 1)

        store.selectedDocumentID = try #require(store.openedDocuments.first { $0.file.fileName == "b.md" }).id
        viewModel.refreshDetailSearch()
        #expect(viewModel.resultCount == 2)
    }
}
