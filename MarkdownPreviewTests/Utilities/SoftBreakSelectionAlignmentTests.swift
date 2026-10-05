//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

/// Find and selection depend on two independent mappings agreeing about the
/// document's visible text: `MarkdownPreviewTextOffsetMapping` walks the
/// markdown source, and the preview's JavaScript walks the rendered DOM. A
/// search result's source offsets are translated through the first and applied
/// through the second, so any disagreement puts the highlight in the wrong
/// place — or nowhere.
///
/// Soft breaks are where that alignment is most at risk: a newline inside a
/// paragraph now renders as `<br />` where it once rendered as a bare newline.
/// These tests stand in for the DOM with `blockTextNodes`, so the agreement can
/// be checked headlessly rather than by selecting text in a running app.
///
/// What this cannot prove: `blockTextNodes` is still a model. If it and WebKit
/// disagree about whitespace around `<br>`, these tests pass and the app is
/// wrong. That single question is all the runtime check still owes.
struct SoftBreakSelectionAlignmentTests {

    /// A paragraph whose lines are separated by bare newlines — soft breaks.
    private let multiLineParagraph = """
    Sincerely yours,
    Syd Polk
    Somewhere in Texas
    """

    /// The text the DOM would expose for the document's first block, which is
    /// what the preview's `acceptedTextNodesInBlock` walks.
    ///
    /// Elements contribute no characters of their own — a `<br>` included. The
    /// builder emits `<br />\n`, so the line break the DOM sees is the literal
    /// newline that follows the tag, which is why one break stays one character.
    private func blockTextNodes(for source: String) -> String {
        let html = MarkdownHTMLBuilder.document(for: source, softBreak: .lineBreak)

        guard let blockStart = html.range(of: "<div class=\"md-block"),
              let contentStart = html.range(of: ">", range: blockStart.upperBound..<html.endIndex),
              let blockEnd = html.range(
                  of: "</div>",
                  options: .backwards,
                  range: contentStart.upperBound..<html.endIndex
              ) else {
            return ""
        }

        var text = ""
        var isInsideTag = false
        for character in html[contentStart.upperBound..<blockEnd.lowerBound] {
            switch character {
            case "<": isInsideTag = true
            case ">": isInsideTag = false
            default: if !isInsideTag { text.append(character) }
            }
        }
        return text
    }

    // MARK: - The two mappings agree

    @Test func sourceAndRenderedMappingsAgreeOnAMultiLineParagraph() {
        let sourceMapping = MarkdownPreviewTextOffsetMapping(sourceText: multiLineParagraph)
        #expect(sourceMapping.displayText == blockTextNodes(for: multiLineParagraph))
    }

    /// A hard break (two trailing spaces) and a soft break both render as
    /// `<br />` now, so they must map identically. If only one of the two paths
    /// learned about `<br />`, this diverges.
    @Test func hardAndSoftBreaksMapToTheSameVisibleText() {
        let softBreaks = "First line\nSecond line"
        let hardBreaks = "First line  \nSecond line"

        let softMapping = MarkdownPreviewTextOffsetMapping(sourceText: softBreaks)
        let hardMapping = MarkdownPreviewTextOffsetMapping(sourceText: hardBreaks)

        #expect(softMapping.displayText == hardMapping.displayText)
        #expect(blockTextNodes(for: softBreaks) == blockTextNodes(for: hardBreaks))
    }

    // MARK: - A search match after a break still lands correctly

    /// The whole find-to-highlight chain except the DOM call: search the source,
    /// reflect the match into preview coordinates, then read those coordinates
    /// out of the *rendered* text and check the same word comes back.
    @Test func searchMatchAfterASoftBreakReflectsToTheSameWord() throws {
        for query in ["Sincerely", "Syd", "Texas"] {
            let match = try #require(
                MarkdownSearch.matches(in: multiLineParagraph, query: query).first,
                "expected a source match for \(query)"
            )
            let reflected = try #require(
                PreviewSelectionReflection.reflectedSelection(
                    in: multiLineParagraph,
                    selectedRange: match
                ),
                "expected a reflected selection for \(query)"
            )

            // A word never spans blocks, so both ends land in the same one.
            #expect(reflected.start.blockStart == reflected.end.blockStart)

            let renderedText = blockTextNodes(for: multiLineParagraph) as NSString
            let reflectedWord = renderedText.substring(
                with: NSRange(
                    location: reflected.start.displayOffset,
                    length: reflected.end.displayOffset - reflected.start.displayOffset
                )
            )

            #expect(reflectedWord == query)
        }
    }

    /// The offsets have to keep agreeing *past* a break, which is where a
    /// one-character discrepancy per line would show up.
    @Test func displayOffsetsStayAlignedAcrossSeveralBreaks() throws {
        let sourceMapping = MarkdownPreviewTextOffsetMapping(sourceText: multiLineParagraph)
        let renderedText = blockTextNodes(for: multiLineParagraph) as NSString

        // The last word sits after two breaks, so any drift has accumulated.
        let match = try #require(MarkdownSearch.matches(in: multiLineParagraph, query: "Texas").first)
        let displayRange = try #require(sourceMapping.displayRange(forSourceRange: match))

        #expect(renderedText.substring(with: displayRange.nsRange) == "Texas")
    }

    // MARK: - The Copy button's text must not count

    /// Copyable blocks carry a `Copy` button in their markup. The preview's
    /// JavaScript skips it when collecting text nodes; a mapping that counted it
    /// would shift every offset in the block by four characters.
    @Test func theCopyButtonsLabelIsNotPartOfABlocksVisibleText() {
        let quote = "> Quoted line one\n> Quoted line two"
        let sourceMapping = MarkdownPreviewTextOffsetMapping(sourceText: quote)

        #expect(sourceMapping.displayText.contains("Copy") == false)
        #expect(
            MarkdownHTMLBuilder.document(for: quote, softBreak: .lineBreak).contains("md-copy-button")
        )
    }
}
