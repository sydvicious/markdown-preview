//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

struct DocumentSearchIndexEntry {
    let documentID: String
    let fileName: String
    let mapping: MarkdownTextOffsetMapping
}

/// What the list's search looks through: each listed document's name, and its
/// text as a search sees it.
///
/// Reading a document's text that way is as much work as showing it, and only
/// a search wants it. So adding a document does not read it. It is read in the
/// background if there is one, and by the first search that gets there before
/// that has finished.
///
/// Used from the main actor: `DocumentSessionStore` owns it, and what is read
/// in the background is handed back there.
final class DocumentSearchIndex {
    /// Reads a document's text somewhere other than the main actor, and hands
    /// what it read back there.
    typealias BackgroundBuild = (
        _ contents: String,
        _ deliver: @escaping @MainActor @Sendable (MarkdownTextOffsetMapping) -> Void
    ) -> Void

    /// Reads the text on a thread of its own.
    static let detached: BackgroundBuild = { contents, deliver in
        Task.detached(priority: .utility) {
            await deliver(MarkdownTextOffsetMapping(sourceText: contents))
        }
    }

    /// A listed document, and its text as a search sees it once that has been
    /// read.
    private struct Listing {
        var fileName: String
        let contents: String
        var mapping: MarkdownTextOffsetMapping?
    }

    private var listingsByDocumentID: [String: Listing] = [:]
    private let backgroundBuild: BackgroundBuild?

    /// - Parameter backgroundBuild: where to read text ahead of a search. With
    ///   none, each document's text is read when a search first needs it.
    init(documents: [MarkdownFile] = [], backgroundBuild: BackgroundBuild? = nil) {
        self.backgroundBuild = backgroundBuild
        rebuild(with: documents)
    }

    func rebuild(with documents: [MarkdownFile]) {
        // A list that names one file twice is indexed once, keeping the first.
        // `Dictionary(uniqueKeysWithValues:)` traps on a repeated key, and this
        // runs while the saved session is restored, so a repeat there was a
        // crash at every launch.
        listingsByDocumentID = Dictionary(
            documents.map { file in
                (file.listedPath, Listing(fileName: file.fileName, contents: file.contents))
            },
            uniquingKeysWith: { first, _ in first }
        )
        for (documentID, listing) in listingsByDocumentID {
            readInBackground(documentID, contents: listing.contents)
        }
    }

    func upsert(_ file: MarkdownFile) {
        let documentID = file.listedPath
        // The same text as before is already read, or is being read.
        if listingsByDocumentID[documentID]?.contents == file.contents {
            listingsByDocumentID[documentID]?.fileName = file.fileName
            return
        }
        listingsByDocumentID[documentID] = Listing(fileName: file.fileName, contents: file.contents)
        readInBackground(documentID, contents: file.contents)
    }

    func remove(documentID: String) {
        listingsByDocumentID.removeValue(forKey: documentID)
    }

    /// Whether the document's text has been read for searching yet.
    func hasReadText(of documentID: String) -> Bool {
        listingsByDocumentID[documentID]?.mapping != nil
    }

    /// The document as the index holds it. Its text is read now if it has not
    /// been.
    func entry(for documentID: String) -> DocumentSearchIndexEntry? {
        guard let listing = listingsByDocumentID[documentID],
              let mapping = mapping(for: documentID) else {
            return nil
        }
        return DocumentSearchIndexEntry(documentID: documentID, fileName: listing.fileName, mapping: mapping)
    }

    private func readInBackground(_ documentID: String, contents: String) {
        backgroundBuild?(contents) { [weak self] mapping in
            self?.keep(mapping, for: documentID, readFrom: contents)
        }
    }

    /// Takes what the background read, unless it is no longer wanted: the
    /// document has gone, its text has changed since, or a search has read it
    /// in the meantime.
    private func keep(_ mapping: MarkdownTextOffsetMapping, for documentID: String, readFrom contents: String) {
        guard let listing = listingsByDocumentID[documentID],
              listing.mapping == nil,
              listing.contents == contents else {
            return
        }
        listingsByDocumentID[documentID]?.mapping = mapping
    }

    /// The document's text as a search sees it, read now if nothing has read
    /// it yet.
    private func mapping(for documentID: String) -> MarkdownTextOffsetMapping? {
        guard let listing = listingsByDocumentID[documentID] else { return nil }
        if let mapping = listing.mapping {
            return mapping
        }

        let read = MarkdownTextOffsetMapping(sourceText: listing.contents)
        listingsByDocumentID[documentID]?.mapping = read
        return read
    }

    func containsMatch(in documentID: String, query: String) -> Bool {
        guard let listing = listingsByDocumentID[documentID] else { return false }
        // The name first: a search it answers has no need of the text.
        if MarkdownSearch.containsMatch(in: listing.fileName, query: query) {
            return true
        }
        guard let mapping = mapping(for: documentID) else { return false }
        return MarkdownSearch.containsMatch(inDisplayText: mapping.displayText, query: query)
    }

    func suggestedCompletions(prefix: String, limit: Int = 5) -> [String] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrefix.count >= 2 else { return [] }

        let foldedPrefix = trimmedPrefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let separatorSet = CharacterSet.alphanumerics.inverted
        var seen = Set<String>()
        var suggestions: [String] = []

        let documentIDsByName = listingsByDocumentID
            .sorted { $0.value.fileName.localizedCaseInsensitiveCompare($1.value.fileName) == .orderedAscending }
            .map(\.key)
        for documentID in documentIDsByName {
            guard let entry = entry(for: documentID) else { continue }
            for candidate in entry.fileName.components(separatedBy: separatorSet) +
                entry.mapping.displayText.components(separatedBy: separatorSet) {
                guard candidate.count > trimmedPrefix.count else { continue }
                let foldedCandidate = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                guard foldedCandidate.hasPrefix(foldedPrefix) else { continue }
                guard seen.insert(foldedCandidate).inserted else { continue }
                suggestions.append(candidate)
                if suggestions.count == limit {
                    return suggestions
                }
            }
        }

        return suggestions
    }

    func suggestedCompletions(in documentID: String, prefix: String, limit: Int = 5) -> [String] {
        guard let entry = entry(for: documentID) else { return [] }
        return MarkdownSearch.suggestedCompletions(inDisplayText: entry.mapping.displayText, prefix: prefix, limit: limit)
    }
}
