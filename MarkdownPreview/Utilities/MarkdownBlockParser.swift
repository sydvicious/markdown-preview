//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

struct MarkdownTable: Equatable {
    let headers: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
}

enum MarkdownTableAlignment: Equatable {
    case leading
    case center
    case trailing
}

struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list([MarkdownListItem])
        case orderedList([MarkdownListItem])
        case table(MarkdownTable)
        case blockquote(String)
        case rule
        case code(String)
    }

    let id = UUID()
    let kind: Kind
    let lineRange: Range<Int>
}

struct MarkdownListItem: Identifiable {
    let id = UUID()
    let text: String
    let indent: Int
    let checkbox: Bool?
    let order: Int?
}

struct MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var paragraphStartLine: Int?
        var listItems: [MarkdownListItem] = []
        var listStartLine: Int?
        var orderedListItems: [MarkdownListItem] = []
        var orderedListStartLine: Int?
        var quoteLines: [String] = []
        var quoteStartLine: Int?
        var code: [String] = []
        var codeStartLine: Int?
        var inCodeFence = false

        func flushParagraph(currentLine: Int) {
            guard !paragraph.isEmpty, let start = paragraphStartLine else { return }
            blocks.append(
                .init(
                    kind: .paragraph(paragraph.joined(separator: " ")),
                    lineRange: start..<currentLine
                )
            )
            paragraph.removeAll()
            paragraphStartLine = nil
        }

        func flushList(currentLine: Int) {
            guard !listItems.isEmpty, let start = listStartLine else { return }
            blocks.append(
                .init(
                    kind: .list(listItems),
                    lineRange: start..<currentLine
                )
            )
            listItems.removeAll()
            listStartLine = nil
        }

        func flushOrderedList(currentLine: Int) {
            guard !orderedListItems.isEmpty, let start = orderedListStartLine else { return }
            blocks.append(
                .init(
                    kind: .orderedList(orderedListItems),
                    lineRange: start..<currentLine
                )
            )
            orderedListItems.removeAll()
            orderedListStartLine = nil
        }

        func flushQuote(currentLine: Int) {
            guard !quoteLines.isEmpty, let start = quoteStartLine else { return }
            blocks.append(
                .init(
                    kind: .blockquote(quoteLines.joined(separator: "\n")),
                    lineRange: start..<currentLine
                )
            )
            quoteLines.removeAll()
            quoteStartLine = nil
        }

        func flushAll(currentLine: Int) {
            flushParagraph(currentLine: currentLine)
            flushList(currentLine: currentLine)
            flushOrderedList(currentLine: currentLine)
            flushQuote(currentLine: currentLine)
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]

            if line.hasPrefix("```") {
                flushAll(currentLine: index)
                if inCodeFence {
                    blocks.append(
                        .init(
                            kind: .code(code.joined(separator: "\n")),
                            lineRange: (codeStartLine ?? index)..<index
                        )
                    )
                    code.removeAll()
                    codeStartLine = nil
                } else {
                    codeStartLine = index + 1
                }
                inCodeFence.toggle()
                index += 1
                continue
            }

            if inCodeFence {
                code.append(line)
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushAll(currentLine: index)
                index += 1
                continue
            }

            if let setextHeading = parseSetextHeading(from: lines, startIndex: index) {
                flushAll(currentLine: index)
                blocks.append(
                    .init(
                        kind: .heading(level: setextHeading.level, text: setextHeading.text),
                        lineRange: index..<(index + 2)
                    )
                )
                index += 2
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

            if let heading = parseHeading(line) {
                flushAll(currentLine: index)
                blocks.append(
                    .init(
                        kind: .heading(level: heading.level, text: heading.text),
                        lineRange: index..<(index + 1)
                    )
                )
                index += 1
                continue
            }

            if let item = parseListItem(line) {
                flushParagraph(currentLine: index)
                flushOrderedList(currentLine: index)
                flushQuote(currentLine: index)
                if listStartLine == nil {
                    listStartLine = index
                }
                listItems.append(item)
                index += 1
                continue
            }

            if let item = parseOrderedListItem(line) {
                flushParagraph(currentLine: index)
                flushList(currentLine: index)
                flushQuote(currentLine: index)
                if orderedListStartLine == nil {
                    orderedListStartLine = index
                }
                orderedListItems.append(item)
                index += 1
                continue
            }

            if let quote = parseBlockquote(line) {
                flushParagraph(currentLine: index)
                flushList(currentLine: index)
                flushOrderedList(currentLine: index)
                if quoteStartLine == nil {
                    quoteStartLine = index
                }
                quoteLines.append(quote)
                index += 1
                continue
            }

            if parseRule(line) {
                flushAll(currentLine: index)
                blocks.append(.init(kind: .rule, lineRange: index..<(index + 1)))
                index += 1
                continue
            }

            flushList(currentLine: index)
            flushOrderedList(currentLine: index)
            flushQuote(currentLine: index)
            if paragraphStartLine == nil {
                paragraphStartLine = index
            }
            paragraph.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }

        flushAll(currentLine: lines.count)
        if !code.isEmpty {
            blocks.append(
                .init(
                    kind: .code(code.joined(separator: "\n")),
                    lineRange: (codeStartLine ?? lines.count)..<lines.count
                )
            )
        }
        return blocks
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }
        let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private static func parseSetextHeading(from lines: [String], startIndex: Int) -> (level: Int, text: String)? {
        guard startIndex + 1 < lines.count else { return nil }
        let textLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        guard !textLine.isEmpty else { return nil }

        let underlineLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard !underlineLine.isEmpty else { return nil }
        guard underlineLine.count >= 3 else { return nil }

        if underlineLine.allSatisfy({ $0 == "=" }) {
            return (1, textLine)
        }
        if underlineLine.allSatisfy({ $0 == "-" }) {
            return (2, textLine)
        }
        return nil
    }

    private static func parseListItem(_ line: String) -> MarkdownListItem? {
        let indent = indentLevel(in: line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        let first = trimmed.first
        guard first == "-" || first == "*" || first == "+" else { return nil }
        guard trimmed.dropFirst().first == " " else { return nil }
        let rawText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        let (text, checkbox) = parseCheckbox(rawText)
        return MarkdownListItem(text: text, indent: indent, checkbox: checkbox, order: nil)
    }

    private static func parseOrderedListItem(_ line: String) -> MarkdownListItem? {
        let indent = indentLevel(in: line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let number = trimmed[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        let afterDot = trimmed[trimmed.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        let rawText = String(afterDot.dropFirst()).trimmingCharacters(in: .whitespaces)
        let (text, checkbox) = parseCheckbox(rawText)
        return MarkdownListItem(
            text: text,
            indent: indent,
            checkbox: checkbox,
            order: Int(number)
        )
    }

    private static func parseBlockquote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == ">" else { return nil }
        let remaining = trimmed.dropFirst()
        return String(remaining.first == " " ? remaining.dropFirst() : remaining)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func parseRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let chars = Array(trimmed)
        guard chars.count >= 3 else { return false }
        let allowed = chars.filter { $0 == "-" || $0 == "*" || $0 == "_" }
        return allowed.count == chars.count && Set(chars).count == 1
    }

    private static func indentLevel(in line: String) -> Int {
        var width = 0
        for ch in line {
            if ch == " " {
                width += 1
            } else if ch == "\t" {
                width += 4
            } else {
                break
            }
        }
        return max(0, width / 2)
    }

    private static func parseCheckbox(_ text: String) -> (String, Bool?) {
        if text.hasPrefix("[ ] ") {
            return (String(text.dropFirst(4)), false)
        }
        if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
            return (String(text.dropFirst(4)), true)
        }
        return (text, nil)
    }

    private static func parseTable(from lines: [String], startIndex: Int) -> (table: MarkdownTable, nextIndex: Int)? {
        guard startIndex + 2 < lines.count else { return nil }
        guard let headers = parseTableRow(lines[startIndex]) else { return nil }
        guard let alignments = parseDelimiterRow(lines[startIndex + 1]) else { return nil }
        guard headers.count == alignments.count else { return nil }
        guard headers.count >= 2 else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            guard let row = parseTableRow(line), row.count == headers.count else {
                break
            }
            rows.append(row)
            index += 1
        }

        // If body rows are missing, treat these lines as plain text.
        guard !rows.isEmpty else { return nil }
        return (MarkdownTable(headers: headers, alignments: alignments, rows: rows), index)
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }

        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for ch in trimmed {
            if isEscaped {
                current.append(ch)
                isEscaped = false
                continue
            }
            if ch == "\\" {
                isEscaped = true
                continue
            }
            if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))

        if cells.first?.isEmpty == true {
            cells.removeFirst()
        }
        if cells.last?.isEmpty == true {
            cells.removeLast()
        }

        guard !cells.isEmpty else { return nil }
        return cells.map { $0.replacingOccurrences(of: "\\|", with: "|") }
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
            guard core.count >= 3, core.allSatisfy({ $0 == "-" }) else { return nil }

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
