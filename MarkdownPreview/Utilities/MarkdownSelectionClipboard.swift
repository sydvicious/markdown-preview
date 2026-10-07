//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import UniformTypeIdentifiers
import MarkdownCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The pasteboard a copy is written to. The app writes to the general one,
/// which is the clipboard; a test passes one of its own.
#if os(iOS)
typealias MarkdownSelectionPasteboard = UIPasteboard
#elseif os(macOS)
typealias MarkdownSelectionPasteboard = NSPasteboard
#endif

struct MarkdownSelectionClipboardPayload {
    let markdown: String
    let rtf: Data?
}

enum MarkdownSelectionClipboard {
    /// - Parameter richTextHTML: the rendered HTML for the selection, when the
    ///   caller has it. The preview does, and it matters: the source ranges a
    ///   preview selection maps back to cover the *visible* text only, so the
    ///   `# ` of a heading is never inside them. Re-rendering that stripped text
    ///   produced rich text with every heading flattened to a paragraph. The
    ///   HTML already on screen is what the user selected, so it is what gets
    ///   converted. The source view has no HTML and falls back to re-rendering,
    ///   which is correct there — its selection is genuine markdown source.
    static func payload(
        for source: String,
        ranges: [MarkdownSelectionRange],
        richTextHTML: String? = nil
    ) -> MarkdownSelectionClipboardPayload? {
        guard let markdown = selectedMarkdown(in: source, ranges: ranges), !markdown.isEmpty else {
            return nil
        }

        return MarkdownSelectionClipboardPayload(
            markdown: markdown,
            rtf: richTextHTML.flatMap(rtf(fromHTML:)) ?? renderedRTF(for: markdown, in: source)
        )
    }

    static func selectedMarkdown(in source: String, ranges: [MarkdownSelectionRange]) -> String? {
        let utf16Length = source.utf16.count
        let sanitized = ranges
            .compactMap { $0.clamped(toUTF16Length: utf16Length) }
            .filter { $0.length > 0 }
            .sorted { lhs, rhs in
                if lhs.location == rhs.location {
                    return lhs.length < rhs.length
                }
                return lhs.location < rhs.location
            }

        guard !sanitized.isEmpty else { return nil }

        let sourceNSString = source as NSString
        return sanitized
            .map { sourceNSString.substring(with: $0.nsRange) }
            .joined(separator: sanitized.count > 1 ? "\n" : "")
    }

    @discardableResult
    static func writeSelection(
        from source: String,
        ranges: [MarkdownSelectionRange],
        richTextHTML: String? = nil,
        to pasteboard: MarkdownSelectionPasteboard = .general
    ) -> Bool {
        guard let payload = payload(for: source, ranges: ranges, richTextHTML: richTextHTML) else {
            return false
        }
        write(payload, to: pasteboard)
        return true
    }

    /// Writes only the plain-text flavor, with no rich text alongside it.
    ///
    /// Used by the block Copy button for quotes and code — see
    /// `MarkdownBlockCopyText.offersRichText(for:)` for why those kinds get
    /// plain text alone.
    @discardableResult
    static func writePlainText(_ text: String, to pasteboard: MarkdownSelectionPasteboard = .general) -> Bool {
        guard !text.isEmpty else { return false }
        write(MarkdownSelectionClipboardPayload(markdown: text, rtf: nil), to: pasteboard)
        return true
    }

    /// Converts rendered HTML straight to RTF, no markdown round trip.
    static func rtf(fromHTML html: String) -> Data? {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return rtf(fromHTMLData: Data(trimmed.utf8))
    }

    private static func rtf(fromHTMLData htmlData: Data) -> Data? {
        guard let attributedString = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ), attributedString.length > 0 else {
            return nil
        }

        return try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private static func renderedRTF(for markdown: String, in source: String) -> Data? {
        // Match the preview's rendering so copied rich text breaks lines the
        // same way the user sees them, and a reference in the selection is
        // still a link though its definition is in the rest of the document.
        let html = MarkdownHTMLBuilder.document(
            for: markdown,
            softBreak: .lineBreak,
            definitions: MarkdownLinkDefinitions(source: source)
        )
        return rtf(fromHTMLData: Data(html.utf8))
    }

    private static func write(
        _ payload: MarkdownSelectionClipboardPayload,
        to pasteboard: MarkdownSelectionPasteboard
    ) {
        #if os(iOS)
        var item: [String: Any] = [UTType.plainText.identifier: payload.markdown]
        if let rtf = payload.rtf {
            item[UTType.rtf.identifier] = rtf
        }
        pasteboard.setItems([item], options: [:])
        #elseif os(macOS)
        pasteboard.clearContents()
        pasteboard.setString(payload.markdown, forType: .string)
        if let rtf = payload.rtf {
            pasteboard.setData(rtf, forType: .rtf)
        }
        #endif
    }
}
