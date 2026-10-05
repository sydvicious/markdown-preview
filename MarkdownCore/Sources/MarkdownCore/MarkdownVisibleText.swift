//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

/// A piece of inline text the reader sees, and the stretch of inline source it
/// came from. See `MarkdownHTMLBuilder.inlineRuns(in:)`.
public struct MarkdownInlineRun {
    /// The stretch of the inline source this came from.
    public var source: Range<String.Index>
    /// What the reader sees in its place — the `&` of `&amp;`, the line break
    /// of a hard break — or nil when they see the source itself, character for
    /// character.
    public var replacement: String?
    /// Whether this is an image's description, which is an attribute of the
    /// image rather than text in the page.
    public var isImageDescription: Bool

    public init(source: Range<String.Index>, replacement: String? = nil, isImageDescription: Bool = false) {
        self.source = source
        self.replacement = replacement
        self.isImageDescription = isImageDescription
    }
}

/// The text of a markdown document as the reader sees it, with a record of
/// which characters of the source each stretch of it came from.
///
/// Find and selection run on this: a search looks through `text`, and `runs`
/// turns a place in it back into a place in the source, or the reverse.
///
/// Nothing here decides for itself what is markup. Blocks come from
/// `MarkdownBlockParser`, where a line's content sits in the line comes from
/// the parser's own line rules, and inline text comes from the pass that writes
/// the HTML. An earlier version parsed inline markup separately, and wherever
/// the two parsers differed a search match was highlighted in the wrong place.
public struct MarkdownVisibleText {
    /// A stretch of `text` and the stretch of source it came from, both as
    /// UTF-16 ranges. The two are the same length when the reader sees the
    /// source as written.
    public struct Run: Equatable {
        public let sourceRange: MarkdownSelectionRange
        public let displayRange: MarkdownSelectionRange
    }

    public let text: String
    public let runs: [Run]

    /// - Parameters:
    ///   - elementSeparator: What goes between the pieces of one block that are
    ///     separate elements in the page: the items of a list, the blocks
    ///     inside a quote. The page has nothing between them, so the preview's
    ///     offsets want the empty string; a search wants a line break, so that
    ///     the end of one item and the start of the next are not one word.
    ///   - includesImageDescriptions: Whether an image's description counts as
    ///     text. It is not text in the page.
    public init(source: String, elementSeparator: String = "\n", includesImageDescriptions: Bool = true) {
        var builder = Builder(
            source: source,
            elementSeparator: elementSeparator,
            includesImageDescriptions: includesImageDescriptions
        )
        builder.appendBlocks(
            MarkdownBlockParser.parse(source),
            lines: source.markdownLineSlices,
            separator: "\n"
        )
        text = builder.text
        runs = builder.runs
    }
}

private struct Builder {
    let source: String
    let elementSeparator: String
    let includesImageDescriptions: Bool

    var text = ""
    var runs: [MarkdownVisibleText.Run] = []
    private var displayOffset = 0

    init(source: String, elementSeparator: String, includesImageDescriptions: Bool) {
        self.source = source
        self.elementSeparator = elementSeparator
        self.includesImageDescriptions = includesImageDescriptions
    }

    /// Inline content assembled from the source, the way the parser assembles a
    /// block's text: stretches of the source, with here and there a character
    /// that stands for something else in it — the newline that joins two lines
    /// of a paragraph, the pipe of an escaped pipe.
    private enum Piece {
        case source(Substring)
        case literal(String, standingFor: Range<Int>)
    }

    // MARK: - Blocks

    /// Appends `blocks`, which were parsed from `lines`. Each line is a stretch
    /// of the source, so a block inside a quote — parsed from the quote's lines
    /// with their markers taken off — still knows where in the source it is.
    mutating func appendBlocks(_ blocks: [MarkdownBlock], lines: [Substring], separator: String) {
        var previousEnd: Int?

        for block in blocks {
            guard block.lineRange.lowerBound >= 0,
                  block.lineRange.upperBound <= lines.count,
                  !block.lineRange.isEmpty else { continue }
            let blockLines = lines[block.lineRange]
            let blockStart = offset(of: blockLines[blockLines.startIndex].startIndex)
            let blockEnd = offset(of: blockLines[blockLines.endIndex - 1].endIndex)

            if let previousEnd, !text.isEmpty, blockStart > previousEnd {
                append(separator, from: previousEnd..<blockStart)
            }

            append(block, lines: blockLines)
            previousEnd = blockEnd
        }
    }

    private mutating func append(_ block: MarkdownBlock, lines: ArraySlice<Substring>) {
        switch block.kind {
        case .heading:
            appendHeading(lines)
        case .paragraph:
            appendParagraph(lines)
        case .list, .orderedList:
            appendList(lines)
        case .table:
            appendTable(lines)
        case .blockquote:
            appendBlockquote(lines)
        case .rule:
            break
        case .code:
            appendCodeBlock(lines)
        }
    }

    private mutating func appendHeading(_ lines: ArraySlice<Substring>) {
        guard let first = lines.first else { return }

        // An ATX heading is one line. A setext heading is the lines above its
        // underline, joined as the parser joins them.
        if lines.count == 1 {
            if let heading = MarkdownBlockParser.headingContent(in: first) {
                appendInline([.source(heading.content)])
            }
            return
        }

        appendInline(joined(lines.dropLast().map(MarkdownBlockParser.paragraphLineContent)))
    }

    private mutating func appendParagraph(_ lines: ArraySlice<Substring>) {
        var contents = lines.map(MarkdownBlockParser.paragraphLineContent)

        // The parser trims the paragraph as a whole, which takes the trailing
        // whitespace off its last line.
        if let first = contents.first {
            contents[0] = first.drop(while: Self.isTrimmedFromParagraph)
        }
        if var last = contents.last {
            while let character = last.last, Self.isTrimmedFromParagraph(character) {
                last = last.dropLast()
            }
            contents[contents.count - 1] = last
        }

        appendInline(joined(contents))
    }

    private static func isTrimmedFromParagraph(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    private mutating func appendList(_ lines: ArraySlice<Substring>) {
        var previousEnd: Int?

        for line in lines {
            // A blank line in a loose list is not an item.
            guard let content = MarkdownBlockParser.listItemContent(in: line) else { continue }

            if let previousEnd {
                append(elementSeparator, from: previousEnd..<offset(of: content.startIndex))
            }
            appendInline([.source(content)])
            previousEnd = offset(of: line.endIndex)
        }
    }

    private mutating func appendTable(_ lines: ArraySlice<Substring>) {
        guard lines.count >= 3,
              let header = lines.first,
              let headerCells = MarkdownBlockParser.tableCellSlices(in: header) else { return }

        // The second line is the delimiter row, which renders as nothing. A row
        // with more cells than the header loses the extra ones.
        for line in [header] + lines.dropFirst(2) {
            guard let cells = MarkdownBlockParser.tableCellSlices(in: line) else { continue }
            for cell in cells.prefix(headerCells.count) {
                appendInline(tableCellPieces(cell))
            }
        }
    }

    /// A cell's text, in which `\|` is a pipe.
    private func tableCellPieces(_ cell: Substring) -> [Piece] {
        var pieces: [Piece] = []
        var pieceStart = cell.startIndex
        var index = cell.startIndex

        while index < cell.endIndex {
            guard cell[index] == "\\" else {
                index = cell.index(after: index)
                continue
            }
            let escaped = cell.index(after: index)
            guard escaped < cell.endIndex else { break }
            let afterEscaped = cell.index(after: escaped)

            if cell[escaped] == "|" {
                if pieceStart < index {
                    pieces.append(.source(cell[pieceStart..<index]))
                }
                pieces.append(.literal("|", standingFor: offset(of: index)..<offset(of: afterEscaped)))
                pieceStart = afterEscaped
            }
            index = afterEscaped
        }

        if pieceStart < cell.endIndex {
            pieces.append(.source(cell[pieceStart...]))
        }
        return pieces
    }

    private mutating func appendBlockquote(_ lines: ArraySlice<Substring>) {
        // What a quote holds is a document of its own: its lines without their
        // markers. That is how the parser reads it, and each of those lines is
        // still a stretch of the source.
        let quoted = lines.compactMap(MarkdownBlockParser.blockquoteContent)
        guard quoted.count == lines.count else { return }

        appendBlocks(
            MarkdownBlockParser.parse(quoted.joined(separator: "\n")),
            lines: quoted,
            separator: elementSeparator
        )
    }

    private mutating func appendCodeBlock(_ lines: ArraySlice<Substring>) {
        guard let opening = lines.first else { return }

        // The first line is the opening fence. The last is the closing one,
        // unless the block runs to the end of the document without one.
        var codeLines = lines.dropFirst()
        if let last = codeLines.last, MarkdownBlockParser.fence(opening, isClosedBy: last) {
            codeLines = codeLines.dropLast()
        }

        var previousEnd: Int?
        for line in codeLines {
            if let previousEnd {
                append("\n", from: previousEnd..<offset(of: line.startIndex))
            }
            append(String(line), from: offset(of: line.startIndex)..<offset(of: line.endIndex))
            previousEnd = offset(of: line.endIndex)
        }
    }

    /// Lines of text joined into one, with a newline standing for whatever lies
    /// between the end of one and the start of the next: the line ending, and
    /// the indentation the parser dropped.
    private func joined(_ lines: [Substring]) -> [Piece] {
        var pieces: [Piece] = []
        var previousEnd: Int?

        for line in lines {
            if let previousEnd {
                pieces.append(.literal("\n", standingFor: previousEnd..<offset(of: line.startIndex)))
            }
            pieces.append(.source(line))
            previousEnd = offset(of: line.endIndex)
        }
        return pieces
    }

    // MARK: - Inline

    /// One stretch of the text handed to the inline pass, and the source it
    /// stands for.
    private struct Segment {
        let inlineRange: Range<Int>
        let sourceRange: Range<Int>
        /// Whether the inline text here is the source, character for character.
        let isSource: Bool
        let literal: String
    }

    private mutating func appendInline(_ pieces: [Piece]) {
        // The usual case is one stretch of the source — a heading, a list item,
        // a table cell, a paragraph of one line — which the inline pass can
        // read where it lies.
        if pieces.count == 1, case let .source(content) = pieces[0] {
            for run in MarkdownHTMLBuilder.inlineRuns(in: content) where includes(run) {
                let sourceRange = offset(of: run.source.lowerBound)..<offset(of: run.source.upperBound)
                append(run.replacement ?? String(source[run.source]), from: sourceRange)
            }
            return
        }

        var inlineText = ""
        var segments: [Segment] = []
        var inlineOffset = 0

        for piece in pieces {
            switch piece {
            case let .source(content):
                let length = content.utf16.count
                guard length > 0 else { continue }
                let start = offset(of: content.startIndex)
                inlineText += content
                segments.append(
                    Segment(
                        inlineRange: inlineOffset..<(inlineOffset + length),
                        sourceRange: start..<(start + length),
                        isSource: true,
                        literal: ""
                    )
                )
                inlineOffset += length
            case let .literal(literal, sourceRange):
                let length = literal.utf16.count
                inlineText += literal
                segments.append(
                    Segment(
                        inlineRange: inlineOffset..<(inlineOffset + length),
                        sourceRange: sourceRange,
                        isSource: false,
                        literal: literal
                    )
                )
                inlineOffset += length
            }
        }

        for run in MarkdownHTMLBuilder.inlineRuns(in: inlineText[...]) where includes(run) {
            let inlineRange = run.source.lowerBound.utf16Offset(in: inlineText)
                ..< run.source.upperBound.utf16Offset(in: inlineText)

            if let replacement = run.replacement {
                append(replacement, from: sourceRange(forInlineRange: inlineRange, in: segments))
                continue
            }

            // Shown as written, so each stretch of it maps onto the source one
            // character for one — except where a character stands for something
            // else, which maps onto all of what it stands for.
            for segment in segments where segment.inlineRange.overlaps(inlineRange) {
                if segment.isSource {
                    let overlap = segment.inlineRange.clamped(to: inlineRange)
                    let start = segment.sourceRange.lowerBound + (overlap.lowerBound - segment.inlineRange.lowerBound)
                    let range = start..<(start + overlap.count)
                    append(sourceText(in: range), from: range)
                } else {
                    append(segment.literal, from: segment.sourceRange)
                }
            }
        }
    }

    private func includes(_ run: MarkdownInlineRun) -> Bool {
        includesImageDescriptions || !run.isImageDescription
    }

    /// The source a stretch of inline text came from, from the start of what its
    /// first character stands for to the end of what its last one does.
    private func sourceRange(forInlineRange inlineRange: Range<Int>, in segments: [Segment]) -> Range<Int> {
        var start: Int?
        var end: Int?

        for segment in segments where segment.inlineRange.overlaps(inlineRange) {
            let overlap = segment.inlineRange.clamped(to: inlineRange)
            let overlapStart = segment.isSource
                ? segment.sourceRange.lowerBound + (overlap.lowerBound - segment.inlineRange.lowerBound)
                : segment.sourceRange.lowerBound
            let overlapEnd = segment.isSource
                ? segment.sourceRange.lowerBound + (overlap.upperBound - segment.inlineRange.lowerBound)
                : segment.sourceRange.upperBound

            start = start ?? overlapStart
            end = overlapEnd
        }

        guard let start, let end, end >= start else { return 0..<0 }
        return start..<end
    }

    // MARK: - Appending

    /// Appends `shown`, recording that it came from `sourceRange`. Appending
    /// nothing records nothing.
    private mutating func append(_ shown: String, from sourceRange: Range<Int>) {
        guard !shown.isEmpty else { return }
        let length = shown.utf16.count

        text += shown
        runs.append(
            MarkdownVisibleText.Run(
                sourceRange: MarkdownSelectionRange(location: sourceRange.lowerBound, length: sourceRange.count),
                displayRange: MarkdownSelectionRange(location: displayOffset, length: length)
            )
        )
        displayOffset += length
    }

    private func offset(of index: String.Index) -> Int {
        index.utf16Offset(in: source)
    }

    private func sourceText(in range: Range<Int>) -> String {
        let start = String.Index(utf16Offset: range.lowerBound, in: source)
        let end = String.Index(utf16Offset: range.upperBound, in: source)
        return String(source[start..<end])
    }
}
