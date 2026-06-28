//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

struct DocumentSearchIndexEntry {
    let documentID: String
    let fileName: String
    let mapping: MarkdownTextOffsetMapping
}

final class DocumentSearchIndex {
    private var entriesByDocumentID: [String: DocumentSearchIndexEntry] = [:]

    init(documents: [MarkdownFile] = []) {
        rebuild(with: documents)
    }

    func rebuild(with documents: [MarkdownFile]) {
        entriesByDocumentID = Dictionary(
            uniqueKeysWithValues: documents.map { file in
                let documentID = file.url.standardizedFileURL.path
                return (
                    documentID,
                    DocumentSearchIndexEntry(
                        documentID: documentID,
                        fileName: file.fileName,
                        mapping: MarkdownTextOffsetMapping(sourceText: file.contents)
                    )
                )
            }
        )
    }

    func upsert(_ file: MarkdownFile) {
        let documentID = file.url.standardizedFileURL.path
        entriesByDocumentID[documentID] = DocumentSearchIndexEntry(
            documentID: documentID,
            fileName: file.fileName,
            mapping: MarkdownTextOffsetMapping(sourceText: file.contents)
        )
    }

    func remove(documentID: String) {
        entriesByDocumentID.removeValue(forKey: documentID)
    }

    func entry(for documentID: String) -> DocumentSearchIndexEntry? {
        entriesByDocumentID[documentID]
    }

    func containsMatch(in documentID: String, query: String) -> Bool {
        guard let entry = entry(for: documentID) else { return false }
        return MarkdownSearch.containsMatch(in: entry.fileName, query: query) ||
            MarkdownSearch.containsMatch(inDisplayText: entry.mapping.displayText, query: query)
    }

    func suggestedCompletions(prefix: String, limit: Int = 5) -> [String] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrefix.count >= 2 else { return [] }

        let foldedPrefix = trimmedPrefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let separatorSet = CharacterSet.alphanumerics.inverted
        var seen = Set<String>()
        var suggestions: [String] = []

        for entry in entriesByDocumentID.values.sorted(by: { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }) {
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
