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

    @Published var detailMode: DetailMode = .preview
    @Published var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @Published var openErrorMessage: String?
    @Published var isInitialOpenSheetPresented = false

    let store: DocumentSessionStore

    private var hasPresentedInitialOpenSheet: Bool
    private var cancellables = Set<AnyCancellable>()

    init(
        previewFiles: [MarkdownFile] = [],
        selectedPreviewFileID: String? = nil,
        showsSourceInPreview: Bool = false,
        disablePersistenceRestore: Bool = false
    ) {
        self.store = DocumentSessionStore(
            previewFiles: previewFiles,
            selectedPreviewFileID: selectedPreviewFileID,
            disablePersistenceRestore: disablePersistenceRestore
        )
        self.detailMode = showsSourceInPreview ? .source : .preview
        self.hasPresentedInitialOpenSheet = disablePersistenceRestore

        // Bridge nested store updates so SwiftUI redraws when document data changes.
        store.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }

    func handleImport(_ result: Result<[URL], Error>, isCompactWidth: Bool) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            load(url: url, isCompactWidth: isCompactWidth)
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
    }

    func presentInitialOpenSheetIfNeeded() {
        #if os(macOS)
        return
        #else
        guard !hasPresentedInitialOpenSheet else { return }
        guard store.didRestoreDocuments else { return }
        guard store.openedDocuments.isEmpty else { return }
        hasPresentedInitialOpenSheet = true
        isInitialOpenSheetPresented = true
        #endif
    }

    func toggleDetailMode() {
        detailMode = detailMode == .preview ? .source : .preview
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
