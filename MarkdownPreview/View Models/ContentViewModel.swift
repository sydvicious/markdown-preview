//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import SwiftUI
import Combine

/// Which search field the keyboard focus targets. The actual `@FocusState` lives
/// in the View, but the view model reasons about focus in these terms.
enum SearchField: Hashable {
    case list
    case detail
}

/// A view-model request for the View to move keyboard focus. The `token` makes
/// each request a distinct value so the View re-applies focus even when the same
/// field is requested twice in a row.
struct SearchFocusRequest: Equatable {
    let field: SearchField?
    let token: Int
}

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
    /// Whether the layout shows one column at a time (iPhone). Mirrored from the
    /// View's size class so command/focus logic can read it without the View env.
    @Published var usesSingleColumnNavigation = false
    /// Whether the app is foregrounded. Mirrored from the View's scene phase so
    /// file-list filtering only hides files while the app is active (a background
    /// system search should not unexpectedly filter the list).
    @Published var isSearchHostAppActive = true
    /// Latest request for the View to move keyboard focus (see `SearchFocusRequest`).
    @Published private(set) var focusRequest: SearchFocusRequest?

    let store: DocumentSessionStore
    let search: SearchViewModel

    private var hasPresentedInitialOpenPrompt: Bool
    private var focusRequestToken = 0
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

        // Search state changes on every keystroke and drives the search field,
        // so forward it synchronously — deferring it to a later runloop tick made
        // typing in the search field visibly lag.
        search.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Store updates (document data, selections, file-monitor polling) are not
        // per-keystroke and can originate outside a user event, so defer them to
        // the next main-actor tick to stay clear of publishing during a view update.
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

    // MARK: - File-list filtering

    var isListSearchFiltering: Bool {
        search.hasSearchText && isSearchHostAppActive
    }

    var filteredSortedDocuments: [DocumentSessionStore.OpenedDocument] {
        guard isListSearchFiltering else { return store.sortedDocuments }
        return store.sortedDocuments.filter(search.documentMatchesSearch)
    }

    var filteredGroupedDocumentsByParentDirectory: [DocumentSessionStore.DocumentSection] {
        guard isListSearchFiltering else { return store.groupedDocumentsByParentDirectory }

        return store.groupedDocumentsByParentDirectory.compactMap { section in
            let documents = section.documents.filter(search.documentMatchesSearch)
            guard !documents.isEmpty else { return nil }
            return DocumentSessionStore.DocumentSection(
                directoryPath: section.directoryPath,
                label: section.label,
                documents: documents
            )
        }
    }

    var filteredDocumentsCount: Int {
        filteredSortedDocuments.count
    }

    // MARK: - Command capabilities

    var canFind: Bool {
        if usesSingleColumnNavigation {
            if preferredCompactColumn == .detail {
                return store.currentDocument != nil
            }
            return !store.openedDocuments.isEmpty
        }
        if store.currentDocument != nil {
            return true
        }
        return !store.openedDocuments.isEmpty
    }

    var canProjectFind: Bool { !store.openedDocuments.isEmpty }
    var canUseSelectionForFind: Bool { search.selectionSearchText(detailMode: detailMode) != nil }
    var canFindNext: Bool { search.resultCount > 0 }
    var canFindPrevious: Bool { search.resultCount > 0 }
    var canIncreaseTextSize: Bool { store.selectedDocumentID.map(store.canIncreaseTextSize(for:)) ?? false }
    var canDecreaseTextSize: Bool { store.selectedDocumentID.map(store.canDecreaseTextSize(for:)) ?? false }
    var canRemoveFromList: Bool { store.selectedDocumentID != nil }

    // MARK: - Find commands (drive focus via `focusRequest`)

    func handleFindCommand() {
        if usesSingleColumnNavigation {
            if preferredCompactColumn == .detail, store.currentDocument != nil {
                focusDetailSearch()
            } else if !store.openedDocuments.isEmpty {
                focusListSearch()
            }
            return
        }
        if store.currentDocument != nil {
            focusDetailSearch()
        } else if !store.openedDocuments.isEmpty {
            focusListSearch()
        }
    }

    func focusListSearch() {
        if usesSingleColumnNavigation {
            preferredCompactColumn = .sidebar
        }
        search.seedFromPasteboardIfEmpty()
        requestFocus(.list)
    }

    func focusDetailSearch() {
        guard store.currentDocument != nil else { return }
        if usesSingleColumnNavigation {
            preferredCompactColumn = .detail
        }
        search.seedFromPasteboardIfEmpty()
        requestFocus(.detail)
    }

    func navigateDetailSearch(_ direction: MarkdownSearchDirection) {
        if !search.moveToAdjacentMatch(direction) {
            focusDetailSearch()
        }
    }

    func useCurrentSelectionForFind() {
        guard let text = search.selectionSearchText(detailMode: detailMode) else { return }
        search.setSearchText(text)
        requestFocus(.detail)
    }

    func cancelFocusedSearch() {
        guard !search.searchText.isEmpty else { return }
        clearSearch()
    }

    func clearSearch() {
        search.clearSearch()
        requestFocus(nil)
    }

    private func requestFocus(_ field: SearchField?) {
        focusRequestToken += 1
        focusRequest = SearchFocusRequest(field: field, token: focusRequestToken)
    }

    // MARK: - Text size

    func increaseSelectedTextSize() {
        guard let id = store.selectedDocumentID else { return }
        store.increaseTextSize(for: id)
    }

    func decreaseSelectedTextSize() {
        guard let id = store.selectedDocumentID else { return }
        store.decreaseTextSize(for: id)
    }

    // MARK: - Removal

    func removeSelectedDocumentFromList() {
        guard let id = store.selectedDocumentID else { return }
        removeDocumentFromList(id: id)
    }

    func removeDocumentFromList(id: String) {
        let shouldShowSidebar = store.removeDocument(id: id, isCompactWidth: usesSingleColumnNavigation)
        if shouldShowSidebar {
            preferredCompactColumn = .sidebar
        }
        // Keep the shared search string intact (the file list stays filtered);
        // just re-run the in-document search against whatever is now current.
        search.refreshDetailSearch()
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
