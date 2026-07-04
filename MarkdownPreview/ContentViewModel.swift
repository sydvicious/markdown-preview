//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ContentViewModel: ObservableObject {
    enum DetailMode {
        case preview
        case source
    }

    enum InitialOpenPresentation {
        case none
        case fileImporter
        case sheet
    }

    @Published var detailMode: DetailMode = .preview
    @Published var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @Published var openErrorMessage: String?
    @Published var isInitialOpenSheetPresented = false

    let store: DocumentSessionStore
    let search: SearchViewModel

    private var hasPresentedInitialOpenPrompt: Bool
    private var cancellables = Set<AnyCancellable>()

    init(
        previewFiles: [MarkdownFile] = [],
        selectedPreviewFileID: String? = nil,
        showsSourceInPreview: Bool = false,
        disablePersistenceRestore: Bool = false
    ) {
        let store = DocumentSessionStore(
            previewFiles: previewFiles,
            selectedPreviewFileID: selectedPreviewFileID,
            disablePersistenceRestore: disablePersistenceRestore
        )
        self.store = store
        self.search = SearchViewModel(store: store)
        self.detailMode = showsSourceInPreview ? .source : .preview
        self.hasPresentedInitialOpenPrompt = disablePersistenceRestore

        // Bridge nested store and search updates so SwiftUI redraws when document
        // data or search state changes.
        for publisher in [store.objectWillChange, search.objectWillChange] {
            publisher
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.objectWillChange.send()
                    }
                }
                .store(in: &cancellables)
        }
    }

    func handleImport(_ result: Result<[URL], Error>, isCompactWidth: Bool) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            for url in urls {
                load(url: url, isCompactWidth: isCompactWidth)
            }
        case .failure(let error):
            openErrorMessage = error.localizedDescription
        }
    }

    func load(url: URL, isCompactWidth: Bool) {
        do {
            try store.openDocument(at: url)
            detailMode = .preview
            preferredCompactColumn = isCompactWidth ? .detail : .sidebar
            openErrorMessage = nil
        } catch {
            openErrorMessage = detailedOpenErrorMessage(for: error, url: url)
        }
    }

    func onDocumentsChanged() {
        store.persistDocuments()
    }

    func onSelectionChanged() {
        store.persistSelectedDocument()
    }

    func restorePersistedDocumentsIfNeeded(isCompactWidth: Bool) {
        store.restorePersistedDocumentsIfNeeded(isCompactWidth: isCompactWidth)
        if isCompactWidth, store.selectedDocumentID != nil {
            preferredCompactColumn = .detail
        }
    }

    func presentInitialOpenPromptIfNeeded() -> InitialOpenPresentation {
        let presentation = initialOpenPresentationIfNeeded(allowsFileImporter: true)
        guard presentation != .none else { return .none }

        hasPresentedInitialOpenPrompt = true
        if presentation == .sheet {
            isInitialOpenSheetPresented = true
        }
        return presentation
    }

    func initialOpenPresentationIfNeeded(allowsFileImporter: Bool) -> InitialOpenPresentation {
        Self.initialOpenPresentation(
            hasPresentedPrompt: hasPresentedInitialOpenPrompt,
            didRestoreDocuments: store.didRestoreDocuments,
            openedDocumentsEmpty: store.openedDocuments.isEmpty,
            allowsFileImporter: allowsFileImporter
        )
    }

    nonisolated static func initialOpenPresentation(
        hasPresentedPrompt: Bool,
        didRestoreDocuments: Bool,
        openedDocumentsEmpty: Bool,
        allowsFileImporter: Bool
    ) -> InitialOpenPresentation {
        guard !hasPresentedPrompt else { return .none }
        guard didRestoreDocuments else { return .none }
        guard openedDocumentsEmpty else { return .none }
        #if os(macOS)
        guard allowsFileImporter else { return .none }
        return .fileImporter
        #else
        return .sheet
        #endif
    }

    func acknowledgeMissingActiveDocument(isCompactWidth: Bool) {
        let shouldShowSidebar = store.acknowledgeMissingActiveDocument(isCompactWidth: isCompactWidth)
        if shouldShowSidebar {
            preferredCompactColumn = .sidebar
        }
    }

    func detailNavigationTitle() -> String {
        guard let currentDocument = store.currentDocument else { return "" }
        #if os(macOS)
        return disambiguatedTitle(for: currentDocument)
        #else
        return currentDocument.file.fileName
        #endif
    }

    func tooltipPath(for url: URL) -> String {
        let fullPath = url.path
        let homePath = NSHomeDirectory()
        guard fullPath == homePath || fullPath.hasPrefix(homePath + "/") else {
            return fullPath
        }
        return "~" + fullPath.dropFirst(homePath.count)
    }

    private func disambiguatedTitle(for document: DocumentSessionStore.OpenedDocument) -> String {
        let baseName = document.file.fileName
        let parentName = document.file.url.deletingLastPathComponent().lastPathComponent
        if parentName.isEmpty {
            return baseName
        }
        return "\(baseName) – \(parentName)"
    }

    private func detailedOpenErrorMessage(for error: Error, url: URL) -> String {
        let nsError = error as NSError
        return "\(error.localizedDescription)\n(\(nsError.domain) code \(nsError.code))\n\(url.path)"
    }
}
