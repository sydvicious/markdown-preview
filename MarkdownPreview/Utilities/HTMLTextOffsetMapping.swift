//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import MarkdownCore

final class HTMLTextOffsetMapping: TextOffsetMapping {
    let sourceText: String
    let displayText: String
    let runs: [TextOffsetRun]

    init(sourceText: String) {
        self.sourceText = sourceText

        let builder = HTMLDisplayBuilder(sourceText: sourceText)
        builder.build()
        displayText = builder.displayText
        runs = builder.runs
    }
}

private final class HTMLDisplayBuilder {
    let sourceText: String
    let nsSourceText: NSString

    private(set) var displayText = ""
    private(set) var runs: [TextOffsetRun] = []
    private var displayOffset = 0

    init(sourceText: String) {
        self.sourceText = sourceText
        nsSourceText = sourceText as NSString
    }

    func build() {
        let length = nsSourceText.length
        let bodyStart = rangeOf("<body", from: 0)
        let bodyContentStart: Int
        if let bodyStart, let bodyOpenEnd = rangeOf(">", from: bodyStart.location).map({ $0.location + $0.length }) {
            bodyContentStart = bodyOpenEnd
        } else {
            bodyContentStart = 0
        }
        let bodyEnd = rangeOf("</body>", from: bodyContentStart)?.location ?? length
        var index = bodyContentStart

        while index < bodyEnd {
            let scalar = nsSourceText.substring(with: NSRange(location: index, length: 1))
            if scalar == "<" {
                let tagStart = index
                guard let tagEnd = rangeOf(">", from: index).map({ $0.location + $0.length }) else {
                    break
                }
                let tagText = nsSourceText.substring(with: NSRange(location: tagStart, length: tagEnd - tagStart))
                if tagText.lowercased().hasPrefix("<br") {
                    appendMappedLiteral("\n", sourceRange: MarkdownSelectionRange(location: tagStart, length: tagEnd - tagStart))
                }
                index = tagEnd
                continue
            }

            if scalar == "&",
               let entityEnd = rangeOf(";", from: index).map({ $0.location + $0.length }) {
                let entityRange = MarkdownSelectionRange(location: index, length: entityEnd - index)
                let entityText = nsSourceText.substring(with: entityRange.nsRange)
                let decoded = decodeEntity(entityText)
                appendMappedLiteral(decoded, sourceRange: entityRange)
                index = entityEnd
                continue
            }

            let nextSpecial = min(rangeOf("<", from: index)?.location ?? bodyEnd, rangeOf("&", from: index)?.location ?? bodyEnd)
            let textRange = MarkdownSelectionRange(location: index, length: nextSpecial - index)
            appendMappedLiteral(nsSourceText.substring(with: textRange.nsRange), sourceRange: textRange)
            index = nextSpecial
        }
    }

    private func appendMappedLiteral(_ literal: String, sourceRange: MarkdownSelectionRange) {
        guard !literal.isEmpty else { return }
        let displayRange = MarkdownSelectionRange(location: displayOffset, length: literal.utf16.count)
        displayText.append(literal)
        runs.append(TextOffsetRun(sourceRange: sourceRange, displayRange: displayRange))
        displayOffset += displayRange.length
    }

    private func rangeOf(_ needle: String, from location: Int) -> NSRange? {
        let searchRange = NSRange(location: location, length: nsSourceText.length - location)
        let found = nsSourceText.range(of: needle, options: [], range: searchRange)
        return found.location == NSNotFound ? nil : found
    }

    private func decodeEntity(_ entity: String) -> String {
        switch entity.lowercased() {
        case "&amp;":
            return "&"
        case "&lt;":
            return "<"
        case "&gt;":
            return ">"
        case "&quot;":
            return "\""
        case "&#39;":
            return "'"
        default:
            if entity.hasPrefix("&#x"), entity.hasSuffix(";") {
                let hex = entity.dropFirst(3).dropLast()
                if let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) {
                    return String(Character(scalar))
                }
            }
            if entity.hasPrefix("&#"), entity.hasSuffix(";") {
                let number = entity.dropFirst(2).dropLast()
                if let value = UInt32(number), let scalar = UnicodeScalar(value) {
                    return String(Character(scalar))
                }
            }
            return entity
        }
    }
}
