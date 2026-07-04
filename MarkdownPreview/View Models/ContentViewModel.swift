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
    @Published var isImporterPresented = false

    let store: DocumentSessionStore
    let search: SearchViewModel

    private var hasPresentedInitialOpenPrompt: Bool
    private var cancellables = Set<AnyCancellable>()
    #if os(macOS)
    private static let startupImporterDelayNanoseconds: UInt64 = 300_000_000
    private var pendingStartupImporterTask: Task<Void, Never>?
    #endif

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

    /// Opens every URL the system queued (a batch Finder Open, or a sequence of
    /// `.onOpenURL` deliveries) and refreshes the in-document search.
    func openPendingURLs(_ urls: [URL], isCompactWidth: Bool) {
        cancelPendingStartupImporter()
        for url in urls {
            load(url: url, isCompactWidth: isCompactWidth)
        }
        search.refreshDetailSearch()
    }

    func cancelPendingStartupImporter() {
        #if os(macOS)
        pendingStartupImporterTask?.cancel()
        pendingStartupImporterTask = nil
        #endif
    }

    #if os(macOS)
    /// Loads the first file URL from a drag-and-drop onto the window.
    func loadDroppedProviders(_ providers: [NSItemProvider], isCompactWidth: Bool) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSURL.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSURL.self) { [weak self] item, _ in
            guard let url = item as? NSURL else { return }
            Task { @MainActor in
                self?.load(url: url as URL, isCompactWidth: isCompactWidth)
            }
        }
        return true
    }

    /// After a short delay, presents the macOS file importer if the app launched
    /// with an empty list and no file was opened externally.
    func scheduleStartupImporterIfNeeded() {
        cancelPendingStartupImporter()

        guard initialOpenPresentationIfNeeded(
            allowsFileImporter: !FileOpenState.shared.didReceiveExternalOpenRequest
        ) == .fileImporter else { return }

        pendingStartupImporterTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.startupImporterDelayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            guard self.initialOpenPresentationIfNeeded(
                allowsFileImporter: !FileOpenState.shared.didReceiveExternalOpenRequest
            ) == .fileImporter else { return }
            if self.presentInitialOpenPromptIfNeeded() == .fileImporter {
                self.isImporterPresented = true
            }
            self.pendingStartupImporterTask = nil
        }
    }
    #endif

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
