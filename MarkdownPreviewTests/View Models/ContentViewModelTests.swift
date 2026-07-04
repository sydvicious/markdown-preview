//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

@MainActor
struct ContentViewModelTests {

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Documents/note.md")
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
}
