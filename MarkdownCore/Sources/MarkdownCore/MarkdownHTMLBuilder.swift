//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

public enum MarkdownHTMLBuilder {
    /// Renders `source` as a standalone HTML document.
    ///
    /// `contentScale` is the Dynamic Type scale factor to apply to the
    /// document's text. It is taken as a plain number rather than a
    /// `DynamicTypeSize` so that the markdown engine stays free of SwiftUI and
    /// can be built and tested from the command line without an app host; call
    /// sites pass `textSize.scaleFactor`.
    public static func document(for source: String, contentScale: CGFloat = 1.0) -> String {
        let sourceLineTable = MarkdownSourceLineTable(source: source)
        let renderedBlocks = MarkdownBlockParser.parse(source)
            .map { renderBlock($0, sourceLineTable: sourceLineTable) }
            .joined(separator: "\n")
        let body = renderedBlocks.isEmpty ? "<p class=\"empty\"></p>" : renderedBlocks

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>
            :root {
              color-scheme: light dark;
              --page-padding: 20px;
              --border-color: rgba(60, 60, 67, 0.24);
              --secondary-border-color: rgba(60, 60, 67, 0.16);
              --blockquote-border: rgba(60, 60, 67, 0.32);
              --code-background: rgba(120, 120, 128, 0.14);
              --table-header-background: rgba(120, 120, 128, 0.12);
              --row-stripe: rgba(120, 120, 128, 0.06);
              --selection-color: rgba(0, 122, 255, 0.26);
              --copy-button-background: rgba(120, 120, 128, 0.16);
              --copy-button-background-active: rgba(120, 120, 128, 0.24);
              --search-active-background: rgba(255, 214, 10, 0.22);
              --search-active-outline: rgba(255, 159, 10, 0.65);
              --content-scale: \(contentScale);
              --body-font-size: calc(17px * var(--content-scale));
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --border-color: rgba(235, 235, 245, 0.22);
                --secondary-border-color: rgba(235, 235, 245, 0.14);
                --blockquote-border: rgba(235, 235, 245, 0.28);
                --code-background: rgba(118, 118, 128, 0.26);
                --table-header-background: rgba(118, 118, 128, 0.22);
                --row-stripe: rgba(118, 118, 128, 0.14);
                --selection-color: rgba(10, 132, 255, 0.34);
                --copy-button-background: rgba(118, 118, 128, 0.3);
                --copy-button-background-active: rgba(118, 118, 128, 0.4);
                --search-active-background: rgba(255, 214, 10, 0.18);
                --search-active-outline: rgba(255, 214, 10, 0.7);
              }
            }
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              color: CanvasText;
              -webkit-text-size-adjust: 100%;
              text-size-adjust: 100%;
            }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              font-size: var(--body-font-size);
              font-weight: 400;
              line-height: 1.55;
            }
            ::selection {
              background: var(--selection-color);
            }
            article {
              box-sizing: border-box;
              width: 100%;
              margin: 0;
              padding: var(--page-padding);
            }
            .md-block {
              position: relative;
              border-radius: 12px;
            }
            .md-copyable-block {
              padding-top: 2rem;
            }
            .md-search-active {
              background: var(--search-active-background);
              box-shadow: inset 0 0 0 1px var(--search-active-outline);
            }
            .md-copy-button {
              position: absolute;
              top: 0.25rem;
              right: 0;
              border: 0;
              border-radius: 999px;
              padding: 0.3rem 0.75rem;
              background: var(--copy-button-background);
              color: inherit;
              font-size: 0.82em;
              font-weight: 600;
              cursor: pointer;
              user-select: none;
              -webkit-user-select: none;
              -webkit-touch-callout: none;
            }
            .md-copy-button:active {
              background: var(--copy-button-background-active);
            }
            h1, h2, h3, h4, h5, h6 {
              margin: 1.4em 0 0.6em 0;
              line-height: 1.2;
              font-weight: 650;
            }
            .md-block:first-child > :first-child {
              margin-top: 0;
            }
            h1 { font-size: 2em; }
            h2 { font-size: 1.65em; }
            h3 { font-size: 1.35em; }
            h4 { font-size: 1em; }
            h5, h6 { font-size: 0.9em; }
            p, ul, ol, blockquote, pre, .table-wrap {
              margin: 0 0 1rem 0;
            }
            p:last-child,
            ul:last-child,
            ol:last-child,
            blockquote:last-child,
            pre:last-child,
            .table-wrap:last-child {
              margin-bottom: 0;
            }
            a {
              color: LinkText;
              text-decoration-thickness: 0.08em;
              text-underline-offset: 0.15em;
            }
            img {
              display: block;
              max-width: 100%;
              height: auto;
              border-radius: 10px;
              margin: 0.6rem 0;
            }
            code {
              font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, monospace;
              font-size: 0.92em;
              background: var(--code-background);
              border-radius: 6px;
              padding: 0.1em 0.35em;
            }
            pre {
              overflow-x: auto;
              padding: 14px 16px;
              border-radius: 12px;
              border: 1px solid var(--secondary-border-color);
              background: var(--code-background);
            }
            pre code {
              padding: 0;
              background: transparent;
              border-radius: 0;
              white-space: pre;
            }
            blockquote {
              padding: 0.2rem 0 0.2rem 1rem;
              border-left: 4px solid var(--blockquote-border);
              color: color-mix(in srgb, CanvasText 84%, transparent);
            }
            hr {
              margin: 1.2rem 0;
              border: 0;
              border-top: 1px solid var(--secondary-border-color);
            }
            ul, ol {
              padding-left: 1.35rem;
            }
            li {
              margin: 0.35rem 0;
            }
            /* Nested lists indent structurally; suppress the block margin they
               would otherwise inherit so sub-items stay tight to their parent. */
            li > ul, li > ol {
              margin: 0.35rem 0 0 0;
              padding-left: 1.35rem;
            }
            li.task {
              list-style: none;
              margin-left: 0;
            }
            li.task > label {
              display: inline-flex;
              align-items: flex-start;
              gap: 0.55rem;
            }
            li.task input {
              margin: 0.12rem 0 0 0;
            }
            .table-wrap {
              overflow-x: auto;
              overflow-y: hidden;
              border: 1px solid var(--secondary-border-color);
              border-radius: 14px;
              background: color-mix(in srgb, Canvas 94%, transparent);
            }
            table {
              width: max-content;
              min-width: 100%;
              border-collapse: collapse;
            }
            th, td {
              padding: 10px 12px;
              vertical-align: top;
              border-right: 1px solid var(--secondary-border-color);
              border-bottom: 1px solid var(--secondary-border-color);
              white-space: pre-wrap;
            }
            th:last-child, td:last-child {
              border-right: 0;
            }
            tr:last-child td {
              border-bottom: 0;
            }
            th {
              background: var(--table-header-background);
              font-size: 1em;
              font-weight: 650;
              text-align: left;
            }
            tbody tr:nth-child(even) td {
              background: var(--row-stripe);
            }
            .a-left { text-align: left; }
            .a-center { text-align: center; }
            .a-right { text-align: right; }
            .empty {
              min-height: 1px;
            }
          </style>
        </head>
        <body>
          <article>
            \(body)
          </article>
        </body>
        </html>
        """
    }

    private static func renderBlock(_ block: MarkdownBlock, sourceLineTable: MarkdownSourceLineTable) -> String {
        let content = blockContent(block)
        let copyButton = blockWantsCopyButton(block)
            ? "<button type=\"button\" class=\"md-copy-button\" data-copy-button>Copy</button>"
            : nil

        guard let sourceRange = sourceLineTable.range(for: block.lineRange) else {
            return content
        }

        return """
        <div class="md-block\(copyButton == nil ? "" : " md-copyable-block")" data-source-start="\(sourceRange.location)" data-source-end="\(sourceRange.location + sourceRange.length)">\(copyButton ?? "")\(content)</div>
        """
    }

    private static func blockWantsCopyButton(_ block: MarkdownBlock) -> Bool {
        switch block.kind {
        case .table, .blockquote, .code:
            return true
        default:
            return false
        }
    }

    /// The block's own markup, without the `md-block` wrapper.
    ///
    /// Blocks nested inside a block quote are rendered through here rather than
    /// `renderBlock`, because the wrapper carries source offsets into the outer
    /// document and a nested block's line numbers refer to the quote's stripped
    /// content instead.
    private static func blockContent(_ block: MarkdownBlock) -> String {
        let content: String
        switch block.kind {
        case .heading(let level, let text):
            let clampedLevel = min(max(level, 1), 6)
            content = "<h\(clampedLevel)>\(renderInlineMarkdownHTML(text))</h\(clampedLevel)>"
        case .paragraph(let text):
            content = "<p>\(renderInlineMarkdownHTML(text))</p>"
        case .list(let items, let isLoose):
            content = renderList(items, ordered: false, isLoose: isLoose)
        case .orderedList(let items, let isLoose):
            content = renderList(items, ordered: true, isLoose: isLoose)
        case .table(let table):
            content = renderTable(table)
        case .blockquote(let children):
            content = "<blockquote>\(children.map(blockContent).joined())</blockquote>"
        case .rule:
            content = "<hr />"
        case .code(let code, let language):
            let languageClass = language.map { " class=\"language-\(escapeHTMLAttribute($0))\"" } ?? ""
            content = "<pre><code\(languageClass)>\(escapeHTML(code))</code></pre>"
        }

        return content
    }

    private static func renderList(_ items: [MarkdownListItem], ordered: Bool, isLoose: Bool) -> String {
        var index = 0
        return renderListLevel(items, index: &index, depth: 0, ordered: ordered, isLoose: isLoose)
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
        isLoose: Bool
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
                    isLoose: isLoose
                )
            }

            if let checked = item.checkbox {
                let checkedAttribute = checked ? " checked" : ""
                rows += "<li class=\"task\"><label><input type=\"checkbox\" disabled\(checkedAttribute) /><span>\(renderInlineMarkdownHTML(item.text))</span></label>\(nested)</li>"
                continue
            }

            let valueAttribute: String
            if item.isOrdered, let order = item.order {
                valueAttribute = " value=\"\(order)\""
            } else {
                valueAttribute = ""
            }

            let text = renderInlineMarkdownHTML(item.text)
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
        text
            .components(separatedBy: "\n")
            .map(renderInlineMarkdownHTML)
            .joined(separator: "<br>")
    }

    private static func renderInlineMarkdownHTML(_ text: String) -> String {
        renderInlineMarkdownHTML(Substring(text))
    }

    /// One piece of inline content: either finished HTML, or a run of `*`/`_`
    /// whose role is not yet decided.
    private enum InlineToken {
        case html(String)
        case delimiter(character: Character, count: Int, canOpen: Bool, canClose: Bool)
    }

    private static func renderInlineMarkdownHTML(_ text: Substring) -> String {
        processEmphasis(tokenizeInline(text))
    }

    /// Splits inline text into finished HTML and undecided emphasis delimiters.
    ///
    /// Everything that outranks emphasis — escapes, entities, images, links,
    /// code spans — is resolved here, so emphasis matching only ever sees text
    /// it is allowed to affect.
    private static func tokenizeInline(_ text: Substring) -> [InlineToken] {
        var tokens: [InlineToken] = []
        var index = text.startIndex

        func appendHTML(_ html: String) {
            if case let .html(existing)? = tokens.last {
                tokens[tokens.count - 1] = .html(existing + html)
            } else {
                tokens.append(.html(html))
            }
        }

        while index < text.endIndex {
            // A backslash escape is resolved before anything else, so the
            // escaped character cannot open or close a construct. A backslash
            // at the end of a line is a hard line break instead.
            if text[index] == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "\n" {
                    appendHTML("<br />\n")
                    index = text.index(after: next)
                    continue
                }
                if next < text.endIndex, isASCIIPunctuation(text[next]) {
                    appendHTML(escapeHTML(String(text[next])))
                    index = text.index(after: next)
                    continue
                }
            }

            // Two or more spaces before a line ending are the other hard break.
            // A single trailing space is dropped, and the line ending itself is
            // a soft break: a newline in the output, not a <br>.
            if text[index] == " " {
                var runEnd = index
                while runEnd < text.endIndex, text[runEnd] == " " {
                    runEnd = text.index(after: runEnd)
                }
                let spaces = text.distance(from: index, to: runEnd)

                if runEnd < text.endIndex, text[runEnd] == "\n" {
                    appendHTML(spaces >= 2 ? "<br />\n" : "\n")
                    index = text.index(after: runEnd)
                    continue
                }

                appendHTML(String(repeating: " ", count: spaces))
                index = runEnd
                continue
            }

            if text[index] == "\n" {
                appendHTML("\n")
                index = text.index(after: index)
                continue
            }

            if let entity = parseEntity(in: text, from: index) {
                // Decoded, then re-escaped for output: "&amp;" in the source is
                // an ampersand, which is written back out as "&amp;".
                appendHTML(escapeHTML(String(entity.character)))
                index = entity.endIndex
                continue
            }

            if let image = parseImage(in: text, from: index) {
                appendHTML(image.html)
                index = image.endIndex
                continue
            }

            if let link = parseLink(in: text, from: index) {
                appendHTML(link.html)
                index = link.endIndex
                continue
            }

            if let code = parseCodeSpan(in: text, from: index) {
                appendHTML(code.html)
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

                tokens.append(
                    .delimiter(
                        character: character,
                        count: count,
                        canOpen: flanking.canOpen,
                        canClose: flanking.canClose
                    )
                )
                index = end
                continue
            }

            appendHTML(escapeHTML(String(character)))
            index = text.index(after: index)
        }

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
    private static func processEmphasis(_ tokens: [InlineToken]) -> String {
        var tokens = tokens
        var index = 0

        while index < tokens.count {
            guard case let .delimiter(character, closeCount, _, canClose) = tokens[index],
                  canClose, closeCount > 0 else {
                index += 1
                continue
            }

            var openerIndex: Int?
            var search = index - 1
            while search >= 0 {
                if case let .delimiter(openCharacter, openCount, canOpen, _) = tokens[search],
                   openCharacter == character, canOpen, openCount > 0 {
                    openerIndex = search
                    break
                }
                search -= 1
            }

            guard let opener = openerIndex,
                  case let .delimiter(_, openCount, canOpen, openCanClose) = tokens[opener] else {
                index += 1
                continue
            }

            let use = (openCount >= 2 && closeCount >= 2) ? 2 : 1
            let inner = flattenTokens(tokens[(opener + 1)..<index])
            let wrapped = use == 2 ? "<strong>\(inner)</strong>" : "<em>\(inner)</em>"

            tokens.replaceSubrange((opener + 1)..<index, with: [.html(wrapped)])

            // After the splice the closer sits two past the opener.
            var closerIndex = opener + 2
            tokens[closerIndex] = .delimiter(
                character: character,
                count: closeCount - use,
                canOpen: false,
                canClose: canClose
            )
            tokens[opener] = .delimiter(
                character: character,
                count: openCount - use,
                canOpen: canOpen,
                canClose: openCanClose
            )

            if case let .delimiter(_, count, _, _) = tokens[closerIndex], count == 0 {
                tokens.remove(at: closerIndex)
                closerIndex -= 1
            }
            if case let .delimiter(_, count, _, _) = tokens[opener], count == 0 {
                tokens.remove(at: opener)
                closerIndex -= 1
            }

            index = max(0, closerIndex)
        }

        return flattenTokens(tokens[...])
    }

    /// Renders tokens as they stand, with unmatched delimiters as literal text.
    private static func flattenTokens(_ tokens: ArraySlice<InlineToken>) -> String {
        tokens.map { token in
            switch token {
            case let .html(html):
                return html
            case let .delimiter(character, count, _, _):
                return String(repeating: character, count: count)
            }
        }.joined()
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
    ) -> (html: String, endIndex: String.Index)? {
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
                var content = String(text[openEnd..<candidate])
                if content.count >= 2,
                   content.first == " ",
                   content.last == " ",
                   content.contains(where: { $0 != " " }) {
                    content = String(content.dropFirst().dropLast())
                }
                return ("<code>\(escapeHTML(content))</code>", closeEnd)
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

    private static func parseDelimited(
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
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return (content, range.upperBound)
        }

        return nil
    }

    private static func parseLink(
        in text: Substring,
        from start: String.Index
    ) -> (html: String, endIndex: String.Index)? {
        guard text[start] == "[" else { return nil }
        guard let closeBracket = text[start...].firstIndex(of: "]") else { return nil }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        let urlStart = text.index(after: afterBracket)
        guard let closeParen = text[urlStart...].firstIndex(of: ")") else { return nil }

        let label = text[text.index(after: start)..<closeBracket]
        guard let target = parseLinkTarget(text[urlStart..<closeParen]) else { return nil }

        let titleAttribute = target.title.map { " title=\"\(escapeHTMLAttribute($0))\"" } ?? ""
        let html = "<a href=\"\(escapeHTMLAttribute(target.destination))\"\(titleAttribute)>"
            + "\(renderInlineMarkdownHTML(label))</a>"
        return (html, text.index(after: closeParen))
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
    ) -> (html: String, endIndex: String.Index)? {
        guard text[start] == "!" else { return nil }
        let labelStart = text.index(after: start)
        guard labelStart < text.endIndex, text[labelStart] == "[" else { return nil }
        guard let closeBracket = text[labelStart...].firstIndex(of: "]") else { return nil }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex, text[afterBracket] == "(" else { return nil }
        let urlStart = text.index(after: afterBracket)
        guard let closeParen = text[urlStart...].firstIndex(of: ")") else { return nil }

        let description = text[text.index(after: labelStart)..<closeBracket]
        guard let target = parseLinkTarget(text[urlStart..<closeParen]) else { return nil }

        // The description is rendered and then flattened, so emphasis inside it
        // contributes its text and nothing else.
        let alt = strippedOfTags(renderInlineMarkdownHTML(description))
        let titleAttribute = target.title.map { " title=\"\(escapeHTMLAttribute($0))\"" } ?? ""

        let html = "<img src=\"\(escapeHTMLAttribute(target.destination))\" alt=\"\(alt)\"\(titleAttribute) />"
        return (html, text.index(after: closeParen))
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        escapeHTML(text)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
