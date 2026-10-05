//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

/// A block kind whose rendered form carries a Copy button.
///
/// The kind travels from the HTML (`data-copy-kind`) back to the copy handler,
/// because what belongs on the pasteboard differs by kind and the handler
/// otherwise sees only a range of source text.
public enum MarkdownCopyableBlockKind: String, Sendable {
    case blockquote
    case code
    case table
}

/// Turns a copyable block's raw source into what the Copy button should put on
/// the pasteboard.
///
/// The raw source is right for a table — the pipe syntax is the useful thing to
/// paste elsewhere — but wrong for the kinds whose syntax is pure decoration
/// around the content the reader can see. A quote copied verbatim arrives with
/// `> ` on every line; a fenced code block arrives wrapped in its fences.
public enum MarkdownBlockCopyText {
    /// Whether the Copy button offers a rich-text flavor as well as plain text.
    ///
    /// Only a table does. For a quote or a code block the button's whole point
    /// is to hand over the text without its markdown syntax, and a rich-text
    /// flavor alongside it would put the decoration back for any target that
    /// prefers formatted paste. Copying a selection by hand is a different path
    /// and still carries both flavors, raw source included.
    public static func offersRichText(for kind: MarkdownCopyableBlockKind?) -> Bool {
        switch kind {
        case .blockquote, .code:
            return false
        case .table, nil:
            return true
        }
    }

    public static func copyText(
        fromBlockSource blockSource: String,
        kind: MarkdownCopyableBlockKind?
    ) -> String {
        switch kind {
        case .blockquote:
            return strippingQuoteMarkers(from: blockSource)
        case .code:
            return strippingCodeDecoration(from: blockSource)
        case .table, nil:
            return blockSource
        }
    }

    /// Removes one level of block-quote marker from each line: up to three
    /// spaces of indent, a `>`, and at most one space after it.
    ///
    /// Only one level comes off. A nested quote stays a quote, which is correct
    /// — its inner `>` is content of the outer quote, and the result is still
    /// the markdown the reader sees quoted.
    private static func strippingQuoteMarkers(from source: String) -> String {
        joined(source.markdownLines.map { line in
            var remainder = Substring(line)
            var indent = 0
            while indent < 3, remainder.first == " " {
                remainder = remainder.dropFirst()
                indent += 1
            }
            guard remainder.first == ">" else { return line }
            remainder = remainder.dropFirst()
            if remainder.first == " " {
                remainder = remainder.dropFirst()
            }
            return String(remainder)
        })
    }

    /// Removes a fenced code block's fences, or an indented code block's
    /// four-space indent, leaving the code itself.
    private static func strippingCodeDecoration(from source: String) -> String {
        var lines = source.markdownLines

        if let first = lines.first, fenceMarker(of: first) != nil {
            // What is copied is the code as the preview shows it, without the
            // indentation it shares with its fence.
            let fenceIndent = MarkdownBlockParser.fenceIndent(of: first[...])
            lines.removeFirst()
            // A fenced block at the end of a document may be unterminated, so a
            // closing fence is stripped only if one is actually there.
            if let last = lines.last, fenceMarker(of: last) != nil {
                lines.removeLast()
            }
            return joined(lines.map { String(MarkdownBlockParser.codeLineContent(in: $0[...], fenceIndent: fenceIndent)) })
        }

        let indentedLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !indentedLines.isEmpty,
              indentedLines.allSatisfy({ $0.hasPrefix("    ") || $0.hasPrefix("\t") }) else {
            return source
        }

        return joined(lines.map { line in
            if line.hasPrefix("    ") { return String(line.dropFirst(4)) }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return line
        })
    }

    /// The run of fence characters opening or closing a fenced code block, or
    /// nil when the line is not a fence.
    private static func fenceMarker(of line: String) -> Character? {
        var remainder = Substring(line)
        var indent = 0
        while indent < 3, remainder.first == " " {
            remainder = remainder.dropFirst()
            indent += 1
        }
        guard let marker = remainder.first, marker == "`" || marker == "~" else { return nil }
        return remainder.prefix(while: { $0 == marker }).count >= 3 ? marker : nil
    }

    /// Rejoins lines, trimming the blank leading/trailing lines that stripping
    /// decoration tends to expose.
    private static func joined(_ lines: [String]) -> String {
        var lines = lines
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
