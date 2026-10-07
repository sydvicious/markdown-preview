//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import SwiftUI
import Testing
import MarkdownCore
@testable import MarkdownPreview

@MainActor
struct ContentViewModelTests {

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func detailSearchStartsInTheToolbar() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)

        #expect(viewModel.detailSearchFitsInToolbar)
    }

    @Test func detailSearchLeavesTheToolbarBelowTheDropoutWidth() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)

        viewModel.updateDetailSearchPlacement(
            forDetailPaneWidth: ContentViewModel.detailSearchToolbarDropoutWidth - 1
        )

        #expect(viewModel.detailSearchFitsInToolbar == false)
    }

    @Test func detailSearchStaysInTheToolbarAtTheDropoutWidth() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)

        viewModel.updateDetailSearchPlacement(
            forDetailPaneWidth: ContentViewModel.detailSearchToolbarDropoutWidth
        )

        #expect(viewModel.detailSearchFitsInToolbar)
    }

    /// The dead band: once the search has moved into the pane, widths between the
    /// two thresholds must not move it back, or dragging the window edge across
    /// the boundary would make the field flicker between title bar and pane.
    @Test func detailSearchStaysInThePaneInsideTheDeadBand() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        viewModel.updateDetailSearchPlacement(forDetailPaneWidth: 400)

        let deadBandWidth = (
            ContentViewModel.detailSearchToolbarDropoutWidth
                + ContentViewModel.detailSearchToolbarRestoreWidth
        ) / 2
        viewModel.updateDetailSearchPlacement(forDetailPaneWidth: deadBandWidth)

        #expect(viewModel.detailSearchFitsInToolbar == false)
    }

    @Test func detailSearchReturnsToTheToolbarAtTheRestoreWidth() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        viewModel.updateDetailSearchPlacement(forDetailPaneWidth: 400)

        viewModel.updateDetailSearchPlacement(
            forDetailPaneWidth: ContentViewModel.detailSearchToolbarRestoreWidth
        )

        #expect(viewModel.detailSearchFitsInToolbar)
    }

    /// SwiftUI reports a zero width before the pane is laid out; that must not be
    /// read as "too narrow" and knock the search out of the toolbar on launch.
    @Test func detailSearchIgnoresUnlaidOutWidths() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)

        viewModel.updateDetailSearchPlacement(forDetailPaneWidth: 0)
        #expect(viewModel.detailSearchFitsInToolbar)

        viewModel.updateDetailSearchPlacement(forDetailPaneWidth: -100)
        #expect(viewModel.detailSearchFitsInToolbar)
    }

    @Test func detailSearchDeadBandIsNotInverted() {
        #expect(
            ContentViewModel.detailSearchToolbarRestoreWidth
                > ContentViewModel.detailSearchToolbarDropoutWidth
        )
    }

    @Test func handleImportOpensEverySelectedFile() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let urls = ["alpha", "beta", "gamma"].map { name -> URL in
            let url = temporaryDirectory.appendingPathComponent("\(name).md")
            try? name.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        viewModel.handleImport(.success(urls), isCompactWidth: false)

        #expect(
            Set(viewModel.store.openedDocuments.map(\.id)) == Set(urls.map(\.standardizedFileURL.path))
        )
    }

    @Test func openPendingURLsOpensEveryQueuedFile() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let urls = ["alpha", "beta", "gamma"].map { name -> URL in
            let url = temporaryDirectory.appendingPathComponent("\(name).md")
            try? name.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        viewModel.openPendingURLs(urls, isCompactWidth: false)

        #expect(
            Set(viewModel.store.openedDocuments.map(\.id)) == Set(urls.map(\.standardizedFileURL.path))
        )
    }

    @Test func loadOpensAndSelectsTheDocument() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let url = temporaryDirectory.appendingPathComponent("note.md")
        try "hello".write(to: url, atomically: true, encoding: .utf8)

        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        viewModel.load(url: url, isCompactWidth: false)

        #expect(viewModel.store.selectedDocumentID == url.standardizedFileURL.path)
        #expect(viewModel.detailMode == .preview)
        #expect(viewModel.openErrorMessage == nil)
    }

    @Test func loadReportsAnErrorForAMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-missing.md")

        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        viewModel.load(url: url, isCompactWidth: false)

        #expect(viewModel.openErrorMessage != nil)
        #expect(viewModel.store.openedDocuments.isEmpty)
    }

    @Test func detailNavigationTitleIsEmptyWithNoSelection() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        #expect(viewModel.detailNavigationTitle().isEmpty)
    }

    // MARK: - Command capabilities & focus/actions (Stage 2)

    @Test func commandCapabilitiesAreFalseWithNoDocuments() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        #expect(!viewModel.canFind)
        #expect(!viewModel.canProjectFind)
        #expect(!viewModel.canRemoveFromList)
        #expect(!viewModel.canFindNext)
        #expect(!viewModel.canIncreaseTextSize)
    }

    @Test func listFilteringReflectsSearchTextAndForegroundState() {
        let alpha = MarkdownFile(url: URL(fileURLWithPath: "/tmp/alpha.md"), contents: "content about alpha")
        let beta = MarkdownFile(url: URL(fileURLWithPath: "/tmp/beta.md"), contents: "content about beta")
        let viewModel = ContentViewModel(previewFiles: [alpha, beta], disablePersistenceRestore: true)

        // No search text → not filtering; every document shows.
        #expect(!viewModel.isListSearchFiltering)
        #expect(viewModel.filteredSortedDocuments.count == 2)

        viewModel.search.setSearchText("alpha")
        #expect(viewModel.isListSearchFiltering)
        #expect(viewModel.filteredSortedDocuments.map(\.file.fileName) == ["alpha.md"])
        #expect(viewModel.filteredDocumentsCount == 1)

        // Backgrounded → filtering suspended so a system search cannot hide files.
        viewModel.isSearchHostAppActive = false
        #expect(!viewModel.isListSearchFiltering)
        #expect(viewModel.filteredSortedDocuments.count == 2)
    }

    @Test func findCapabilitiesReflectDocumentAndSearchState() {
        let file = MarkdownFile(url: URL(fileURLWithPath: "/tmp/doc.md"), contents: "alpha beta alpha")
        let viewModel = ContentViewModel(previewFiles: [file], disablePersistenceRestore: true)

        #expect(viewModel.canFind)
        #expect(viewModel.canProjectFind)
        #expect(viewModel.canRemoveFromList)
        #expect(!viewModel.canFindNext)

        viewModel.search.setSearchText("alpha")
        viewModel.search.flushPendingSearch()
        #expect(viewModel.canFindNext)
        #expect(viewModel.canFindPrevious)
    }

    @Test func focusListSearchRequestsListFocus() {
        let file = MarkdownFile(url: URL(fileURLWithPath: "/tmp/doc.md"), contents: "alpha")
        let viewModel = ContentViewModel(previewFiles: [file], disablePersistenceRestore: true)

        viewModel.focusListSearch()
        #expect(viewModel.focusRequest?.field == .list)
    }

    @Test func clearSearchClearsTheTextAndRequestsNoFocus() {
        let file = MarkdownFile(url: URL(fileURLWithPath: "/tmp/doc.md"), contents: "alpha")
        let viewModel = ContentViewModel(previewFiles: [file], disablePersistenceRestore: true)

        viewModel.search.setSearchText("alpha")
        viewModel.clearSearch()

        #expect(viewModel.search.searchText.isEmpty)
        #expect(viewModel.focusRequest?.field == nil)
    }

    @Test func useCurrentSelectionForFindSeedsSearchFromSourceSelection() throws {
        let file = MarkdownFile(url: URL(fileURLWithPath: "/tmp/doc.md"), contents: "alpha beta")
        let viewModel = ContentViewModel(
            previewFiles: [file],
            showsSourceInPreview: true,
            disablePersistenceRestore: true
        )
        let id = try #require(viewModel.store.selectedDocumentID)
        viewModel.store.setSelections(
            [MarkdownSelectionRange(location: 6, length: 4)], // "beta"
            for: id,
            text: "alpha beta"
        )

        viewModel.useCurrentSelectionForFind()

        #expect(viewModel.search.searchText == "beta")
        #expect(viewModel.focusRequest?.field == .detail)
    }

    @Test func removeSelectedDocumentFromListRemovesTheSelectedDocument() {
        let alpha = MarkdownFile(url: URL(fileURLWithPath: "/tmp/alpha.md"), contents: "alpha")
        let beta = MarkdownFile(url: URL(fileURLWithPath: "/tmp/beta.md"), contents: "beta")
        let viewModel = ContentViewModel(
            previewFiles: [alpha, beta],
            selectedPreviewFileID: alpha.url.standardizedFileURL.path,
            disablePersistenceRestore: true
        )

        viewModel.removeSelectedDocumentFromList()

        #expect(viewModel.store.openedDocuments.map(\.id) == [beta.url.standardizedFileURL.path])
    }

    @Test func increaseSelectedTextSizeBumpsTheSelectedDocument() throws {
        let file = MarkdownFile(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).md"), contents: "alpha")
        let viewModel = ContentViewModel(previewFiles: [file], disablePersistenceRestore: true)
        let id = try #require(viewModel.store.selectedDocumentID)
        let before = viewModel.store.textSize(for: id)

        viewModel.increaseSelectedTextSize()

        #expect(viewModel.store.textSize(for: id) != before)
        #expect(viewModel.canDecreaseTextSize)
    }

    @Test func tooltipPathAbbreviatesTheHomeDirectory() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        let url = URL(fileURLWithPath: UserHomeDirectory.path + "/Documents/note.md")
        #expect(viewModel.tooltipPath(for: url) == "~/Documents/note.md")
    }

    @Test func initialOpenPresentationOnlyPromptsWhenTheRestoredListIsEmpty() {
        // Restored, empty list, not yet prompted → present the picker (a file
        // importer on macOS, a sheet on iOS/iPadOS).
        let shouldPrompt = ContentViewModel.initialOpenPresentation(
            hasPresentedPrompt: false,
            didRestoreDocuments: true,
            openedDocumentsEmpty: true,
            allowsFileImporter: true
        )
        #if os(macOS)
        #expect(shouldPrompt == .fileImporter)
        #else
        #expect(shouldPrompt == .sheet)
        #endif

        // Already prompted → nothing.
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: true,
                didRestoreDocuments: true,
                openedDocumentsEmpty: true,
                allowsFileImporter: true
            ) == .none
        )
        // Restore not finished yet → wait.
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: false,
                didRestoreDocuments: false,
                openedDocumentsEmpty: true,
                allowsFileImporter: true
            ) == .none
        )
        // List already has documents → nothing.
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: false,
                didRestoreDocuments: true,
                openedDocumentsEmpty: false,
                allowsFileImporter: true
            ) == .none
        )
        #if os(macOS)
        // macOS suppresses the prompt when the file importer is not allowed.
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: false,
                didRestoreDocuments: true,
                openedDocumentsEmpty: true,
                allowsFileImporter: false
            ) == .none
        )
        #endif
    }

    // MARK: - A list in two folders, and a document on screen

    /// Three documents in two folders, none of them on disk.
    private static let alpha = MarkdownFile(
        url: URL(fileURLWithPath: "/tmp/notes/alpha.md"),
        contents: "alpha apple alpha"
    )
    private static let beta = MarkdownFile(
        url: URL(fileURLWithPath: "/tmp/notes/beta.md"),
        contents: "beta banana alpha"
    )
    private static let gamma = MarkdownFile(
        url: URL(fileURLWithPath: "/tmp/other/gamma.md"),
        contents: "gamma grape"
    )

    private static func id(_ file: MarkdownFile) -> String {
        file.url.standardizedFileURL.path
    }

    /// A view model over those three with `beta.md` on screen, or with nothing
    /// on screen if `showingADocument` is false. `singleColumn` is an iPhone's
    /// layout, showing `column`.
    private func makeViewModel(
        showingADocument: Bool = true,
        singleColumn: Bool = false,
        column: NavigationSplitViewColumn = .sidebar
    ) -> ContentViewModel {
        let viewModel = ContentViewModel(
            previewFiles: [Self.gamma, Self.alpha, Self.beta],
            selectedPreviewFileID: Self.id(Self.beta),
            disablePersistenceRestore: true
        )
        if !showingADocument {
            viewModel.store.selectedDocumentID = nil
        }
        viewModel.usesSingleColumnNavigation = singleColumn
        viewModel.preferredCompactColumn = column
        return viewModel
    }

    /// Searches as a selection's Search action does: without taking focus, and
    /// without publishing the term to the find buffer the whole machine shares.
    private func search(_ viewModel: ContentViewModel, for query: String) {
        viewModel.search.setSearchText(query, origin: .passive)
        viewModel.search.flushPendingSearch()
    }

    // MARK: - Find, with the list and a document side by side

    @Test func findGoesToTheDocumentsSearchFieldWhenADocumentIsOnScreen() {
        let viewModel = makeViewModel()

        viewModel.handleFindCommand()

        #expect(viewModel.focusRequest?.field == .detail)
    }

    @Test func findGoesToTheListsSearchFieldWhenNoDocumentIsOnScreen() {
        let viewModel = makeViewModel(showingADocument: false)

        viewModel.handleFindCommand()

        #expect(viewModel.focusRequest?.field == .list)
    }

    @Test func findDoesNothingWithNoDocuments() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)

        viewModel.handleFindCommand()

        #expect(viewModel.focusRequest == nil)
    }

    // MARK: - Find, one column at a time

    @Test func findOnASingleColumnShowingADocumentGoesToItsSearchField() {
        let viewModel = makeViewModel(singleColumn: true, column: .detail)

        viewModel.handleFindCommand()

        #expect(viewModel.focusRequest?.field == .detail)
        #expect(viewModel.preferredCompactColumn == .detail)
    }

    /// The list is what the reader is looking at, so that is what Find
    /// searches, whichever document they last had open.
    @Test func findOnASingleColumnShowingTheListGoesToTheListsSearchField() {
        let viewModel = makeViewModel(singleColumn: true, column: .sidebar)

        viewModel.handleFindCommand()

        #expect(viewModel.focusRequest?.field == .list)
        #expect(viewModel.preferredCompactColumn == .sidebar)
    }

    /// The document column with no document in it has nothing to search, so
    /// Find takes the reader to the list and searches there.
    @Test func findOnASingleColumnShowingNoDocumentGoesBackToTheList() {
        let viewModel = makeViewModel(showingADocument: false, singleColumn: true, column: .detail)

        viewModel.handleFindCommand()

        #expect(viewModel.focusRequest?.field == .list)
        #expect(viewModel.preferredCompactColumn == .sidebar)
    }

    @Test func findOnASingleColumnDoesNothingWithNoDocuments() {
        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        viewModel.usesSingleColumnNavigation = true
        viewModel.preferredCompactColumn = .detail

        viewModel.handleFindCommand()

        #expect(viewModel.focusRequest == nil)
        #expect(viewModel.preferredCompactColumn == .detail)
    }

    @Test func whetherFindIsOfferedOnASingleColumnDependsOnWhatIsShowing() {
        // The list, with documents in it: there is something to search.
        #expect(makeViewModel(showingADocument: false, singleColumn: true, column: .sidebar).canFind)
        // A document: there is something to search.
        #expect(makeViewModel(singleColumn: true, column: .detail).canFind)
        // The document column with no document in it: nothing to search there.
        #expect(!makeViewModel(showingADocument: false, singleColumn: true, column: .detail).canFind)
        // Side by side, the list is on screen too, so Find is still offered.
        #expect(makeViewModel(showingADocument: false).canFind)
    }

    // MARK: - Going to a search field

    @Test func goingToTheDocumentsSearchFieldNeedsADocument() {
        let viewModel = makeViewModel(showingADocument: false, singleColumn: true, column: .sidebar)

        viewModel.focusDetailSearch()

        #expect(viewModel.focusRequest == nil)
        #expect(viewModel.preferredCompactColumn == .sidebar)
    }

    @Test func goingToTheDocumentsSearchFieldOnASingleColumnShowsTheDocument() {
        let viewModel = makeViewModel(singleColumn: true, column: .sidebar)

        viewModel.focusDetailSearch()

        #expect(viewModel.focusRequest?.field == .detail)
        #expect(viewModel.preferredCompactColumn == .detail)
    }

    @Test func goingToTheListsSearchFieldOnASingleColumnShowsTheList() {
        let viewModel = makeViewModel(singleColumn: true, column: .detail)

        viewModel.focusListSearch()

        #expect(viewModel.focusRequest?.field == .list)
        #expect(viewModel.preferredCompactColumn == .sidebar)
    }

    /// Side by side, both are on screen already, and which column a narrower
    /// window would prefer is left as it was.
    @Test func goingToASearchFieldSideBySideLeavesTheColumnsAlone() {
        let viewModel = makeViewModel(column: .detail)

        viewModel.focusListSearch()
        #expect(viewModel.preferredCompactColumn == .detail)

        viewModel.preferredCompactColumn = .sidebar
        viewModel.focusDetailSearch()
        #expect(viewModel.preferredCompactColumn == .sidebar)
    }

    /// Asking for the field that already has the request is still a new
    /// request, or the view would not put the focus back there a second time.
    @Test func askingForTheSameSearchFieldTwiceIsTwoRequests() throws {
        let viewModel = makeViewModel()

        viewModel.focusDetailSearch()
        let first = try #require(viewModel.focusRequest)
        viewModel.focusDetailSearch()
        let second = try #require(viewModel.focusRequest)

        #expect(first.field == .detail)
        #expect(second.field == .detail)
        #expect(first != second)
    }

    // MARK: - Find Next and Find Previous

    @Test func findNextMovesToTheNextMatchAndLeavesTheFocusWhereItIs() {
        let viewModel = makeViewModel()
        viewModel.store.selectedDocumentID = Self.id(Self.alpha)
        search(viewModel, for: "alpha")
        #expect(viewModel.store.selections(for: Self.id(Self.alpha)) == [MarkdownSelectionRange(location: 0, length: 5)])

        viewModel.navigateDetailSearch(.forward)

        #expect(viewModel.store.selections(for: Self.id(Self.alpha)) == [MarkdownSelectionRange(location: 12, length: 5)])
        #expect(viewModel.focusRequest == nil)
    }

    @Test func findPreviousMovesToTheMatchBefore() {
        let viewModel = makeViewModel()
        viewModel.store.selectedDocumentID = Self.id(Self.alpha)
        search(viewModel, for: "alpha")
        viewModel.navigateDetailSearch(.forward)

        viewModel.navigateDetailSearch(.backward)

        #expect(viewModel.store.selections(for: Self.id(Self.alpha)) == [MarkdownSelectionRange(location: 0, length: 5)])
        #expect(viewModel.focusRequest == nil)
    }

    /// With nothing being searched for there is no next match to go to, so the
    /// reader is taken to the search field to say what they want.
    @Test func findNextWithNothingToFindGoesToTheDocumentsSearchField() {
        let viewModel = makeViewModel()
        viewModel.search.setSearchText("", origin: .passive)
        viewModel.search.flushPendingSearch()

        viewModel.navigateDetailSearch(.forward)

        #expect(viewModel.focusRequest?.field == .detail)
    }

    @Test func findNextWithNothingToFindAndNoDocumentDoesNothing() {
        let viewModel = makeViewModel(showingADocument: false)

        viewModel.navigateDetailSearch(.forward)

        #expect(viewModel.focusRequest == nil)
    }

    // MARK: - Cancelling a search

    /// The request with no field in it is the one that takes the focus out of
    /// the search fields.
    @Test func cancellingASearchClearsItAndTakesTheFocusOutOfTheSearchFields() throws {
        let viewModel = makeViewModel()
        search(viewModel, for: "banana")
        viewModel.focusDetailSearch()

        viewModel.cancelFocusedSearch()

        #expect(viewModel.search.searchText.isEmpty)
        #expect(!viewModel.isListSearchFiltering)
        let request = try #require(viewModel.focusRequest)
        #expect(request.field == nil)
    }

    // MARK: - Smaller text

    @Test func smallerTextTakesTheDocumentOnScreenDownOneStep() throws {
        let viewModel = makeViewModel()
        let smaller = try #require(DynamicTypeSize.defaultValue.nextSmaller)

        viewModel.decreaseSelectedTextSize()

        #expect(viewModel.store.textSize(for: Self.id(Self.beta)) == smaller)
        // The other documents are as they were.
        #expect(viewModel.store.textSize(for: Self.id(Self.alpha)) == .defaultValue)
        #expect(viewModel.store.textSize(for: Self.id(Self.gamma)) == .defaultValue)
    }

    @Test func largerAndThenSmallerTextIsTheSizeItStartedAt() {
        let viewModel = makeViewModel()

        viewModel.increaseSelectedTextSize()
        viewModel.decreaseSelectedTextSize()

        #expect(viewModel.store.textSize(for: Self.id(Self.beta)) == .defaultValue)
        // The size everything starts at is not kept as a size of its own.
        #expect(viewModel.store.textSizesByDocumentID[Self.id(Self.beta)] == nil)
    }

    @Test func smallerTextStopsAtTheSmallestSize() {
        let viewModel = makeViewModel()

        var steps = 0
        while viewModel.canDecreaseTextSize, steps < 20 {
            viewModel.decreaseSelectedTextSize()
            steps += 1
        }
        let smallest = viewModel.store.textSize(for: Self.id(Self.beta))
        viewModel.decreaseSelectedTextSize()

        #expect(steps > 0)
        #expect(smallest.nextSmaller == nil)
        #expect(viewModel.store.textSize(for: Self.id(Self.beta)) == smallest)
        #expect(!viewModel.canDecreaseTextSize)
        #expect(viewModel.canIncreaseTextSize)
    }

    @Test func smallerTextWithNoDocumentOnScreenChangesNothing() {
        let viewModel = makeViewModel(showingADocument: false)

        viewModel.decreaseSelectedTextSize()

        #expect(!viewModel.canDecreaseTextSize)
        #expect(viewModel.store.textSizesByDocumentID.isEmpty)
    }

    // MARK: - What the Mac's sidebar shows

    @Test func withNoSearchTheSidebarShowsEveryFolderAndDocument() {
        let viewModel = makeViewModel()

        let sections = viewModel.filteredGroupedDocumentsByParentDirectory

        #expect(sections == viewModel.store.groupedDocumentsByParentDirectory)
        #expect(sections.map { $0.documents.map(\.file.fileName) } == [["alpha.md", "beta.md"], ["gamma.md"]])
    }

    /// A folder none of whose documents match is not shown at all, and one
    /// that is shown lists only the documents that match.
    @Test func aSearchLeavesOnlyTheFoldersAndDocumentsThatMatch() {
        let viewModel = makeViewModel()

        search(viewModel, for: "banana")
        let sections = viewModel.filteredGroupedDocumentsByParentDirectory

        #expect(sections.map(\.directoryPath) == ["/tmp/notes"])
        #expect(sections.map { $0.documents.map(\.file.fileName) } == [["beta.md"]])
        // The folder is named as it is when nothing is being searched for.
        let unfiltered = viewModel.store.groupedDocumentsByParentDirectory.first { $0.directoryPath == "/tmp/notes" }
        #expect(sections.first?.label == unfiltered?.label)
    }

    @Test func aSearchThatMatchesInBothFoldersShowsBoth() {
        let viewModel = makeViewModel()

        search(viewModel, for: "a")
        let sections = viewModel.filteredGroupedDocumentsByParentDirectory

        #expect(sections.map { $0.documents.map(\.file.fileName) } == [["alpha.md", "beta.md"], ["gamma.md"]])
    }

    @Test func aSearchThatMatchesNothingShowsNoFolders() {
        let viewModel = makeViewModel()

        search(viewModel, for: "zucchini")

        #expect(viewModel.filteredGroupedDocumentsByParentDirectory.isEmpty)
        #expect(viewModel.filteredDocumentsCount == 0)
    }

    /// The same rule as the plain list: with the app in the background a
    /// search does not hide anything.
    @Test func aSearchHidesNothingInTheSidebarWhileTheAppIsInTheBackground() {
        let viewModel = makeViewModel()
        search(viewModel, for: "banana")

        viewModel.isSearchHostAppActive = false

        #expect(viewModel.filteredGroupedDocumentsByParentDirectory == viewModel.store.groupedDocumentsByParentDirectory)
    }

    @Test func theSidebarAndThePlainListShowTheSameDocuments() {
        let viewModel = makeViewModel()

        for query in ["", "banana", "alpha", "a", "zucchini"] {
            search(viewModel, for: query)

            let inSidebar = viewModel.filteredGroupedDocumentsByParentDirectory.flatMap(\.documents).map(\.id)
            let inList = viewModel.filteredSortedDocuments.map(\.id)
            #expect(Set(inSidebar) == Set(inList), "searching for \"\(query)\"")
            #expect(inSidebar.count == viewModel.filteredDocumentsCount, "searching for \"\(query)\"")
        }
    }

    // MARK: - Taking a document off the list

    @Test func removingTheDocumentOnScreenShowsTheFirstOneLeftAndSearchesIt() {
        let viewModel = makeViewModel()
        search(viewModel, for: "alpha")
        #expect(viewModel.search.resultCount == 1)

        viewModel.removeSelectedDocumentFromList()

        #expect(viewModel.store.selectedDocumentID == Self.id(Self.alpha))
        // The search is still what it was, and is now of the document that
        // took the removed one's place.
        #expect(viewModel.search.searchText == "alpha")
        #expect(viewModel.search.resultCount == 2)
    }

    /// One column at a time, with the document that was showing gone, the
    /// reader is taken back to the list, as they are when a missing document
    /// is taken off it.
    @Test func removingTheDocumentOnScreenOnASingleColumnGoesBackToTheList() {
        let viewModel = makeViewModel(singleColumn: true, column: .detail)

        viewModel.removeSelectedDocumentFromList()

        #expect(viewModel.store.selectedDocumentID == nil)
        #expect(viewModel.preferredCompactColumn == .sidebar)
    }

    @Test func removingAnotherDocumentOnASingleColumnLeavesTheOneShowing() {
        let viewModel = makeViewModel(singleColumn: true, column: .detail)

        viewModel.removeDocumentFromList(id: Self.id(Self.gamma))

        #expect(viewModel.store.selectedDocumentID == Self.id(Self.beta))
        #expect(viewModel.preferredCompactColumn == .detail)
    }

    // MARK: - Opening, at either width

    @Test(arguments: [true, false])
    func openingADocumentShowsItOnACompactScreenAndNotOtherwise(isCompactWidth: Bool) throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let url = temporaryDirectory.appendingPathComponent("note.md")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        let viewModel = ContentViewModel(disablePersistenceRestore: true)

        viewModel.load(url: url, isCompactWidth: isCompactWidth)

        #expect(viewModel.preferredCompactColumn == (isCompactWidth ? .detail : .sidebar))
    }

    @Test(arguments: [true, false])
    func answeringAMissingDocumentGoesBackToTheListOnACompactScreen(isCompactWidth: Bool) throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let url = temporaryDirectory.appendingPathComponent("note.md")
        try "hello".write(to: url, atomically: true, encoding: .utf8)
        let viewModel = ContentViewModel(disablePersistenceRestore: true)
        viewModel.load(url: url, isCompactWidth: isCompactWidth)
        viewModel.preferredCompactColumn = .detail

        try FileManager.default.removeItem(at: url)
        viewModel.store.checkActiveDocumentForChanges(isCompactWidth: isCompactWidth)
        try #require(viewModel.store.missingActiveDocumentAlert != nil)
        viewModel.acknowledgeMissingActiveDocument(isCompactWidth: isCompactWidth)

        #expect(viewModel.store.openedDocuments.isEmpty)
        #expect(viewModel.store.missingActiveDocumentAlert == nil)
        #expect(viewModel.preferredCompactColumn == (isCompactWidth ? .sidebar : .detail))
    }
}
