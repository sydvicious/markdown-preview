//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import SwiftUI

@MainActor
final class DocumentSessionStore: ObservableObject {
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

    @Published var openedDocuments: [OpenedDocument]
    @Published var selectedDocumentID: OpenedDocument.ID?
    @Published var knownModificationDates: [String: Date] = [:]
    @Published private(set) var selectionsByDocumentID: [String: [MarkdownSelectionRange]] = [:]
    @Published var missingActiveDocumentAlert: MissingActiveDocumentAlert?

    private(set) var didRestoreDocuments = false

    init(
        previewFiles: [MarkdownFile] = [],
        selectedPreviewFileID: String? = nil,
        disablePersistenceRestore: Bool = false
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
    }

    var sortedDocuments: [OpenedDocument] {
        openedDocuments.sorted(by: Self.sortDocumentsByFileName)
    }

    var currentDocument: OpenedDocument? {
        guard let selectedDocumentID else { return nil }
        return openedDocuments.first(where: { $0.id == selectedDocumentID })
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
        }
        if let selectedDocumentID, idsToDelete.contains(selectedDocumentID) {
            self.selectedDocumentID = isCompactWidth ? nil : sortedDocuments.first?.id
        }
    }

    @discardableResult
    func removeDocument(id: String, forceShowSidebarOnCompact: Bool = false, isCompactWidth: Bool) -> Bool {
        let wasSelected = selectedDocumentID == id
        openedDocuments.removeAll(where: { $0.id == id })
        knownModificationDates.removeValue(forKey: id)
        selectionsByDocumentID.removeValue(forKey: id)

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

    func restorePersistedDocumentsIfNeeded(isCompactWidth: Bool) {
        guard !didRestoreDocuments else { return }
        didRestoreDocuments = true

        let decoder = JSONDecoder()
        guard let data = UserDefaults.standard.data(forKey: persistedDocumentsKey),
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
        if isCompactWidth {
            selectedDocumentID = nil
        } else {
            if let persistedSelection = UserDefaults.standard.string(forKey: persistedSelectionKey),
               restored.contains(where: { $0.id == persistedSelection }) {
                selectedDocumentID = persistedSelection
            } else {
                selectedDocumentID = restored.first?.id
            }
        }
    }

    func persistDocuments() {
        let encoder = JSONEncoder()
        let persisted = openedDocuments.map {
            PersistedDocument(id: $0.id, lastOpened: $0.lastOpened, bookmarkData: $0.bookmarkData)
        }
        guard let data = try? encoder.encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: persistedDocumentsKey)
    }

    func persistSelectedDocument() {
        UserDefaults.standard.set(selectedDocumentID, forKey: persistedSelectionKey)
    }

    func checkActiveDocumentForChanges(isCompactWidth: Bool) {
        guard let selectedDocumentID else { return }
        reloadDocumentIfNeeded(documentID: selectedDocumentID, alertIfMissing: true, isCompactWidth: isCompactWidth)
    }

    func checkAllDocumentsForChanges(isCompactWidth: Bool) {
        guard !openedDocuments.isEmpty else { return }
        let activeID = selectedDocumentID
        let ids = openedDocuments.map(\.id)
        for id in ids where id != activeID {
            reloadDocumentIfNeeded(documentID: id, alertIfMissing: false, isCompactWidth: isCompactWidth)
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

    private func reloadDocumentIfNeeded(documentID: String, alertIfMissing: Bool, isCompactWidth: Bool) {
        guard let index = openedDocuments.firstIndex(where: { $0.id == documentID }) else { return }
        let document = openedDocuments[index]

        guard let loaded = loadFromBookmarkData(document.bookmarkData) else {
            handleMissingDocument(document, alertIfMissing: alertIfMissing, isCompactWidth: isCompactWidth)
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

    private func handleMissingDocument(_ document: OpenedDocument, alertIfMissing: Bool, isCompactWidth: Bool) {
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

    private static func sortDocumentsByFileName(_ lhs: OpenedDocument, _ rhs: OpenedDocument) -> Bool {
        let nameComparison = lhs.file.fileName.localizedStandardCompare(rhs.file.fileName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.file.url.path.localizedStandardCompare(rhs.file.url.path) == .orderedAscending
    }
}
