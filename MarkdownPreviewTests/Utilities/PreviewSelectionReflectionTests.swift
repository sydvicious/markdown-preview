//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore

struct PreviewSelectionReflectionTests {

    @Test func previewSelectionReflectionFindsSydInLicenseParagraph() async throws {
        let source = """
        Copyright (c) 2026, Syd Polk
        All rights reserved.
        """
        let selection = MarkdownSearch.matches(in: source, query: "Syd").first

        let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: source,
            selectedRange: selection
        )

        #expect(reflectedSelection?.start.blockStart == 0)
        #expect(reflectedSelection?.start.blockEnd == 49)
        #expect(reflectedSelection?.start.displayOffset == 20)
        #expect(reflectedSelection?.end.blockStart == 0)
        #expect(reflectedSelection?.end.blockEnd == 49)
        #expect(reflectedSelection?.end.displayOffset == 23)
    }

    @Test func previewSelectionReflectionAdjustsForOrderedListOffsets() async throws {
        let source = """
        1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
        2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
        3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
        """
        let selection = MarkdownSearch.matches(in: source, query: "be").first

        let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: source,
            selectedRange: selection
        )

        #expect(reflectedSelection?.start.blockStart == 0)
        #expect(reflectedSelection?.start.blockEnd == source.utf16.count)
        #expect(reflectedSelection?.start.displayOffset == 405)
        #expect(reflectedSelection?.end.displayOffset == 407)
    }

    @Test func previewSelectionReflectionMapsVisibleSearchMatchesInsideMixedMarkdownBlocks() async throws {
        let source = """
        Paragraph with [beta](https://example.com), **gamma**, and `delta`.

        1. Theta item
        2. Iota item

        | Name | Count |
        | --- | ---: |
        | Lambda | 12 |
        """
        let queries = ["beta", "gamma", "delta", "Iota", "Lambda", "12"]

        for query in queries {
            guard let selection = MarkdownSearch.matches(in: source, query: query).first else {
                Issue.record("Expected source match for \(query)")
                continue
            }

            guard let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
                in: source,
                selectedRange: selection
            ) else {
                Issue.record("Expected reflected selection for \(query)")
                continue
            }

            // A search match never spans blocks, so both ends land in the same one.
            #expect(reflectedSelection.start.blockStart == reflectedSelection.end.blockStart)

            let blockSource = (source as NSString).substring(
                with: NSRange(
                    location: reflectedSelection.start.blockStart,
                    length: reflectedSelection.start.blockEnd - reflectedSelection.start.blockStart
                )
            )
            let previewMapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource)
            let previewSnippet = (previewMapping.displayText as NSString).substring(
                with: NSRange(
                    location: reflectedSelection.start.displayOffset,
                    length: reflectedSelection.end.displayOffset - reflectedSelection.start.displayOffset
                )
            )

            #expect(previewSnippet == query)
        }
    }

    /// The bug this rewrite fixes: a selection dragged across a paragraph
    /// boundary in the source view reflected to nothing, so switching to the
    /// preview showed no selection at all.
    @Test func selectionSpanningTwoParagraphsReflectsToBothBlocks() throws {
        let source = """
        First paragraph here.

        Second paragraph here.
        """
        let start = (source as NSString).range(of: "paragraph here.").location
        let secondEnd = (source as NSString).range(of: "Second paragraph").location + "Second paragraph".utf16.count
        let selection = MarkdownSelectionRange(location: start, length: secondEnd - start)

        let reflected = try #require(
            PreviewSelectionReflection.reflectedSelection(in: source, selectedRange: selection)
        )

        #expect(reflected.start.blockStart == 0)
        #expect(reflected.end.blockStart > reflected.start.blockStart)
        #expect(reflected.start.displayOffset == "First ".utf16.count)
        #expect(reflected.end.displayOffset == "Second paragraph".utf16.count)
    }

    /// Selecting whole paragraphs sweeps up the blank line between them, which
    /// belongs to no block; overlap rather than containment is what makes that
    /// work.
    @Test func selectionCoveringWholeParagraphsIncludingTheBlankLineReflects() throws {
        let source = """
        First paragraph here.

        Second paragraph here.
        """
        let selection = MarkdownSelectionRange(location: 0, length: source.utf16.count)

        let reflected = try #require(
            PreviewSelectionReflection.reflectedSelection(in: source, selectedRange: selection)
        )

        #expect(reflected.start.displayOffset == 0)
        #expect(reflected.end.blockStart > reflected.start.blockStart)
        #expect(reflected.end.displayOffset == "Second paragraph here.".utf16.count)
    }

    @Test func anEmptySelectionReflectsToNothing() {
        #expect(PreviewSelectionReflection.reflectedSelection(in: "Some text.", selectedRange: nil) == nil)
        #expect(
            PreviewSelectionReflection.reflectedSelection(
                in: "Some text.",
                selectedRange: MarkdownSelectionRange(location: 2, length: 0)
            ) == nil
        )
    }

    // MARK: - In a document that has already been read

    // The page is built from a reading of the document, off the main actor,
    // and the reading comes back with the page. A selection is placed from
    // that, so that the document is not read again to place it: 90 ms for
    // 1.4 MB, on the main actor, for each document a selection was put in.
    @Test func aSelectionIsPlacedInAReadingAsItIsInItsSource() throws {
        let source = """
        # Notes

        A paragraph with a [link][home] and *emphasis*,
        on two lines.

        - one
        - two

        > Quoted, with a [link][home] of its own.

        [home]: https://example.com
        """
        let reading = MarkdownReading(of: source)
        let length = source.utf16.count
        let selections = [
            MarkdownSelectionRange(location: 2, length: 5),
            MarkdownSelectionRange(location: 9, length: 40),
            MarkdownSelectionRange(location: 30, length: 12),
            MarkdownSelectionRange(location: 0, length: length),
            MarkdownSelectionRange(location: length - 30, length: 30)
        ]

        var placed = 0
        for selection in selections {
            let inSource = PreviewSelectionReflection.reflectedSelection(in: source, selectedRange: selection)
            let inReading = PreviewSelectionReflection.reflectedSelection(in: reading, selectedRange: selection)

            #expect(inReading == inSource, "\(selection)")
            if inReading != nil {
                placed += 1
            }
        }
        // Or it would hold of a function that places nothing.
        #expect(placed >= 4)
    }

    @Test func noSelectionIsPlacedNowhereInAReading() {
        let reading = MarkdownReading(of: "Some text.")

        #expect(PreviewSelectionReflection.reflectedSelection(in: reading, selectedRange: nil) == nil)
    }

    // MARK: - Across many blocks

    private static let fiveParagraphs = "Alpha one.\n\nBeta two.\n\nGamma three.\n\nDelta four.\n\nEpsilon five."

    // A selection is two points, one in the first block it touches and one in
    // the last. The blocks between are passed over, however many there are.
    @Test func aSelectionAcrossSeveralBlocksIsPlacedByItsFirstAndItsLast() {
        // From "two" in the second paragraph to the end of "Delta" in the fourth.
        let selection = MarkdownSelectionRange(location: 17, length: 25)

        let placed = PreviewSelectionReflection.reflectedSelection(
            in: MarkdownReading(of: Self.fiveParagraphs),
            selectedRange: selection
        )

        #expect(placed == PreviewReflectedSelection(
            start: PreviewReflectedSelectionPoint(blockStart: 12, blockEnd: 21, displayOffset: 5),
            end: PreviewReflectedSelectionPoint(blockStart: 37, blockEnd: 48, displayOffset: 5)
        ))
    }

    @Test func aDocumentSelectedWholeIsPlacedFromItsFirstBlockToItsLast() {
        let source = Self.fiveParagraphs
        let everything = MarkdownSelectionRange(location: 0, length: source.utf16.count)

        let placed = PreviewSelectionReflection.reflectedSelection(
            in: MarkdownReading(of: source),
            selectedRange: everything
        )

        #expect(placed == PreviewReflectedSelection(
            start: PreviewReflectedSelectionPoint(blockStart: 0, blockEnd: 10, displayOffset: 0),
            end: PreviewReflectedSelectionPoint(blockStart: 50, blockEnd: 63, displayOffset: 13)
        ))
    }

    @Test func aSelectionInOneBlockOfManyIsPlacedInThatBlock() {
        // "Gamma".
        let selection = MarkdownSelectionRange(location: 23, length: 5)

        let placed = PreviewSelectionReflection.reflectedSelection(
            in: MarkdownReading(of: Self.fiveParagraphs),
            selectedRange: selection
        )

        #expect(placed == PreviewReflectedSelection(
            start: PreviewReflectedSelectionPoint(blockStart: 23, blockEnd: 35, displayOffset: 0),
            end: PreviewReflectedSelectionPoint(blockStart: 23, blockEnd: 35, displayOffset: 5)
        ))
    }
}
