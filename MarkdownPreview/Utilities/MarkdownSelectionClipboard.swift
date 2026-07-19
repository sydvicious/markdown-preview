//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import UniformTypeIdentifiers
import MarkdownCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MarkdownSelectionClipboardPayload {
    let markdown: String
    let rtf: Data?
}

enum MarkdownSelectionClipboard {
    static func payload(for source: String, ranges: [MarkdownSelectionRange]) -> MarkdownSelectionClipboardPayload? {
        guard let markdown = selectedMarkdown(in: source, ranges: ranges), !markdown.isEmpty else {
            return nil
        }

        return MarkdownSelectionClipboardPayload(
            markdown: markdown,
            rtf: renderedRTF(for: markdown)
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
    static func writeSelection(from source: String, ranges: [MarkdownSelectionRange]) -> Bool {
        guard let payload = payload(for: source, ranges: ranges) else { return false }
        write(payload)
        return true
    }

    private static func renderedRTF(for markdown: String) -> Data? {
        let html = MarkdownHTMLBuilder.document(for: markdown)
        let htmlData = Data(html.utf8)
        guard let attributedString = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) else {
            return nil
        }

        let fullRange = NSRange(location: 0, length: attributedString.length)
        return try? attributedString.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private static func write(_ payload: MarkdownSelectionClipboardPayload) {
        #if os(iOS)
        var item: [String: Any] = [UTType.plainText.identifier: payload.markdown]
        if let rtf = payload.rtf {
            item[UTType.rtf.identifier] = rtf
        }
        UIPasteboard.general.setItems([item], options: [:])
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload.markdown, forType: .string)
        if let rtf = payload.rtf {
            pasteboard.setData(rtf, forType: .rtf)
        }
        #endif
    }
}
