//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Combine
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

/// How a bookmark is turned back into the URL of its file.
///
/// The store goes through this so that a test can count how often it asks.
/// Asking is most of what a check for changes on disk costs, and a document
/// that is still where it was found is not asked about.
struct BookmarkResolver {
    var resolve: (Data) -> URL?

    static let system = BookmarkResolver { bookmarkData in
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        // `.withoutImplicitStartAccessing` for the same reason
        // `DirectoryAccessStore` passes it: on iOS resolving a bookmark
        // *starts* the implicit scope it carries, and the system permits only
        // a limited number of open scoped URLs. Without it each resolution
        // leaks a scope until access is refused. Access is taken explicitly in
        // `withSecurityScope`.
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutImplicitStartAccessing]
        #endif
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

/// How a document's file is read.
///
/// The store goes through this so that a test can stand in for a file iCloud
/// has not delivered to this device, which no test can make.
struct DocumentReader {
    /// Reads the file, once, and waits for nothing. A file iCloud has not
    /// delivered is refused with `MarkdownFile.NotDelivered`.
    var read: (URL) throws -> MarkdownFile
    /// Waits for a file that was refused that way, somewhere other than the
    /// main actor, reads it there, and hands what came of it back here.
    var readWhenDelivered: (
        _ url: URL,
        _ deliver: @escaping @MainActor @Sendable (Result<MarkdownFile, Error>) -> Void
    ) -> Void

    static let system = DocumentReader(
        read: { try MarkdownFile.load(from: $0) },
        readWhenDelivered: { url, deliver in
            Task.detached(priority: .userInitiated) {
                let result: Result<MarkdownFile, Error>
                do {
                    result = .success(try await MarkdownFile.loadWhenDelivered(from: url))
                } catch {
                    result = .failure(error)
                }
                await deliver(result)
            }
        }
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
        /// The file's path, which is what the list, the saved session and
        /// everything kept per document go by. It changes when the file is
        /// moved or renamed; see `documentDidMove`.
        var id: String
        var file: MarkdownFile
        var lastOpened: Date
        var bookmarkData: Data
        /// Names this entry for as long as it is in the list, wherever its file
        /// goes. To the reader a document that was moved is the same document,
        /// so the preview keeps their place by this and not by `id`.
        var stableID = UUID()
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
        let onTheirWay: [AwaitedDocument]
    }

    /// What became of a request to open a document.
    enum Opening {
        /// It is in the list and on screen.
        case shown
        /// iCloud has not delivered its file. It will be listed and shown
        /// when the file comes; `lateArrivals` says when, or that it did not.
        case onItsWay
    }

    /// What came of waiting for a document's file.
    enum LateArrival {
        /// The document is in the list now, and on screen if `isShown`.
        case arrived(id: String, isShown: Bool)
        /// The file never came, and the reader who asked to open it is owed
        /// the reason.
        case failedToOpen(URL, Error)
    }

    /// A document that is not in the list yet, because iCloud had not
    /// delivered its file when it was opened or when the saved list was
    /// restored.
    private struct AwaitedDocument {
        let id: String
        let url: URL
        let bookmarkData: Data
        let lastOpened: Date
        /// The reader asked to open it just now. It goes on screen when it
        /// comes, and they are told if it does not. Otherwise it is one the
        /// saved list held, and comes and goes quietly.
        var wasAskedFor: Bool
        /// One from the saved list that was on screen when the list was saved.
        var wasOnScreen = false
        let since = ContinuousClock.now
    }

    /// What reading a document's file came to.
    private enum Reading {
        case read((file: MarkdownFile, modificationDate: Date?))
        /// iCloud has not delivered the file. It is not missing.
        case notDelivered
        case failed
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
    private let bookmarkResolver: BookmarkResolver
    private let documentReader: DocumentReader
    /// The documents whose files are being waited for. None of them is in the
    /// list. They are saved with it, so that a launch which ends before a file
    /// comes is not the end of its document.
    private var awaitedDocuments: [AwaitedDocument] = []
    /// What came of each of them, for whoever shows the reader the result.
    let lateArrivals = PassthroughSubject<LateArrival, Never>()
    /// Where the reader was in each listed document's preview. Kept here, with
    /// the rest of what is kept for each document, so that it outlasts the
    /// view that shows them. The preview knows a document by its `stableID`.
    let previewScrollMemory = PreviewScrollMemory()

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

    /// Where each bookmark's file was last found, as the URL the bookmark
    /// resolved to, which is the one its security scope can be taken on.
    ///
    /// A check for changes on disk used to ask every time where the bookmark's
    /// file was now and whether that was the Trash, which between them were
    /// nearly all it cost: a millisecond or more for each document, and four or
    /// five for the one on screen, every second. Both are questions about a
    /// file that has gone somewhere. A file still at the place kept here has
    /// not, so the check looks there first, and asks only if nothing is there.
    private var knownLocations: [Data: URL] = [:]

    private(set) var didRestoreDocuments = false

    init(
        previewFiles: [MarkdownFile] = [],
        selectedPreviewFileID: String? = nil,
        disablePersistenceRestore: Bool = false,
        userDefaults: UserDefaults = .standard,
        securityScope: SecurityScope = .system,
        bookmarkResolver: BookmarkResolver = .system,
        documentReader: DocumentReader = .system,
        searchIndexBuild: DocumentSearchIndex.BackgroundBuild? = DocumentSearchIndex.detached
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
        self.documentSearchIndex = DocumentSearchIndex(
            documents: opened.map(\.file),
            backgroundBuild: searchIndexBuild
        )
        self.securityScope = securityScope
        self.bookmarkResolver = bookmarkResolver
        self.documentReader = documentReader
    }

    /// Whether there is nothing to show and nothing coming. A list that is
    /// empty only until iCloud delivers a file is not an empty list.
    var hasNoDocumentsHereOrOnTheirWay: Bool {
        openedDocuments.isEmpty && awaitedDocuments.isEmpty
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

    /// The document's text as a search sees it, which the index keeps. A
    /// search in the document on screen is handed this, and does not work out
    /// again what the list's search already has.
    func searchMapping(for documentID: String) -> MarkdownTextOffsetMapping? {
        documentSearchIndex.entry(for: documentID)?.mapping
    }

    /// Whether the document's text has been read for searching yet. It is
    /// read in the background, or by the first search that needs it.
    func hasReadTextForSearching(of documentID: String) -> Bool {
        documentSearchIndex.hasReadText(of: documentID)
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
    ///
    /// A file iCloud has not delivered is not waited for here. It is asked
    /// for, and the document is listed and shown when it comes.
    @discardableResult
    func openDocument(at url: URL, bookmarkData suppliedBookmarkData: Data? = nil) throws -> Opening {
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

        guard let resolvedURL = resolveBookmarkURL(from: bookmarkData) else {
            throw CocoaError(.fileNoSuchFile)
        }
        // Whatever stopped the read goes up as it is. A file that is there and
        // is not text the app reads is not a missing file, and saying it is
        // sends the reader looking for one.
        let loaded: (file: MarkdownFile, modificationDate: Date?)
        do {
            loaded = try readDocument(at: resolvedURL, resolvedFrom: bookmarkData)
        } catch is MarkdownFile.NotDelivered {
            return openWhenDelivered(resolvedURL, bookmarkData: bookmarkData)
        }
        upsertDocument(loaded.file, bookmarkData: bookmarkData, modificationDate: loaded.modificationDate)
        knownLocations[bookmarkData] = resolvedURL
        return .shown
    }

    /// Opens a document whose file iCloud has not delivered: now, as it was,
    /// if it is in the list already, and otherwise when the file comes.
    private func openWhenDelivered(_ url: URL, bookmarkData: Data) -> Opening {
        let id = url.standardizedFileURL.path
        if let index = openedDocuments.firstIndex(where: { $0.id == id }) {
            // iCloud took back the contents of a file that is open here. The
            // reader has its text. Any newer is found by the check for changes
            // on disk, once it can be read.
            Self.log.info("[read] open: \(url.lastPathComponent, privacy: .public) is listed; shown as it was")
            openedDocuments[index].lastOpened = Date()
            selectedDocumentID = id
            return .shown
        }
        if let index = awaitedDocuments.firstIndex(where: { $0.id == id }) {
            awaitedDocuments[index].wasAskedFor = true
            return .onItsWay
        }
        wait(for: AwaitedDocument(
            id: id,
            url: url,
            bookmarkData: bookmarkData,
            lastOpened: Date(),
            wasAskedFor: true
        ))
        return .onItsWay
    }

    /// Has the file read when iCloud delivers it, somewhere other than the
    /// main actor, holding the scope its bookmark carries until then.
    private func wait(for awaited: AwaitedDocument) {
        awaitedDocuments.append(awaited)
        let holdsScope = startSecurityScope(of: awaited.url, resolvedFrom: awaited.bookmarkData)
        Self.log.info("""
            [read] \(awaited.wasAskedFor ? "open" : "restore", privacy: .public): \
            \(awaited.url.lastPathComponent, privacy: .public) is not delivered; waiting for it in the \
            background, holdsScope=\(holdsScope)
            """)
        let (id, url) = (awaited.id, awaited.url)
        documentReader.readWhenDelivered(url) { [weak self] result in
            self?.stopWaiting(forDocument: id, at: url, holdingScope: holdsScope, with: result)
        }
    }

    private func stopWaiting(
        forDocument id: String,
        at url: URL,
        holdingScope holdsScope: Bool,
        with result: Result<MarkdownFile, Error>
    ) {
        defer {
            if holdsScope {
                securityScope.stop(url)
            }
        }
        // It may have been opened again in the meantime, and found there.
        guard let index = awaitedDocuments.firstIndex(where: { $0.id == id }) else {
            Self.log.info("[read] \(url.lastPathComponent, privacy: .public) is no longer waited for; nothing done")
            return
        }
        let awaited = awaitedDocuments.remove(at: index)
        let waited = ContinuousClock.now - awaited.since
        let isListed = openedDocuments.contains(where: { $0.id == id })

        switch result {
        case .success(let file):
            let modificationDate = modificationDateWithinAccess(for: url)
            knownLocations[awaited.bookmarkData] = url
            var isShown = false
            if awaited.wasAskedFor {
                upsertDocument(file, bookmarkData: awaited.bookmarkData, modificationDate: modificationDate)
                isShown = true
            } else if !isListed {
                openedDocuments.append(.init(
                    id: id,
                    file: file,
                    lastOpened: awaited.lastOpened,
                    bookmarkData: awaited.bookmarkData
                ))
                if let modificationDate {
                    knownModificationDates[id] = modificationDate
                }
                documentSearchIndex.upsert(file)
                // Back on screen if that is where it was, unless the reader
                // has put something else there since.
                if awaited.wasOnScreen, selectedDocumentID == nil {
                    selectedDocumentID = id
                    isShown = true
                }
            }
            Self.log.info("""
                [read] \(awaited.wasAskedFor ? "open" : "restore", privacy: .public): \
                \(url.lastPathComponent, privacy: .public) arrived after \(waited, privacy: .public); \
                listed, isShown=\(isShown)
                """)
            lateArrivals.send(.arrived(id: id, isShown: isShown))
        case .failure(let error):
            let nsError = error as NSError
            Self.log.info("""
                [read] \(awaited.wasAskedFor ? "open" : "restore", privacy: .public): \
                \(url.lastPathComponent, privacy: .public) did not arrive after \(waited, privacy: .public): \
                \(nsError.domain, privacy: .public) \(nsError.code)
                """)
            if !isListed {
                textSizesByDocumentID.removeValue(forKey: id)
            }
            if awaited.wasAskedFor {
                lateArrivals.send(.failedToOpen(url, error))
            }
        }
    }

    func upsertDocument(_ file: MarkdownFile, bookmarkData: Data, modificationDate: Date?) {
        let id = file.url.standardizedFileURL.path
        awaitedDocuments.removeAll(where: { $0.id == id })
        if !openedDocuments.contains(where: { $0.id == id }) {
            // Not in the list under this path, but it may be there under the
            // one it was moved from: the entry is only brought up to date when
            // it is next looked at, which for a document that is not on screen
            // can be ten seconds away. Adding it now would list it twice.
            //
            // A document that is still where it was last found has not been
            // moved here, and its bookmark is not asked where it leads. Asking
            // every listed document's, for every document opened, was a
            // couple of milliseconds for each one in the list.
            for document in openedDocuments
            where !isStillWhereItWasFound(document) && resolvedID(of: document) == id {
                documentDidMove(from: document.id, to: file, modificationDate: modificationDate)
            }
        }
        if let index = openedDocuments.firstIndex(where: { $0.id == id }) {
            if openedDocuments[index].bookmarkData != bookmarkData {
                bookmarksWithRefusedScope.remove(openedDocuments[index].bookmarkData)
                knownLocations.removeValue(forKey: openedDocuments[index].bookmarkData)
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
            knownLocations.removeValue(forKey: document.bookmarkData)
            previewScrollMemory.forget(documentID: document.stableID.uuidString)
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
            knownLocations.removeValue(forKey: document.bookmarkData)
            previewScrollMemory.forget(documentID: document.stableID.uuidString)
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

        var onTheirWay = migration.onTheirWay
        openedDocuments = migration.documents
        knownModificationDates = migration.modificationDates
        // A document that is still coming keeps its text size until it does.
        textSizesByDocumentID = Self.restoreTextSizes(
            from: userDefaults,
            validDocumentIDs: Set(migration.documents.map(\.id)).union(onTheirWay.map(\.id)),
            idMap: migration.idMap
        )
        documentSearchIndex.rebuild(with: migration.documents.map(\.file))
        if let persistedSelection = userDefaults.string(forKey: persistedSelectionKey) {
            let resolvedSelection = migration.idMap[persistedSelection] ?? persistedSelection
            if migration.documents.contains(where: { $0.id == resolvedSelection }) {
                selectedDocumentID = resolvedSelection
            } else {
                selectedDocumentID = nil
                if let index = onTheirWay.firstIndex(where: { $0.id == resolvedSelection }) {
                    onTheirWay[index].wasOnScreen = true
                }
            }
        } else {
            selectedDocumentID = nil
        }
        for awaited in onTheirWay {
            wait(for: awaited)
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
        let listed = openedDocuments.map {
            PersistedDocument(id: $0.id, lastOpened: $0.lastOpened, bookmarkData: $0.bookmarkData)
        }
        let onTheirWay = awaitedDocuments.map {
            PersistedDocument(id: $0.id, lastOpened: $0.lastOpened, bookmarkData: $0.bookmarkData)
        }
        let persisted = listed + onTheirWay
        guard let data = try? encoder.encode(persisted) else { return }
        userDefaults.set(data, forKey: persistedDocumentsKey)
    }

    func persistDocuments() {
        persistDocuments(to: .standard)
    }

    func persistSelectedDocument(to userDefaults: UserDefaults) {
        // With nothing on screen because what was there is still coming, that
        // is still what was there.
        let onItsWay = awaitedDocuments.first(where: \.wasOnScreen)?.id
        userDefaults.set(selectedDocumentID ?? onItsWay, forKey: persistedSelectionKey)
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

        if lookWhereTheFileWas(for: document, at: index) {
            return
        }

        guard let url = resolveBookmarkURL(from: document.bookmarkData) else {
            Self.log.info("[track] Bookmark for \(document.id, privacy: .public) did not resolve")
            handleMissingDocument(
                document,
                alertIfMissing: alertIfMissing,
                isCompactWidth: isCompactWidth
            )
            return
        }

        // One security scope for both questions. This runs for every listed
        // document on every tick, and the scope is not taken twice over.
        let (inTrash, currentModificationDate) = withSecurityScope(of: url, resolvedFrom: document.bookmarkData) {
            (isInTrashWithinAccess(url), modificationDateWithinAccess(for: url))
        }

        guard !inTrash else {
            Self.log.info("[track] \(document.id, privacy: .public) is in the Trash")
            handleMissingDocument(
                document,
                alertIfMissing: alertIfMissing,
                isCompactWidth: isCompactWidth
            )
            return
        }

        guard url.standardizedFileURL.path == document.id else {
            // The bookmark followed the file somewhere else. It only counts as
            // a move if the file can be read there; a bookmark can also resolve
            // to a path with nothing at it.
            Self.log.info("""
                [track] Bookmark for \(document.id, privacy: .public) resolves to \
                \(url.standardizedFileURL.path, privacy: .public)
                """)
            let loaded: (file: MarkdownFile, modificationDate: Date?)
            switch reading(at: url, resolvedFrom: document.bookmarkData) {
            case .read(let read):
                loaded = read
            case .notDelivered:
                // Not missing: followed there when it can be read there.
                Self.log.info("[read] check: \(url.lastPathComponent, privacy: .public) is not delivered where it went; left as it is")
                return
            case .failed:
                Self.log.info("[track] Could not read it at \(url.standardizedFileURL.path, privacy: .public)")
                handleMissingDocument(
                    document,
                    alertIfMissing: alertIfMissing,
                    isCompactWidth: isCompactWidth
                )
                return
            }
            // The bookmark in hand was made at the old path, and a bookmark is
            // looked up by path before it is looked up by file. Kept, it would
            // lose the document to the next atomic save, which leaves a new file
            // at the new path and nothing at the old one, and would hand the
            // entry to any new file put where this one used to be. If a new one
            // cannot be made the old one stays, and reads as it did.
            let bookmarkData = withSecurityScope(of: url, resolvedFrom: document.bookmarkData) {
                try? makeBookmarkData(for: url)
            }
            Self.log.info("[track] Following it there; newBookmark=\(bookmarkData != nil)")
            knownLocations.removeValue(forKey: document.bookmarkData)
            knownLocations[bookmarkData ?? document.bookmarkData] = url
            documentDidMove(
                from: document.id,
                to: loaded.file,
                modificationDate: loaded.modificationDate,
                bookmarkData: bookmarkData
            )
            return
        }

        // Found where it is listed. That is where it is looked for from now on.
        knownLocations[document.bookmarkData] = url

        if let modificationDate = currentModificationDate {
            let knownDate = knownModificationDates[document.id]
            if knownDate != nil, modificationDate <= knownDate! {
                return
            }
        }

        switch reading(at: url, resolvedFrom: document.bookmarkData) {
        case .read(let loaded):
            take(loaded, for: document, at: index)
        case .notDelivered:
            Self.log.info("[read] check: \(url.lastPathComponent, privacy: .public) is not delivered; left as it is")
        case .failed:
            Self.log.info("[track] Could not read \(document.id, privacy: .public), where its bookmark still says it is")
            handleMissingDocument(
                document,
                alertIfMissing: alertIfMissing,
                isCompactWidth: isCompactWidth
            )
        }
    }

    /// Whether a document's file is at the place it was last found. False is
    /// also the answer when it has not been found anywhere yet, or cannot be
    /// seen there, so false is not that it has gone: it is that its bookmark
    /// has to be asked.
    private func isStillWhereItWasFound(_ document: OpenedDocument) -> Bool {
        guard let location = knownLocations[document.bookmarkData],
              location.standardizedFileURL.path == document.id else {
            return false
        }
        let modificationDate = withSecurityScope(of: location, resolvedFrom: document.bookmarkData) {
            modificationDateWithinAccess(for: location)
        }
        return modificationDate != nil
    }

    /// Looks at a document's file where it was last found, and says whether
    /// that settled the check: the file is there, and either has not changed
    /// or has been read again.
    ///
    /// False is not that the file has gone. It is that looking there did not
    /// say: nothing has been found there yet, nothing is there now, or what is
    /// there cannot be read. A file there that iCloud has not delivered does
    /// settle it: the document is where it was, and stays as it is. The check then asks where the bookmark's file is,
    /// which finds one that was moved, put in the Trash or deleted.
    private func lookWhereTheFileWas(for document: OpenedDocument, at index: Int) -> Bool {
        guard let location = knownLocations[document.bookmarkData],
              location.standardizedFileURL.path == document.id else {
            return false
        }

        let modificationDate = withSecurityScope(of: location, resolvedFrom: document.bookmarkData) {
            modificationDateWithinAccess(for: location)
        }
        guard let modificationDate else { return false }

        if let knownDate = knownModificationDates[document.id], modificationDate <= knownDate {
            return true
        }
        switch reading(at: location, resolvedFrom: document.bookmarkData) {
        case .read(let loaded):
            take(loaded, for: document, at: index)
            return true
        case .notDelivered:
            // The file is there and newer, and its text has not come. The
            // reader keeps the text they have, and the next check asks again.
            Self.log.info("[read] check: \(location.lastPathComponent, privacy: .public) is not delivered; left as it is")
            return true
        case .failed:
            return false
        }
    }

    /// Takes what was just read of a document's file: its date, and its text
    /// if that has changed.
    private func take(
        _ loaded: (file: MarkdownFile, modificationDate: Date?),
        for document: OpenedDocument,
        at index: Int
    ) {
        if let modificationDate = loaded.modificationDate {
            knownModificationDates[document.id] = modificationDate
        }

        guard loaded.file.contents != document.file.contents else { return }
        openedDocuments[index].file = loaded.file
        documentSearchIndex.upsert(loaded.file)
        clampSelections(for: document.id, text: loaded.file.contents)
    }

    /// Brings the entry listed as `oldID` up to date with where its file is now.
    ///
    /// A bookmark follows its file, so a document that is moved or renamed
    /// while it is in the list stays readable — under a path that is no longer
    /// its own. Left like that, opening the file from its new place adds it to
    /// the list a second time, and both entries are saved. So the entry moves
    /// with the file, and takes with it everything kept under its path: the
    /// selection, the text size, its place in the search index.
    ///
    /// If the file is already listed where it is now, that entry stays and this
    /// one goes, handing over whatever the other has no value of its own for.
    private func documentDidMove(
        from oldID: String,
        to file: MarkdownFile,
        modificationDate: Date?,
        bookmarkData: Data? = nil
    ) {
        let newID = file.url.standardizedFileURL.path
        guard newID != oldID,
              let index = openedDocuments.firstIndex(where: { $0.id == oldID }) else {
            return
        }

        documentSearchIndex.remove(documentID: oldID)
        if let existingIndex = openedDocuments.firstIndex(where: { $0.id == newID }) {
            openedDocuments[existingIndex].file = file
            bookmarksWithRefusedScope.remove(openedDocuments[index].bookmarkData)
            previewScrollMemory.forget(documentID: openedDocuments[index].stableID.uuidString)
            openedDocuments.remove(at: index)
        } else {
            openedDocuments[index].id = newID
            openedDocuments[index].file = file
            if let bookmarkData, bookmarkData != openedDocuments[index].bookmarkData {
                bookmarksWithRefusedScope.remove(openedDocuments[index].bookmarkData)
                openedDocuments[index].bookmarkData = bookmarkData
            }
        }
        documentSearchIndex.upsert(file)

        Self.moveValue(in: &knownModificationDates, from: oldID, to: newID)
        Self.moveValue(in: &selectionsByDocumentID, from: oldID, to: newID)
        Self.moveValue(in: &textSizesByDocumentID, from: oldID, to: newID)
        if let modificationDate {
            knownModificationDates[newID] = modificationDate
        }
        clampSelections(for: newID, text: file.contents)

        if selectedDocumentID == oldID {
            selectedDocumentID = newID
        }
        if missingActiveDocumentAlert?.id == oldID {
            missingActiveDocumentAlert = nil
        }
    }

    /// Moves what is kept for `oldID` to `newID`, unless `newID` already has a
    /// value, in which case the old one is dropped.
    private static func moveValue<Value>(in values: inout [String: Value], from oldID: String, to newID: String) {
        guard let value = values.removeValue(forKey: oldID), values[newID] == nil else { return }
        values[newID] = value
    }

    /// The path `document` would be listed under if it were opened now, or nil
    /// if its bookmark no longer leads anywhere.
    private func resolvedID(of document: OpenedDocument) -> String? {
        guard !document.bookmarkData.isEmpty else { return nil }
        return resolveBookmarkURL(from: document.bookmarkData)?.standardizedFileURL.path
    }

    /// Whether the system says `url` is in the Trash, for callers that hold its
    /// security scope.
    ///
    /// A bookmark follows its file there as it does anywhere else, and the
    /// file can still be read. To the reader it is gone, so it is handled as a
    /// missing file is. If the system cannot say, the file is taken not to be
    /// in the Trash.
    private func isInTrashWithinAccess(_ url: URL) -> Bool {
        var relationship: FileManager.URLRelationship = .other
        do {
            try FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: [], toItemAt: url)
        } catch {
            return false
        }
        return relationship == .contains
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

    private func resolveBookmarkURL(from bookmarkData: Data) -> URL? {
        bookmarkResolver.resolve(bookmarkData)
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
        perform body: () throws -> T
    ) rethrows -> T {
        let holdsScope = startSecurityScope(of: url, resolvedFrom: bookmarkData)
        defer {
            if holdsScope {
                securityScope.stop(url)
            }
        }
        return try body()
    }

    /// Takes the security scope of `url`, and says whether it was given. If it
    /// was, it is the caller's to release.
    private func startSecurityScope(of url: URL, resolvedFrom bookmarkData: Data) -> Bool {
        guard !bookmarksWithRefusedScope.contains(bookmarkData) else { return false }
        guard securityScope.start(url) else {
            bookmarksWithRefusedScope.insert(bookmarkData)
            logRefusedScope(for: url)
            return false
        }
        return true
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

    /// Reads the document, and tells a file iCloud has not delivered from one
    /// that cannot be read.
    private func reading(at url: URL, resolvedFrom bookmarkData: Data) -> Reading {
        do {
            return .read(try readDocument(at: url, resolvedFrom: bookmarkData))
        } catch is MarkdownFile.NotDelivered {
            return .notDelivered
        } catch {
            return .failed
        }
    }

    /// Reads the document, passing up whatever stopped it being read.
    private func readDocument(
        at url: URL,
        resolvedFrom bookmarkData: Data
    ) throws -> (file: MarkdownFile, modificationDate: Date?) {
        try withSecurityScope(of: url, resolvedFrom: bookmarkData) {
            let file = try documentReader.read(url)
            let modificationDate = modificationDateWithinAccess(for: url)
            return (file, modificationDate)
        }
    }

    /// The document's modification date, for callers that hold the URL's
    /// security scope.
    ///
    /// Reading a resource value is itself privileged. Sandboxed, and without
    /// the scope, the read returns nil — which does not fail loudly: in
    /// `reloadDocumentIfNeeded` it defeats the "unchanged, so skip" check and
    /// silently re-reads every open document on every tick.
    ///
    /// The URL may be one that has been kept and asked before, and a URL holds
    /// on to what it was last told. What it holds is thrown away first, so that
    /// the date is the file's as it is now.
    private func modificationDateWithinAccess(for url: URL) -> Date? {
        var asked = url
        asked.removeAllCachedResourceValues()
        let values = try? asked.resourceValues(forKeys: [.contentModificationDateKey])
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
        var onTheirWay: [AwaitedDocument] = []

        for entry in persisted {
            guard let url = resolveBookmarkURL(from: entry.bookmarkData) else { continue }
            let loaded: (file: MarkdownFile, modificationDate: Date?)
            switch reading(at: url, resolvedFrom: entry.bookmarkData) {
            case .read(let read):
                loaded = read
                knownLocations[entry.bookmarkData] = url
            case .notDelivered:
                // Not waited for here, where the launch would wait with it.
                // It joins the list when its file comes.
                let inTrash = withSecurityScope(of: url, resolvedFrom: entry.bookmarkData) {
                    isInTrashWithinAccess(url)
                }
                guard !inTrash else { continue }
                let resolvedID = url.standardizedFileURL.path
                idMap[entry.id] = resolvedID
                guard !restored.contains(where: { $0.id == resolvedID }),
                      !onTheirWay.contains(where: { $0.id == resolvedID }) else { continue }
                onTheirWay.append(AwaitedDocument(
                    id: resolvedID,
                    url: url,
                    bookmarkData: entry.bookmarkData,
                    lastOpened: entry.lastOpened,
                    wasAskedFor: false
                ))
                continue
            case .failed:
                continue
            }
            let inTrash = withSecurityScope(of: loaded.file.url, resolvedFrom: entry.bookmarkData) {
                isInTrashWithinAccess(loaded.file.url)
            }
            guard !inTrash else { continue }
            let resolvedID = loaded.file.url.standardizedFileURL.path
            idMap[entry.id] = resolvedID
            // Two entries can resolve to one file. A list saved before entries
            // followed their files (`documentDidMove`) holds a document that was
            // opened, moved, and opened again from its new place under both
            // paths, and the first entry's bookmark follows the file. `persisted`
            // arrives newest first, so the one kept is the one opened last; the
            // other's ID still maps to it, for the selection and text size saved
            // under that ID.
            guard !restored.contains(where: { $0.id == resolvedID }) else { continue }
            // Here after all, under an entry that came later in the list.
            onTheirWay.removeAll(where: { $0.id == resolvedID })
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
            idMap: idMap,
            onTheirWay: onTheirWay
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
