//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

enum MarkdownTableHTMLBuilder {
    static func document(for table: MarkdownTable) -> String {
        let headerRow = zip(table.headers, table.alignments).map { text, alignment in
            "<th class=\"\(alignmentClass(alignment))\">\(renderInlineMarkdownHTML(text))</th>"
        }.joined()

        let bodyRows = table.rows.map { row -> String in
            let cells = table.alignments.indices.map { index -> String in
                let text = index < row.count ? row[index] : ""
                let alignment = table.alignments[index]
                return "<td class=\"\(alignmentClass(alignment))\">\(renderInlineMarkdownHTML(text))</td>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>
            :root {
              color-scheme: light dark;
            }
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              -webkit-text-size-adjust: 100%;
              text-size-adjust: 100%;
            }
            body {
              font: -apple-system-body;
              color: CanvasText;
            }
            .wrap {
              overflow-x: auto;
              overflow-y: hidden;
            }
            table {
              border-collapse: collapse;
              width: max-content;
            }
            th, td {
              border: 1px solid rgba(0,0,0,0.16);
              padding: 8px 8px;
              vertical-align: top;
              white-space: pre;
              word-break: normal;
              overflow-wrap: normal;
              hyphens: none;
              color: inherit;
            }
            th {
              background: rgba(0,0,0,0.08);
              font-weight: 600;
            }
            .a-left { text-align: left; }
            .a-center { text-align: center; }
            .a-right { text-align: right; }
            code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: \(codeFontSize);
              background: rgba(0,0,0,0.08);
              border-radius: 4px;
              padding: 1px 4px;
            }
            @media (prefers-color-scheme: dark) {
              th, td {
                border-color: rgba(255,255,255,0.24);
              }
              th {
                background: rgba(255,255,255,0.14);
              }
              code {
                background: rgba(255,255,255,0.18);
              }
            }
          </style>
        </head>
        <body>
          <div class="wrap">
            <table>
              <thead><tr>\(headerRow)</tr></thead>
              <tbody>\(bodyRows)</tbody>
            </table>
          </div>
          <script>
            function reportSize() {
              const table = document.querySelector('table');
              const h = (table && table.getBoundingClientRect) ? Math.ceil(table.getBoundingClientRect().height) : (document.documentElement.scrollHeight || document.body.scrollHeight || 44);
              const w = (table && table.scrollWidth) ? table.scrollWidth : (document.documentElement.scrollWidth || document.body.scrollWidth || 120);
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.size) {
                window.webkit.messageHandlers.size.postMessage({ height: h, width: w });
              }
            }
            window.addEventListener('load', reportSize);
            window.addEventListener('resize', reportSize);
            setTimeout(reportSize, 50);
          </script>
        </body>
        </html>
        """
    }

    private static func alignmentClass(_ alignment: MarkdownTableAlignment) -> String {
        switch alignment {
        case .leading: return "a-left"
        case .center: return "a-center"
        case .trailing: return "a-right"
        }
    }

    private static func renderInlineMarkdownHTML(_ text: String) -> String {
        var result = ""
        var buffer = ""
        var insideCode = false

        for character in text {
            if character == "`" {
                if insideCode {
                    result += "<code>\(escapeHTML(buffer))</code>"
                    buffer.removeAll(keepingCapacity: true)
                    insideCode = false
                } else {
                    if !buffer.isEmpty {
                        result += escapeHTML(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                    insideCode = true
                }
            } else {
                buffer.append(character)
            }
        }

        if insideCode {
            result += "&#96;\(escapeHTML(buffer))"
        } else if !buffer.isEmpty {
            result += escapeHTML(buffer)
        }

        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    #if os(iOS)
    private static let codeFontSize = "0.88em"
    #else
    private static let codeFontSize = "0.95em"
    #endif
}
