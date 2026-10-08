//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownCore

/// A document read once, for everything that needs it read.
///
/// Building a document's page and placing a selection in it both start by
/// reading the whole of it into blocks, and for a long document that is most
/// of what either costs. A reading is that work done once and handed to both.
struct MarkdownReadingTests {

    private static let source = """
    # Notes

    A paragraph with a [link][home] and *emphasis*,
    on two lines.

    - one
    - two
      - nested

    | Name | Size |
    | :--- | ---: |
    | a.md | 12 |

    > Quoted, with a [link][home] of its own.

    ```swift
    let answer = 42
    ```

    [home]: https://example.com "Home"
    """

    @Test func aReadingHoldsTheSourceItWasMadeFrom() {
        #expect(MarkdownReading(of: Self.source).source == Self.source)
    }

    @Test func aReadingHoldsTheBlocksAndDefinitionsTheParserFinds() {
        let reading = MarkdownReading(of: Self.source)
        let parsed = MarkdownBlockParser.parseDocument(Self.source)

        #expect(reading.blocks.map(\.lineRange) == parsed.blocks.map(\.lineRange))
        #expect(reading.blocks.count == 6)
        #expect(reading.definitions.target(for: "home")?.destination == "https://example.com")
    }

    @Test func aReadingHoldsWhereTheLinesAre() {
        let reading = MarkdownReading(of: Self.source)
        let table = MarkdownSourceLineTable(source: Self.source)

        #expect(reading.lineTable.lineStartOffsets == table.lineStartOffsets)
        #expect(reading.lineTable.lineEndOffsets == table.lineEndOffsets)
        #expect(reading.lineTable.sourceUTF16Length == table.sourceUTF16Length)
    }

    // The page is built in the background and what was read for it goes back
    // to the main actor with it.
    @Test func aReadingCanBeHandedFromOneThreadToAnother() {
        let reading: any Sendable = MarkdownReading(of: Self.source)

        #expect(reading is MarkdownReading)
    }

    @Test(arguments: [MarkdownHTMLBuilder.SoftBreak.newline, .lineBreak])
    func thePageBuiltFromAReadingIsThePageBuiltFromItsSource(softBreak: MarkdownHTMLBuilder.SoftBreak) {
        let fromSource = MarkdownHTMLBuilder.document(for: Self.source, contentScale: 1.5, softBreak: softBreak)

        let fromReading = MarkdownHTMLBuilder.document(
            for: MarkdownReading(of: Self.source),
            contentScale: 1.5,
            softBreak: softBreak
        )

        #expect(fromReading == fromSource)
    }

    @Test func aPageBuiltFromAReadingUsesDefinitionsFromOutsideItToo() {
        let part = "A [link][elsewhere]."
        let outside = MarkdownLinkDefinitions(source: "[elsewhere]: https://example.org")

        let page = MarkdownHTMLBuilder.document(for: MarkdownReading(of: part), definitions: outside)

        #expect(page.contains("href=\"https://example.org\""))
        #expect(page == MarkdownHTMLBuilder.document(for: part, definitions: outside))
    }

    @Test func anEmptyDocumentIsReadAsNoBlocks() {
        let reading = MarkdownReading(of: "")

        #expect(reading.blocks.isEmpty)
        #expect(MarkdownHTMLBuilder.document(for: reading) == MarkdownHTMLBuilder.document(for: ""))
    }
}
