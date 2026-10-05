//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

public enum MarkdownHTMLBuilder {
    /// How a soft line break — an ordinary line ending inside a paragraph — is
    /// rendered.
    ///
    /// CommonMark says a soft break is a newline in the output and nothing more,
    /// so two source lines flow together as one line on screen. GitHub renders
    /// its comment fields the other way, turning every soft break into a `<br>`
    /// ("hardbreaks") so the text lands exactly as it was typed. The core
    /// defaults to `.newline` to stay CommonMark-conformant; the app selects
    /// `.lineBreak` so a carriage return in the source is a line break in the
    /// preview.
    public enum SoftBreak: Sendable {
        /// A soft break renders as a newline (CommonMark).
        case newline
        /// A soft break renders as `<br />` (GitHub "hardbreaks").
        case lineBreak
    }

    /// Renders `source` as a standalone HTML document.
    ///
    /// `contentScale` is the Dynamic Type scale factor to apply to the
    /// document's text. It is taken as a plain number rather than a
    /// `DynamicTypeSize` so that the markdown engine stays free of SwiftUI and
    /// can be built and tested from the command line without an app host; call
    /// sites pass `textSize.scaleFactor`.
    ///
    /// `softBreak` chooses how ordinary line endings inside a paragraph render;
    /// see `SoftBreak`.
    public static func document(
        for source: String,
        contentScale: CGFloat = 1.0,
        softBreak: SoftBreak = .newline
    ) -> String {
        let sourceLineTable = MarkdownSourceLineTable(source: source)
        let renderedBlocks = MarkdownBlockParser.parse(source)
            .map { renderBlock($0, sourceLineTable: sourceLineTable, softBreak: softBreak) }
            .joined(separator: "\n")
        let body = renderedBlocks.isEmpty ? "<p class=\"empty\"></p>" : renderedBlocks

        // Only the first line of the body is indented, as it always has been:
        // the blocks are joined before they are placed, and what sits between
        // them is in the document, so nothing is added there.
        return MarkdownWebResources.documentTemplate
            .replacingOccurrences(of: "{{stylesheet}}", with: MarkdownWebResources.stylesheet)
            .replacingOccurrences(of: "{{content-scale}}", with: "\(contentScale)")
            .replacingOccurrences(of: "{{body}}", with: body)
    }

    private static func renderBlock(
        _ block: MarkdownBlock,
        sourceLineTable: MarkdownSourceLineTable,
        softBreak: SoftBreak
    ) -> String {
        let content = blockContent(block, softBreak: softBreak)
        let copyKind = copyableKind(of: block)
        let copyButton = copyKind == nil
            ? nil
            : "<button type=\"button\" class=\"md-copy-button\" data-copy-button>Copy</button>"
        // The kind rides along so the copy handler knows what the source range
        // it is handed actually is; see `MarkdownBlockCopyText`.
        let copyKindAttribute = copyKind.map { " data-copy-kind=\"\($0.rawValue)\"" } ?? ""

        guard let sourceRange = sourceLineTable.range(for: block.lineRange) else {
            return content
        }

        return """
        <div class="md-block\(copyButton == nil ? "" : " md-copyable-block")"\(copyKindAttribute) data-source-start="\(sourceRange.location)" data-source-end="\(sourceRange.location + sourceRange.length)">\(copyButton ?? "")\(content)</div>
        """
    }

    private static func copyableKind(of block: MarkdownBlock) -> MarkdownCopyableBlockKind? {
        switch block.kind {
        case .table:
            return .table
        case .blockquote:
            return .blockquote
        case .code:
            return .code
        default:
            return nil
        }
    }

    /// The block's own markup, without the `md-block` wrapper.
    ///
    /// Blocks nested inside a block quote are rendered through here rather than
    /// `renderBlock`, because the wrapper carries source offsets into the outer
    /// document and a nested block's line numbers refer to the quote's stripped
    /// content instead.
    private static func blockContent(_ block: MarkdownBlock, softBreak: SoftBreak) -> String {
        let content: String
        switch block.kind {
        case .heading(let level, let text):
            // Headings are a single source line, so no soft break ever reaches
            // here; the default rendering is correct regardless of `softBreak`.
            let clampedLevel = min(max(level, 1), 6)
            content = "<h\(clampedLevel)>\(renderInlineMarkdownHTML(text))</h\(clampedLevel)>"
        case .paragraph(let text):
            content = "<p>\(renderInlineMarkdownHTML(text, softBreak: softBreak))</p>"
        case .list(let items, let isLoose):
            content = renderList(items, ordered: false, isLoose: isLoose, softBreak: softBreak)
        case .orderedList(let items, let isLoose):
            content = renderList(items, ordered: true, isLoose: isLoose, softBreak: softBreak)
        case .table(let table):
            content = renderTable(table)
        case .blockquote(let children):
            content = "<blockquote>\(children.map { blockContent($0, softBreak: softBreak) }.joined())</blockquote>"
        case .rule:
            content = "<hr />"
        case .code(let code, let language):
            let languageClass = language.map { " class=\"language-\(escapeHTMLAttribute($0))\"" } ?? ""
            content = "<pre><code\(languageClass)>\(escapeHTML(code))</code></pre>"
        }

        return content
    }

    private static func renderList(
        _ items: [MarkdownListItem],
        ordered: Bool,
        isLoose: Bool,
        softBreak: SoftBreak
    ) -> String {
        var index = 0
        return renderListLevel(
            items,
            index: &index,
            depth: 0,
            ordered: ordered,
            isLoose: isLoose,
            softBreak: softBreak
        )
    }

    /// Emits one nesting level, recursing into deeper items so they land inside
    /// the `<li>` they belong to.
    ///
    /// The markup is deliberately emitted without any whitespace between tags:
    /// the preview's text walker accumulates display offsets over text nodes, so
    /// pretty-printing here would introduce whitespace nodes and shift every
    /// offset after the list.
    private static func renderListLevel(
        _ items: [MarkdownListItem],
        index: inout Int,
        depth: Int,
        ordered: Bool,
        isLoose: Bool,
        softBreak: SoftBreak
    ) -> String {
        let tag = ordered ? "ol" : "ul"
        var rows = ""

        while index < items.count, items[index].indent >= depth {
            let item = items[index]
            index += 1

            // Anything deeper that follows belongs inside this item.
            var nested = ""
            if index < items.count, items[index].indent > depth {
                nested = renderListLevel(
                    items,
                    index: &index,
                    depth: items[index].indent,
                    ordered: items[index].isOrdered,
                    isLoose: isLoose,
                    softBreak: softBreak
                )
            }

            if let checked = item.checkbox {
                let checkedAttribute = checked ? " checked" : ""
                rows += "<li class=\"task\"><label><input type=\"checkbox\" disabled\(checkedAttribute) /><span>\(renderInlineMarkdownHTML(item.text, softBreak: softBreak))</span></label>\(nested)</li>"
                continue
            }

            let valueAttribute: String
            if item.isOrdered, let order = item.order {
                valueAttribute = " value=\"\(order)\""
            } else {
                valueAttribute = ""
            }

            let text = renderInlineMarkdownHTML(item.text, softBreak: softBreak)
            let body = isLoose ? "<p>\(text)</p>" : text
            rows += "<li\(valueAttribute)>\(body)\(nested)</li>"
        }

        return "<\(tag)>\(rows)</\(tag)>"
    }

    private static func renderTable(_ table: MarkdownTable) -> String {
        let headerRow = table.headers.enumerated().map { index, text in
            let alignment = table.alignments[safe: index] ?? .leading
            return "<th class=\"\(alignmentClass(alignment))\">\(renderLinesAsHTML(text))</th>"
        }.joined()

        let bodyRows = table.rows.map { row in
            let cells = table.headers.indices.map { index -> String in
                let alignment = table.alignments[safe: index] ?? .leading
                let text = row[safe: index] ?? ""
                return "<td class=\"\(alignmentClass(alignment))\">\(renderLinesAsHTML(text))</td>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()

        return "<div class=\"table-wrap\"><table><thead><tr>\(headerRow)</tr></thead><tbody>\(bodyRows)</tbody></table></div>"
    }

    private static func alignmentClass(_ alignment: MarkdownTableAlignment) -> String {
        switch alignment {
        case .leading: return "a-left"
        case .center: return "a-center"
        case .trailing: return "a-right"
        }
    }

    private static func renderLinesAsHTML(_ text: String) -> String {
        // Table cells split their own lines into <br>-joined pieces, so each
        // piece has no line ending left for the soft-break option to act on; the
        // default rendering is correct here.
        text
            .components(separatedBy: "\n")
            .map { renderInlineMarkdownHTML($0) }
            .joined(separator: "<br>")
    }

    private static func renderInlineMarkdownHTML(_ text: String, softBreak: SoftBreak = .newline) -> String {
        renderInline(Substring(text), softBreak: softBreak).html
    }

    /// The text of `text` as the reader sees it once it is rendered, in order,
    /// each piece with the stretch of `text` it came from.
    ///
    /// This is the same pass that writes the HTML, reporting what it showed as
    /// it goes, so the two cannot disagree: whatever becomes a text node in the
    /// page is a run here, and markup that renders as nothing — emphasis
    /// delimiters, a link's destination, the backslash of an escape — is in no
    /// run at all. `MarkdownVisibleText` builds find and selection offsets
    /// from it.
    public static func inlineRuns(in text: Substring) -> [MarkdownInlineRun] {
        renderInline(text).runs
    }

    /// Inline content rendered: its HTML, and what of it the reader sees.
    private typealias InlineRendering = (html: String, runs: [MarkdownInlineRun])

    /// One piece of inline content: either finished, or a run of `*`/`_` whose
    /// role is not yet decided.
    private enum InlineToken {
        case content(html: String, runs: [MarkdownInlineRun])
        /// `count` delimiters not yet paired, the first of them at `start`.
        case delimiter(character: Character, count: Int, start: String.Index, canOpen: Bool, canClose: Bool)
    }

    private static func renderInline(_ text: Substring, softBreak: SoftBreak = .newline) -> InlineRendering {
        processEmphasis(tokenizeInline(text, softBreak: softBreak), in: text)
    }

    /// Adds `run` to `runs`, joining it to the last one when both are shown as
    /// written and one picks up where the other left off.
    private static func append(_ run: MarkdownInlineRun, to runs: inout [MarkdownInlineRun]) {
        guard !run.source.isEmpty || run.replacement?.isEmpty == false else { return }
        if let last = runs.last,
           last.replacement == nil, run.replacement == nil,
           last.isImageDescription == run.isImageDescription,
           last.source.upperBound == run.source.lowerBound {
            runs[runs.count - 1].source = last.source.lowerBound..<run.source.upperBound
        } else {
            runs.append(run)
        }
    }

    /// The characters the tokenizer looks at twice. Anything else is text, and
    /// is taken a stretch at a time.
    private static func startsInlineConstruct(_ character: Character) -> Bool {
        switch character {
        case "\\", " ", "\n", "&", "!", "[", "`", "*", "_":
            return true
        default:
            return false
        }
    }

    /// Splits inline text into finished content and undecided emphasis
    /// delimiters.
    ///
    /// Everything that outranks emphasis — escapes, entities, images, links,
    /// code spans — is resolved here, so emphasis matching only ever sees text
    /// it is allowed to affect.
    private static func tokenizeInline(_ text: Substring, softBreak: SoftBreak = .newline) -> [InlineToken] {
        var tokens: [InlineToken] = []
        // Content gathers here until a delimiter run, or the end, closes it off.
        var pendingHTML = ""
        var pendingRuns: [MarkdownInlineRun] = []
        var index = text.startIndex

        /// Content the reader sees as written: `source`, character for character.
        func appendShown(_ html: String, from start: String.Index, to end: String.Index) {
            pendingHTML += html
            append(MarkdownInlineRun(source: start..<end), to: &pendingRuns)
        }

        /// Content the reader sees as `shown`, where the source says something else.
        func appendShown(_ html: String, as shown: String, from start: String.Index, to end: String.Index) {
            pendingHTML += html
            append(MarkdownInlineRun(source: start..<end, replacement: shown), to: &pendingRuns)
        }

        func appendRendered(_ rendering: InlineRendering) {
            pendingHTML += rendering.html
            for run in rendering.runs {
                append(run, to: &pendingRuns)
            }
        }

        func flushPending() {
            guard !pendingHTML.isEmpty || !pendingRuns.isEmpty else { return }
            tokens.append(.content(html: pendingHTML, runs: pendingRuns))
            pendingHTML = ""
            pendingRuns = []
        }

        while index < text.endIndex {
            // A backslash escape is resolved before anything else, so the
            // escaped character cannot open or close a construct. A backslash
            // at the end of a line is a hard line break instead.
            if text[index] == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "\n" {
                    let end = text.index(after: next)
                    appendShown("<br />\n", as: "\n", from: index, to: end)
                    index = end
                    continue
                }
                if next < text.endIndex, isASCIIPunctuation(text[next]) {
                    let end = text.index(after: next)
                    appendShown(escapeHTML(String(text[next])), as: String(text[next]), from: index, to: end)
                    index = end
                    continue
                }
            }

            // Two or more spaces before a line ending are the other hard break.
            // A single trailing space is dropped, and the line ending itself is
            // a soft break. Under `.newline` that soft break is a newline in the
            // output, not a <br>; under `.lineBreak` it becomes a <br> too, so a
            // line ending in the source is a line break on screen.
            if text[index] == " " {
                var runEnd = index
                while runEnd < text.endIndex, text[runEnd] == " " {
                    runEnd = text.index(after: runEnd)
                }
                let spaces = text.distance(from: index, to: runEnd)

                if runEnd < text.endIndex, text[runEnd] == "\n" {
                    let isHardBreak = spaces >= 2 || softBreak == .lineBreak
                    let end = text.index(after: runEnd)
                    appendShown(isHardBreak ? "<br />\n" : "\n", as: "\n", from: index, to: end)
                    index = end
                    continue
                }

                appendShown(String(repeating: " ", count: spaces), from: index, to: runEnd)
                index = runEnd
                continue
            }

            if text[index] == "\n" {
                let end = text.index(after: index)
                appendShown(softBreak == .lineBreak ? "<br />\n" : "\n", from: index, to: end)
                index = end
                continue
            }

            if let entity = parseEntity(in: text, from: index) {
                // Decoded, then re-escaped for output: "&amp;" in the source is
                // an ampersand, which is written back out as "&amp;".
                appendShown(
                    escapeHTML(String(entity.character)),
                    as: String(entity.character),
                    from: index,
                    to: entity.endIndex
                )
                index = entity.endIndex
                continue
            }

            if let image = parseImage(in: text, from: index) {
                appendRendered((image.html, image.runs))
                index = image.endIndex
                continue
            }

            if let link = parseLink(in: text, from: index) {
                appendRendered((link.html, link.runs))
                index = link.endIndex
                continue
            }

            if let code = parseCodeSpan(in: text, from: index) {
                appendShown(code.html, from: code.content.lowerBound, to: code.content.upperBound)
                index = code.endIndex
                continue
            }

            let character = text[index]
            if character == "*" || character == "_" {
                var end = index
                while end < text.endIndex, text[end] == character {
                    end = text.index(after: end)
                }
                let count = text.distance(from: index, to: end)

                let before: Character? = index > text.startIndex
                    ? text[text.index(before: index)]
                    : nil
                let after: Character? = end < text.endIndex ? text[end] : nil
                let flanking = flankingRules(character: character, before: before, after: after)

                flushPending()
                tokens.append(
                    .delimiter(
                        character: character,
                        count: count,
                        start: index,
                        canOpen: flanking.canOpen,
                        canClose: flanking.canClose
                    )
                )
                index = end
                continue
            }

            // Plain text, up to the next character that might start something.
            var end = text.index(after: index)
            while end < text.endIndex, !startsInlineConstruct(text[end]) {
                end = text.index(after: end)
            }
            appendShown(escapeHTML(String(text[index..<end])), from: index, to: end)
            index = end
        }

        flushPending()
        return tokens
    }

    /// Decides whether a delimiter run may open or close emphasis.
    ///
    /// A run is left-flanking when it is not followed by whitespace and either
    /// is not followed by punctuation or is itself preceded by whitespace or
    /// punctuation; right-flanking is the mirror image. Asterisks may open when
    /// left-flanking and close when right-flanking. Underscores are stricter —
    /// a run that is both left- and right-flanking can do neither unless
    /// punctuation sits on the far side — which is what keeps `snake_case_names`
    /// intact while `foo*bar*baz` still emphasises.
    private static func flankingRules(
        character: Character,
        before: Character?,
        after: Character?
    ) -> (canOpen: Bool, canClose: Bool) {
        let whitespaceBefore = before.map(\.isWhitespace) ?? true
        let whitespaceAfter = after.map(\.isWhitespace) ?? true
        let punctuationBefore = before.map(isPunctuation) ?? false
        let punctuationAfter = after.map(isPunctuation) ?? false

        let leftFlanking = !whitespaceAfter
            && (!punctuationAfter || whitespaceBefore || punctuationBefore)
        let rightFlanking = !whitespaceBefore
            && (!punctuationBefore || whitespaceAfter || punctuationAfter)

        if character == "*" {
            return (leftFlanking, rightFlanking)
        }

        return (
            leftFlanking && (!rightFlanking || punctuationBefore),
            rightFlanking && (!leftFlanking || punctuationAfter)
        )
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        isASCIIPunctuation(character) || character.isPunctuation || character.isSymbol
    }

    /// Pairs delimiter runs into `<em>` and `<strong>`.
    ///
    /// Closers are considered left to right, each matched to the nearest
    /// preceding opener of the same character, which is what makes nesting fall
    /// out correctly. Two delimiters are consumed at a time when both sides have
    /// them to spare, so `***x***` becomes emphasis wrapping strong. Delimiters
    /// that never find a partner are emitted as literal text.
    private static func processEmphasis(_ tokens: [InlineToken], in text: Substring) -> InlineRendering {
        var tokens = tokens
        var index = 0

        while index < tokens.count {
            guard case let .delimiter(character, closeCount, closeStart, _, canClose) = tokens[index],
                  canClose, closeCount > 0 else {
                index += 1
                continue
            }

            var openerIndex: Int?
            var search = index - 1
            while search >= 0 {
                if case let .delimiter(openCharacter, openCount, _, canOpen, _) = tokens[search],
                   openCharacter == character, canOpen, openCount > 0 {
                    openerIndex = search
                    break
                }
                search -= 1
            }

            guard let opener = openerIndex,
                  case let .delimiter(_, openCount, openStart, canOpen, openCanClose) = tokens[opener] else {
                index += 1
                continue
            }

            let use = (openCount >= 2 && closeCount >= 2) ? 2 : 1
            let inner = flattenTokens(tokens[(opener + 1)..<index], in: text)
            let wrapped = use == 2 ? "<strong>\(inner.html)</strong>" : "<em>\(inner.html)</em>"

            tokens.replaceSubrange((opener + 1)..<index, with: [.content(html: wrapped, runs: inner.runs)])

            // After the splice the closer sits two past the opener. Each side
            // gives up the delimiters nearest what they enclose: the closer its
            // first ones, the opener its last. What is left of a run, and so
            // shown as text if it never pairs, is its outer end.
            var closerIndex = opener + 2
            tokens[closerIndex] = .delimiter(
                character: character,
                count: closeCount - use,
                start: text.index(closeStart, offsetBy: use),
                canOpen: false,
                canClose: canClose
            )
            tokens[opener] = .delimiter(
                character: character,
                count: openCount - use,
                start: openStart,
                canOpen: canOpen,
                canClose: openCanClose
            )

            if case let .delimiter(_, count, _, _, _) = tokens[closerIndex], count == 0 {
                tokens.remove(at: closerIndex)
                closerIndex -= 1
            }
            if case let .delimiter(_, count, _, _, _) = tokens[opener], count == 0 {
                tokens.remove(at: opener)
                closerIndex -= 1
            }

            index = max(0, closerIndex)
        }

        return flattenTokens(tokens[...], in: text)
    }

    /// Renders tokens as they stand, with unmatched delimiters as literal text.
    private static func flattenTokens(_ tokens: ArraySlice<InlineToken>, in text: Substring) -> InlineRendering {
        var html = ""
        var runs: [MarkdownInlineRun] = []

        for token in tokens {
            switch token {
            case let .content(tokenHTML, tokenRuns):
                html += tokenHTML
                for run in tokenRuns {
                    append(run, to: &runs)
                }
            case let .delimiter(character, count, start, _, _):
                guard count > 0 else { continue }
                html += String(repeating: character, count: count)
                append(MarkdownInlineRun(source: start..<text.index(start, offsetBy: count)), to: &runs)
            }
        }

        return (html, runs)
    }

    /// Parses a code span.
    ///
    /// A run of N backticks opens the span and only a run of exactly N closes
    /// it, which is how `` `` foo ` bar `` `` holds a literal backtick. One
    /// leading and one trailing space are stripped together when both are
    /// present, so `` ` `foo` ` `` can hold a backtick at its edge.
    private static func parseCodeSpan(
        in text: Substring,
        from start: String.Index
    ) -> (html: String, content: Range<String.Index>, endIndex: String.Index)? {
        guard text[start] == "`" else { return nil }

        var openEnd = start
        while openEnd < text.endIndex, text[openEnd] == "`" {
            openEnd = text.index(after: openEnd)
        }
        let openLength = text.distance(from: start, to: openEnd)

        var search = openEnd
        while search < text.endIndex {
            guard let candidate = text[search...].firstIndex(of: "`") else { return nil }

            var closeEnd = candidate
            while closeEnd < text.endIndex, text[closeEnd] == "`" {
                closeEnd = text.index(after: closeEnd)
            }

            if text.distance(from: candidate, to: closeEnd) == openLength {
                var content = text[openEnd..<candidate]
                if content.count >= 2,
                   content.first == " ",
                   content.last == " ",
                   content.contains(where: { $0 != " " }) {
                    content = content.dropFirst().dropLast()
                }
                return (
                    "<code>\(escapeHTML(String(content)))</code>",
                    content.startIndex..<content.endIndex,
                    closeEnd
                )
            }

            search = closeEnd
        }

        return nil
    }

    /// The characters a backslash may escape, per CommonMark: any ASCII
    /// punctuation. A backslash before anything else is a literal backslash.
    private static func isASCIIPunctuation(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        switch ascii {
        case 0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E:
            return true
        default:
            return false
        }
    }

    /// Named entity references recognised in source text. CommonMark accepts
    /// the full HTML5 set; this covers the ones that actually turn up in
    /// documents, and anything unrecognised is left as literal text.
    private static let namedEntities: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
        "hellip": "…", "mdash": "—", "ndash": "–", "deg": "°",
        "laquo": "«", "raquo": "»", "ldquo": "“", "rdquo": "”",
        "lsquo": "‘", "rsquo": "’", "times": "×", "divide": "÷",
    ]

    /// Parses an entity reference — `&name;`, `&#123;`, or `&#xAB;` — returning
    /// the character it denotes.
    private static func parseEntity(
        in text: Substring,
        from start: String.Index
    ) -> (character: Character, endIndex: String.Index)? {
        guard text[start] == "&" else { return nil }

        let bodyStart = text.index(after: start)
        guard bodyStart < text.endIndex else { return nil }
        guard let semicolon = text[bodyStart...].firstIndex(of: ";") else { return nil }

        let body = text[bodyStart..<semicolon]
        guard !body.isEmpty, body.count <= 32 else { return nil }
        let end = text.index(after: semicolon)

        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            // A numeric reference to a disallowed code point becomes U+FFFD.
            guard let value else { return nil }
            let scalar = UnicodeScalar(value == 0 ? 0xFFFD : value) ?? "\u{FFFD}"
            return (Character(scalar), end)
        }

        guard let character = namedEntities[String(body)] else { return nil }
        return (character, end)
    }

    /// The `]` that closes the bracket at `open`, which is where a link's text
    /// or an image's description ends.
    ///
    /// Brackets inside pair up, so `[foo [bar]](/url)` and a badge —
    /// `[![alt](image)](/url)` — end where they should. A backslash escape and
    /// a code span are skipped whole, so a bracket inside either is not counted.
    private static func closingBracket(in text: Substring, forBracketAt open: String.Index) -> String.Index? {
        var depth = 0
        var index = text.index(after: open)

        while index < text.endIndex {
            switch text[index] {
            case "\\":
                let next = text.index(after: index)
                if next < text.endIndex, isASCIIPunctuation(text[next]) {
                    index = next
                }
            case "`":
                if let code = parseCodeSpan(in: text, from: index) {
                    index = code.endIndex
                    continue
                }
            case "[":
                depth += 1
            case "]":
                if depth == 0 { return index }
                depth -= 1
            default:
                break
            }
            index = text.index(after: index)
        }

        return nil
    }

    /// The `)` that ends a link's destination and title, which start at `start`.
    ///
    /// Parentheses in the destination pair up, so `/wiki/Foo_(bar)` is one
    /// destination. A destination in angle brackets and a quoted title are
    /// skipped whole, so a parenthesis inside either is not counted.
    private static func closingParenthesis(in text: Substring, from start: String.Index) -> String.Index? {
        var index = start
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }

        if index < text.endIndex, text[index] == "<" {
            guard let close = text[index...].firstIndex(of: ">") else { return nil }
            index = text.index(after: close)
        }

        var depth = 0
        while index < text.endIndex {
            let character = text[index]
            switch character {
            case "\\":
                let next = text.index(after: index)
                if next < text.endIndex, isASCIIPunctuation(text[next]) {
                    index = next
                }
            case "\"", "'":
                // A quote after whitespace opens a title, if another closes it.
                let afterQuote = text.index(after: index)
                if index > start, text[text.index(before: index)].isWhitespace,
                   let close = text[afterQuote...].firstIndex(of: character) {
                    index = close
                }
            case "(":
                depth += 1
            case ")":
                if depth == 0 { return index }
                depth -= 1
            default:
                break
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func parseLink(
        in text: Substring,
        from start: String.Index
    ) -> (html: String, runs: [MarkdownInlineRun], endIndex: String.Index)? {
        guard text[start] == "[" else { return nil }
        guard let closeBracket = closingBracket(in: text, forBracketAt: start) else { return nil }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        let urlStart = text.index(after: afterBracket)
        guard let closeParen = closingParenthesis(in: text, from: urlStart) else { return nil }

        let label = text[text.index(after: start)..<closeBracket]
        guard let target = parseLinkTarget(text[urlStart..<closeParen]) else { return nil }

        // What the reader sees of a link is its text, rendered.
        let rendered = renderInline(label)
        // Links do not nest. If the text holds a link of its own, that one is
        // the link, and these brackets are text around it.
        guard !rendered.html.contains("<a href=\"") else { return nil }
        let titleAttribute = target.title.map { " title=\"\(escapeHTMLAttribute($0))\"" } ?? ""
        let html = "<a href=\"\(escapeHTMLAttribute(target.destination))\"\(titleAttribute)>"
            + "\(rendered.html)</a>"
        return (html, rendered.runs, text.index(after: closeParen))
    }

    /// Splits the parenthesised part of a link or image into its destination
    /// and optional title.
    ///
    /// A destination may be wrapped in angle brackets, which is how it can
    /// contain spaces; the brackets are dropped and the spaces percent-encoded.
    /// A title follows the destination in double quotes, single quotes, or
    /// parentheses.
    private static func parseLinkTarget(
        _ raw: Substring
    ) -> (destination: String, title: String?)? {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        var destination: String
        if body.hasPrefix("<") {
            guard let close = body.firstIndex(of: ">") else { return nil }
            destination = String(body[body.index(after: body.startIndex)..<close])
            body = String(body[body.index(after: close)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let split = body.firstIndex(where: \.isWhitespace) ?? body.endIndex
            destination = String(body[..<split])
            body = String(body[split...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !destination.isEmpty else { return nil }
        destination = destination.replacingOccurrences(of: " ", with: "%20")

        guard !body.isEmpty else { return (destination, nil) }

        let openingQuote = body.removeFirst()
        let closingQuote: Character
        switch openingQuote {
        case "\"": closingQuote = "\""
        case "'": closingQuote = "'"
        case "(": closingQuote = ")"
        default: return (destination, nil)
        }

        guard let end = body.lastIndex(of: closingQuote) else { return (destination, nil) }
        return (destination, String(body[..<end]))
    }

    /// The text content of rendered inline HTML, with the tags removed. Image
    /// alt text is plain text, so any markup in the description contributes
    /// only its characters.
    private static func strippedOfTags(_ html: String) -> String {
        var result = ""
        var insideTag = false
        for character in html {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false
            default: if !insideTag { result.append(character) }
            }
        }
        return result
    }

    private static func parseImage(
        in text: Substring,
        from start: String.Index
    ) -> (html: String, runs: [MarkdownInlineRun], endIndex: String.Index)? {
        guard text[start] == "!" else { return nil }
        let labelStart = text.index(after: start)
        guard labelStart < text.endIndex, text[labelStart] == "[" else { return nil }
        guard let closeBracket = closingBracket(in: text, forBracketAt: labelStart) else { return nil }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        let urlStart = text.index(after: afterBracket)
        guard let closeParen = closingParenthesis(in: text, from: urlStart) else { return nil }

        let description = text[text.index(after: labelStart)..<closeBracket]
        guard let target = parseLinkTarget(text[urlStart..<closeParen]) else { return nil }

        // The description is rendered and then flattened, so emphasis inside it
        // contributes its text and nothing else. It is an attribute, not text in
        // the page, so its runs are marked: a search may want them, the preview's
        // offsets must not count them.
        let rendered = renderInline(description)
        let alt = strippedOfTags(rendered.html)
        let titleAttribute = target.title.map { " title=\"\(escapeHTMLAttribute($0))\"" } ?? ""

        let html = "<img src=\"\(escapeHTMLAttribute(target.destination))\" alt=\"\(alt)\"\(titleAttribute) />"
        let runs = rendered.runs.map { run in
            MarkdownInlineRun(source: run.source, replacement: run.replacement, isImageDescription: true)
        }
        return (html, runs, text.index(after: closeParen))
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func escapeHTMLAttribute(_ text: String) -> String {
        escapeHTML(text)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
