//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import UniformTypeIdentifiers
import MarkdownCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
@testable import MarkdownPreview

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

/// What a copy puts on the pasteboard.
///
/// Every test here writes to a pasteboard of its own, made for the test and
/// thrown away after it, so that running the tests never touches the clipboard
/// of whoever is running them.
@MainActor
struct MarkdownSelectionClipboardWritingTests {

    /// A pasteboard nothing else has, read the way another app pasting from
    /// it would read it.
    @MainActor
    private struct PrivatePasteboard {
        #if os(macOS)
        let pasteboard = NSPasteboard.withUniqueName()

        var plainText: String? { pasteboard.string(forType: .string) }
        var richText: Data? { pasteboard.data(forType: .rtf) }
        var isEmpty: Bool { (pasteboard.pasteboardItems ?? []).isEmpty }

        /// Puts something there first, as a copy made earlier would have.
        func hold(plainText: String, richText: Data) {
            pasteboard.clearContents()
            pasteboard.setString(plainText, forType: .string)
            pasteboard.setData(richText, forType: .rtf)
        }

        func discard() { pasteboard.releaseGlobally() }
        #else
        let pasteboard = UIPasteboard.withUniqueName()

        var plainText: String? { pasteboard.string }
        var richText: Data? { pasteboard.data(forPasteboardType: UTType.rtf.identifier) }
        var isEmpty: Bool { pasteboard.numberOfItems == 0 }

        func hold(plainText: String, richText: Data) {
            pasteboard.setItems(
                [[UTType.plainText.identifier: plainText, UTType.rtf.identifier: richText]],
                options: [:]
            )
        }

        func discard() { UIPasteboard.remove(withName: pasteboard.name) }
        #endif

        /// The words of the rich text there, without their formatting.
        var richTextWords: String? {
            guard let richText,
                  let attributed = try? NSAttributedString(
                    data: richText,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                  ) else {
                return nil
            }
            return attributed.string
        }
    }

    private static let source = "# Feature Sample\n\nA paragraph with **bold** text."
    private static let earlierRichText = Data("{\\rtf1 earlier}".utf8)

    private static func whole(_ text: String) -> [MarkdownSelectionRange] {
        [MarkdownSelectionRange(location: 0, length: text.utf16.count)]
    }

    // MARK: - Copying a selection

    /// The markdown as it was written, for anything that takes plain text, and
    /// the same thing rendered, for anything that takes rich text.
    @Test func copyingASelectionPutsItsMarkdownAndItsRichTextOnThePasteboard() throws {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }

        let copied = MarkdownSelectionClipboard.writeSelection(
            from: Self.source,
            ranges: Self.whole(Self.source),
            to: pasteboard.pasteboard
        )

        #expect(copied)
        #expect(pasteboard.plainText == Self.source)
        let words = try #require(pasteboard.richTextWords)
        #expect(words.contains("Feature Sample"))
        #expect(words.contains("A paragraph with bold text."))
        // Rendered, so the markdown's own characters are not in it.
        #expect(!words.contains("#"))
        #expect(!words.contains("**"))
    }

    @Test func copyingPartOfADocumentPutsOnlyThatPartOnThePasteboard() throws {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }
        let paragraph = (Self.source as NSString).range(of: "A paragraph with **bold** text.")

        let copied = MarkdownSelectionClipboard.writeSelection(
            from: Self.source,
            ranges: [MarkdownSelectionRange(paragraph)],
            to: pasteboard.pasteboard
        )

        #expect(copied)
        #expect(pasteboard.plainText == "A paragraph with **bold** text.")
        let words = try #require(pasteboard.richTextWords)
        #expect(!words.contains("Feature Sample"))
    }

    /// The preview hands over the HTML the reader selected, and that is what
    /// the rich text is made from: the heading's `# ` is not in the ranges a
    /// preview selection maps back to, so rendering them again would lose it.
    @Test func copyingFromThePreviewMakesTheRichTextFromTheHTMLItWasGiven() throws {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }

        let copied = MarkdownSelectionClipboard.writeSelection(
            from: Self.source,
            ranges: [MarkdownSelectionRange(location: 2, length: "Feature Sample".utf16.count)],
            richTextHTML: "<h1>Rendered heading</h1>",
            to: pasteboard.pasteboard
        )

        #expect(copied)
        #expect(pasteboard.plainText == "Feature Sample")
        let words = try #require(pasteboard.richTextWords)
        #expect(words.contains("Rendered heading"))
    }

    @Test func copyingSeveralRangesPutsThemInTheOrderOfTheDocument() {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }
        let source = "alpha beta gamma"

        MarkdownSelectionClipboard.writeSelection(
            from: source,
            ranges: [
                MarkdownSelectionRange(location: 11, length: 5),
                MarkdownSelectionRange(location: 0, length: 5),
            ],
            to: pasteboard.pasteboard
        )

        #expect(pasteboard.plainText == "alpha\ngamma")
    }

    @Test func aCopyReplacesWhatWasOnThePasteboard() throws {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }
        pasteboard.hold(plainText: "earlier", richText: Self.earlierRichText)

        MarkdownSelectionClipboard.writeSelection(
            from: "alpha beta",
            ranges: [MarkdownSelectionRange(location: 0, length: 5)],
            to: pasteboard.pasteboard
        )

        #expect(pasteboard.plainText == "alpha")
        #expect(pasteboard.richText != Self.earlierRichText)
        let words = try #require(pasteboard.richTextWords)
        #expect(words.contains("alpha"))
        #expect(!words.contains("earlier"))
    }

    /// The ways a copy can have nothing in it.
    enum NothingSelected: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case noRanges = "no ranges"
        case anInsertionPoint = "an insertion point"
        case aRangePastTheEndOfTheText = "a range past the end of the text"

        var testDescription: String { rawValue }

        var ranges: [MarkdownSelectionRange] {
            switch self {
            case .noRanges: []
            case .anInsertionPoint: [MarkdownSelectionRange(location: 3, length: 0)]
            case .aRangePastTheEndOfTheText: [MarkdownSelectionRange(location: 500, length: 5)]
            }
        }
    }

    /// Copy with nothing selected must not cost the reader what they copied
    /// before.
    @Test(arguments: NothingSelected.allCases)
    func copyingNothingLeavesThePasteboardAsItWas(nothing: NothingSelected) {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }
        pasteboard.hold(plainText: "earlier", richText: Self.earlierRichText)

        let copied = MarkdownSelectionClipboard.writeSelection(
            from: "alpha beta",
            ranges: nothing.ranges,
            to: pasteboard.pasteboard
        )

        #expect(!copied)
        #expect(pasteboard.plainText == "earlier")
        #expect(pasteboard.richText == Self.earlierRichText)
    }

    // MARK: - Copying plain text alone

    /// The Copy button on a quote or a code block hands over the text and no
    /// rich text with it, so nothing that prefers formatted paste can put the
    /// markdown's decoration back.
    @Test func copyingPlainTextPutsNoRichTextWithIt() {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }

        let copied = MarkdownSelectionClipboard.writePlainText("let x = 1", to: pasteboard.pasteboard)

        #expect(copied)
        #expect(pasteboard.plainText == "let x = 1")
        #expect(pasteboard.richText == nil)
    }

    /// Rich text left there by an earlier copy would be pasted in place of the
    /// plain text by anything that prefers it, so it has to go.
    @Test func copyingPlainTextRemovesTheRichTextOfAnEarlierCopy() {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }
        pasteboard.hold(plainText: "earlier", richText: Self.earlierRichText)

        MarkdownSelectionClipboard.writePlainText("let x = 1", to: pasteboard.pasteboard)

        #expect(pasteboard.plainText == "let x = 1")
        #expect(pasteboard.richText == nil)
    }

    @Test func copyingPlainTextKeepsItsLinesAndIndentation() {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }
        let code = "if x {\n    return\n}"

        MarkdownSelectionClipboard.writePlainText(code, to: pasteboard.pasteboard)

        #expect(pasteboard.plainText == code)
    }

    @Test func copyingEmptyPlainTextLeavesThePasteboardAsItWas() {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }
        pasteboard.hold(plainText: "earlier", richText: Self.earlierRichText)

        let copied = MarkdownSelectionClipboard.writePlainText("", to: pasteboard.pasteboard)

        #expect(!copied)
        #expect(pasteboard.plainText == "earlier")
        #expect(pasteboard.richText == Self.earlierRichText)
    }

    @Test func aNewPasteboardHoldsNothingUntilSomethingIsCopied() {
        let pasteboard = PrivatePasteboard()
        defer { pasteboard.discard() }

        #expect(pasteboard.isEmpty)
        #expect(pasteboard.plainText == nil)

        MarkdownSelectionClipboard.writePlainText("copied", to: pasteboard.pasteboard)

        #expect(!pasteboard.isEmpty)
    }
}
