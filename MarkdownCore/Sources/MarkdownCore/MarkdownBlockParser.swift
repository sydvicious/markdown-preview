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
    /// What marks the item: its bullet character, or for a numbered item the
    /// delimiter after the number. Items side by side with different markers
    /// are in different lists.
    public let marker: Character
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
    /// The bullet character, or the delimiter after a number.
    let marker: Character
    /// An item with nothing after its marker.
    var isEmpty: Bool { content.isEmpty && checkbox == nil }
    /// Column the list marker starts at.
    let markerColumn: Int
    /// Column the item's text starts at; a following line indented at least
    /// this far is a child of this item.
    let contentColumn: Int
}

public struct MarkdownBlockParser {
    /// The blocks of `source`. Its link reference definitions are read and set
    /// aside; `parseDocument` returns them as well.
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var definitions = MarkdownLinkDefinitions()
        return parse(source, definitions: &definitions)
    }

    /// The blocks of `source`, and the link reference definitions found
    /// anywhere in it — inside a block quote included — which a reference
    /// anywhere else in the document may use.
    public static func parseDocument(_ source: String) -> (blocks: [MarkdownBlock], definitions: MarkdownLinkDefinitions) {
        var definitions = MarkdownLinkDefinitions()
        let blocks = parse(source, definitions: &definitions)
        return (blocks, definitions)
    }

    private static func parse(_ source: String, definitions: inout MarkdownLinkDefinitions) -> [MarkdownBlock] {
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
        // A blank line has gone by since the last item. Whether that makes the
        // list loose depends on whether the next item is another of its own.
        var blankLineSinceLastItem = false
        var quoteLines: [String] = []
        var quoteStartLine: Int?
        var code: [String] = []
        var codeContentStartLine: Int?
        var codeFenceStartLine: Int?
        var inCodeFence = false
        var fenceMarker: Character?
        var fenceLength = 0
        var fenceIndent = 0
        var fenceLanguage: String?

        /// Takes any link reference definitions off the front of the open
        /// paragraph. They are not part of it: they render as nothing, and the
        /// paragraph, if anything is left, starts on the line after them.
        func takeLeadingDefinitions() {
            while let definition = linkDefinition(atStartOf: paragraph[...]) {
                definitions.define(definition.label, destination: definition.destination, title: definition.title)
                paragraph.removeFirst(definition.lineCount)
                paragraphStartLine = paragraphStartLine.map { $0 + definition.lineCount }
            }
            if paragraph.isEmpty {
                paragraphStartLine = nil
            }
        }

        func flushParagraph(currentLine: Int) {
            takeLeadingDefinitions()
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
            blankLineSinceLastItem = false
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

            // A different marker at the top level starts a separate list: a
            // numbered item after bulleted ones, but also `+` after `-`, or `2)`
            // after `1.`. Deeper down the items stay in this block, and the
            // renderer splits them into lists by their markers.
            if depth == 0, let first = listItems.first, first.marker != parsed.marker {
                flushList(currentLine: index)
                openLevels = [(parsed.markerColumn, parsed.contentColumn)]
            }

            // A blank line between two items of one list makes it loose. One
            // between the end of a list and the start of the next does not.
            if blankLineSinceLastItem, !listItems.isEmpty {
                listIsLoose = true
            }
            blankLineSinceLastItem = false

            if listStartLine == nil {
                listStartLine = index
            }

            listItems.append(
                MarkdownListItem(
                    text: parsed.text,
                    indent: depth,
                    checkbox: parsed.checkbox,
                    order: parsed.order,
                    isOrdered: parsed.isOrdered,
                    marker: parsed.marker
                )
            )
        }

        func flushQuote(currentLine: Int) {
            guard !quoteLines.isEmpty, let start = quoteStartLine else { return }
            blocks.append(
                .init(
                    // Parsed recursively: the stripped content is itself a
                    // document, which is how quotes nest and hold other blocks.
                    kind: .blockquote(parse(quoteLines.joined(separator: "\n"), definitions: &definitions)),
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
                    code.append(String(codeLineContent(in: line[...], fenceIndent: fenceIndent)))
                }
                index += 1
                continue
            }

            if let fence = parseCodeFence(line) {
                flushAll(currentLine: index)
                inCodeFence = true
                fenceMarker = fence.marker
                fenceLength = fence.length
                fenceIndent = Self.fenceIndent(of: line[...])
                // Only the first word of the info string names the language.
                fenceLanguage = fence.info.split(separator: " ").first.map(String.init)
                codeFenceStartLine = index
                codeContentStartLine = index + 1
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // A blank line inside a list does not end it if another item
                // follows. If that item turns out to be one of this list's own,
                // the list is loose, and every item's content is then wrapped
                // in a paragraph.
                if !listItems.isEmpty, nextNonBlankLineContinuesList(lines, after: index) {
                    blankLineSinceLastItem = true
                    index += 1
                    continue
                }

                flushAll(currentLine: index)
                index += 1
                continue
            }

            // A setext underline turns the paragraph above it into a heading, so
            // the heading's content is however many lines that paragraph had.
            if setextUnderlineLevel(line) != nil, !paragraph.isEmpty {
                // Definitions come off first. If they were all there was, there
                // is nothing to underline and this line is ordinary text.
                takeLeadingDefinitions()
            }
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

            // Not everything that looks like an item may interrupt a paragraph:
            // an empty item may not, and a numbered one only if it starts at 1.
            // Otherwise a wrapped sentence whose next line happens to begin
            // "14." would turn into a list.
            if let item = parseListItem(line[...]) ?? parseOrderedListItem(line[...]),
               paragraph.isEmpty || (!item.isEmpty && (!item.isOrdered || item.order == 1)) {
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

    /// A link reference definition at the start of a paragraph's lines:
    /// `[label]: destination`, with an optional title in quotes or parentheses.
    ///
    /// The destination may be on the line after the label, and the title on the
    /// line after the destination. Anything else after the title means the line
    /// is not a definition at all; a following line that is not a whole title is
    /// just the next line of text.
    private static func linkDefinition(
        atStartOf lines: ArraySlice<String>
    ) -> (label: Substring, destination: String, title: String?, lineCount: Int)? {
        guard let first = lines.first else { return nil }
        let line = first.drop { $0 == " " || $0 == "\t" }
        guard line.first == "[" else { return nil }

        // The label runs to the first bracket that is not escaped, and may not
        // hold one that opens.
        var index = line.index(after: line.startIndex)
        let labelStart = index
        var labelEnd: Substring.Index?
        while index < line.endIndex {
            let character = line[index]
            if character == "\\" {
                let next = line.index(after: index)
                index = next < line.endIndex ? line.index(after: next) : next
                continue
            }
            if character == "[" { return nil }
            if character == "]" {
                labelEnd = index
                break
            }
            index = line.index(after: index)
        }
        guard let labelEnd else { return nil }
        let label = line[labelStart..<labelEnd]
        guard MarkdownLinkDefinitions.normalized(label) != nil else { return nil }

        let afterLabel = line.index(after: labelEnd)
        guard afterLabel < line.endIndex, line[afterLabel] == ":" else { return nil }

        var lineCount = 1
        var rest = line[line.index(after: afterLabel)...].trimmingMarkdownWhitespace()
        if rest.isEmpty {
            guard lines.count > 1 else { return nil }
            rest = lines[lines.startIndex + 1][...].trimmingMarkdownWhitespace()
            lineCount = 2
        }

        let destination: String
        let afterDestination: Substring
        if rest.first == "<" {
            guard let close = rest.dropFirst().firstIndex(where: { $0 == ">" || $0 == "<" }), rest[close] == ">" else {
                return nil
            }
            destination = String(rest[rest.index(after: rest.startIndex)..<close])
            afterDestination = rest[rest.index(after: close)...]
        } else {
            let end = rest.firstIndex(where: \.isMarkdownWhitespace) ?? rest.endIndex
            destination = String(rest[..<end])
            afterDestination = rest[end...]
            guard !destination.isEmpty else { return nil }
        }
        let encodedDestination = destination.replacingOccurrences(of: " ", with: "%20")

        let afterWhitespace = afterDestination.trimmingMarkdownWhitespace()
        if !afterWhitespace.isEmpty {
            // On the same line, what follows has to be a title and nothing else,
            // with whitespace before it.
            guard afterDestination.first?.isMarkdownWhitespace == true,
                  let title = linkDefinitionTitle(afterWhitespace) else { return nil }
            return (label, encodedDestination, title, lineCount)
        }

        if lines.count > lineCount,
           let title = linkDefinitionTitle(lines[lines.startIndex + lineCount][...].trimmingMarkdownWhitespace()) {
            return (label, encodedDestination, title, lineCount + 1)
        }
        return (label, encodedDestination, nil, lineCount)
    }

    /// The text of a title, if `text` is one and nothing more: quoted with
    /// either kind of quote, or in parentheses.
    private static func linkDefinitionTitle(_ text: Substring) -> String? {
        guard text.count >= 2, let opening = text.first, let last = text.last else { return nil }
        let closing: Character
        switch opening {
        case "\"": closing = "\""
        case "'": closing = "'"
        case "(": closing = ")"
        default: return nil
        }
        guard last == closing else { return nil }

        var title = ""
        var isEscaped = false
        for character in text.dropFirst().dropLast() {
            if isEscaped {
                title.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == closing || (opening == "(" && character == "(") {
                // The title ended before the end of the text.
                return nil
            } else {
                title.append(character)
            }
        }
        return isEscaped ? nil : title
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

    /// How many spaces the opening line of a fenced code block is indented by.
    static func fenceIndent(of opening: Substring) -> Int {
        opening.prefix { $0 == " " }.count
    }

    /// A line inside a fenced code block as code: the line without the
    /// indentation it shares with the fence. A block indented to sit under a
    /// list item is not indented code.
    static func codeLineContent(in line: Substring, fenceIndent: Int) -> Substring {
        var content = line
        var removed = 0
        while removed < fenceIndent, content.first == " " {
            content = content.dropFirst()
            removed += 1
        }
        return content
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
        guard let marker = trimmed.first, marker == "-" || marker == "*" || marker == "+" else { return nil }
        // The marker is followed by a space or a tab, or by nothing at all,
        // which is an empty item.
        let afterMarker = trimmed.dropFirst()
        guard afterMarker.isEmpty || afterMarker.first == " " || afterMarker.first == "\t" else { return nil }
        let (content, checkbox) = parseCheckbox(afterMarker.trimmingMarkdownWhitespace())
        return ParsedListItem(
            content: content,
            checkbox: checkbox,
            order: nil,
            isOrdered: false,
            marker: marker,
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
        guard afterDot.isEmpty || afterDot.first == " " || afterDot.first == "\t" else { return nil }
        let (content, checkbox) = parseCheckbox(afterDot.trimmingMarkdownWhitespace())
        return ParsedListItem(
            content: content,
            checkbox: checkbox,
            order: Int(number),
            isOrdered: true,
            marker: trimmed[delimiterIndex],
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

    /// A cell's text as the renderer is given it. `\|` is a pipe: that escape is
    /// the table's, there so a cell can hold one. Every other backslash is the
    /// cell's own content and is left for the inline pass, so `\*` is still an
    /// escaped asterisk and a backslash in a code span is still a backslash.
    private static func tableCellText(_ cell: Substring) -> String {
        var text = ""
        var index = cell.startIndex

        while index < cell.endIndex {
            let ch = cell[index]
            let next = cell.index(after: index)
            if ch == "\\", next < cell.endIndex {
                if cell[next] != "|" {
                    text.append(ch)
                }
                text.append(cell[next])
                index = cell.index(after: next)
            } else {
                text.append(ch)
                index = next
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

/// The link reference definitions of a document: `[label]: destination "title"`
/// lines, which render as nothing and give `[text][label]`, `[text][]` and
/// `[label]` somewhere to point.
public struct MarkdownLinkDefinitions: Sendable {
    public struct Target: Sendable {
        public let destination: String
        public let title: String?
    }

    private var targets: [String: Target] = [:]

    /// No definitions at all.
    public static let none = MarkdownLinkDefinitions()

    public init() {}

    /// The definitions in `source`.
    public init(source: String) {
        // A definition has to have "]:" in it, and most documents have none, so
        // most documents are not parsed for this.
        guard source.contains("]:") else { return }
        self = MarkdownBlockParser.parseDocument(source).definitions
    }

    public var isEmpty: Bool { targets.isEmpty }

    /// What `label` refers to. Labels match without regard to case, or to how
    /// the whitespace inside them is written.
    public func target(for label: Substring) -> Target? {
        guard !targets.isEmpty, let key = Self.normalized(label) else { return nil }
        return targets[key]
    }

    /// Records a definition. The first one for a label is the one that counts.
    mutating func define(_ label: Substring, destination: String, title: String?) {
        guard let key = Self.normalized(label), targets[key] == nil else { return }
        targets[key] = Target(destination: destination, title: title)
    }

    /// Adds `other`'s definitions for labels this does not already define.
    public func merging(_ other: MarkdownLinkDefinitions) -> MarkdownLinkDefinitions {
        guard !other.targets.isEmpty else { return self }
        var merged = self
        merged.targets.merge(other.targets) { mine, _ in mine }
        return merged
    }

    /// A label as it is compared: case folded, with each run of whitespace
    /// inside it as one space and none at its ends. Nil if nothing is left.
    static func normalized(_ label: Substring) -> String? {
        let words = label.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, label.count <= 999 else { return nil }
        return words.joined(separator: " ").folding(options: [.caseInsensitive], locale: nil)
    }
}
