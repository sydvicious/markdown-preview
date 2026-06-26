//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

enum MarkdownHTMLBuilder {
    static func document(for source: String) -> String {
        let renderedBlocks = MarkdownBlockParser.parse(source).map(renderBlock).joined(separator: "\n")
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
              --content-width: 920px;
              --border-color: rgba(60, 60, 67, 0.24);
              --secondary-border-color: rgba(60, 60, 67, 0.16);
              --blockquote-border: rgba(60, 60, 67, 0.32);
              --code-background: rgba(120, 120, 128, 0.14);
              --table-header-background: rgba(120, 120, 128, 0.12);
              --row-stripe: rgba(120, 120, 128, 0.06);
              --selection-color: rgba(0, 122, 255, 0.26);
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
              font: -apple-system-body;
              line-height: 1.55;
            }
            ::selection {
              background: var(--selection-color);
            }
            article {
              box-sizing: border-box;
              max-width: var(--content-width);
              margin: 0 auto;
              padding: var(--page-padding);
            }
            h1, h2, h3, h4, h5, h6 {
              margin: 0 0 0.6em 0;
              line-height: 1.2;
              font-weight: 650;
            }
            h1 { font: -apple-system-large-title; }
            h2 { font: -apple-system-title1; }
            h3 { font: -apple-system-title2; }
            h4 { font: -apple-system-headline; }
            h5, h6 { font: -apple-system-subheadline; }
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
            li.depth-1 { margin-left: 1.1rem; }
            li.depth-2 { margin-left: 2.2rem; }
            li.depth-3 { margin-left: 3.3rem; }
            li.depth-4 { margin-left: 4.4rem; }
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
              font: -apple-system-headline;
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

    private static func renderBlock(_ block: MarkdownBlock) -> String {
        switch block.kind {
        case .heading(let level, let text):
            let clampedLevel = min(max(level, 1), 6)
            return "<h\(clampedLevel)>\(renderInlineMarkdownHTML(text))</h\(clampedLevel)>"
        case .paragraph(let text):
            return "<p>\(renderInlineMarkdownHTML(text))</p>"
        case .list(let items):
            return renderList(items, ordered: false)
        case .orderedList(let items):
            return renderList(items, ordered: true)
        case .table(let table):
            return renderTable(table)
        case .blockquote(let text):
            return "<blockquote><p>\(renderLinesAsHTML(text))</p></blockquote>"
        case .rule:
            return "<hr />"
        case .code(let code):
            return "<pre><code>\(escapeHTML(code))</code></pre>"
        }
    }

    private static func renderList(_ items: [MarkdownListItem], ordered: Bool) -> String {
        let tag = ordered ? "ol" : "ul"
        let rows = items.map { item -> String in
            let depthClass = "depth-\(min(item.indent, 4))"
            if let checked = item.checkbox {
                return """
                <li class="task \(depthClass)">
                  <label>
                    <input type="checkbox" disabled \(checked ? "checked" : "") />
                    <span>\(renderInlineMarkdownHTML(item.text))</span>
                  </label>
                </li>
                """
            }

            let valueAttribute: String
            if ordered, let order = item.order {
                valueAttribute = " value=\"\(order)\""
            } else {
                valueAttribute = ""
            }

            return "<li class=\"\(depthClass)\"\(valueAttribute)>\(renderInlineMarkdownHTML(item.text))</li>"
        }.joined(separator: "\n")

        return "<\(tag)>\n\(rows)\n</\(tag)>"
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
        }.joined(separator: "\n")

        return """
        <div class="table-wrap">
          <table>
            <thead><tr>\(headerRow)</tr></thead>
            <tbody>
              \(bodyRows)
            </tbody>
          </table>
        </div>
        """
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

    private static func renderInlineMarkdownHTML(_ text: Substring) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if let image = parseImage(in: text, from: index) {
                result += image.html
                index = image.endIndex
                continue
            }

            if let link = parseLink(in: text, from: index) {
                result += link.html
                index = link.endIndex
                continue
            }

            if let code = parseDelimited(in: text, from: index, delimiter: "`") {
                result += "<code>\(escapeHTML(String(code.content)))</code>"
                index = code.endIndex
                continue
            }

            if let strong = parseDelimited(in: text, from: index, delimiter: "**") ??
                parseDelimited(in: text, from: index, delimiter: "__") {
                result += "<strong>\(renderInlineMarkdownHTML(strong.content))</strong>"
                index = strong.endIndex
                continue
            }

            if let emphasis = parseDelimited(in: text, from: index, delimiter: "*") ??
                parseDelimited(in: text, from: index, delimiter: "_") {
                result += "<em>\(renderInlineMarkdownHTML(emphasis.content))</em>"
                index = emphasis.endIndex
                continue
            }

            result += escapeHTML(String(text[index]))
            index = text.index(after: index)
        }

        return result
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
        let destination = text[urlStart..<closeParen].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }

        let html = "<a href=\"\(escapeHTMLAttribute(destination))\">\(renderInlineMarkdownHTML(label))</a>"
        return (html, text.index(after: closeParen))
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

        let alt = text[text.index(after: labelStart)..<closeBracket]
        let destination = text[urlStart..<closeParen].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }

        let html = "<img src=\"\(escapeHTMLAttribute(destination))\" alt=\"\(escapeHTMLAttribute(String(alt)))\" />"
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
