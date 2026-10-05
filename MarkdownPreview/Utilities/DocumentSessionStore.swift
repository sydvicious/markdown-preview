//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import SwiftUI
import os
import MarkdownCore
#if canImport(UIKit)
import UIKit
#endif

extension DynamicTypeSize {
    static let defaultValue: DynamicTypeSize = .large

    private static let persistenceOrder: [DynamicTypeSize] = [
        .xSmall,
        .small,
        .medium,
        .large,
        .xLarge,
        .xxLarge,
        .xxxLarge,
        .accessibility1,
        .accessibility2,
        .accessibility3,
        .accessibility4,
        .accessibility5
    ]

    var persistedValue: String {
        switch self {
        case .xSmall: return "xSmall"
        case .small: return "small"
        case .medium: return "medium"
        case .large: return "large"
        case .xLarge: return "xLarge"
        case .xxLarge: return "xxLarge"
        case .xxxLarge: return "xxxLarge"
        case .accessibility1: return "accessibility1"
        case .accessibility2: return "accessibility2"
        case .accessibility3: return "accessibility3"
        case .accessibility4: return "accessibility4"
        case .accessibility5: return "accessibility5"
        @unknown default: return Self.defaultValue.persistedValue
        }
    }

    init?(persistedValue: String) {
        switch persistedValue {
        case "xSmall": self = .xSmall
        case "small": self = .small
        case "medium": self = .medium
        case "large": self = .large
        case "xLarge": self = .xLarge
        case "xxLarge": self = .xxLarge
        case "xxxLarge": self = .xxxLarge
        case "accessibility1": self = .accessibility1
        case "accessibility2": self = .accessibility2
        case "accessibility3": self = .accessibility3
        case "accessibility4": self = .accessibility4
        case "accessibility5": self = .accessibility5
        default: return nil
        }
    }

    var scaleFactor: CGFloat {
        #if canImport(UIKit)
        let baseFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        let metrics = UIFontMetrics(forTextStyle: .body)
        let basePointSize = metrics.scaledFont(
            for: baseFont,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
        let scaledPointSize = metrics.scaledFont(
            for: baseFont,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: uiContentSizeCategory)
        ).pointSize
        return scaledPointSize / basePointSize
        #else
        switch self {
        case .xSmall: return 14.0 / 17.0
        case .small: return 15.0 / 17.0
        case .medium: return 16.0 / 17.0
        case .large: return 1.0
        case .xLarge: return 19.0 / 17.0
        case .xxLarge: return 21.0 / 17.0
        case .xxxLarge: return 23.0 / 17.0
        case .accessibility1: return 28.0 / 17.0
        case .accessibility2: return 33.0 / 17.0
        case .accessibility3: return 40.0 / 17.0
        case .accessibility4: return 47.0 / 17.0
        case .accessibility5: return 53.0 / 17.0
        @unknown default: return Self.defaultValue.scaleFactor
        }
        #endif
    }

    #if canImport(UIKit)
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
    #endif

    var nextLarger: DynamicTypeSize? {
        guard let index = Self.persistenceOrder.firstIndex(of: self),
              index < Self.persistenceOrder.index(before: Self.persistenceOrder.endIndex) else {
            return nil
        }
        return Self.persistenceOrder[index + 1]
    }

    var nextSmaller: DynamicTypeSize? {
        guard let index = Self.persistenceOrder.firstIndex(of: self),
              index > Self.persistenceOrder.startIndex else {
            return nil
        }
        return Self.persistenceOrder[index - 1]
    }
}

/// How the security scope of a bookmark-resolved URL is taken and released.
///
/// The store goes through this rather than calling the URL directly so a test
/// can stand in for a sandbox that refuses the scope, which no test host does.
struct SecurityScope {
    var start: (URL) -> Bool
    var stop: (URL) -> Void

    static let system = SecurityScope(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )
}

@MainActor
final class DocumentSessionStore: ObservableObject {
    struct DocumentSection: Identifiable, Equatable {
        let directoryPath: String
        let label: String
        let documents: [OpenedDocument]

        var id: String { directoryPath }
    }

    struct MissingActiveDocumentAlert: Identifiable {
        let id: String
        let fileName: String
    }

    struct OpenedDocument: Identifiable, Equatable {
        let id: String
        var file: MarkdownFile
        var lastOpened: Date
        var bookmarkData: Data
    }

    private struct PersistedDocument: Codable {
        let id: String
        let lastOpened: Date
        let bookmarkData: Data
    }

    private struct RestoreMigration {
        let documents: [OpenedDocument]
        let modificationDates: [String: Date]
        let idMap: [String: String]
    }

    private let persistedDocumentsKey = "openedMarkdownDocuments"
    private let persistedSelectionKey = "selectedMarkdownDocumentID"
    private static let persistedTextSizesKey = "markdownDocumentTextSizes"

    private static let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "Session")

    @Published var openedDocuments: [OpenedDocument]
    @Published var selectedDocumentID: OpenedDocument.ID?
    private var knownModificationDates: [String: Date] = [:]
    @Published private(set) var selectionsByDocumentID: [String: [MarkdownSelectionRange]] = [:]
    @Published private(set) var textSizesByDocumentID: [String: DynamicTypeSize] = [:]
    @Published var missingActiveDocumentAlert: MissingActiveDocumentAlert?
    private let documentSearchIndex: DocumentSearchIndex
    private let securityScope: SecurityScope

    /// Bookmarks whose security scope the system refused during this launch.
    ///
    /// A refusal is a property of the bookmark, not of the moment: every
    /// resolution hands back the same sandbox token, and one the kernel has
    /// rejected is rejected again each time it is offered. The active document
    /// is polled once a second, so asking again is a failed call — and a
    /// `sandbox_extension_consume failed` line in the console — per second, for
    /// as long as the document is on screen. The read goes ahead without the
    /// scope either way, which is all that asking again could have achieved.
    private var bookmarksWithRefusedScope: Set<Data> = []

    private(set) var didRestoreDocuments = false

    init(
        previewFiles: [MarkdownFile] = [],
        selectedPreviewFileID: String? = nil,
        disablePersistenceRestore: Bool = false,
        userDefaults: UserDefaults = .standard,
        securityScope: SecurityScope = .system
    ) {
        let now = Date()
        let opened = previewFiles.map {
            OpenedDocument(
                id: $0.url.standardizedFileURL.path,
                file: $0,
                lastOpened: now,
                bookmarkData: Data()
            )
        }
        self.openedDocuments = opened
        self.selectedDocumentID = selectedPreviewFileID ?? opened.first?.id
        self.didRestoreDocuments = disablePersistenceRestore
        self.textSizesByDocumentID = Self.restoreTextSizes(
            from: userDefaults,
            validDocumentIDs: Set(opened.map(\.id))
        )
        self.documentSearchIndex = DocumentSearchIndex(documents: opened.map(\.file))
        self.securityScope = securityScope
    }

    var sortedDocuments: [OpenedDocument] {
        openedDocuments.sorted(by: Self.sortDocumentsByFileName)
    }

    var groupedDocumentsByParentDirectory: [DocumentSection] {
        let grouped = Dictionary(grouping: openedDocuments, by: { document in
            document.file.url.deletingLastPathComponent().standardizedFileURL.path
        })

        return grouped
            .map { directoryPath, documents in
                DocumentSection(
                    directoryPath: directoryPath,
                    label: Self.displayDirectoryPath(directoryPath),
                    documents: documents.sorted(by: Self.sortDocumentsByFileName)
                )
            }
            .sorted { lhs, rhs in
                let labelComparison = lhs.label.localizedCaseInsensitiveCompare(rhs.label)
                if labelComparison != .orderedSame {
                    return labelComparison == .orderedAscending
                }
                return lhs.directoryPath < rhs.directoryPath
            }
    }

    var currentDocument: OpenedDocument? {
        guard let selectedDocumentID else { return nil }
        return openedDocuments.first(where: { $0.id == selectedDocumentID })
    }

    func documentMatchesListSearch(_ documentID: String, query: String) -> Bool {
        documentSearchIndex.containsMatch(in: documentID, query: query)
    }

    func listSearchSuggestions(prefix: String, limit: Int = 5) -> [String] {
        documentSearchIndex.suggestedCompletions(prefix: prefix, limit: limit)
    }

    func detailSearchSuggestions(for documentID: String, prefix: String, limit: Int = 5) -> [String] {
        documentSearchIndex.suggestedCompletions(in: documentID, prefix: prefix, limit: limit)
    }

    func textSize(for documentID: String) -> DynamicTypeSize {
        textSizesByDocumentID[documentID] ?? .defaultValue
    }

    func canIncreaseTextSize(for documentID: String) -> Bool {
        textSize(for: documentID).nextLarger != nil
    }

    func canDecreaseTextSize(for documentID: String) -> Bool {
        textSize(for: documentID).nextSmaller != nil
    }

    func increaseTextSize(for documentID: String) {
        guard let next = textSize(for: documentID).nextLarger else { return }
        setTextSize(next, for: documentID)
    }

    func decreaseTextSize(for documentID: String) {
        guard let next = textSize(for: documentID).nextSmaller else { return }
        setTextSize(next, for: documentID)
    }

    /// Opens `url`, reusing a bookmark the caller already made if it has one.
    ///
    /// Drag-and-drop supplies `bookmarkData` because the sandbox extension a drop
    /// vends belongs to the drag session: by the time the URL has crossed onto the
    /// main actor there may be nothing left to bookmark. Callers that hold a
    /// durable scope — the file importer, an open request from Finder, a restored
    /// session — pass nothing and let this make its own.
    func openDocument(at url: URL, bookmarkData suppliedBookmarkData: Data? = nil) throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmarkData: Data
        do {
            bookmarkData = try suppliedBookmarkData ?? makeBookmarkData(for: url)
        } catch {
            // Bookmark failures surface as an opaque "couldn't be opened", which
            // reads like the file is missing when the real problem is that no
            // security scope was held to record. Log the two facts that tell
            // those apart before letting it go up.
            let nsError = error as NSError
            Self.log.error("""
                Could not bookmark \(url.lastPathComponent, privacy: .public): \
                \(nsError.domain, privacy: .public) \(nsError.code) — \
                \(error.localizedDescription, privacy: .public); \
                scopeOpened=\(hasAccess), callerSuppliedBookmark=\(suppliedBookmarkData != nil)
                """)
            throw error
        }

        guard let loaded = loadFromBookmarkData(bookmarkData) else {
            throw CocoaError(.fileNoSuchFile)
        }
        upsertDocument(loaded.file, bookmarkData: bookmarkData, modificationDate: loaded.modificationDate)
    }

    func upsertDocument(_ file: MarkdownFile, bookmarkData: Data, modificationDate: Date?) {
        let id = file.url.standardizedFileURL.path
        if let index = openedDocuments.firstIndex(where: { $0.id == id }) {
            if openedDocuments[index].bookmarkData != bookmarkData {
                bookmarksWithRefusedScope.remove(openedDocuments[index].bookmarkData)
            }
            openedDocuments[index].file = file
            openedDocuments[index].lastOpened = Date()
            openedDocuments[index].bookmarkData = bookmarkData
        } else {
            openedDocuments.append(.init(id: id, file: file, lastOpened: Date(), bookmarkData: bookmarkData))
        }
        if let modificationDate {
            knownModificationDates[id] = modificationDate
        }
        documentSearchIndex.upsert(file)
        selectedDocumentID = id
    }

    func deleteDocuments(at offsets: IndexSet, isCompactWidth: Bool) {
        let idsToDelete = offsets.map { sortedDocuments[$0].id }
        for document in openedDocuments where idsToDelete.contains(document.id) {
            bookmarksWithRefusedScope.remove(document.bookmarkData)
        }
        openedDocuments.removeAll(where: { idsToDelete.contains($0.id) })
        idsToDelete.forEach {
            knownModificationDates.removeValue(forKey: $0)
            selectionsByDocumentID.removeValue(forKey: $0)
            textSizesByDocumentID.removeValue(forKey: $0)
            documentSearchIndex.remove(documentID: $0)
        }
        if let selectedDocumentID, idsToDelete.contains(selectedDocumentID) {
            self.selectedDocumentID = isCompactWidth ? nil : sortedDocuments.first?.id
        }
    }

    @discardableResult
    func removeDocument(
        id: String,
        forceShowSidebarOnCompact: Bool = false,
        isCompactWidth: Bool
    ) -> Bool {
        let wasSelected = selectedDocumentID == id
        for document in openedDocuments where document.id == id {
            bookmarksWithRefusedScope.remove(document.bookmarkData)
        }
        openedDocuments.removeAll(where: { $0.id == id })
        knownModificationDates.removeValue(forKey: id)
        selectionsByDocumentID.removeValue(forKey: id)
        textSizesByDocumentID.removeValue(forKey: id)
        documentSearchIndex.remove(documentID: id)

        var shouldShowSidebar = false
        if wasSelected {
            if isCompactWidth {
                selectedDocumentID = nil
                shouldShowSidebar = forceShowSidebarOnCompact
            } else {
                selectedDocumentID = sortedDocuments.first?.id
            }
        }
        return shouldShowSidebar
    }

    func selections(for documentID: String) -> [MarkdownSelectionRange] {
        selectionsByDocumentID[documentID] ?? []
    }

    func setSelections(_ ranges: [MarkdownSelectionRange], for documentID: String, text: String) {
        let maxLength = text.utf16.count
        let sanitized = ranges.compactMap { $0.clamped(toUTF16Length: maxLength) }
        if sanitized.isEmpty {
            selectionsByDocumentID.removeValue(forKey: documentID)
        } else {
            selectionsByDocumentID[documentID] = sanitized
        }
    }

    func restorePersistedDocumentsIfNeeded(isCompactWidth _: Bool, userDefaults: UserDefaults) {
        guard !didRestoreDocuments else { return }
        didRestoreDocuments = true

        let decoder = JSONDecoder()
        guard let data = userDefaults.data(forKey: persistedDocumentsKey),
              let persisted = try? decoder.decode([PersistedDocument].self, from: data) else {
            return
        }

        let migration = restoreMigration(
            from: persisted.sorted(by: { $0.lastOpened > $1.lastOpened })
        )

        openedDocuments = migration.documents
        knownModificationDates = migration.modificationDates
        textSizesByDocumentID = Self.restoreTextSizes(
            from: userDefaults,
            validDocumentIDs: Set(migration.documents.map(\.id)),
            idMap: migration.idMap
        )
        documentSearchIndex.rebuild(with: migration.documents.map(\.file))
        if let persistedSelection = userDefaults.string(forKey: persistedSelectionKey) {
            let resolvedSelection = migration.idMap[persistedSelection] ?? persistedSelection
            if migration.documents.contains(where: { $0.id == resolvedSelection }) {
                selectedDocumentID = resolvedSelection
            } else {
                selectedDocumentID = nil
            }
        } else {
            selectedDocumentID = nil
        }
    }

    func restorePersistedDocumentsIfNeeded(isCompactWidth: Bool) {
        restorePersistedDocumentsIfNeeded(isCompactWidth: isCompactWidth, userDefaults: .standard)
    }

    /// Whether a document list has ever been persisted, which is distinct from the
    /// list being empty. A brand-new install has no key at all; a user who has
    /// opened and then removed every document has an empty array persisted under
    /// the key. Callers that must tell a first-ever launch apart from an emptied
    /// list — the bundled-sample seed — key off this rather than off emptiness.
    func hasPersistedDocumentList(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: persistedDocumentsKey) != nil
    }

    func persistDocuments(to userDefaults: UserDefaults) {
        let encoder = JSONEncoder()
        let persisted = openedDocuments.map {
            PersistedDocument(id: $0.id, lastOpened: $0.lastOpened, bookmarkData: $0.bookmarkData)
        }
        guard let data = try? encoder.encode(persisted) else { return }
        userDefaults.set(data, forKey: persistedDocumentsKey)
    }

    func persistDocuments() {
        persistDocuments(to: .standard)
    }

    func persistSelectedDocument(to userDefaults: UserDefaults) {
        userDefaults.set(selectedDocumentID, forKey: persistedSelectionKey)
    }

    func persistSelectedDocument() {
        persistSelectedDocument(to: .standard)
    }

    func checkActiveDocumentForChanges(isCompactWidth: Bool) {
        guard let selectedDocumentID else { return }
        reloadDocumentIfNeeded(
            documentID: selectedDocumentID,
            alertIfMissing: true,
            isCompactWidth: isCompactWidth
        )
    }

    func checkAllDocumentsForChanges(isCompactWidth: Bool) {
        guard !openedDocuments.isEmpty else { return }
        let activeID = selectedDocumentID
        let ids = openedDocuments.map(\.id)
        for id in ids where id != activeID {
            reloadDocumentIfNeeded(
                documentID: id,
                alertIfMissing: false,
                isCompactWidth: isCompactWidth
            )
        }
    }

    func acknowledgeMissingActiveDocument(isCompactWidth: Bool) -> Bool {
        guard let alert = missingActiveDocumentAlert else { return false }
        let shouldShowSidebar = removeDocument(
            id: alert.id,
            forceShowSidebarOnCompact: true,
            isCompactWidth: isCompactWidth
        )
        missingActiveDocumentAlert = nil
        return shouldShowSidebar
    }

    private func reloadDocumentIfNeeded(
        documentID: String,
        alertIfMissing: Bool,
        isCompactWidth: Bool
    ) {
        guard let index = openedDocuments.firstIndex(where: { $0.id == documentID }) else { return }
        let document = openedDocuments[index]

        guard let url = resolveBookmarkURL(from: document.bookmarkData) else {
            handleMissingDocument(
                document,
                alertIfMissing: alertIfMissing,
                isCompactWidth: isCompactWidth
            )
            return
        }

        if let modificationDate = currentModificationDate(for: url, resolvedFrom: document.bookmarkData) {
            let knownDate = knownModificationDates[document.id]
            if knownDate != nil, modificationDate <= knownDate! {
                return
            }
        }

        guard let loaded = loadDocument(at: url, resolvedFrom: document.bookmarkData) else {
            handleMissingDocument(
                document,
                alertIfMissing: alertIfMissing,
                isCompactWidth: isCompactWidth
            )
            return
        }

        if let modificationDate = loaded.modificationDate {
            knownModificationDates[document.id] = modificationDate
        }

        guard loaded.file.contents != document.file.contents else { return }
        openedDocuments[index].file = loaded.file
        documentSearchIndex.upsert(loaded.file)
        clampSelections(for: document.id, text: loaded.file.contents)
    }

    private func handleMissingDocument(
        _ document: OpenedDocument,
        alertIfMissing: Bool,
        isCompactWidth: Bool
    ) {
        if alertIfMissing {
            guard missingActiveDocumentAlert?.id != document.id else { return }
            missingActiveDocumentAlert = .init(id: document.id, fileName: document.file.fileName)
        } else {
            _ = removeDocument(id: document.id, isCompactWidth: isCompactWidth)
        }
    }

    private func makeBookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        // Deliberately no fallback to a non-scoped bookmark. One resolves fine
        // and then yields a URL the sandbox refuses, so the document reopens
        // normally for the rest of the launch and is dropped by `restoreMigration`
        // on the next one — a failure that surfaces far from its cause. Throwing
        // sends it up through `openDocument(at:)` to the open error message
        // instead, where the user sees it against the file they just opened.
        return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private func loadFromBookmarkData(_ bookmarkData: Data) -> (file: MarkdownFile, modificationDate: Date?)? {
        guard let url = resolveBookmarkURL(from: bookmarkData) else {
            return nil
        }
        return loadDocument(at: url, resolvedFrom: bookmarkData)
    }

    private func resolveBookmarkURL(from bookmarkData: Data) -> URL? {
        var isStale = false
        do {
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            // `.withoutImplicitStartAccessing` for the same reason
            // `DirectoryAccessStore` passes it: on iOS resolving a bookmark
            // *starts* the implicit scope it carries, and the system permits only
            // a limited number of open scoped URLs. This resolves once per
            // document at launch and again on every polling tick, so without it
            // each one leaks a scope until access is refused. Access is taken
            // explicitly in `withSecurityScope`.
            let options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutImplicitStartAccessing]
            #endif
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return url
        } catch {
            return nil
        }
    }

    /// Runs `body` holding the security scope of `url`, which was resolved from
    /// `bookmarkData`, and releases it afterwards.
    ///
    /// `body` runs whether or not the scope could be taken: plenty of documents
    /// are readable without one — anything in the app's own container, and
    /// everything when the app is not sandboxed — and a read that does need it
    /// fails on its own, which the callers already treat as a missing document.
    /// A refused scope is asked for once and not again; see
    /// `bookmarksWithRefusedScope`.
    private func withSecurityScope<T>(
        of url: URL,
        resolvedFrom bookmarkData: Data,
        perform body: () -> T
    ) -> T {
        guard !bookmarksWithRefusedScope.contains(bookmarkData) else {
            return body()
        }
        guard securityScope.start(url) else {
            bookmarksWithRefusedScope.insert(bookmarkData)
            logRefusedScope(for: url)
            return body()
        }
        defer { securityScope.stop(url) }
        return body()
    }

    /// One line per refused bookmark per launch, saying what would tell a dead
    /// token on a document that never needed one apart from a document that is
    /// about to go missing. Filter the console on `[scope]`.
    private func logRefusedScope(for url: URL) {
        let readableAnyway = FileManager.default.isReadableFile(atPath: url.path)
        let inAppContainer = url.standardizedFileURL.path.hasPrefix(
            URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path + "/"
        )
        Self.log.info("""
            [scope] Security scope refused for \(url.lastPathComponent, privacy: .public); \
            not asking again this launch. readableWithoutScope=\(readableAnyway), \
            inAppContainer=\(inAppContainer)
            """)
    }

    private func loadDocument(
        at url: URL,
        resolvedFrom bookmarkData: Data
    ) -> (file: MarkdownFile, modificationDate: Date?)? {
        withSecurityScope(of: url, resolvedFrom: bookmarkData) {
            do {
                let file = try MarkdownFile.load(from: url)
                let modificationDate = modificationDateWithinAccess(for: url)
                return (file, modificationDate)
            } catch {
                return nil
            }
        }
    }

    /// The document's modification date, taking the URL's security scope for the
    /// read.
    ///
    /// Reading a resource value is itself privileged. `reloadDocumentIfNeeded`
    /// polls this for every open document without holding a scope of its own, and
    /// sandboxed that read returns nil — which does not fail loudly, it defeats
    /// the "unchanged, so skip" check and silently re-reads every open document
    /// on every tick.
    private func currentModificationDate(for url: URL, resolvedFrom bookmarkData: Data) -> Date? {
        withSecurityScope(of: url, resolvedFrom: bookmarkData) {
            modificationDateWithinAccess(for: url)
        }
    }

    /// The same read for callers that already hold the scope, so it is not taken
    /// twice over.
    private func modificationDateWithinAccess(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private func clampSelections(for documentID: String, text: String) {
        guard let current = selectionsByDocumentID[documentID] else { return }
        let maxLength = text.utf16.count
        let clamped = current.compactMap { $0.clamped(toUTF16Length: maxLength) }
        if clamped.isEmpty {
            selectionsByDocumentID.removeValue(forKey: documentID)
        } else {
            selectionsByDocumentID[documentID] = clamped
        }
    }

    private func setTextSize(_ textSize: DynamicTypeSize, for documentID: String) {
        if textSize == .defaultValue {
            textSizesByDocumentID.removeValue(forKey: documentID)
        } else {
            textSizesByDocumentID[documentID] = textSize
        }
    }

    func persistTextSizes(to userDefaults: UserDefaults) {
        let persisted = textSizesByDocumentID.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key] = entry.value.persistedValue
        }
        userDefaults.set(persisted, forKey: Self.persistedTextSizesKey)
    }

    func persistTextSizes() {
        persistTextSizes(to: .standard)
    }

    private func restoreMigration(from persisted: [PersistedDocument]) -> RestoreMigration {
        var restored: [OpenedDocument] = []
        var restoredModificationDates: [String: Date] = [:]
        var idMap: [String: String] = [:]

        for entry in persisted {
            guard let loaded = loadFromBookmarkData(entry.bookmarkData) else { continue }
            let resolvedID = loaded.file.url.standardizedFileURL.path
            idMap[entry.id] = resolvedID
            // Two entries can resolve to one file: a document opened, moved, and
            // opened again from its new place is saved under both paths, and the
            // first entry's bookmark follows the file. `persisted` arrives newest
            // first, so the one kept is the one opened last; the other's ID still
            // maps to it, for the selection and text size saved under that ID.
            guard !restored.contains(where: { $0.id == resolvedID }) else { continue }
            restored.append(
                .init(
                    id: resolvedID,
                    file: loaded.file,
                    lastOpened: entry.lastOpened,
                    bookmarkData: entry.bookmarkData
                )
            )
            if let modificationDate = loaded.modificationDate {
                restoredModificationDates[resolvedID] = modificationDate
            }
        }

        return RestoreMigration(
            documents: restored,
            modificationDates: restoredModificationDates,
            idMap: idMap
        )
    }

    private static func restoreTextSizes(
        from userDefaults: UserDefaults,
        validDocumentIDs: Set<String>,
        idMap: [String: String] = [:]
    ) -> [String: DynamicTypeSize] {
        guard let persisted = userDefaults.dictionary(forKey: Self.persistedTextSizesKey) as? [String: String] else {
            return [:]
        }

        return persisted.reduce(into: [String: DynamicTypeSize]()) { partialResult, entry in
            let resolvedID = idMap[entry.key] ?? entry.key
            guard validDocumentIDs.contains(resolvedID) else {
                return
            }
            guard let textSize = DynamicTypeSize(persistedValue: entry.value),
                  textSize != .defaultValue else {
                return
            }
            partialResult[resolvedID] = textSize
        }
    }

    private static func sortDocumentsByFileName(_ lhs: OpenedDocument, _ rhs: OpenedDocument) -> Bool {
        let nameComparison = lhs.file.fileName.localizedStandardCompare(rhs.file.fileName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.file.url.path.localizedStandardCompare(rhs.file.url.path) == .orderedAscending
    }

    private static func displayDirectoryPath(_ path: String) -> String {
        let homePath = UserHomeDirectory.path
        guard !homePath.isEmpty else { return path }

        if path == homePath {
            return "~"
        }

        if path.hasPrefix(homePath + "/") {
            return "~/" + path.dropFirst(homePath.count + 1)
        }

        return path
    }
}
