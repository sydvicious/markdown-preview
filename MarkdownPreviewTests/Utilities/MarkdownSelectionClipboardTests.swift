//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

struct MarkdownSelectionClipboardTests {

    @Test func clipboardPayloadIncludesMarkdownAndRichText() async throws {
        let source = """
        # Title

        Paragraph with **bold** text.
        """

        let payload = MarkdownSelectionClipboard.payload(
            for: source,
            ranges: [MarkdownSelectionRange(location: 0, length: source.utf16.count)]
        )

        #expect(payload?.markdown == source)
        #expect(payload?.rtf?.isEmpty == false)
    }

    @Test func selectedMarkdownUsesSelectionRangesInSourceOrder() async throws {
        let source = "alpha beta gamma"
        let ranges = [
            MarkdownSelectionRange(location: 11, length: 5),
            MarkdownSelectionRange(location: 0, length: 5)
        ]

        #expect(MarkdownSelectionClipboard.selectedMarkdown(in: source, ranges: ranges) == "alpha\ngamma")
    }
}
