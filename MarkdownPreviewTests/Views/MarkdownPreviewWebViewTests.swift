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
            PreviewScriptCall.scrollToFraction(x: 0, ofMaxY: 0)
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
