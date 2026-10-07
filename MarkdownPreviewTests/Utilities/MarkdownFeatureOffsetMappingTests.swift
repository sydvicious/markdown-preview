//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//
//  One small fragment per markdown feature, each checked for the thing find and
//  selection depend on: that the app's idea of a block's visible text is the
//  text the rendered block actually has, and that an offset in one can be
//  turned into an offset in the other and back.
//
//  `MarkdownFeature.visible` is written out by hand for each fragment. It is
//  NOT derived from what either side currently produces, so a failure here
//  means the source mapping is wrong, and a failure of the same fragment in
//  `WebKitTextNodeAlignmentTests` means the rendered side is. Do not weaken,
//  skip, or disable a case to make the run green.
//

import Foundation
import Testing
import MarkdownCore

struct MarkdownFeatureOffsetMappingTests {

    /// Every fragment is meant to be one block, which is the whole of its
    /// source apart from any definitions after it. If the parser disagrees, the
    /// offsets below are measured against the wrong thing, so say so before
    /// anything else does.
    @Test(arguments: MarkdownFeature.all)
    func fragmentIsOneBlockSpanningItsSource(feature: MarkdownFeature) throws {
        let blocks = MarkdownBlockParser.parse(feature.source)
        try #require(blocks.count == 1, "parsed into \(blocks.count) blocks")

        let range = MarkdownSourceLineTable(source: feature.source).range(for: blocks[0].lineRange)
        #expect(range == MarkdownSelectionRange(location: 0, length: feature.block.utf16.count))
    }

    // MARK: - Source to display text, and back

    @Test(arguments: MarkdownFeature.all)
    func sourceMappingShowsWhatTheRenderedBlockShows(feature: MarkdownFeature) {
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: feature.source)

        #expect(mapping.displayText == feature.visible)
    }

    @Test(arguments: MarkdownFeature.all.filter { !$0.words.isEmpty })
    func wordsRoundTripBetweenSourceAndDisplayText(feature: MarkdownFeature) throws {
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: feature.source)

        for word in feature.words {
            let inSource = try #require(feature.sourceRange(of: word), "\(word) is not in the source")
            let inVisible = try #require(feature.visibleRange(of: word), "\(word) is not in the visible text")

            // Source to display, and back to where it started.
            let displayed = mapping.displayRange(forSourceRange: inSource)
            #expect(displayed == inVisible, "source to display, for \(word)")
            if let displayed {
                #expect(mapping.sourceRange(forDisplayRange: displayed) == inSource, "and back, for \(word)")
            }

            // Display to source, and back to where it started.
            let sourced = mapping.sourceRange(forDisplayRange: inVisible)
            #expect(sourced == inSource, "display to source, for \(word)")
            if let sourced {
                #expect(mapping.displayRange(forSourceRange: sourced) == inVisible, "and back, for \(word)")
            }
        }
    }

    // MARK: - Source to the rendered block, and back, as the app does it

    /// The two calls the preview makes: `PreviewSelectionReflection` to place a
    /// source selection in a rendered block, and `PreviewSelectionBridge` to
    /// turn what the page reports back into a source selection. The page's own
    /// half of each trip is exercised in `WebKitTextNodeAlignmentTests`.
    @Test(arguments: MarkdownFeature.all.filter { !$0.words.isEmpty })
    func wordsRoundTripBetweenSourceAndTheRenderedBlock(feature: MarkdownFeature) throws {
        let blockEnd = feature.block.utf16.count

        for word in feature.words {
            let inSource = try #require(feature.sourceRange(of: word), "\(word) is not in the source")
            let inVisible = try #require(feature.visibleRange(of: word), "\(word) is not in the visible text")

            let reflected = PreviewSelectionReflection.reflectedSelection(
                in: feature.source,
                selectedRange: inSource
            )
            #expect(
                reflected == PreviewReflectedSelection(
                    start: .init(blockStart: 0, blockEnd: blockEnd, displayOffset: inVisible.location),
                    end: .init(
                        blockStart: 0,
                        blockEnd: blockEnd,
                        displayOffset: inVisible.location + inVisible.length
                    )
                ),
                "source to rendered block, for \(word)"
            )

            let reported: [[String: Any]] = [[
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: blockEnd),
                "displayLocation": NSNumber(value: inVisible.location),
                "displayLength": NSNumber(value: inVisible.length),
            ]]
            #expect(
                PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: reported, source: feature.source)
                    == [inSource],
                "rendered block to source, for \(word)"
            )
        }
    }

    // MARK: - Blocks after the first

    /// Everything above is measured in a block that starts at offset zero.
    /// Here the same fragments sit one after another in a single document, so
    /// each block's offsets have to be found relative to its own start, with
    /// text outside ASCII ahead of it.
    @Test func wordsRoundTripInBlocksFurtherDownADocument() throws {
        let fragments = [
            "# Héllo 😀 title",
            "First *Alpha* paragraph\nwith a second line",
            "- one\n- **Beta** two",
            "> quoted `Gamma` text",
            "| Name | Count |\n| --- | --- |\n| Delta | 12 |",
            "```\nlet epsilon = 1\n```",
            "Last [Zeta](/url) paragraph",
        ]
        let source = fragments.joined(separator: "\n\n")
        let nsSource = source as NSString

        for (fragment, word) in zip(fragments, ["title", "Alpha", "Beta", "Gamma", "Delta", "epsilon", "Zeta"]) {
            let blockRange = nsSource.range(of: fragment)
            let inSource = MarkdownSelectionRange(nsSource.range(of: word))
            let blockText = MarkdownPreviewTextOffsetMapping(sourceText: fragment).displayText as NSString
            let inBlock = blockText.range(of: word)
            try #require(inBlock.location != NSNotFound, "\(word) is not in its block's display text")

            let reflected = try #require(
                PreviewSelectionReflection.reflectedSelection(in: source, selectedRange: inSource),
                "no reflection for \(word)"
            )
            #expect(reflected.start.blockStart == blockRange.location, "block start, for \(word)")
            #expect(reflected.start.blockEnd == blockRange.location + blockRange.length, "block end, for \(word)")
            #expect(reflected.end.blockStart == reflected.start.blockStart)
            #expect(reflected.start.displayOffset == inBlock.location, "display start, for \(word)")
            #expect(reflected.end.displayOffset == inBlock.location + inBlock.length, "display end, for \(word)")

            let reported: [[String: Any]] = [[
                "blockStart": NSNumber(value: reflected.start.blockStart),
                "blockEnd": NSNumber(value: reflected.start.blockEnd),
                "displayLocation": NSNumber(value: reflected.start.displayOffset),
                "displayLength": NSNumber(value: reflected.end.displayOffset - reflected.start.displayOffset),
            ]]
            #expect(
                PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: reported, source: source) == [inSource],
                "and back to the source, for \(word)"
            )
        }
    }
}
