//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import SwiftUI
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

    private let persistedDocumentsKey = "openedMarkdownDocuments"
    private let persistedSelectionKey = "selectedMarkdownDocumentID"
    private static let persistedTextSizesKey = "markdownDocumentTextSizes"

    @Published var openedDocuments: [OpenedDocument]
    @Published var selectedDocumentID: OpenedDocument.ID?
    @Published var knownModificationDates: [String: Date] = [:]
    @Published private(set) var selectionsByDocumentID: [String: [MarkdownSelectionRange]] = [:]
    @Published private(set) var textSizesByDocumentID: [String: DynamicTypeSize] = [:]
    @Published var missingActiveDocumentAlert: MissingActiveDocumentAlert?

    private(set) var didRestoreDocuments = false

    init(
        previewFiles: [MarkdownFile] = [],
        selectedPreviewFileID: String? = nil,
        disablePersistenceRestore: Bool = false,
        userDefaults: UserDefaults = .standard
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

    func openDocument(at url: URL) throws {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmarkData = try makeBookmarkData(for: url)
        guard let loaded = loadFromBookmarkData(bookmarkData) else {
            throw CocoaError(.fileNoSuchFile)
        }
        upsertDocument(loaded.file, bookmarkData: bookmarkData, modificationDate: loaded.modificationDate)
    }

    func upsertDocument(_ file: MarkdownFile, bookmarkData: Data, modificationDate: Date?) {
        let id = file.url.standardizedFileURL.path
        if let index = openedDocuments.firstIndex(where: { $0.id == id }) {
            openedDocuments[index].file = file
            openedDocuments[index].lastOpened = Date()
            openedDocuments[index].bookmarkData = bookmarkData
        } else {
            openedDocuments.append(.init(id: id, file: file, lastOpened: Date(), bookmarkData: bookmarkData))
        }
        if let modificationDate {
            knownModificationDates[id] = modificationDate
        }
        selectedDocumentID = id
    }

    func deleteDocuments(at offsets: IndexSet, isCompactWidth: Bool) {
        let idsToDelete = offsets.map { sortedDocuments[$0].id }
        openedDocuments.removeAll(where: { idsToDelete.contains($0.id) })
        idsToDelete.forEach {
            knownModificationDates.removeValue(forKey: $0)
            selectionsByDocumentID.removeValue(forKey: $0)
            textSizesByDocumentID.removeValue(forKey: $0)
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
        openedDocuments.removeAll(where: { $0.id == id })
        knownModificationDates.removeValue(forKey: id)
        selectionsByDocumentID.removeValue(forKey: id)
        textSizesByDocumentID.removeValue(forKey: id)

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

        var restored: [OpenedDocument] = []
        var restoredModificationDates: [String: Date] = [:]
        for entry in persisted.sorted(by: { $0.lastOpened > $1.lastOpened }) {
            guard let loaded = loadFromBookmarkData(entry.bookmarkData) else { continue }
            restored.append(
                .init(
                    id: entry.id,
                    file: loaded.file,
                    lastOpened: entry.lastOpened,
                    bookmarkData: entry.bookmarkData
                )
            )
            if let modificationDate = loaded.modificationDate {
                restoredModificationDates[entry.id] = modificationDate
            }
        }

        openedDocuments = restored
        knownModificationDates = restoredModificationDates
        textSizesByDocumentID = Self.restoreTextSizes(
            from: userDefaults,
            validDocumentIDs: Set(restored.map(\.id))
        )
        if let persistedSelection = userDefaults.string(forKey: persistedSelectionKey),
           restored.contains(where: { $0.id == persistedSelection }) {
            selectedDocumentID = persistedSelection
        } else {
            selectedDocumentID = nil
        }
    }

    func restorePersistedDocumentsIfNeeded(isCompactWidth: Bool) {
        restorePersistedDocumentsIfNeeded(isCompactWidth: isCompactWidth, userDefaults: .standard)
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

        guard let loaded = loadFromBookmarkData(document.bookmarkData) else {
            handleMissingDocument(
                document,
                alertIfMissing: alertIfMissing,
                isCompactWidth: isCompactWidth
            )
            return
        }

        if let modificationDate = loaded.modificationDate {
            let knownDate = knownModificationDates[document.id]
            if knownDate != nil, modificationDate <= knownDate! {
                return
            }
            knownModificationDates[document.id] = modificationDate
        }

        guard loaded.file.contents != document.file.contents else { return }
        openedDocuments[index].file = loaded.file
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
        do {
            return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        #else
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private func loadFromBookmarkData(_ bookmarkData: Data) -> (file: MarkdownFile, modificationDate: Date?)? {
        var isStale = false
        do {
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
            #else
            let options: URL.BookmarkResolutionOptions = [.withoutUI]
            #endif
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let file = try MarkdownFile.load(from: url)
            let modificationDate = currentModificationDate(for: url)
            return (file, modificationDate)
        } catch {
            return nil
        }
    }

    private func currentModificationDate(for url: URL) -> Date? {
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

    private static func restoreTextSizes(
        from userDefaults: UserDefaults,
        validDocumentIDs: Set<String>
    ) -> [String: DynamicTypeSize] {
        guard let persisted = userDefaults.dictionary(forKey: Self.persistedTextSizesKey) as? [String: String] else {
            return [:]
        }

        return persisted.reduce(into: [String: DynamicTypeSize]()) { partialResult, entry in
            guard validDocumentIDs.contains(entry.key) else {
                return
            }
            guard let textSize = DynamicTypeSize(persistedValue: entry.value),
                  textSize != .defaultValue else {
                return
            }
            partialResult[entry.key] = textSize
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
        let homePath = NSHomeDirectory()
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
