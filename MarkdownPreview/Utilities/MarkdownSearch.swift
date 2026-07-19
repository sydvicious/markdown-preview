//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import MarkdownCore

enum MarkdownSearchDirection {
    case forward
    case backward
}

struct MarkdownSearchSession: Equatable {
    private(set) var query = ""
    private(set) var matches: [MarkdownSelectionRange] = []
    private(set) var currentMatchIndex: Int?
    private(set) var pendingWrapDirection: MarkdownSearchDirection?

    var resultCount: Int {
        matches.count
    }

    var currentMatch: MarkdownSelectionRange? {
        guard let currentMatchIndex, matches.indices.contains(currentMatchIndex) else { return nil }
        return matches[currentMatchIndex]
    }

    var resultPositionText: String? {
        guard let currentMatchIndex else { return nil }
        return "\(currentMatchIndex + 1) of \(matches.count)"
    }

    mutating func updateQuery(_ query: String, in text: String) {
        self.query = query
        matches = MarkdownSearch.matches(in: text, query: query)
        currentMatchIndex = matches.isEmpty ? nil : 0
        pendingWrapDirection = nil
    }

    mutating func refresh(in text: String) {
        let refreshedMatches = MarkdownSearch.matches(in: text, query: query)
        matches = refreshedMatches
        if refreshedMatches.isEmpty {
            currentMatchIndex = nil
        } else if let currentMatchIndex {
            self.currentMatchIndex = min(currentMatchIndex, refreshedMatches.index(before: refreshedMatches.endIndex))
        } else {
            currentMatchIndex = 0
        }
        pendingWrapDirection = nil
    }

    @discardableResult
    mutating func move(_ direction: MarkdownSearchDirection) -> Bool {
        guard !matches.isEmpty else {
            currentMatchIndex = nil
            pendingWrapDirection = nil
            return false
        }

        guard let currentMatchIndex else {
            self.currentMatchIndex = direction == .backward ? matches.index(before: matches.endIndex) : 0
            pendingWrapDirection = nil
            return true
        }

        switch direction {
        case .forward:
            let lastIndex = matches.index(before: matches.endIndex)
            if currentMatchIndex < lastIndex {
                self.currentMatchIndex = currentMatchIndex + 1
                pendingWrapDirection = nil
                return true
            }
        case .backward:
            if currentMatchIndex > matches.startIndex {
                self.currentMatchIndex = currentMatchIndex - 1
                pendingWrapDirection = nil
                return true
            }
        }

        if pendingWrapDirection == direction {
            self.currentMatchIndex = direction == .forward ? matches.startIndex : matches.index(before: matches.endIndex)
            pendingWrapDirection = nil
            return true
        }

        pendingWrapDirection = direction
        return false
    }
}

enum MarkdownSearch {
    static func matches(in text: String, query: String) -> [MarkdownSelectionRange] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let mapping = MarkdownTextOffsetMapping(sourceText: text)
        let nsText = mapping.displayText as NSString
        let searchOptions: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        var searchRange = NSRange(location: 0, length: nsText.length)
        var matches: [MarkdownSelectionRange] = []

        while searchRange.length > 0 {
            let foundRange = nsText.range(of: trimmedQuery, options: searchOptions, range: searchRange)
            guard foundRange.location != NSNotFound, foundRange.length > 0 else { break }

            if let sourceRange = mapping.sourceRange(forDisplayRange: MarkdownSelectionRange(foundRange)) {
                matches.append(sourceRange)
            }

            let nextLocation = foundRange.location + foundRange.length
            guard nextLocation < nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return matches
    }

    static func containsMatch(in text: String, query: String) -> Bool {
        !matches(in: text, query: query).isEmpty
    }

    static func suggestedCompletions(in text: String, prefix: String, limit: Int = 5) -> [String] {
        let mapping = MarkdownTextOffsetMapping(sourceText: text)
        return suggestedCompletions(inDisplayText: mapping.displayText, prefix: prefix, limit: limit)
    }

    static func containsMatch(inDisplayText text: String, query: String) -> Bool {
        !displayTextMatches(in: text, query: query).isEmpty
    }

    static func suggestedCompletions(inDisplayText text: String, prefix: String, limit: Int = 5) -> [String] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrefix.count >= 2 else { return [] }

        let foldedPrefix = trimmedPrefix.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let separatorSet = CharacterSet.alphanumerics.inverted
        let candidates = text.components(separatedBy: separatorSet)

        var seen = Set<String>()
        var suggestions: [String] = []

        for candidate in candidates {
            guard candidate.count > trimmedPrefix.count else { continue }
            let foldedCandidate = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard foldedCandidate.hasPrefix(foldedPrefix) else { continue }
            guard seen.insert(foldedCandidate).inserted else { continue }

            suggestions.append(candidate)
            if suggestions.count == limit {
                break
            }
        }

        return suggestions
    }

    private static func displayTextMatches(in text: String, query: String) -> [MarkdownSelectionRange] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let nsText = text as NSString
        let searchOptions: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        var searchRange = NSRange(location: 0, length: nsText.length)
        var matches: [MarkdownSelectionRange] = []

        while searchRange.length > 0 {
            let foundRange = nsText.range(of: trimmedQuery, options: searchOptions, range: searchRange)
            guard foundRange.location != NSNotFound, foundRange.length > 0 else { break }

            matches.append(MarkdownSelectionRange(foundRange))

            let nextLocation = foundRange.location + foundRange.length
            guard nextLocation < nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return matches
    }
}
