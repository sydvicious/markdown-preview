//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore

struct MarkdownSelectionClipboardTests {

    /// The preview's selection maps back to source ranges covering visible text
    /// only, so the `# ` of a heading is never in them. Re-rendering that text
    /// flattened every heading to a paragraph, which is why pasting into Notes
    /// looked plain. Rich text now comes from the rendered HTML instead.
    @Test func richTextFromRenderedHTMLKeepsHeadingsThatSourceRangesLose() throws {
        let source = "# Feature Sample\n\nA paragraph."
        // What the preview reports: the heading's visible text, without its `# `.
        let visibleRanges = [
            MarkdownSelectionRange(location: 2, length: "Feature Sample".utf16.count),
            MarkdownSelectionRange(
                location: (source as NSString).range(of: "A paragraph.").location,
                length: "A paragraph.".utf16.count
            )
        ]
        let renderedHTML = "<h1>Feature Sample</h1><p>A paragraph.</p>"

        let withHTML = try #require(
            MarkdownSelectionClipboard.payload(
                for: source,
                ranges: visibleRanges,
                richTextHTML: renderedHTML
            )
        )
        let withoutHTML = try #require(
            MarkdownSelectionClipboard.payload(for: source, ranges: visibleRanges)
        )

        #expect(withHTML.markdown.contains("#") == false)
        #expect(withHTML.rtf != nil)
        // The heading survives only when the rendered HTML is used.
        #expect(withHTML.rtf != withoutHTML.rtf)
    }

    @Test func emptyOrBlankSelectionHTMLProducesNoRichText() {
        #expect(MarkdownSelectionClipboard.rtf(fromHTML: "") == nil)
        #expect(MarkdownSelectionClipboard.rtf(fromHTML: "   \n  ") == nil)
    }

    /// A multi-block selection — headings plus paragraphs, as copied from the
    /// preview — must still produce a rich-text flavor.
    @Test func multiBlockSelectionStillProducesRichText() throws {
        let source = """
        # Markdown Preview — Feature Sample

        This document exercises everything the renderer supports.

        ## Headings

        Headings come in six levels, written with leading hashes.
        """

        let payload = try #require(
            MarkdownSelectionClipboard.payload(
                for: source,
                ranges: [MarkdownSelectionRange(location: 0, length: source.utf16.count)]
            )
        )

        #expect(payload.markdown.contains("# Markdown Preview"))
        #expect(payload.rtf != nil)
    }

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
