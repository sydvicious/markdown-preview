//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

final class MarkdownTextOffsetMapping: TextOffsetMapping {
    let sourceText: String
    let displayText: String
    let runs: [TextOffsetRun]

    init(sourceText: String) {
        self.sourceText = sourceText

        let builder = MarkdownDisplayBuilder(sourceText: sourceText)
        builder.build()
        displayText = builder.displayText
        runs = builder.runs
    }
}

final class MarkdownPreviewTextOffsetMapping: TextOffsetMapping {
    let sourceText: String
    let displayText: String
    let runs: [TextOffsetRun]

    init(sourceText: String) {
        self.sourceText = sourceText

        let builder = MarkdownDisplayBuilder(
            sourceText: sourceText,
            listItemSeparator: "",
            includesImageAltText: false
        )
        builder.build()
        displayText = builder.displayText
        runs = builder.runs
    }
}

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

private final class MarkdownDisplayBuilder {
    let sourceText: String
    let nsSourceText: NSString
    let lineTable: MarkdownSourceLineTable
    let lines: [String]
    let listItemSeparator: String
    let includesImageAltText: Bool

    private(set) var displayText = ""
    private(set) var runs: [TextOffsetRun] = []
    private var displayOffset = 0
    private var consumedSourceOffset = 0
    private var hasVisibleContent = false

    init(
        sourceText: String,
        listItemSeparator: String = "\n",
        includesImageAltText: Bool = true
    ) {
        self.sourceText = sourceText
        nsSourceText = sourceText as NSString
        lineTable = MarkdownSourceLineTable(source: sourceText)
        lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        self.listItemSeparator = listItemSeparator
        self.includesImageAltText = includesImageAltText
    }

    func build() {
        for block in MarkdownBlockParser.parse(sourceText) {
            guard let blockSourceRange = lineTable.range(for: block.lineRange) else { continue }
            appendGapBeforeBlock(blockSourceRange)

            switch block.kind {
            case .heading:
                appendHeading(block)
            case .paragraph:
                appendParagraph(block)
            case .list:
                appendList(block, ordered: false)
            case .orderedList:
                appendList(block, ordered: true)
            case .table:
                appendTable(block)
            case .blockquote:
                appendBlockquote(block)
            case .rule:
                break
            case .code:
                appendCodeBlock(block)
            }

            consumedSourceOffset = blockSourceRange.location + blockSourceRange.length
        }
    }

    private func appendGapBeforeBlock(_ blockSourceRange: MarkdownSelectionRange) {
        let gapLength = blockSourceRange.location - consumedSourceOffset
        guard hasVisibleContent, gapLength > 0 else {
            consumedSourceOffset = min(consumedSourceOffset, blockSourceRange.location)
            return
        }

        appendMappedLiteral(
            "\n",
            sourceRange: MarkdownSelectionRange(location: consumedSourceOffset, length: gapLength)
        )
    }

    private func appendHeading(_ block: MarkdownBlock) {
        guard let firstLineRange = lineTable.range(forLine: block.lineRange.lowerBound) else { return }

        if block.lineRange.count >= 2 {
            appendInline(from: trimmedRange(firstLineRange, trimming: .whitespaces))
            return
        }

        let line = substring(firstLineRange)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        let markerLength = hashes.count
        guard markerLength > 0 else {
            appendInline(from: trimmedRange(firstLineRange, trimming: .whitespaces))
            return
        }

        let leadingWhitespace = line.utf16LeadingWhitespaceCount
        let start = firstLineRange.location + leadingWhitespace + markerLength
        let remainderLength = max(0, firstLineRange.location + firstLineRange.length - start)
        let remainderRange = MarkdownSelectionRange(location: start, length: remainderLength)
        appendInline(from: trimmedRange(remainderRange, trimming: .whitespaces))
    }

    private func appendParagraph(_ block: MarkdownBlock) {
        appendTrimmedInlineLines(in: block.lineRange, separator: " ")
    }

    private func appendList(_ block: MarkdownBlock, ordered: Bool) {
        var previousContentEnd: Int?
        for lineNumber in block.lineRange {
            guard let lineRange = lineTable.range(forLine: lineNumber),
                  let contentRange = listItemContentRange(in: lineRange, ordered: ordered) else {
                continue
            }

            if let previousContentEnd {
                let gapLength = max(0, contentRange.location - previousContentEnd)
                appendMappedLiteral(
                    listItemSeparator,
                    sourceRange: MarkdownSelectionRange(location: previousContentEnd, length: gapLength)
                )
            }

            appendInline(from: trimmedRange(contentRange, trimming: .whitespaces))
            previousContentEnd = contentRange.location + contentRange.length
        }
    }

    private func appendTable(_ block: MarkdownBlock) {
        guard block.lineRange.count >= 3 else { return }

        if block.lineRange.lowerBound < block.lineRange.upperBound,
           let headerRange = lineTable.range(forLine: block.lineRange.lowerBound) {
            let headerLine = substring(headerRange)
            for cellRange in tableCellRanges(in: headerRange, line: headerLine) {
                appendInline(from: cellRange)
            }
        }

        for lineNumber in (block.lineRange.lowerBound + 2)..<block.lineRange.upperBound {
            guard let lineRange = lineTable.range(forLine: lineNumber) else { continue }
            let line = substring(lineRange)
            for cellRange in tableCellRanges(in: lineRange, line: line) {
                appendInline(from: cellRange)
            }
        }
    }

    private func appendBlockquote(_ block: MarkdownBlock) {
        for lineNumber in block.lineRange {
            guard let lineRange = lineTable.range(forLine: lineNumber),
                  let contentRange = blockquoteContentRange(in: lineRange) else {
                continue
            }
            appendInline(from: trimmedRange(contentRange, trimming: .whitespaces))
        }
    }

    private func appendCodeBlock(_ block: MarkdownBlock) {
        guard block.lineRange.count >= 2 else { return }

        let firstContentLine = block.lineRange.lowerBound + 1
        let lastContentLine = max(firstContentLine, block.lineRange.upperBound - 1)
        var previousContentEnd: Int?

        for lineNumber in firstContentLine..<lastContentLine {
            guard let lineRange = lineTable.range(forLine: lineNumber) else { continue }
            if let previousContentEnd {
                let gapLength = max(0, lineRange.location - previousContentEnd)
                appendMappedLiteral(
                    "\n",
                    sourceRange: MarkdownSelectionRange(location: previousContentEnd, length: gapLength)
                )
            }
            appendSource(range: lineRange)
            previousContentEnd = lineRange.location + lineRange.length
        }
    }

    private func appendTrimmedInlineLines(in lineRange: Range<Int>, separator: String) {
        var previousTrimmedEnd: Int?
        for lineNumber in lineRange {
            guard let sourceRange = lineTable.range(forLine: lineNumber) else { continue }
            let trimmed = trimmedRange(sourceRange, trimming: .whitespaces)
            guard trimmed.length > 0 else { continue }

            if let previousTrimmedEnd {
                let gapLength = max(0, trimmed.location - previousTrimmedEnd)
                appendMappedLiteral(
                    separator,
                    sourceRange: MarkdownSelectionRange(location: previousTrimmedEnd, length: gapLength)
                )
            }

            appendInline(from: trimmed)
            previousTrimmedEnd = trimmed.location + trimmed.length
        }
    }

    private func appendInline(from sourceRange: MarkdownSelectionRange) {
        guard sourceRange.length > 0 else { return }

        let sourceSubstring = Substring(substring(sourceRange))
        let startIndex = sourceSubstring.startIndex
        let endIndex = sourceSubstring.endIndex

        var cursor = startIndex
        while cursor < endIndex {
            if let image = parseImage(in: sourceSubstring, from: cursor) {
                if includesImageAltText {
                    appendSource(range: relativeRange(image.alt, in: sourceRange, base: sourceSubstring))
                }
                cursor = image.endIndex
                continue
            }

            if let link = parseLink(in: sourceSubstring, from: cursor) {
                appendInline(from: relativeRange(link.label, in: sourceRange, base: sourceSubstring))
                cursor = link.endIndex
                continue
            }

            if let code = parseDelimited(in: sourceSubstring, from: cursor, delimiter: "`") {
                appendSource(range: relativeRange(code.content, in: sourceRange, base: sourceSubstring))
                cursor = code.endIndex
                continue
            }

            if let strong = parseDelimited(in: sourceSubstring, from: cursor, delimiter: "**") ??
                parseDelimited(in: sourceSubstring, from: cursor, delimiter: "__") {
                appendInline(from: relativeRange(strong.content, in: sourceRange, base: sourceSubstring))
                cursor = strong.endIndex
                continue
            }

            if let emphasis = parseDelimited(in: sourceSubstring, from: cursor, delimiter: "*") ??
                parseDelimited(in: sourceSubstring, from: cursor, delimiter: "_") {
                appendInline(from: relativeRange(emphasis.content, in: sourceRange, base: sourceSubstring))
                cursor = emphasis.endIndex
                continue
            }

            let nextIndex = sourceSubstring.index(after: cursor)
            let piece = sourceSubstring[cursor..<nextIndex]
            appendSource(range: relativeRange(piece, in: sourceRange, base: sourceSubstring))
            cursor = nextIndex
        }
    }

    private func appendSource(range: MarkdownSelectionRange) {
        guard range.length > 0 else { return }
        appendMappedLiteral(substring(range), sourceRange: range)
    }

    private func appendMappedLiteral(_ literal: String, sourceRange: MarkdownSelectionRange) {
        guard !literal.isEmpty else { return }
        let displayRange = MarkdownSelectionRange(location: displayOffset, length: literal.utf16.count)
        displayText.append(literal)
        runs.append(TextOffsetRun(sourceRange: sourceRange, displayRange: displayRange))
        displayOffset += displayRange.length
        hasVisibleContent = true
    }

    private func trimmedRange(_ range: MarkdownSelectionRange?, trimming set: CharacterSet) -> MarkdownSelectionRange {
        guard let range else { return MarkdownSelectionRange(location: 0, length: 0) }
        let text = substring(range)
        var start = 0
        var end = text.utf16.count
        let utf16 = Array(text.utf16)

        while start < end, let scalar = UnicodeScalar(utf16[start]), set.contains(scalar) {
            start += 1
        }
        while end > start, let scalar = UnicodeScalar(utf16[end - 1]), set.contains(scalar) {
            end -= 1
        }

        return MarkdownSelectionRange(location: range.location + start, length: end - start)
    }

    private func substring(_ range: MarkdownSelectionRange) -> String {
        nsSourceText.substring(with: range.nsRange)
    }

    private func relativeRange(
        _ substring: Substring,
        in parentRange: MarkdownSelectionRange,
        base: Substring
    ) -> MarkdownSelectionRange {
        let prefixLength = base[..<substring.startIndex].utf16.count
        return MarkdownSelectionRange(location: parentRange.location + prefixLength, length: substring.utf16.count)
    }

    private func listItemContentRange(in lineRange: MarkdownSelectionRange, ordered: Bool) -> MarkdownSelectionRange? {
        let line = substring(lineRange)
        let utf16 = Array(line.utf16)
        var index = 0

        while index < utf16.count, let scalar = UnicodeScalar(utf16[index]), CharacterSet.whitespaces.contains(scalar) {
            index += 1
        }

        if ordered {
            while index < utf16.count, let scalar = UnicodeScalar(utf16[index]), CharacterSet.decimalDigits.contains(scalar) {
                index += 1
            }
            guard index < utf16.count, utf16[index] == 46 else { return nil }
            index += 1
        } else {
            guard index < utf16.count, [45, 42, 43].contains(utf16[index]) else { return nil }
            index += 1
        }

        guard index < utf16.count, utf16[index] == 32 else { return nil }
        index += 1

        if index + 3 <= utf16.count,
           utf16[index] == 91,
           (utf16[index + 1] == 32 || utf16[index + 1] == 120 || utf16[index + 1] == 88),
           utf16[index + 2] == 93,
           index + 3 < utf16.count,
           utf16[index + 3] == 32 {
            index += 4
        }

        return MarkdownSelectionRange(location: lineRange.location + index, length: max(0, utf16.count - index))
    }

    private func blockquoteContentRange(in lineRange: MarkdownSelectionRange) -> MarkdownSelectionRange? {
        let line = substring(lineRange)
        let utf16 = Array(line.utf16)
        var index = 0

        while index < utf16.count, let scalar = UnicodeScalar(utf16[index]), CharacterSet.whitespaces.contains(scalar) {
            index += 1
        }
        guard index < utf16.count, utf16[index] == 62 else { return nil }
        index += 1
        if index < utf16.count, utf16[index] == 32 {
            index += 1
        }

        return MarkdownSelectionRange(location: lineRange.location + index, length: max(0, utf16.count - index))
    }

    private func tableCellRanges(in lineRange: MarkdownSelectionRange, line: String) -> [MarkdownSelectionRange] {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.contains("|") else { return [] }

        let leadingWhitespace = line.utf16LeadingWhitespaceCount
        let leadingTrimmedLine = String(line.dropFirst(leadingWhitespace))
        let offsetBase = lineRange.location + leadingWhitespace
        let utf16 = Array(leadingTrimmedLine.utf16)
        var cells: [MarkdownSelectionRange] = []
        var cellStart = 0
        var index = 0
        var sawPipe = false

        while index <= utf16.count {
            let isPipe = index < utf16.count && utf16[index] == 124
            if isPipe || index == utf16.count {
                sawPipe = sawPipe || isPipe
                let rawStart = cellStart
                let rawEnd = index
                var trimmedStart = rawStart
                var trimmedEnd = rawEnd

                while trimmedStart < trimmedEnd,
                      let scalar = UnicodeScalar(utf16[trimmedStart]),
                      CharacterSet.whitespaces.contains(scalar) {
                    trimmedStart += 1
                }
                while trimmedEnd > trimmedStart,
                      let scalar = UnicodeScalar(utf16[trimmedEnd - 1]),
                      CharacterSet.whitespaces.contains(scalar) {
                    trimmedEnd -= 1
                }

                if !(cells.isEmpty && trimmedStart == trimmedEnd) && trimmedEnd >= trimmedStart {
                    cells.append(
                        MarkdownSelectionRange(
                            location: offsetBase + trimmedStart,
                            length: trimmedEnd - trimmedStart
                        )
                    )
                }

                cellStart = index + 1
            }
            index += 1
        }

        guard sawPipe else { return [] }
        if cells.last?.length == 0 {
            cells.removeLast()
        }
        return cells.filter { $0.length > 0 }
    }

    private func parseDelimited(
        in text: Substring,
        from start: String.Index,
        delimiter: String
    ) -> (content: Substring, endIndex: String.Index)? {
        guard text[start...].hasPrefix(delimiter) else { return nil }

        let contentStart = text.index(start, offsetBy: delimiter.count)
        guard contentStart < text.endIndex else { return nil }

        var searchIndex = contentStart
        while searchIndex < text.endIndex {
            guard let range = text[searchIndex...].range(of: delimiter) else { return nil }
            guard range.lowerBound > contentStart else {
                searchIndex = range.upperBound
                continue
            }

            let content = text[contentStart..<range.lowerBound]
            guard !String(content).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (content, range.upperBound)
        }

        return nil
    }

    private func parseLink(
        in text: Substring,
        from start: String.Index
    ) -> (label: Substring, endIndex: String.Index)? {
        guard text[start] == "[" else { return nil }
        guard let closeBracket = text[start...].firstIndex(of: "]") else { return nil }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        let urlStart = text.index(after: afterBracket)
        guard let closeParen = text[urlStart...].firstIndex(of: ")") else { return nil }

        let label = text[text.index(after: start)..<closeBracket]
        let destination = String(text[urlStart..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }

        return (label, text.index(after: closeParen))
    }

    private func parseImage(
        in text: Substring,
        from start: String.Index
    ) -> (alt: Substring, endIndex: String.Index)? {
        guard text[start] == "!" else { return nil }
        let labelStart = text.index(after: start)
        guard labelStart < text.endIndex, text[labelStart] == "[" else { return nil }
        guard let closeBracket = text[labelStart...].firstIndex(of: "]") else { return nil }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        let urlStart = text.index(after: afterBracket)
        guard let closeParen = text[urlStart...].firstIndex(of: ")") else { return nil }

        let alt = text[text.index(after: labelStart)..<closeBracket]
        let destination = String(text[urlStart..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }

        return (alt, text.index(after: closeParen))
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

private extension String {
    var utf16LeadingWhitespaceCount: Int {
        let utf16 = Array(self.utf16)
        var count = 0
        while count < utf16.count,
              let scalar = UnicodeScalar(utf16[count]),
              CharacterSet.whitespaces.contains(scalar) {
            count += 1
        }
        return count
    }
}
