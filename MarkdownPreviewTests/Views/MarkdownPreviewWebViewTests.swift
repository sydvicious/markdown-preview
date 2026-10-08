//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore

struct MarkdownPreviewWebViewTests {

    /// The regression this guards: with nothing selected in the preview and
    /// nothing incoming, comparing the optionals directly reported an echo, so
    /// clearing the selection never reached the web view and a stale search
    /// highlight stayed on screen.
    @Test func noSelectionIsNotMistakenForAPreviewEcho() {
        #expect(
            PreviewSelectionBridge.isEcho(ofPreviewOriginated: nil, incoming: nil) == false
        )
    }

    @Test func clearingASelectionIsNotAPreviewEcho() {
        let previewOriginated = MarkdownSelectionRange(location: 4, length: 8)

        #expect(
            PreviewSelectionBridge.isEcho(ofPreviewOriginated: previewOriginated, incoming: nil) == false
        )
    }

    @Test func aMatchingPreviewOriginatedSelectionIsAnEcho() {
        let range = MarkdownSelectionRange(location: 4, length: 8)

        #expect(
            PreviewSelectionBridge.isEcho(ofPreviewOriginated: range, incoming: range)
        )
    }

    @Test func aDifferentSelectionIsNotAPreviewEcho() {
        #expect(
            PreviewSelectionBridge.isEcho(
                ofPreviewOriginated: MarkdownSelectionRange(location: 4, length: 8),
                incoming: MarkdownSelectionRange(location: 9, length: 2)
            ) == false
        )
    }

    /// The preview reports one contiguous selection as several ranges, one per
    /// visible run. Spanning them is what puts the markdown syntax between those
    /// runs back into the plain-text clip.
    @Test func enclosingRangeSpansTheGapsBetweenVisibleRuns() throws {
        let ranges = [
            MarkdownSelectionRange(location: 10, length: 5),
            MarkdownSelectionRange(location: 40, length: 8),
            MarkdownSelectionRange(location: 22, length: 3)
        ]

        let enclosing = try #require(PreviewSelectionBridge.enclosingRange(of: ranges))

        #expect(enclosing == MarkdownSelectionRange(location: 10, length: 38))
    }

    /// A selection is one contiguous source range, whichever view reported it,
    /// so the preview's per-run ranges collapse before they reach the model.
    @Test func previewSelectionIsReportedAsOneContiguousRange() throws {
        let source = "# Heading\n\nA paragraph with text."
        let payload: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: 9),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 7)
            ],
            [
                "blockStart": NSNumber(value: 11),
                "blockEnd": NSNumber(value: source.utf16.count),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 11)
            ]
        ]

        let ranges = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: source
        )

        // "Heading" in the first block and "A paragraph" in the second, and
        // everything in the source between them: the `#` before the heading is
        // outside it, the blank line after is inside.
        #expect(ranges == [MarkdownSelectionRange(location: 2, length: 20)])
        let selected = try #require(ranges.first?.range(in: source))
        #expect(source[selected] == "Heading\n\nA paragraph")
    }

    // A reference is a link only by a definition somewhere else in the
    // document, so where a selection in the preview falls in the source
    // depends on the document's definitions. They are handed over with the
    // selection, from what was read to build the page. Without them the whole
    // document was read for them each time the selection changed.
    @Test func aPreviewSelectionIsMappedWithTheDefinitionsItIsGiven() {
        let source = "See [home] now.\n\n[home]: https://example.com"
        // "home", as the reader sees the line when `[home]` is a link: "See home now."
        let payload: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: 15),
                "displayLocation": NSNumber(value: 4),
                "displayLength": NSNumber(value: 4)
            ]
        ]

        let withTheDocuments = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: source,
            definitions: MarkdownReading(of: source).definitions
        )
        // With none, `[home]` is so many characters and the same four fall
        // one earlier: "[hom".
        let withNone = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: source,
            definitions: MarkdownLinkDefinitions.none
        )
        let leftToFindThem = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: source
        )

        #expect(withTheDocuments == [MarkdownSelectionRange(location: 5, length: 4)])
        #expect(withNone == [MarkdownSelectionRange(location: 4, length: 4)])
        #expect(leftToFindThem == withTheDocuments)
    }

    // MARK: - A selection across many blocks

    /// Six paragraphs, each on a line of its own with a blank line after:
    /// "Paragraph 0 is here." at 0, "Paragraph 1 is here." at 22, and so on.
    private static let sixParagraphs = (0..<6).map { "Paragraph \($0) is here." }.joined(separator: "\n\n")

    /// What the page reports for a block selected from `from` for `length`
    /// characters of its text.
    private static func reported(
        paragraph index: Int,
        from location: Int = 0,
        length: Int = 20,
        continuesPastText: Bool = false
    ) -> [String: Any] {
        var range: [String: Any] = [
            "blockStart": NSNumber(value: index * 22),
            "blockEnd": NSNumber(value: index * 22 + 20),
            "displayLocation": NSNumber(value: location),
            "displayLength": NSNumber(value: length)
        ]
        if continuesPastText {
            range["continuesPastText"] = true
        }
        return range
    }

    // A selection is one stretch of the source, from where its first block's
    // share begins to where its last block's ends. The blocks between decide
    // nothing, however many there are, and are not read to find out: a
    // selection across a thousand blocks took a third of a second to follow,
    // each time it changed.
    @Test func aSelectionAcrossManyBlocksRunsFromItsFirstToItsLast() {
        // From "1 is here." in the second paragraph to "Paragraph" in the fifth.
        let payload: [[String: Any]] = [
            Self.reported(paragraph: 1, from: 10, length: 10, continuesPastText: true),
            Self.reported(paragraph: 2, continuesPastText: true),
            Self.reported(paragraph: 3, continuesPastText: true),
            Self.reported(paragraph: 4, length: 9)
        ]

        let ranges = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: Self.sixParagraphs
        )

        #expect(ranges == [MarkdownSelectionRange(location: 32, length: 65)])
    }

    @Test func wholeBlocksSelectedAreWholeLinesOfTheSource() {
        let payload = (1...4).map { Self.reported(paragraph: $0, continuesPastText: true) }

        let ranges = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: Self.sixParagraphs
        )

        // From the start of the second paragraph's line to the start of the
        // line after the fifth's.
        #expect(ranges == [MarkdownSelectionRange(location: 22, length: 87)])
    }

    // What the page says of a block that is not in the source, or of none of
    // a block's text, is passed over, at either end.
    @Test func aBlockThatMapsToNothingAtEitherEndIsPassedOver() {
        let outside: [String: Any] = [
            "blockStart": NSNumber(value: 5_000),
            "blockEnd": NSNumber(value: 5_020),
            "displayLocation": NSNumber(value: 0),
            "displayLength": NSNumber(value: 20)
        ]
        let payload: [[String: Any]] = [
            Self.reported(paragraph: 0, length: 0),
            Self.reported(paragraph: 1, from: 10, length: 10),
            Self.reported(paragraph: 2),
            Self.reported(paragraph: 3, length: 9),
            outside
        ]

        let ranges = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: Self.sixParagraphs
        )

        #expect(ranges == [MarkdownSelectionRange(location: 32, length: 43)])
    }

    @Test func blocksReportedOutOfOrderStillRunFromTheEarliestToTheLatest() {
        let payload: [[String: Any]] = [
            Self.reported(paragraph: 3, length: 9),
            Self.reported(paragraph: 1, from: 10, length: 10),
            Self.reported(paragraph: 4, length: 9),
            Self.reported(paragraph: 2)
        ]

        let ranges = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: Self.sixParagraphs
        )

        #expect(ranges == [MarkdownSelectionRange(location: 32, length: 65)])
    }

    @Test func aSelectionAcrossBlocksThatAllMapToNothingIsNoSelection() {
        let payload = (0..<4).map { Self.reported(paragraph: $0, length: 0) }

        let ranges = PreviewSelectionBridge.contiguousSelectionRanges(
            fromDisplayRangeResult: payload,
            source: Self.sixParagraphs
        )

        #expect(ranges.isEmpty)
    }

    @Test func enclosingRangeOfNothingIsNil() {
        #expect(PreviewSelectionBridge.enclosingRange(of: []) == nil)
        #expect(
            PreviewSelectionBridge.enclosingRange(
                of: [MarkdownSelectionRange(location: 4, length: 0)]
            ) == nil
        )
    }

    @Test func copyBlockMessageCarriesTheBlockKind() throws {
        let message = try #require(
            PreviewCopyBlockMessage(messageBody: [
                "start": NSNumber(value: 4),
                "end": NSNumber(value: 20),
                "kind": "blockquote"
            ])
        )

        #expect(message == PreviewCopyBlockMessage(start: 4, end: 20, kind: .blockquote))
    }

    /// A page without the attribute, or with a value this build does not know,
    /// still copies — just as raw source.
    @Test func copyBlockMessageToleratesAMissingOrUnknownKind() throws {
        let missing = try #require(
            PreviewCopyBlockMessage(messageBody: [
                "start": NSNumber(value: 0),
                "end": NSNumber(value: 5)
            ])
        )
        #expect(missing.kind == nil)

        let unknown = try #require(
            PreviewCopyBlockMessage(messageBody: [
                "start": NSNumber(value: 0),
                "end": NSNumber(value: 5),
                "kind": "sonnet"
            ])
        )
        #expect(unknown.kind == nil)
    }

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

    @Test func aSelectionArrivingWithNoneFromThePreviewIsNotAnEcho() {
        #expect(
            PreviewSelectionBridge.isEcho(
                ofPreviewOriginated: nil,
                incoming: MarkdownSelectionRange(location: 4, length: 8)
            ) == false
        )
    }

    /// The span ends where the range reaching furthest ends, which need not be
    /// the range that starts last.
    @Test func enclosingRangeEndsAtTheLatestEndWhicheverRangeHasIt() {
        let holdingTheOthers = [
            MarkdownSelectionRange(location: 10, length: 50),
            MarkdownSelectionRange(location: 20, length: 5),
            MarkdownSelectionRange(location: 40, length: 8)
        ]
        let overlapping = [
            MarkdownSelectionRange(location: 15, length: 10),
            MarkdownSelectionRange(location: 10, length: 10)
        ]

        #expect(
            PreviewSelectionBridge.enclosingRange(of: holdingTheOthers)
                == MarkdownSelectionRange(location: 10, length: 50)
        )
        #expect(
            PreviewSelectionBridge.enclosingRange(of: overlapping)
                == MarkdownSelectionRange(location: 10, length: 15)
        )
    }

    @Test func enclosingRangeOfOneRangeIsThatRange() {
        let range = MarkdownSelectionRange(location: 12, length: 7)

        #expect(PreviewSelectionBridge.enclosingRange(of: [range]) == range)
    }

    /// An empty range covers nothing, but it is still a place, and the span
    /// runs from the earliest start to the latest end.
    @Test func enclosingRangeReachesAnEmptyRangeBesideOnesWithText() {
        let ranges = [
            MarkdownSelectionRange(location: 4, length: 0),
            MarkdownSelectionRange(location: 10, length: 5)
        ]

        #expect(
            PreviewSelectionBridge.enclosingRange(of: ranges)
                == MarkdownSelectionRange(location: 4, length: 11)
        )
    }

    /// No ranges is what makes a copy from the preview fall back, and what
    /// leaves the last selection the preview reported in place.
    @Test func aPreviewSelectionWithNothingUsableInItIsNoSelection() {
        let source = "Alpha beta"
        let results: [Any?] = [
            nil,
            "not ranges",
            [[String: Any]](),
            // A block reaching past the end of the source.
            [displayRange(blockStart: 0, blockEnd: source.utf16.count + 20, displayLocation: 0, displayLength: 5)],
            // Text the block does not have.
            [displayRange(blockStart: 0, blockEnd: source.utf16.count, displayLocation: 50, displayLength: 3)]
        ]

        for result in results {
            #expect(
                PreviewSelectionBridge.contiguousSelectionRanges(fromDisplayRangeResult: result, source: source)
                    .isEmpty,
                "\(String(describing: result))"
            )
        }
    }

    /// `displayRanges(from:)` asks only that a block end after it starts, so
    /// one that starts before the source gets as far as here.
    @Test func previewSelectionBridgeIgnoresABlockStartingBeforeTheSource() {
        let source = "Alpha beta"
        let payload = [
            displayRange(blockStart: -4, blockEnd: source.utf16.count, displayLocation: 0, displayLength: 5),
            displayRange(blockStart: 0, blockEnd: source.utf16.count, displayLocation: 6, displayLength: 4)
        ]

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges == [MarkdownSelectionRange(location: 6, length: 4)])
    }

    @Test func previewSelectionBridgeKeepsTheValidDisplayRangesAfterInvalidOnes() {
        let valid = displayRange(blockStart: 30, blockEnd: 40, displayLocation: 2, displayLength: 4)
        let payload: [[String: Any]] = [
            // Numbers written as text.
            ["blockStart": "0", "blockEnd": "20", "displayLocation": "4", "displayLength": "8"],
            // A block that ends before it starts.
            displayRange(blockStart: 20, blockEnd: 10, displayLocation: 0, displayLength: 4),
            displayRange(blockStart: 0, blockEnd: 20, displayLocation: 4, displayLength: -8),
            valid
        ]

        #expect(PreviewSelectionBridge.displayRanges(from: payload) == [
            PreviewDisplaySelectionRange(blockStart: 30, blockEnd: 40, displayLocation: 2, displayLength: 4)
        ])
    }

    /// The page reports a list of ranges and nothing else. A list with
    /// something else in it is not that message, so none of it is read.
    @Test func previewSelectionBridgeReadsNothingFromAListThatIsNotAllRanges() {
        let payload: [Any] = [
            displayRange(blockStart: 0, blockEnd: 20, displayLocation: 4, displayLength: 8),
            "not a range"
        ]

        #expect(PreviewSelectionBridge.displayRanges(from: payload).isEmpty)
    }

    @Test func copyBlockMessageNeedsAnEndThatIsANumberPastTheStart() {
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: 4)
        ]) == nil)
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: 4),
            "end": "12"
        ]) == nil)
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: 12),
            "end": NSNumber(value: 4)
        ]) == nil)
    }

    @Test func copyBlockMessageToleratesAKindThatIsNotText() throws {
        let message = try #require(
            PreviewCopyBlockMessage(messageBody: [
                "start": NSNumber(value: 0),
                "end": NSNumber(value: 5),
                "kind": NSNumber(value: 3)
            ])
        )

        #expect(message == PreviewCopyBlockMessage(start: 0, end: 5))
    }

    @Test func previewSelectionChangedMessageTrimsLineEndingsAndKeepsTheSpacesInside() {
        let message = PreviewSelectionChangedMessage(messageBody: [
            "text": "\n\t beta gamma \n"
        ])

        #expect(message.selectedText == "beta gamma")
        #expect(message.displayRangeResult == nil)
    }

    @Test func previewSelectionChangedMessageWithoutTextStillCarriesItsRanges() {
        let ranges = [displayRange(blockStart: 0, blockEnd: 10, displayLocation: 2, displayLength: 4)]
        let expected = [
            PreviewDisplaySelectionRange(blockStart: 0, blockEnd: 10, displayLocation: 2, displayLength: 4)
        ]

        let missing = PreviewSelectionChangedMessage(messageBody: ["ranges": ranges])
        #expect(missing.selectedText == nil)
        #expect(PreviewSelectionBridge.displayRanges(from: missing.displayRangeResult) == expected)

        let notText = PreviewSelectionChangedMessage(messageBody: [
            "text": NSNumber(value: 4),
            "ranges": ranges
        ])
        #expect(notText.selectedText == nil)
        #expect(PreviewSelectionBridge.displayRanges(from: notText.displayRangeResult) == expected)
    }

    // MARK: - A selection that takes a whole line

    /// Clicking three times on a line selects the line and its ending, as it
    /// does in any text view, and the page says so: the selection it reports
    /// goes on past the text it took. The copy is then the line as it is
    /// written, from where it starts to where the next one does.
    @Test func aLineSelectedWithItsEndingIsCopiedAsItIsWritten() {
        let source = "### Async file loading off `@Main`.\n- Read source files.\n"
        let payload = continuingPastItsText(
            displayRangePayload(in: source, visibleText: "Async file loading off @Main.")
        )

        #expect(copiedMarkdown(for: payload, in: source) == "### Async file loading off `@Main`.\n")
    }

    /// A selection dragged to the end of a line stops there, and is the words
    /// that were dragged over.
    @Test func aSelectionThatStopsWithItsTextTakesNoLineEndingAndNoLineStart() {
        let source = "### Async file loading off `@Main`.\n- Read source files.\n"
        let payload = displayRangePayload(in: source, visibleText: "Async file loading off @Main.")

        #expect(copiedMarkdown(for: payload, in: source) == "Async file loading off `@Main`.")
    }

    /// The last word the reader sees is not always the last thing on the line.
    @Test func whatIsWrittenAfterTheLastWordOfTheLineComesWithItsEnding() {
        let source = "A line that ends in **bold**\n\nNext."
        let payload = continuingPastItsText(
            displayRangePayload(in: source, visibleText: "A line that ends in bold")
        )

        #expect(copiedMarkdown(for: payload, in: source) == "A line that ends in **bold**\n")
    }

    @Test func aWindowsLineEndingIsTakenWhole() {
        let source = "First line.\r\n\r\nSecond."
        let payload = continuingPastItsText(displayRangePayload(in: source, visibleText: "First line."))

        #expect(copiedMarkdown(for: payload, in: source) == "First line.\r\n")
    }

    /// The last line of a document may have no ending to take. It is a whole
    /// line all the same.
    @Test func theLastLineOfADocumentThatHasNoEndingIsStillAWholeLine() {
        let source = "# Only line."
        let wholeLine = continuingPastItsText(displayRangePayload(in: source, visibleText: "Only line."))
        let dragged = displayRangePayload(in: source, visibleText: "Only line.")

        #expect(copiedMarkdown(for: wholeLine, in: source) == "# Only line.")
        #expect(copiedMarkdown(for: dragged, in: source) == "Only line.")
    }

    /// The line after the last line of a code block is its closing fence, which
    /// is not something the reader selected.
    @Test func theLastLineOfACodeBlockDoesNotTakeTheFenceWithIt() {
        let source = "```\nlet a = 1\nlet b = 2\n```\n\nAfter."
        let payload = continuingPastItsText(
            displayRangePayloads(in: source, visibleTexts: ["let b = 2"], toTheEndOfTheBlock: true)
        )

        #expect(copiedMarkdown(for: payload, in: source) == "let b = 2\n")
    }

    /// The items of a list are one block, and each is a line of its own.
    @Test func anItemInTheMiddleOfAListIsCopiedWithItsMarkerAndItsEnding() {
        let source = "- one\n- two\n- three\n"
        let wholeLine = continuingPastItsText(displayRangePayload(in: source, visibleText: "two"))
        let dragged = displayRangePayload(in: source, visibleText: "two")

        #expect(copiedMarkdown(for: wholeLine, in: source) == "- two\n")
        #expect(copiedMarkdown(for: dragged, in: source) == "two")
    }

    @Test func aQuotedLineIsCopiedWithItsMarker() {
        let source = "> Quoted line.\n\nAfter."
        let payload = continuingPastItsText(displayRangePayload(in: source, visibleText: "Quoted line."))

        #expect(copiedMarkdown(for: payload, in: source) == "> Quoted line.\n")
    }

    /// A selection can go on past its text in the middle of a line, from one
    /// run of bold into the plain text after it. That is not the end of a line.
    @Test func aSelectionThatGoesOnPastItsTextMidLineTakesNoLineEnding() {
        let source = "Some **bold** words here\n\nNext."
        let payload = continuingPastItsText(displayRangePayload(in: source, visibleText: "Some bold"))

        #expect(copiedMarkdown(for: payload, in: source) == "Some **bold")
    }

    /// The line's ending was taken, but the line was not taken from its start.
    @Test func aSelectionFromTheMiddleOfALineToItsEndingStartsWhereItWasMade() {
        let source = "## Long title\n\nNext."
        let payload = continuingPastItsText(displayRangePayload(in: source, visibleText: "title"))

        #expect(copiedMarkdown(for: payload, in: source) == "title\n")
    }

    /// Dragged from the first word of a heading into the middle of the
    /// paragraph after it. It does not end with a line, so it is not lines
    /// that were selected, and it starts with the word it was started on.
    @Test func aSelectionThatEndsMidLineStartsWhereItWasMade() {
        let source = "## Title\n\nNext paragraph.\n"
        let payload = continuingPastItsText(displayRangePayload(in: source, visibleText: "Title"))
            + displayRangePayload(in: source, visibleText: "Next")

        #expect(copiedMarkdown(for: payload, in: source) == "Title\n\nNext")
    }

    /// Several lines selected whole, as Select All does, or clicking three
    /// times and dragging.
    @Test func severalWholeLinesAreCopiedFromTheStartOfTheFirst() {
        let source = "## Title\n\nNext paragraph.\n"
        let payload = continuingPastItsText(
            displayRangePayloads(in: source, visibleTexts: ["Title", "Next paragraph."])
        )

        #expect(copiedMarkdown(for: payload, in: source) == source)
    }

    @Test func aDisplayRangeSaysWhetherItsSelectionGoesOnPastItsText() {
        var continuing = displayRange(blockStart: 0, blockEnd: 10, displayLocation: 2, displayLength: 4)
        continuing["continuesPastText"] = NSNumber(value: true)
        let silent = displayRange(blockStart: 12, blockEnd: 20, displayLocation: 0, displayLength: 3)
        var notAYesOrNo = displayRange(blockStart: 22, blockEnd: 30, displayLocation: 1, displayLength: 2)
        notAYesOrNo["continuesPastText"] = "yes"

        #expect(PreviewSelectionBridge.displayRanges(from: [continuing, silent, notAYesOrNo]) == [
            PreviewDisplaySelectionRange(
                blockStart: 0, blockEnd: 10, displayLocation: 2, displayLength: 4, continuesPastText: true
            ),
            PreviewDisplaySelectionRange(blockStart: 12, blockEnd: 20, displayLocation: 0, displayLength: 3),
            PreviewDisplaySelectionRange(blockStart: 22, blockEnd: 30, displayLocation: 1, displayLength: 2)
        ])
    }

    /// What a copy of the selection the page reported puts on the pasteboard
    /// as plain text.
    private func copiedMarkdown(for payload: [[String: Any]], in source: String) -> String? {
        MarkdownSelectionClipboard.selectedMarkdown(
            in: source,
            ranges: PreviewSelectionBridge.contiguousSelectionRanges(fromDisplayRangeResult: payload, source: source)
        )
    }

    private func continuingPastItsText(_ payload: [[String: Any]]) -> [[String: Any]] {
        payload.map { $0.merging(["continuesPastText": NSNumber(value: true)]) { _, new in new } }
    }

    private func displayRange(
        blockStart: Int,
        blockEnd: Int,
        displayLocation: Int,
        displayLength: Int
    ) -> [String: Any] {
        [
            "blockStart": NSNumber(value: blockStart),
            "blockEnd": NSNumber(value: blockEnd),
            "displayLocation": NSNumber(value: displayLocation),
            "displayLength": NSNumber(value: displayLength)
        ]
    }

    private func displayRangePayload(in source: String, visibleText: String) -> [[String: Any]] {
        displayRangePayloads(in: source, visibleTexts: [visibleText])
    }

    /// - Parameter toTheEndOfTheBlock: the range runs from the start of the
    ///   text named to the end of everything its block shows.
    private func displayRangePayloads(
        in source: String,
        visibleTexts: [String],
        toTheEndOfTheBlock: Bool = false
    ) -> [[String: Any]] {
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
                    "displayLength": NSNumber(
                        value: toTheEndOfTheBlock
                            ? (mapping.displayText as NSString).length - displayRange.location
                            : displayRange.length
                    )
                ]
            }

            Issue.record("Expected visible text \(visibleText) in preview display text")
            return nil
        }
    }
}

/// A reload starts the page at the top. When the preview reloads because the
/// document it is already showing changed, the reader should be left where they
/// were — reading a long plan while it is being edited is the case that matters.
struct PreviewScrollRestorationTests {

    private typealias Content = PreviewScrollRestoration.Content

    private let plan = "/tmp/notes/plan.md"
    private let halfway = PreviewScrollPosition(x: 0, y: 1200, maxY: 2400)

    @Test func anEditedDocumentKeepsTheReadersOffset() {
        let restoration = PreviewScrollRestoration.restoration(
            of: halfway,
            from: Content(documentID: plan, source: "before"),
            to: Content(documentID: plan, source: "after")
        )

        // The text changed, so the page's height may have too. The offset is
        // what stays true for everything above the edit.
        #expect(restoration == .offset(x: 0, y: 1200))
    }

    // A text size change, or an image becoming readable, redraws the same text
    // at a different height. The same offset would land somewhere else, so the
    // reader is put back the same way down the page.
    @Test func theSameTextRedrawnKeepsTheReadersPlaceInProportion() {
        let restoration = PreviewScrollRestoration.restoration(
            of: halfway,
            from: Content(documentID: plan, source: "same"),
            to: Content(documentID: plan, source: "same")
        )

        #expect(restoration == .fraction(x: 0, ofMaxY: 0.5))
    }

    @Test func aDifferentDocumentStartsAtTheTop() {
        let restoration = PreviewScrollRestoration.restoration(
            of: halfway,
            from: Content(documentID: plan, source: "same"),
            to: Content(documentID: "/tmp/notes/other.md", source: "same")
        )

        #expect(restoration == .top)
    }

    @Test func theFirstLoadStartsAtTheTop() {
        let restoration = PreviewScrollRestoration.restoration(
            of: halfway,
            from: nil,
            to: Content(documentID: plan, source: "text")
        )

        #expect(restoration == .top)
    }

    // Without an identity there is no telling an update from a different
    // document that happens to have the same text.
    @Test func contentWithNoIdentityStartsAtTheTop() {
        let restoration = PreviewScrollRestoration.restoration(
            of: halfway,
            from: Content(documentID: nil, source: "same"),
            to: Content(documentID: nil, source: "same")
        )

        #expect(restoration == .top)
    }

    // MARK: - Where the reader was in each document

    private let notes = "/tmp/notes/notes.md"
    private let nearTheTop = PreviewScrollPosition(x: 0, y: 300, maxY: 2400)
    private let atTheTop = PreviewScrollPosition(x: 0, y: 0, maxY: 2400)

    /// To another document and back: each is where it was left.
    @Test func aDocumentGoneBackToIsPutBackWhereItWasLeft() {
        let memory = PreviewScrollMemory()
        memory.remember(halfway, in: Content(documentID: plan, source: "the plan"))
        memory.remember(nearTheTop, in: Content(documentID: notes, source: "the notes"))

        #expect(
            memory.restoration(for: Content(documentID: plan, source: "the plan"))
                == .fraction(x: 0, ofMaxY: 0.5)
        )
        #expect(
            memory.restoration(for: Content(documentID: notes, source: "the notes"))
                == .fraction(x: 0, ofMaxY: 0.125)
        )
    }

    @Test func aDocumentNotSeenBeforeStartsAtTheTop() {
        let memory = PreviewScrollMemory()
        memory.remember(halfway, in: Content(documentID: plan, source: "the plan"))

        #expect(memory.restoration(for: Content(documentID: notes, source: "the notes")) == .top)
    }

    /// The same rule as for a document edited while it is on screen: its
    /// height may have changed, and the offset is what stays true above the
    /// edit.
    @Test func aDocumentEditedWhileTheReaderWasAwayKeepsItsOffset() {
        let memory = PreviewScrollMemory()
        memory.remember(halfway, in: Content(documentID: plan, source: "before"))

        #expect(memory.restoration(for: Content(documentID: plan, source: "after")) == .offset(x: 0, y: 1200))
    }

    @Test func theLastPlaceReportedIsTheOneKept() {
        let memory = PreviewScrollMemory()
        let content = Content(documentID: plan, source: "the plan")
        memory.remember(nearTheTop, in: content)
        memory.remember(halfway, in: content)

        #expect(memory.restoration(for: content) == .fraction(x: 0, ofMaxY: 0.5))
    }

    @Test func aDocumentScrolledBackToTheTopStartsAtTheTop() {
        let memory = PreviewScrollMemory()
        let content = Content(documentID: plan, source: "the plan")
        memory.remember(halfway, in: content)
        memory.remember(atTheTop, in: content)

        #expect(memory.restoration(for: content) == .top)
    }

    @Test func forgettingADocumentLeavesTheOthers() {
        let memory = PreviewScrollMemory()
        let planContent = Content(documentID: plan, source: "the plan")
        let notesContent = Content(documentID: notes, source: "the notes")
        memory.remember(halfway, in: planContent)
        memory.remember(nearTheTop, in: notesContent)

        memory.forget(documentID: plan)

        #expect(memory.restoration(for: planContent) == .top)
        #expect(memory.restoration(for: notesContent) == .fraction(x: 0, ofMaxY: 0.125))
    }

    /// A page with no identity, as in a SwiftUI preview, is nobody's to come
    /// back to.
    @Test func aPageThatIsNoDocumentIsNotRemembered() {
        let memory = PreviewScrollMemory()
        let content = Content(documentID: nil, source: "same")
        memory.remember(halfway, in: content)

        #expect(memory.restoration(for: content) == .top)
    }

    // MARK: - The same place in the preview and in the source

    /// The page says where the reader is twice over: where in the page, and
    /// what of the source is at the top of it. The second is what the source
    /// pane opens at.
    @Test func whereTheReaderIsInThePreviewIsAPlaceInTheSourceToo() {
        let memory = PreviewScrollMemory()
        let content = Content(documentID: plan, source: "the plan")
        memory.remember(halfway, in: content)
        memory.rememberSourceOffset(4200, in: plan, by: .preview)

        #expect(memory.sourceOffset(for: plan) == 4200)
        // And the preview itself goes back to exactly where it was.
        #expect(memory.restoration(for: content) == .fraction(x: 0, ofMaxY: 0.5))
    }

    @Test func afterTheReaderMovesInTheSourceThePreviewOpensAtThatPlaceInTheSource() {
        let memory = PreviewScrollMemory()
        let content = Content(documentID: plan, source: "the plan")
        memory.remember(halfway, in: content)
        memory.rememberSourceOffset(4200, in: plan, by: .preview)

        memory.rememberSourceOffset(9000, in: plan, by: .source)

        #expect(memory.sourceOffset(for: plan) == 9000)
        #expect(memory.restoration(for: content) == .sourceOffset(9000))
    }

    @Test func movingInThePreviewAgainPutsItBackWhereItWasItself() {
        let memory = PreviewScrollMemory()
        let content = Content(documentID: plan, source: "the plan")
        memory.rememberSourceOffset(9000, in: plan, by: .source)

        memory.remember(nearTheTop, in: content)
        memory.rememberSourceOffset(700, in: plan, by: .preview)

        #expect(memory.restoration(for: content) == .fraction(x: 0, ofMaxY: 0.125))
        #expect(memory.sourceOffset(for: plan) == 700)
    }

    @Test func aDocumentReadOnlyInTheSourceOpensInThePreviewAtThatPlace() {
        let memory = PreviewScrollMemory()
        memory.rememberSourceOffset(9000, in: plan, by: .source)

        #expect(memory.restoration(for: Content(documentID: plan, source: "the plan")) == .sourceOffset(9000))
    }

    @Test func theStartOfTheSourceIsTheTopOfThePreview() {
        let memory = PreviewScrollMemory()
        let content = Content(documentID: plan, source: "the plan")
        memory.remember(halfway, in: content)

        memory.rememberSourceOffset(0, in: plan, by: .source)

        #expect(memory.restoration(for: content) == .top)
    }

    @Test func eachDocumentHasItsOwnPlaceInTheSource() {
        let memory = PreviewScrollMemory()
        memory.rememberSourceOffset(9000, in: plan, by: .source)
        memory.rememberSourceOffset(40, in: notes, by: .preview)

        #expect(memory.sourceOffset(for: plan) == 9000)
        #expect(memory.sourceOffset(for: notes) == 40)
        #expect(memory.sourceOffset(for: "/tmp/notes/unread.md") == nil)
    }

    @Test func aForgottenDocumentHasNoPlaceInTheSource() {
        let memory = PreviewScrollMemory()
        memory.rememberSourceOffset(9000, in: plan, by: .source)

        memory.forget(documentID: plan)

        #expect(memory.sourceOffset(for: plan) == nil)
        #expect(memory.restoration(for: Content(documentID: plan, source: "the plan")) == .top)
    }

    @Test func aPageThatIsNoDocumentHasNoPlaceInTheSource() {
        let memory = PreviewScrollMemory()
        memory.rememberSourceOffset(9000, in: nil, by: .source)

        #expect(memory.sourceOffset(for: nil) == nil)
    }

    // MARK: - A selection made in one pane is where the other goes

    /// The selection is the same in both panes, and has been since before
    /// either kept a place: select something in one, and the other shows it.
    /// A place kept for the other pane does not come before that.
    @Test func aSelectionMadeInOnePaneIsForTheOtherToShow() {
        let memory = PreviewScrollMemory()
        memory.remember(halfway, in: Content(documentID: plan, source: "the plan"))

        memory.rememberSelection(in: plan, by: .preview)

        #expect(memory.takeSelectionToShow(in: plan, for: .source))
    }

    @Test func aSelectionMadeInTheSourceIsForThePreviewToShow() {
        let memory = PreviewScrollMemory()
        memory.rememberSelection(in: plan, by: .source)

        #expect(memory.takeSelectionToShow(in: plan, for: .preview))
    }

    /// It is shown once. After that the pane is where the reader left it, as
    /// any other time.
    @Test func aSelectionIsShownOnce() {
        let memory = PreviewScrollMemory()
        memory.rememberSelection(in: plan, by: .preview)

        #expect(memory.takeSelectionToShow(in: plan, for: .source))
        #expect(memory.takeSelectionToShow(in: plan, for: .source) == false)
    }

    /// The pane the selection was made in is already showing it.
    @Test func aSelectionIsNotForThePaneItWasMadeInToShow() {
        let memory = PreviewScrollMemory()
        memory.rememberSelection(in: plan, by: .preview)

        #expect(memory.takeSelectionToShow(in: plan, for: .preview) == false)
        // And asking did not use it up.
        #expect(memory.takeSelectionToShow(in: plan, for: .source))
    }

    /// Select something, then read on somewhere else: where the reader is now
    /// is where they are reading, and the other pane goes there.
    @Test func scrollingInThePreviewAfterSelectingPutsThePlaceFirstAgain() {
        let memory = PreviewScrollMemory()
        memory.rememberSelection(in: plan, by: .preview)

        // The reader moving the page is told both ways: where in the page,
        // and what of the source is at the top of it.
        memory.remember(halfway, in: Content(documentID: plan, source: "the plan"))
        memory.rememberSourceOffset(4200, in: plan, by: .preview)

        #expect(memory.takeSelectionToShow(in: plan, for: .source) == false)
    }

    @Test func scrollingInTheSourceAfterSelectingPutsThePlaceFirstAgain() {
        let memory = PreviewScrollMemory()
        memory.rememberSelection(in: plan, by: .source)

        memory.rememberSourceOffset(9000, in: plan, by: .source)

        #expect(memory.takeSelectionToShow(in: plan, for: .preview) == false)
    }

    // MARK: - Each pane stays where it was left unless the reader moved in the other

    /// Both panes are kept, each where the reader left it. One follows the
    /// other only when the reader has moved there since.
    @Test func afterTheReaderMovesInThePreviewTheSourceHasAPlaceToFollow() {
        let memory = PreviewScrollMemory()
        memory.remember(halfway, in: Content(documentID: plan, source: "the plan"))
        memory.rememberSourceOffset(4200, in: plan, by: .preview)

        #expect(memory.takePlaceToFollow(in: plan, for: .source) == 4200)
        // Followed once. After that the source pane is where the reader
        // leaves it.
        #expect(memory.takePlaceToFollow(in: plan, for: .source) == nil)
    }

    @Test func theSourceHasNothingToFollowWhenTheReaderLastMovedInIt() {
        let memory = PreviewScrollMemory()
        memory.rememberSourceOffset(4200, in: plan, by: .preview)

        memory.rememberSourceOffset(9000, in: plan, by: .source)

        #expect(memory.takePlaceToFollow(in: plan, for: .source) == nil)
    }

    /// The page tells the app where it is whenever it moves, and what of the
    /// source is at the top of it only when it was the reader who moved it.
    /// Moved by the app, to show a selection or to put the reader back, it has
    /// given the source pane nowhere to go.
    @Test func thePreviewMovedByTheAppGivesTheSourceNothingToFollow() {
        let memory = PreviewScrollMemory()
        memory.rememberSourceOffset(9000, in: plan, by: .source)

        memory.remember(halfway, in: Content(documentID: plan, source: "the plan"))

        #expect(memory.takePlaceToFollow(in: plan, for: .source) == nil)
    }

    /// Nor has it stopped being the source the reader was last in: a preview
    /// loaded again goes to where they were there.
    @Test func thePreviewMovedByTheAppIsStillFollowingTheSource() {
        let memory = PreviewScrollMemory()
        let content = Content(documentID: plan, source: "the plan")
        memory.rememberSourceOffset(9000, in: plan, by: .source)

        memory.remember(halfway, in: content)

        #expect(memory.restoration(for: content) == .sourceOffset(9000))
    }

    @Test func thePreviewMovedByTheAppLeavesASelectionStillToShow() {
        let memory = PreviewScrollMemory()
        memory.rememberSelection(in: plan, by: .preview)

        memory.remember(halfway, in: Content(documentID: plan, source: "the plan"))

        #expect(memory.takeSelectionToShow(in: plan, for: .source))
    }

    /// The preview's place to follow is where `restoration` puts it.
    @Test func thePreviewIsNotAskedForAPlaceToFollowThisWay() {
        let memory = PreviewScrollMemory()
        memory.rememberSourceOffset(9000, in: plan, by: .source)

        #expect(memory.takePlaceToFollow(in: plan, for: .preview) == nil)
    }

    @Test func aForgottenDocumentHasNoPlaceToFollow() {
        let memory = PreviewScrollMemory()
        memory.rememberSourceOffset(4200, in: plan, by: .preview)

        memory.forget(documentID: plan)

        #expect(memory.takePlaceToFollow(in: plan, for: .source) == nil)
        #expect(memory.takePlaceToFollow(in: nil, for: .source) == nil)
    }

    @Test func aSelectionInOneDocumentIsNotAnothersToShow() {
        let memory = PreviewScrollMemory()
        memory.rememberSelection(in: plan, by: .preview)

        #expect(memory.takeSelectionToShow(in: notes, for: .source) == false)
        #expect(memory.takeSelectionToShow(in: nil, for: .source) == false)
        #expect(memory.takeSelectionToShow(in: plan, for: .source))
    }

    @Test func aForgottenDocumentHasNoSelectionToShow() {
        let memory = PreviewScrollMemory()
        memory.rememberSelection(in: plan, by: .preview)

        memory.forget(documentID: plan)

        #expect(memory.takeSelectionToShow(in: plan, for: .source) == false)
    }

    /// The page says of a selection whether the app put it there. One it did
    /// is an echo, and not the reader selecting something in the preview.
    @Test func thePageSaysWhetherASelectionWasTheAppsDoing() {
        let ranges = [["blockStart": NSNumber(value: 0), "blockEnd": NSNumber(value: 10),
                       "displayLocation": NSNumber(value: 2), "displayLength": NSNumber(value: 4)]]

        #expect(PreviewSelectionChangedMessage(messageBody: ["ranges": ranges, "applied": NSNumber(value: true)]).wasApplied)
        #expect(PreviewSelectionChangedMessage(messageBody: ["ranges": ranges]).wasApplied == false)
        #expect(PreviewSelectionChangedMessage(messageBody: ["ranges": ranges, "applied": "yes"]).wasApplied == false)
        #expect(PreviewSelectionChangedMessage(messageBody: "not a payload").wasApplied == false)
    }

    // MARK: - What the page says of the place in the source

    @Test func thePlaceInTheSourceIsReadAsAWholeNumber() {
        #expect(PreviewSourceOffsetMessage(messageBody: NSNumber(value: 160))?.offset == 160)
        #expect(PreviewSourceOffsetMessage(messageBody: NSNumber(value: 0))?.offset == 0)
        #expect(PreviewSourceOffsetMessage(messageBody: NSNumber(value: 160.4))?.offset == 160)
    }

    @Test func aPlaceInTheSourceThatIsNotOneIsIgnored() {
        #expect(PreviewSourceOffsetMessage(messageBody: "160") == nil)
        #expect(PreviewSourceOffsetMessage(messageBody: NSNumber(value: -4)) == nil)
        #expect(PreviewSourceOffsetMessage(messageBody: NSNumber(value: Double.nan)) == nil)
        #expect(PreviewSourceOffsetMessage(messageBody: NSNumber(value: Double.infinity)) == nil)
        #expect(PreviewSourceOffsetMessage(messageBody: [NSNumber(value: 160)]) == nil)
        #expect(PreviewSourceOffsetMessage(messageBody: NSNull()) == nil)
    }

    @Test func aReaderAlreadyAtTheTopStaysThere() {
        let edited = PreviewScrollRestoration.restoration(
            of: PreviewScrollPosition(x: 0, y: 0, maxY: 2400),
            from: Content(documentID: plan, source: "before"),
            to: Content(documentID: plan, source: "after")
        )
        let unknown = PreviewScrollRestoration.restoration(
            of: nil,
            from: Content(documentID: plan, source: "before"),
            to: Content(documentID: plan, source: "after")
        )

        #expect(edited == .top)
        #expect(unknown == .top)
    }

    // A page that fits has nowhere to scroll, so there is no proportion to keep.
    @Test func aPageThatFitsHasNoProportionToKeep() {
        let restoration = PreviewScrollRestoration.restoration(
            of: PreviewScrollPosition(x: 40, y: 0, maxY: 0),
            from: Content(documentID: plan, source: "same"),
            to: Content(documentID: plan, source: "same")
        )

        #expect(restoration == .offset(x: 40, y: 0))
    }

    @Test func scrollPositionIsReadFromThePagesMessage() throws {
        let position = try #require(
            PreviewScrollPosition(messageBody: [NSNumber(value: 12.5), NSNumber(value: 640), NSNumber(value: 1800)])
        )

        #expect(position == PreviewScrollPosition(x: 12.5, y: 640, maxY: 1800))
    }

    // Rubber-banding reports offsets past either end; they are not places.
    @Test func scrollPositionIsClampedToThePage() throws {
        let above = try #require(
            PreviewScrollPosition(messageBody: [NSNumber(value: -8), NSNumber(value: -30), NSNumber(value: 1800)])
        )
        let below = try #require(
            PreviewScrollPosition(messageBody: [NSNumber(value: 0), NSNumber(value: 1900), NSNumber(value: 1800)])
        )

        #expect(above == PreviewScrollPosition(x: 0, y: 0, maxY: 1800))
        #expect(below == PreviewScrollPosition(x: 0, y: 1800, maxY: 1800))
    }

    @Test func aMalformedScrollMessageIsIgnored() {
        #expect(PreviewScrollPosition(messageBody: "top") == nil)
        #expect(PreviewScrollPosition(messageBody: [NSNumber(value: 1), NSNumber(value: 2)]) == nil)
        #expect(PreviewScrollPosition(messageBody: [NSNumber(value: 0), NSNumber(value: Double.nan), NSNumber(value: 10)]) == nil)
    }

    @Test func aScrollMessageOfTheWrongLengthOrKindIsIgnored() {
        #expect(PreviewScrollPosition(messageBody: [NSNumber]()) == nil)
        #expect(
            PreviewScrollPosition(
                messageBody: [NSNumber(value: 0), NSNumber(value: 640), NSNumber(value: 1800), NSNumber(value: 1)]
            ) == nil
        )
        #expect(PreviewScrollPosition(messageBody: ["0", "640", "1800"]) == nil)
    }

    @Test func aScrollMessageWithAnInfiniteNumberIsIgnored() {
        #expect(
            PreviewScrollPosition(
                messageBody: [NSNumber(value: 0), NSNumber(value: 640), NSNumber(value: Double.infinity)]
            ) == nil
        )
        #expect(
            PreviewScrollPosition(
                messageBody: [NSNumber(value: -Double.infinity), NSNumber(value: 640), NSNumber(value: 1800)]
            ) == nil
        )
    }

    // A page cannot scroll less than not at all, and there is then nowhere
    // down it for the reader to be.
    @Test func aPageSaidToScrollLessThanNothingDoesNotScroll() throws {
        let position = try #require(
            PreviewScrollPosition(messageBody: [NSNumber(value: 5), NSNumber(value: 30), NSNumber(value: -10)])
        )

        #expect(position == PreviewScrollPosition(x: 5, y: 0, maxY: 0))
    }

    // How far across the reader is does not depend on the page's height, so it
    // is kept as it was whichever way the place down the page is kept.
    @Test func theReadersPlaceAcrossThePageIsKeptEitherWay() {
        let acrossAndDown = PreviewScrollPosition(x: 40, y: 600, maxY: 2400)

        let edited = PreviewScrollRestoration.restoration(
            of: acrossAndDown,
            from: Content(documentID: plan, source: "before"),
            to: Content(documentID: plan, source: "after")
        )
        let redrawn = PreviewScrollRestoration.restoration(
            of: acrossAndDown,
            from: Content(documentID: plan, source: "same"),
            to: Content(documentID: plan, source: "same")
        )

        #expect(edited == .offset(x: 40, y: 600))
        #expect(redrawn == .fraction(x: 40, ofMaxY: 0.25))
    }

    @Test func aReaderWhoHasOnlyScrolledAcrossIsNotAtTheTop() {
        let restoration = PreviewScrollRestoration.restoration(
            of: PreviewScrollPosition(x: 40, y: 0, maxY: 2400),
            from: Content(documentID: plan, source: "same"),
            to: Content(documentID: plan, source: "same")
        )

        #expect(restoration == .fraction(x: 40, ofMaxY: 0))
    }

    @Test func aRestorationToTheTopHasNothingToRun() {
        #expect(PreviewScrollRestoration.Restoration.top.script == nil)
    }

    @Test func eachRestorationRunsTheCallThatCarriesItOut() {
        #expect(
            PreviewScrollRestoration.Restoration.offset(x: 40, y: 900).script
                == PreviewScriptCall.scrollToOffset(x: 40, y: 900)
        )
        #expect(
            PreviewScrollRestoration.Restoration.fraction(x: 40, ofMaxY: 0.5).script
                == PreviewScriptCall.scrollToFraction(x: 40, ofMaxY: 0.5)
        )
        #expect(
            PreviewScrollRestoration.Restoration.sourceOffset(9000).script
                == PreviewScriptCall.scrollToSourceOffset(9000)
        )
    }
}

/// The calls the app makes into the page's scripts. Each finds its function by
/// name, and is written to find nothing, without complaint, when the function
/// is not there. So a name that is wrong here is a call that quietly does
/// nothing, in a web view and nowhere a test without one would see.
struct PreviewScriptCallTests {

    @Test func everyCallNamesAFunctionAScriptDefines() throws {
        let calls = [
            PreviewScriptCall.selectionSnapshot,
            PreviewScriptCall.selectedDisplayRanges,
            PreviewScriptCall.selectedHTML,
            PreviewScriptCall.scrollPosition,
            PreviewScriptCall.applySelection("null, null, null, null, null, null"),
            PreviewScriptCall.scrollToOffset(x: 0, y: 0),
            PreviewScriptCall.scrollToFraction(x: 0, ofMaxY: 0),
            PreviewScriptCall.scrollToSourceOffset(0)
        ]
        let scripts = MarkdownWebResources.Script.allCases.map(MarkdownWebResources.script)

        for call in calls {
            let name = try #require(functionName(calledBy: call), "no function named in \(call)")
            #expect(
                scripts.contains { $0.contains("window.markdownPreview.\(name) =") },
                "no script defines \(name)"
            )
        }
    }

    @Test func applySelectionPassesItsArgumentsAsTheyAreGiven() {
        #expect(
            PreviewScriptCall.applySelection("0, 9, 2, 11, 30, 7")
                == "window.markdownPreview?.applySelection?.(0, 9, 2, 11, 30, 7)"
        )
    }

    @Test func theScrollCallsPassAcrossAndThenDown() {
        #expect(
            PreviewScriptCall.scrollToOffset(x: 12.5, y: 640)
                == "window.markdownPreview?.scrollToOffset?.(12.5, 640.0);"
        )
        #expect(
            PreviewScriptCall.scrollToFraction(x: 12.5, ofMaxY: 0.25)
                == "window.markdownPreview?.scrollToFraction?.(12.5, 0.25);"
        )
        #expect(
            PreviewScriptCall.scrollToSourceOffset(9000)
                == "window.markdownPreview?.scrollToSourceOffset?.(9000);"
        )
    }

    /// The name between `window.markdownPreview?.` and the `?.(` that calls it.
    private func functionName(calledBy call: String) -> String? {
        let prefix = "window.markdownPreview?."
        guard call.hasPrefix(prefix) else { return nil }
        let rest = call.dropFirst(prefix.count)
        guard let invocation = rest.range(of: "?.(") else { return nil }
        let name = rest[..<invocation.lowerBound]
        return name.isEmpty ? nil : String(name)
    }
}
