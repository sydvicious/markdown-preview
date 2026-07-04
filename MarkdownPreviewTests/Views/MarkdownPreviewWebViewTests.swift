//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct MarkdownPreviewWebViewTests {

    @Test func previewSelectionBridgeParsesOnlyValidDisplayRangePayloads() async throws {
        let payload: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: 20),
                "displayLocation": NSNumber(value: 4),
                "displayLength": NSNumber(value: 8)
            ],
            [
                "blockStart": NSNumber(value: 20),
                "blockEnd": NSNumber(value: 20),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 4)
            ],
            [
                "blockStart": NSNumber(value: 25),
                "blockEnd": NSNumber(value: 40),
                "displayLocation": NSNumber(value: -1),
                "displayLength": NSNumber(value: 4)
            ],
            [
                "blockStart": NSNumber(value: 45),
                "blockEnd": NSNumber(value: 60),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 0)
            ],
            [
                "blockStart": NSNumber(value: 65),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 4)
            ]
        ]

        #expect(PreviewSelectionBridge.displayRanges(from: payload) == [
            PreviewDisplaySelectionRange(blockStart: 0, blockEnd: 20, displayLocation: 4, displayLength: 8)
        ])
        #expect(PreviewSelectionBridge.displayRanges(from: nil).isEmpty)
        #expect(PreviewSelectionBridge.displayRanges(from: ["not": "an array"]).isEmpty)
    }

    @Test func previewCopyBlockMessageRequiresValidIncreasingSourceOffsets() async throws {
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: 4),
            "end": NSNumber(value: 12)
        ]) == PreviewCopyBlockMessage(start: 4, end: 12))

        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: 4),
            "end": NSNumber(value: 4)
        ]) == nil)
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: -1),
            "end": NSNumber(value: 4)
        ]) == nil)
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": "4",
            "end": NSNumber(value: 12)
        ]) == nil)
        #expect(PreviewCopyBlockMessage(messageBody: "not a payload") == nil)
    }

    @Test func previewSelectionChangedMessageNormalizesTextAndKeepsRawRangePayload() async throws {
        let ranges: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: 10),
                "displayLocation": NSNumber(value: 2),
                "displayLength": NSNumber(value: 4)
            ]
        ]
        let message = PreviewSelectionChangedMessage(messageBody: [
            "text": "  beta  ",
            "ranges": ranges
        ])

        #expect(message.selectedText == "beta")
        #expect(PreviewSelectionBridge.displayRanges(from: message.displayRangeResult) == [
            PreviewDisplaySelectionRange(blockStart: 0, blockEnd: 10, displayLocation: 2, displayLength: 4)
        ])

        let emptyTextMessage = PreviewSelectionChangedMessage(messageBody: [
            "text": "   ",
            "ranges": ranges
        ])
        #expect(emptyTextMessage.selectedText == nil)

        let malformedMessage = PreviewSelectionChangedMessage(messageBody: "not a payload")
        #expect(malformedMessage.selectedText == nil)
        #expect(PreviewSelectionBridge.displayRanges(from: malformedMessage.displayRangeResult).isEmpty)
    }

    @Test func previewSelectionBridgeMapsPartialParagraphSelectionWithoutExpandingToWholeBlock() async throws {
        let source = "Alpha beta gamma"
        let payload = displayRangePayload(in: source, visibleText: "beta")

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.count == 1)
        #expect(ranges.first?.range(in: source).map { String(source[$0]) } == "beta")
        #expect(MarkdownSelectionClipboard.selectedMarkdown(in: source, ranges: ranges) == "beta")
    }

    @Test func previewSelectionBridgeMapsInlineMarkdownSelectionsToVisibleSourceTextOnly() async throws {
        let source = "Paragraph with [beta](https://example.com), **gamma**, and `delta`."
        let payload = displayRangePayloads(in: source, visibleTexts: ["beta", "gamma", "delta"])

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.compactMap { $0.range(in: source).map { String(source[$0]) } } == [
            "beta",
            "gamma",
            "delta"
        ])
        #expect(MarkdownSelectionClipboard.selectedMarkdown(in: source, ranges: ranges) == "beta\ngamma\ndelta")
    }

    @Test func previewSelectionBridgeMapsSelectionsAcrossRenderedBlocks() async throws {
        let source = """
        # Alpha Heading

        Paragraph with beta.

        > Quote gamma

        ```
        let delta = 4
        ```
        """
        let payload = displayRangePayloads(in: source, visibleTexts: [
            "Alpha",
            "beta",
            "gamma",
            "delta"
        ])

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.compactMap { $0.range(in: source).map { String(source[$0]) } } == [
            "Alpha",
            "beta",
            "gamma",
            "delta"
        ])
    }

    @Test func previewSelectionBridgeIgnoresOutOfBoundsSourceBlocks() async throws {
        let source = "Alpha beta"
        let payload: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: 10),
                "displayLocation": NSNumber(value: 6),
                "displayLength": NSNumber(value: 4)
            ],
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: source.utf16.count + 20),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 5)
            ],
            [
                "blockStart": NSNumber(value: source.utf16.count + 1),
                "blockEnd": NSNumber(value: source.utf16.count + 5),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 4)
            ]
        ]

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.count == 1)
        #expect(ranges.first?.range(in: source).map { String(source[$0]) } == "beta")
    }

    @Test func previewSelectionBridgeIgnoresDisplayRangesThatDoNotMapToSourceText() async throws {
        let source = "Alpha beta"
        let payload: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: source.utf16.count),
                "displayLocation": NSNumber(value: 6),
                "displayLength": NSNumber(value: 4)
            ],
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: source.utf16.count),
                "displayLocation": NSNumber(value: 50),
                "displayLength": NSNumber(value: 3)
            ]
        ]

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.count == 1)
        #expect(ranges.first?.range(in: source).map { String(source[$0]) } == "beta")
    }

    @Test func previewSelectionBridgeHandlesDisplayRangesInsideListAndTableBlocks() async throws {
        let source = """
        - Alpha item
        - Beta item

        | Name | Count |
        | --- | ---: |
        | Gamma | 12 |
        """
        let payload = displayRangePayloads(in: source, visibleTexts: [
            "Beta",
            "Gamma",
            "12"
        ])

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.compactMap { $0.range(in: source).map { String(source[$0]) } } == [
            "Beta",
            "Gamma",
            "12"
        ])
    }

    private func displayRangePayload(in source: String, visibleText: String) -> [[String: Any]] {
        displayRangePayloads(in: source, visibleTexts: [visibleText])
    }

    private func displayRangePayloads(in source: String, visibleTexts: [String]) -> [[String: Any]] {
        let blocks = MarkdownBlockParser.parse(source)
        let lineTable = MarkdownSourceLineTable(source: source)

        return visibleTexts.compactMap { visibleText -> [String: Any]? in
            for block in blocks {
                guard let blockRange = lineTable.range(for: block.lineRange) else { continue }
                let blockSource = (source as NSString).substring(with: blockRange.nsRange)
                let mapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource)
                let displayRange = (mapping.displayText as NSString).range(of: visibleText)
                guard displayRange.location != NSNotFound else { continue }

                return [
                    "blockStart": NSNumber(value: blockRange.location),
                    "blockEnd": NSNumber(value: blockRange.location + blockRange.length),
                    "displayLocation": NSNumber(value: displayRange.location),
                    "displayLength": NSNumber(value: displayRange.length)
                ]
            }

            Issue.record("Expected visible text \(visibleText) in preview display text")
            return nil
        }
    }
}
