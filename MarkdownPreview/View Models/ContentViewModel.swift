//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import SwiftUI
import Combine
import os

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
    private let disablePersistenceRestore: Bool
    private static let bundledSampleSeededKey = "hasSeededBundledSample"
    private static let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "FirstLaunch")
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
        self.disablePersistenceRestore = disablePersistenceRestore

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

    func load(url: URL, bookmarkData: Data? = nil, isCompactWidth: Bool) {
        do {
            try store.openDocument(at: url, bookmarkData: bookmarkData)
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
            guard let url = item as? NSURL as URL? else { return }

            // Bookmark here rather than after the hop below. The extension a drop
            // vends is tied to the drag session, and this handler is the last
            // point it is reliably live — two async boundaries later it may be
            // reclaimed, and the bookmark that reopens this file on the next
            // launch would fail to be made at all.
            let bookmarkData = Self.securityScopedBookmark(for: url)

            Task { @MainActor in
                self?.load(url: url, bookmarkData: bookmarkData, isCompactWidth: isCompactWidth)
            }
        }
        return true
    }

    /// A security-scoped bookmark for a URL whose scope is live right now.
    ///
    /// Returns nil rather than throwing: a drop that cannot be bookmarked should
    /// still open, and `openDocument(at:bookmarkData:)` will try again itself.
    nonisolated private static func securityScopedBookmark(for url: URL) -> Data? {
        let opened = url.startAccessingSecurityScopedResource()
        defer {
            if opened {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
        seedBundledSampleIfNeeded(isCompactWidth: isCompactWidth)
        refreshSeededSampleIfNeeded(isCompactWidth: isCompactWidth)
        if isCompactWidth, store.selectedDocumentID != nil {
            preferredCompactColumn = .detail
        }
    }

    /// On the very first launch, puts the bundled `SAMPLE.md` into the list as if
    /// the user had opened it, so a new user (and a screenshot) is met with a
    /// rendered document rather than an empty window.
    ///
    /// The one-and-only attempt is recorded up front (see `BundledSampleSeeder`
    /// for why the gate needs all three conditions), so a decline or a failure is
    /// never retried on a later launch, where the sample turning up on its own
    /// after the user has added their own files would be confusing.
    ///
    /// The sample is copied into the app's own container and opened from there
    /// rather than in place: the bundle file reads fine, but the sandbox refuses to
    /// mint a security-scoped bookmark for a file the user did not pick, so opening
    /// it in place fails when the list persists it (NSCocoaError 256). Failures are
    /// logged, not shown — this is a first-launch nicety, not a user action.
    func seedBundledSampleIfNeeded(isCompactWidth: Bool, userDefaults: UserDefaults = .standard) {
        guard !disablePersistenceRestore else { return }

        let alreadyAttempted = userDefaults.bool(forKey: Self.bundledSampleSeededKey)
        if !alreadyAttempted {
            userDefaults.set(true, forKey: Self.bundledSampleSeededKey)
        }

        guard BundledSampleSeeder.shouldSeed(
            alreadyAttempted: alreadyAttempted,
            hasPersistedList: store.hasPersistedDocumentList(in: userDefaults),
            listIsEmpty: store.openedDocuments.isEmpty
        ) else { return }

        guard let templateURL = Self.bundledSampleURL() else {
            Self.log.error("Sample not seeded: SAMPLE.md is missing from the app bundle.")
            return
        }
        guard let container = Self.containerDocumentsURL() else {
            Self.log.error("Sample not seeded: could not locate the app's Documents directory.")
            return
        }

        do {
            let copiedURL = try BundledSampleSeeder.materialize(
                templateURL: templateURL,
                imageURL: Self.bundledSampleImageURL(),
                version: Self.marketingVersion(),
                build: Self.buildNumber(),
                in: container
            )
            try store.openDocument(at: copiedURL)
            detailMode = .preview
            preferredCompactColumn = isCompactWidth ? .detail : .sidebar
        } catch {
            let nsError = error as NSError
            Self.log.error("Sample not seeded: \(nsError.domain, privacy: .public) code \(nsError.code): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Brings an already-seeded copy up to date when a newly shipped build carries
    /// a different sample — a version bump changes the substituted title line. Only
    /// the on-disk file is rewritten; the document is never re-added to the list,
    /// so one the user removed stays gone. Failures are logged and retried next
    /// launch, leaving the existing copy untouched.
    func refreshSeededSampleIfNeeded(isCompactWidth: Bool) {
        guard !disablePersistenceRestore else { return }
        guard let templateURL = Self.bundledSampleURL() else { return }
        guard let containerURL = seededSampleURLInList(named: templateURL.lastPathComponent) else { return }

        do {
            let didReplace = try BundledSampleSeeder.refresh(
                templateURL: templateURL,
                containerURL: containerURL,
                version: Self.marketingVersion(),
                build: Self.buildNumber()
            )
            if didReplace {
                store.checkActiveDocumentForChanges(isCompactWidth: isCompactWidth)
                store.checkAllDocumentsForChanges(isCompactWidth: isCompactWidth)
            }
        } catch {
            let nsError = error as NSError
            Self.log.error("Sample not refreshed: \(containerURL.lastPathComponent, privacy: .public) — \(nsError.domain, privacy: .public) code \(nsError.code): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The seeded sample among the open documents, if it is still in the list:
    /// matched by name and by living in the app's Documents directory, resolving
    /// symlinks so the container path (under `/private/var`) compares equal.
    private func seededSampleURLInList(named fileName: String) -> URL? {
        guard let documents = Self.containerDocumentsURL() else { return nil }
        let documentsPath = documents.resolvingSymlinksInPath().path
        return store.openedDocuments.first(where: { document in
            document.file.url.lastPathComponent == fileName &&
            document.file.url.deletingLastPathComponent().resolvingSymlinksInPath().path == documentsPath
        })?.file.url
    }

    private static func bundledSampleURL() -> URL? {
        Bundle.main.url(forResource: "SAMPLE", withExtension: "md")
    }

    private static func bundledSampleImageURL() -> URL? {
        Bundle.main.url(forResource: "lilsyd", withExtension: "JPG")
    }

    private static func containerDocumentsURL() -> URL? {
        try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    /// The marketing version (e.g. "0.7") substituted for the template's
    /// `{{VERSION}}` token when the copy is written.
    private static func marketingVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// The build number (e.g. "1") substituted for the template's `{{BUILD}}` token.
    private static func buildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
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
        let homePath = UserHomeDirectory.path
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
