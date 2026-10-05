//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public struct MarkdownTable: Equatable {
    public let headers: [String]
    public let alignments: [MarkdownTableAlignment]
    public let rows: [[String]]

    public init(headers: [String], alignments: [MarkdownTableAlignment], rows: [[String]]) {
        self.headers = headers
        self.alignments = alignments
        self.rows = rows
    }
}

public enum MarkdownTableAlignment: Equatable {
    case leading
    case center
    case trailing
}

public struct MarkdownBlock: Identifiable {
    public enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list([MarkdownListItem], isLoose: Bool)
        case orderedList([MarkdownListItem], isLoose: Bool)
        case table(MarkdownTable)
        case blockquote([MarkdownBlock])
        case rule
        case code(String, language: String?)
    }

    public let id = UUID()
    public let kind: Kind
    public let lineRange: Range<Int>
}

public struct MarkdownListItem: Identifiable {
    public let id = UUID()
    public let text: String
    /// Nesting depth, 0 for a top-level item. Derived from how far the item is
    /// indented relative to its parent's content column, not from an absolute
    /// space count, so two spaces, four spaces, or a tab all nest one level.
    public let indent: Int
    public let checkbox: Bool?
    public let order: Int?
    public let isOrdered: Bool
}

/// A list item as it appears on one source line, before its nesting depth is
/// known. Depth depends on the surrounding lines, so the parser resolves it
/// while walking the list.
private struct ParsedListItem {
    /// The item's text, as a stretch of the line it was parsed from.
    let content: Substring
    var text: String { String(content) }
    let checkbox: Bool?
    let order: Int?
    let isOrdered: Bool
    /// Column the list marker starts at.
    let markerColumn: Int
    /// Column the item's text starts at; a following line indented at least
    /// this far is a child of this item.
    let contentColumn: Int
}

public struct MarkdownBlockParser {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.markdownLines
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var paragraphStartLine: Int?
        var listItems: [MarkdownListItem] = []
        var listStartLine: Int?
        // Content/marker columns of each currently open nesting level, used to
        // resolve each item's depth relative to its parent rather than from an
        // absolute indent width.
        var openLevels: [(markerColumn: Int, contentColumn: Int)] = []
        var listIsLoose = false
        var quoteLines: [String] = []
        var quoteStartLine: Int?
        var code: [String] = []
        var codeContentStartLine: Int?
        var codeFenceStartLine: Int?
        var inCodeFence = false
        var fenceMarker: Character?
        var fenceLength = 0
        var fenceLanguage: String?

        func flushParagraph(currentLine: Int) {
            guard !paragraph.isEmpty, let start = paragraphStartLine else { return }
            blocks.append(
                .init(
                    kind: .paragraph(
                        paragraph.joined(separator: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    ),
                    lineRange: start..<currentLine
                )
            )
            paragraph.removeAll()
            paragraphStartLine = nil
        }

        func flushList(currentLine: Int) {
            guard !listItems.isEmpty, let start = listStartLine else { return }
            // A list block takes its type from its first item; nested items of
            // the other type are rendered as their own sub-list.
            let kind: MarkdownBlock.Kind = listItems[0].isOrdered
                ? .orderedList(listItems, isLoose: listIsLoose)
                : .list(listItems, isLoose: listIsLoose)
            blocks.append(.init(kind: kind, lineRange: start..<currentLine))
            listItems.removeAll()
            listStartLine = nil
            openLevels.removeAll()
            listIsLoose = false
        }

        /// Resolves `parsed` against the open nesting levels and appends it,
        /// starting a new list block when a top-level item switches marker type.
        func appendListItem(_ parsed: ParsedListItem, at index: Int) {
            // Dedent out of any levels the item has moved back past.
            while openLevels.count > 1, parsed.markerColumn < openLevels[openLevels.count - 1].markerColumn {
                openLevels.removeLast()
            }

            if let current = openLevels.last {
                if parsed.markerColumn >= current.contentColumn {
                    openLevels.append((parsed.markerColumn, parsed.contentColumn))
                } else {
                    openLevels[openLevels.count - 1] = (parsed.markerColumn, parsed.contentColumn)
                }
            } else {
                openLevels.append((parsed.markerColumn, parsed.contentColumn))
            }

            let depth = openLevels.count - 1

            // Switching between bulleted and numbered at the top level starts a
            // separate list, matching CommonMark and keeping the two kinds of
            // block distinct.
            if depth == 0, let first = listItems.first, first.isOrdered != parsed.isOrdered {
                flushList(currentLine: index)
                openLevels = [(parsed.markerColumn, parsed.contentColumn)]
            }

            if listStartLine == nil {
                listStartLine = index
            }

            listItems.append(
                MarkdownListItem(
                    text: parsed.text,
                    indent: depth,
                    checkbox: parsed.checkbox,
                    order: parsed.order,
                    isOrdered: parsed.isOrdered
                )
            )
        }

        func flushQuote(currentLine: Int) {
            guard !quoteLines.isEmpty, let start = quoteStartLine else { return }
            blocks.append(
                .init(
                    // Parsed recursively: the stripped content is itself a
                    // document, which is how quotes nest and hold other blocks.
                    kind: .blockquote(parse(quoteLines.joined(separator: "\n"))),
                    lineRange: start..<currentLine
                )
            )
            quoteLines.removeAll()
            quoteStartLine = nil
        }

        func flushAll(currentLine: Int) {
            flushParagraph(currentLine: currentLine)
            flushList(currentLine: currentLine)
            flushQuote(currentLine: currentLine)
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]

            if inCodeFence {
                // Only a fence of the same character, at least as long as the
                // opener and carrying no info string, closes the block.
                if let fence = parseCodeFence(line),
                   fence.marker == fenceMarker,
                   fence.length >= fenceLength,
                   fence.info.isEmpty {
                    blocks.append(
                        .init(
                            kind: .code(code.joined(separator: "\n"), language: fenceLanguage),
                            lineRange: (codeFenceStartLine ?? index)..<(index + 1)
                        )
                    )
                    code.removeAll()
                    codeContentStartLine = nil
                    codeFenceStartLine = nil
                    fenceMarker = nil
                    fenceLanguage = nil
                    inCodeFence = false
                } else {
                    code.append(line)
                }
                index += 1
                continue
            }

            if let fence = parseCodeFence(line) {
                flushAll(currentLine: index)
                inCodeFence = true
                fenceMarker = fence.marker
                fenceLength = fence.length
                // Only the first word of the info string names the language.
                fenceLanguage = fence.info.split(separator: " ").first.map(String.init)
                codeFenceStartLine = index
                codeContentStartLine = index + 1
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // A blank line inside a list does not end it if another item
                // follows; it makes the list loose, and every item's content is
                // then wrapped in a paragraph.
                if !listItems.isEmpty, nextNonBlankLineContinuesList(lines, after: index) {
                    listIsLoose = true
                    index += 1
                    continue
                }

                flushAll(currentLine: index)
                index += 1
                continue
            }

            // A setext underline turns the paragraph above it into a heading, so
            // the heading's content is however many lines that paragraph had.
            if let level = setextUnderlineLevel(line),
               !paragraph.isEmpty,
               let start = paragraphStartLine {
                let text = paragraph.joined(separator: "\n")
                paragraph.removeAll()
                paragraphStartLine = nil
                blocks.append(
                    .init(
                        kind: .heading(level: level, text: text),
                        lineRange: start..<(index + 1)
                    )
                )
                index += 1
                continue
            }

            if let tableResult = parseTable(from: lines, startIndex: index) {
                flushAll(currentLine: index)
                blocks.append(
                    .init(
                        kind: .table(tableResult.table),
                        lineRange: index..<tableResult.nextIndex
                    )
                )
                index = tableResult.nextIndex
                continue
            }

            if let heading = headingContent(in: line[...]) {
                flushAll(currentLine: index)
                blocks.append(
                    .init(
                        kind: .heading(level: heading.level, text: String(heading.content)),
                        lineRange: index..<(index + 1)
                    )
                )
                index += 1
                continue
            }

            // Checked before list items: "- - -" and "* * *" are thematic
            // breaks, even though their first characters also look like list
            // markers. The setext underline case above has already had its say.
            if parseRule(line) {
                flushAll(currentLine: index)
                blocks.append(.init(kind: .rule, lineRange: index..<(index + 1)))
                index += 1
                continue
            }

            if let item = parseListItem(line[...]) ?? parseOrderedListItem(line[...]) {
                flushParagraph(currentLine: index)
                flushQuote(currentLine: index)
                appendListItem(item, at: index)
                index += 1
                continue
            }

            if let quote = blockquoteContent(in: line[...]) {
                flushParagraph(currentLine: index)
                flushList(currentLine: index)
                if quoteStartLine == nil {
                    quoteStartLine = index
                }
                quoteLines.append(String(quote))
                index += 1
                continue
            }

            flushList(currentLine: index)
            flushQuote(currentLine: index)
            if paragraphStartLine == nil {
                paragraphStartLine = index
            }
            // Leading whitespace is dropped, but trailing whitespace is kept:
            // two trailing spaces are a hard line break and the renderer needs
            // to see them.
            paragraph.append(String(paragraphLineContent(in: line[...])))
            index += 1
        }

        flushAll(currentLine: lines.count)
        if !code.isEmpty {
            blocks.append(
                .init(
                    kind: .code(code.joined(separator: "\n"), language: fenceLanguage),
                    lineRange: (codeFenceStartLine ?? codeContentStartLine ?? lines.count)..<lines.count
                )
            )
        }
        return blocks
    }

    // The functions from here to `tableCellSlices` say where a line's content
    // sits in the line, as a `Substring` of it. The parser turns that into the
    // block's text; `MarkdownVisibleText` uses the same answer to say which
    // characters of the source a piece of rendered text came from, so the two
    // cannot disagree about what is content and what is markup.

    /// The level and text of an ATX heading line, or nil if it is not one.
    static func headingContent(in line: Substring) -> (level: Int, content: Substring)? {
        let trimmed = line.trimmingMarkdownWhitespace()
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }

        let remainder = trimmed.dropFirst(level)
        // The opening run must be followed by a space or end the line, so that
        // "#hashtag" stays text rather than becoming a heading.
        guard remainder.isEmpty || remainder.first == " " || remainder.first == "\t" else {
            return nil
        }

        var content = remainder.trimmingMarkdownWhitespace()

        // An optional closing run of hashes is decoration and is dropped, but
        // only when it is preceded by a space: "foo#" keeps its hash.
        var withoutClosing = content
        while withoutClosing.last == "#" {
            withoutClosing = withoutClosing.dropLast()
        }
        if withoutClosing.endIndex < content.endIndex,
           withoutClosing.isEmpty || withoutClosing.last == " " || withoutClosing.last == "\t" {
            content = withoutClosing.trimmingMarkdownWhitespace()
        }

        // An empty heading is valid: "#" alone is <h1></h1>.
        return (level, content)
    }

    /// A paragraph line's text: the line without its leading spaces and tabs.
    /// Trailing whitespace is kept, because two trailing spaces are a hard line
    /// break and the renderer needs to see them.
    static func paragraphLineContent(in line: Substring) -> Substring {
        line.drop { $0 == " " || $0 == "\t" }
    }

    /// The text of a list item line — after its marker and any task box — or
    /// nil if the line is not a list item.
    static func listItemContent(in line: Substring) -> Substring? {
        (parseListItem(line) ?? parseOrderedListItem(line))?.content
    }

    /// Whether `closing` is the line that closes the fenced code block `opening`
    /// opens: a fence of the same character, at least as long, with no info
    /// string.
    static func fence(_ opening: Substring, isClosedBy closing: Substring) -> Bool {
        guard let open = parseCodeFence(opening), let close = parseCodeFence(closing) else { return false }
        return close.marker == open.marker && close.length >= open.length && close.info.isEmpty
    }

    /// Whether the next non-blank line after `index` is another list item,
    /// which is what distinguishes a blank line inside a loose list from one
    /// that ends the list.
    private static func nextNonBlankLineContinuesList(_ lines: [String], after index: Int) -> Bool {
        var probe = index + 1
        while probe < lines.count, lines[probe].trimmingCharacters(in: .whitespaces).isEmpty {
            probe += 1
        }
        guard probe < lines.count else { return false }
        return listItemContent(in: lines[probe][...]) != nil
    }

    /// Recognises a code fence: a run of at least three backticks or tildes,
    /// indented no more than three spaces, optionally followed by an info
    /// string naming the language.
    private static func parseCodeFence<Line: StringProtocol>(_ line: Line) -> (marker: Character, length: Int, info: String)? {
        guard indentColumns(in: line) <= 3 else { return nil }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }

        let run = trimmed.prefix { $0 == marker }
        guard run.count >= 3 else { return nil }

        let info = trimmed.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
        // A backtick fence's info string may not itself contain a backtick,
        // which is what keeps inline code from being read as a fence.
        if marker == "`", info.contains("`") { return nil }

        return (marker, run.count, info)
    }

    /// The heading level a line denotes when used as a setext underline, or nil
    /// if it is not one. The spec puts no minimum on the run's length, so a
    /// single character counts.
    private static func setextUnderlineLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.allSatisfy({ $0 == "=" }) {
            return 1
        }
        if trimmed.allSatisfy({ $0 == "-" }) {
            return 2
        }
        return nil
    }

    private static func parseListItem(_ line: Substring) -> ParsedListItem? {
        let markerColumn = indentColumns(in: line)
        let trimmed = line.trimmingMarkdownWhitespace()
        guard trimmed.count >= 3 else { return nil }
        let first = trimmed.first
        guard first == "-" || first == "*" || first == "+" else { return nil }
        guard trimmed.dropFirst().first == " " else { return nil }
        let (content, checkbox) = parseCheckbox(trimmed.dropFirst(2).trimmingMarkdownWhitespace())
        return ParsedListItem(
            content: content,
            checkbox: checkbox,
            order: nil,
            isOrdered: false,
            markerColumn: markerColumn,
            contentColumn: markerColumn + 2
        )
    }

    private static func parseOrderedListItem(_ line: Substring) -> ParsedListItem? {
        let markerColumn = indentColumns(in: line)
        let trimmed = line.trimmingMarkdownWhitespace()
        // Either "1." or "1)" starts a numbered item.
        guard let delimiterIndex = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }) else {
            return nil
        }
        let number = trimmed[..<delimiterIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterDot = trimmed[trimmed.index(after: delimiterIndex)...]
        guard afterDot.first == " " else { return nil }
        let (content, checkbox) = parseCheckbox(afterDot.dropFirst().trimmingMarkdownWhitespace())
        return ParsedListItem(
            content: content,
            checkbox: checkbox,
            order: Int(number),
            isOrdered: true,
            markerColumn: markerColumn,
            // "12. " is a wider marker than "1. ", so children line up further in.
            contentColumn: markerColumn + number.count + 2
        )
    }

    /// Strips one level of block quote marker from a line.
    ///
    /// Only the marker and a single following space are removed. Whatever is
    /// left keeps its own indentation and trailing spaces, so a nested quote,
    /// an indented list, or a hard line break inside the quote all survive to
    /// the recursive parse.
    static func blockquoteContent(in line: Substring) -> Substring? {
        let withoutIndent = line.drop { $0 == " " || $0 == "\t" }
        guard withoutIndent.first == ">" else { return nil }

        let remaining = withoutIndent.dropFirst()
        return remaining.first == " " ? remaining.dropFirst() : remaining
    }

    private static func parseRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Spaces and tabs may separate the characters, so "* * *" is a rule.
        let marks = trimmed.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3 else { return false }
        guard marks.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) else { return false }
        return Set(marks).count == 1
    }

    /// Width of a line's leading whitespace in columns, expanding tabs to the
    /// next four-column tab stop as CommonMark specifies.
    private static func indentColumns<Line: StringProtocol>(in line: Line) -> Int {
        var width = 0
        for ch in line {
            if ch == " " {
                width += 1
            } else if ch == "\t" {
                width += 4 - (width % 4)
            } else {
                break
            }
        }
        return width
    }

    private static func parseCheckbox(_ text: Substring) -> (Substring, Bool?) {
        if text.hasPrefix("[ ] ") {
            return (text.dropFirst(4), false)
        }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return (text.dropFirst(4), true)
        }
        return (text, nil)
    }

    private static func parseTable(from lines: [String], startIndex: Int) -> (table: MarkdownTable, nextIndex: Int)? {
        guard startIndex + 2 < lines.count else { return nil }
        guard let headers = parseTableRow(lines[startIndex]) else { return nil }
        guard let alignments = parseDelimiterRow(lines[startIndex + 1]) else { return nil }
        guard headers.count == alignments.count else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            guard var row = parseTableRow(line) else { break }
            // A row may be short or long; pad or truncate it to the header width
            // rather than abandoning the table.
            if row.count < headers.count {
                row.append(contentsOf: Array(repeating: "", count: headers.count - row.count))
            } else if row.count > headers.count {
                row = Array(row.prefix(headers.count))
            }
            rows.append(row)
            index += 1
        }

        // If body rows are missing, treat these lines as plain text.
        guard !rows.isEmpty else { return nil }
        return (MarkdownTable(headers: headers, alignments: alignments, rows: rows), index)
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        tableCellSlices(in: line[...])?.map(tableCellText)
    }

    /// The cells of a table row as they are written, each trimmed of the
    /// whitespace around it, or nil if the line has no pipe and so is not a row.
    ///
    /// A backslash escapes the character after it, so `\|` does not end a cell.
    /// An empty cell before the first pipe or after the last is the row's edge,
    /// not a cell.
    static func tableCellSlices(in line: Substring) -> [Substring]? {
        let trimmed = line.trimmingMarkdownWhitespace()
        guard trimmed.contains("|") else { return nil }

        var cells: [Substring] = []
        var cellStart = trimmed.startIndex
        var isEscaped = false
        var index = trimmed.startIndex

        while index < trimmed.endIndex {
            let ch = trimmed[index]
            if isEscaped {
                isEscaped = false
            } else if ch == "\\" {
                isEscaped = true
            } else if ch == "|" {
                cells.append(trimmed[cellStart..<index].trimmingMarkdownWhitespace())
                cellStart = trimmed.index(after: index)
            }
            index = trimmed.index(after: index)
        }
        cells.append(trimmed[cellStart...].trimmingMarkdownWhitespace())

        if let first = cells.first, tableCellText(first).isEmpty {
            cells.removeFirst()
        }
        if let last = cells.last, tableCellText(last).isEmpty {
            cells.removeLast()
        }

        guard !cells.isEmpty else { return nil }
        return cells
    }

    /// A cell's text as the renderer is given it: the cell without the
    /// backslashes that escape something.
    private static func tableCellText(_ cell: Substring) -> String {
        var text = ""
        var isEscaped = false
        for ch in cell {
            if isEscaped {
                text.append(ch)
                isEscaped = false
            } else if ch == "\\" {
                isEscaped = true
            } else {
                text.append(ch)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func parseDelimiterRow(_ line: String) -> [MarkdownTableAlignment]? {
        guard let cells = parseTableRow(line) else { return nil }
        var alignments: [MarkdownTableAlignment] = []
        alignments.reserveCapacity(cells.count)

        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let startsWithColon = trimmed.hasPrefix(":")
            let endsWithColon = trimmed.hasSuffix(":")

            let core = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }

            if startsWithColon && endsWithColon {
                alignments.append(.center)
            } else if endsWithColon {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }
        return alignments
    }
}

extension Character {
    /// A space, a tab, or one of the other characters `CharacterSet.whitespaces`
    /// holds. A line ending is not one.
    var isMarkdownWhitespace: Bool {
        unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains)
    }
}

extension Substring {
    /// This stretch of text without the whitespace at either end, still as a
    /// stretch of the string it came from.
    func trimmingMarkdownWhitespace() -> Substring {
        var trimmed = self
        while let first = trimmed.first, first.isMarkdownWhitespace {
            trimmed = trimmed.dropFirst()
        }
        while let last = trimmed.last, last.isMarkdownWhitespace {
            trimmed = trimmed.dropLast()
        }
        return trimmed
    }
}
