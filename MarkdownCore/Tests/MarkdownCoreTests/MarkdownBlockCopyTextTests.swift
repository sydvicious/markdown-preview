//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownCore

struct MarkdownBlockCopyTextTests {

    /// What the Copy button on the first copyable block of `document` puts on
    /// the pasteboard. The block's kind and where its source starts and ends
    /// are read from the page, which is where the preview's script gets them,
    /// and the source is then cut out and stripped as the app does it.
    private func copiedFromFirstCopyableBlock(of document: String) throws -> String {
        let html = MarkdownHTMLBuilder.document(for: document)
        let block = /md-copyable-block" data-copy-kind="(\w+)" data-source-start="(\d+)" data-source-end="(\d+)"/
        let match = try #require(html.firstMatch(of: block), "the page has no copyable block")
        let start = try #require(Int(match.2))
        let end = try #require(Int(match.3))
        let range = try #require(
            MarkdownSelectionRange(location: start, length: end - start).range(in: document)
        )

        return MarkdownBlockCopyText.copyText(
            fromBlockSource: String(document[range]),
            kind: MarkdownCopyableBlockKind(rawValue: String(match.1))
        )
    }

    /// The code the preview shows for the first code block of `document`.
    private func codeShown(for document: String) throws -> String {
        let html = MarkdownHTMLBuilder.document(for: document)
        let code = /<pre><code[^>]*>(.*?)<\/code><\/pre>/.dotMatchesNewlines()
        let match = try #require(html.firstMatch(of: code), "the page has no code block")

        return String(match.1)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Block quotes

    @Test func quoteMarkersAreStrippedFromEveryLine() {
        let source = "> To be, or not to be,\n> that is the question."

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .blockquote)
                == "To be, or not to be,\nthat is the question."
        )
    }

    @Test func quoteMarkerWithoutATrailingSpaceIsStripped() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: ">tight", kind: .blockquote) == "tight"
        )
    }

    /// At most one space comes off, so indentation inside the quote survives.
    @Test func onlyOneSpaceAfterTheMarkerIsStripped() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: ">     indented", kind: .blockquote)
                == "    indented"
        )
    }

    @Test func upToThreeSpacesOfIndentBeforeTheMarkerAreAllowed() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "   > quoted", kind: .blockquote) == "quoted"
        )
    }

    /// Only one level comes off: the inner quote is content of the outer one.
    @Test func nestedQuotesKeepTheirInnerMarker() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "> > deep", kind: .blockquote) == "> deep"
        )
    }

    @Test func blankQuotedLinesSurviveInTheMiddle() {
        let source = "> first\n>\n> second"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .blockquote)
                == "first\n\nsecond"
        )
    }

    // MARK: - Code

    @Test func backtickFencesAreStripped() {
        let source = "```swift\nlet x = 1\n```"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code) == "let x = 1"
        )
    }

    @Test func tildeFencesAreStripped() {
        let source = "~~~\nplain\n~~~"

        #expect(MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code) == "plain")
    }

    /// A fenced block at the end of a document can be unterminated; stripping a
    /// closing fence that is not there would eat the last line of code.
    @Test func anUnterminatedFenceKeepsItsLastLine() {
        let source = "```\nlet x = 1\nlet y = 2"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "let x = 1\nlet y = 2"
        )
    }

    /// What is copied is the code as the preview shows it, and the preview
    /// takes off the indentation a block shares with its fence.
    @Test func aFencedBlockLosesTheIndentationItSharesWithItsFence() {
        let source = "  ```\n  let x = 1\n    let y = 2\n ragged\n  ```"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "let x = 1\n  let y = 2\nragged"
        )
    }

    @Test func indentedCodeLosesItsIndent() {
        let source = "    let x = 1\n    let y = 2"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "let x = 1\nlet y = 2"
        )
    }

    /// Indentation beyond the four that make it a code block is the code's own.
    @Test func indentedCodeKeepsItsInnerIndentation() {
        let source = "    if x {\n        return\n    }"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "if x {\n    return\n}"
        )
    }

    @Test func backtickCharactersInsideAFencedBlockAreNotMistakenForFences() {
        let source = "```\nlet tick = \"`\"\n```"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "let tick = \"`\""
        )
    }

    // MARK: - Tabs and mixed indentation

    @Test func tabIndentedCodeLosesItsTab() {
        let source = "\tlet x = 1\n\tlet y = 2"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "let x = 1\nlet y = 2"
        )
    }

    /// The first tab is what makes it a code block. A tab after it is the
    /// code's own indentation.
    @Test func tabIndentedCodeKeepsItsInnerTabs() {
        let source = "\tif x {\n\t\treturn\n\t}"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "if x {\n\treturn\n}"
        )
    }

    @Test func aBlockIndentedWithSpacesOnSomeLinesAndATabOnOthersLosesBoth() {
        let source = "    let x = 1\n\tlet y = 2\n    let z = 3"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "let x = 1\nlet y = 2\nlet z = 3"
        )
    }

    /// A tab reaches the next column that is a multiple of four, so one, two
    /// or three spaces and then a tab are four columns: the same indent as a
    /// tab alone, or as four spaces.
    @Test(arguments: [" \t", "  \t", "   \t"])
    func spacesAndThenATabAreOneIndent(indent: String) {
        let source = "\(indent)let x = 1\n\(indent)let y = 2"

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code)
                == "let x = 1\nlet y = 2"
        )
    }

    /// The Copy button hands over the code as the preview shows it, however it
    /// was indented.
    @Test(arguments: [
        "    let x = 1\n    let y = 2",
        "\tlet x = 1\n\tlet y = 2",
        "\tif x {\n\t\treturn\n\t}",
        "    let x = 1\n\tlet y = 2",
        "  \tlet x = 1\n  \tlet y = 2",
        "     five spaces\n    four",
    ])
    func copiedIndentedCodeIsTheCodeThePreviewShows(code: String) throws {
        let document = "A paragraph.\n\n\(code)\n\nAnother."

        #expect(try copiedFromFirstCopyableBlock(of: document) == codeShown(for: document))
    }

    // MARK: - Indented fences

    /// A fence may be indented by up to three spaces, and its code loses the
    /// same indentation.
    @Test(arguments: [" ", "  ", "   "])
    func aFenceIndentedUpToThreeSpacesIsStillAFence(indent: String) {
        let source = "\(indent)```swift\n\(indent)let x = 1\n\(indent)```"

        #expect(MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .code) == "let x = 1")
    }

    @Test func aClosingFenceNeedNotBeIndentedAsItsOpeningFenceIs() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "```\nlet x = 1\n   ```", kind: .code)
                == "let x = 1"
        )
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "   ```\n   let x = 1\n```", kind: .code)
                == "let x = 1"
        )
    }

    /// Four spaces are too many for a fence, so this block was never closed
    /// and the indented backticks are a line of its code.
    @Test func backticksIndentedFourSpacesAreCodeAndNotAClosingFence() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "```\nlet x = 1\n    ```", kind: .code)
                == "let x = 1\n    ```"
        )
    }

    @Test(arguments: [
        " ```\n let x = 1\n ```",
        "   ```swift\n   let x = 1\n     let y = 2\n   ```",
        "  ~~~\n  let x = 1\n ragged\n  ~~~",
        "```\nlet x = 1\n   ```",
    ])
    func copiedFencedCodeIsTheCodeThePreviewShows(code: String) throws {
        let document = "A paragraph.\n\n\(code)\n\nAnother."

        #expect(try copiedFromFirstCopyableBlock(of: document) == codeShown(for: document))
    }

    // MARK: - A last line that looks like a closing fence and is not one

    // A fenced block that is never closed runs to the end of the document, and
    // every line in it is code. That holds for a last line of backticks or
    // tildes that does not close this block: a fence closes only a block opened
    // with the same character, by a run at least as long, with nothing after it.

    @Test func aFenceShorterThanTheOpeningOneIsCodeAndNotAClosingFence() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "````\nlet x = 1\n```", kind: .code)
                == "let x = 1\n```"
        )
    }

    @Test func aFenceOfTheOtherCharacterIsCodeAndNotAClosingFence() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "```\nlet x = 1\n~~~", kind: .code)
                == "let x = 1\n~~~"
        )
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "~~~\nlet x = 1\n```", kind: .code)
                == "let x = 1\n```"
        )
    }

    @Test func aFenceWithTextAfterItIsCodeAndNotAClosingFence() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "```\nlet x = 1\n``` swift", kind: .code)
                == "let x = 1\n``` swift"
        )
    }

    @Test func aClosingFenceLongerThanTheOpeningOneClosesIt() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "```\nlet x = 1\n`````", kind: .code)
                == "let x = 1"
        )
    }

    @Test(arguments: [
        "````\nlet x = 1\n```",
        "```\nlet x = 1\n~~~",
        "~~~\nlet x = 1\n```",
        "```\nlet x = 1\n``` swift",
        "```\nlet x = 1\n`````",
    ])
    func copiedCodeFromABlockThatIsNeverClosedIsTheCodeThePreviewShows(code: String) throws {
        // Last in the document, so that a block with no closing fence ends
        // where the document does and not at a paragraph after it.
        let document = "A paragraph.\n\n\(code)"

        #expect(try copiedFromFirstCopyableBlock(of: document) == codeShown(for: document))
    }

    // MARK: - A quote's lines written without their marker

    /// A paragraph in a quote may run on to a line with no `>`. That line is
    /// still in the quote, so it is still in what is copied.
    @Test func aQuoteLineWrittenWithoutItsMarkerIsKeptAsItIs() {
        let source = "> To be, or not to be,\nthat is the question."

        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .blockquote)
                == "To be, or not to be,\nthat is the question."
        )
    }

    @Test func aLineWithoutItsMarkerInANestedQuoteIsKept() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "> > deep\nstill deep", kind: .blockquote)
                == "> deep\nstill deep"
        )
    }

    /// The same, from the page: the block the Copy button is on has to reach
    /// as far as the line without a marker, or that line is never handed over.
    @Test func theCopyButtonOnAQuoteCopiesTheLineWrittenWithoutItsMarker() throws {
        let document = "Before.\n\n> To be, or not to be,\nthat is the question.\n\nAfter."

        #expect(
            try copiedFromFirstCopyableBlock(of: document)
                == "To be, or not to be,\nthat is the question."
        )
    }

    // MARK: - Windows line endings

    @Test func aQuoteWithWindowsLineEndingsLosesItsMarkersOnEveryLine() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "> first\r\n> second", kind: .blockquote)
                == "first\nsecond"
        )
    }

    @Test func aFencedBlockWithWindowsLineEndingsLosesItsFences() {
        #expect(
            MarkdownBlockCopyText.copyText(fromBlockSource: "```swift\r\nlet x = 1\r\nlet y = 2\r\n```", kind: .code)
                == "let x = 1\nlet y = 2"
        )
    }

    // MARK: - Tables and unknown kinds

    /// A table's pipe syntax is the useful thing to paste elsewhere, so it is
    /// copied verbatim.
    @Test func tablesAreCopiedAsSource() {
        let source = "| a | b |\n| - | - |\n| 1 | 2 |"

        #expect(MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: .table) == source)
    }

    @Test func anUnknownKindIsCopiedAsSource() {
        let source = "> quoted"

        #expect(MarkdownBlockCopyText.copyText(fromBlockSource: source, kind: nil) == source)
    }

    // MARK: - Which flavors the Copy button offers

    /// Quotes and code get plain text alone, so a formatted paste cannot put the
    /// markers and fences back.
    @Test func onlyTablesOfferRichText() {
        #expect(MarkdownBlockCopyText.offersRichText(for: .table))
        #expect(MarkdownBlockCopyText.offersRichText(for: nil))
        #expect(MarkdownBlockCopyText.offersRichText(for: .blockquote) == false)
        #expect(MarkdownBlockCopyText.offersRichText(for: .code) == false)
    }

    // MARK: - The kind reaches the HTML

    @Test func copyableBlocksCarryTheirKindInTheHTML() {
        #expect(MarkdownHTMLBuilder.document(for: "> quoted").contains("data-copy-kind=\"blockquote\""))
        #expect(MarkdownHTMLBuilder.document(for: "```\ncode\n```").contains("data-copy-kind=\"code\""))
        #expect(
            MarkdownHTMLBuilder.document(for: "| a | b |\n| - | - |\n| 1 | 2 |")
                .contains("data-copy-kind=\"table\"")
        )
    }

    @Test func blocksWithoutACopyButtonCarryNoKind() {
        #expect(MarkdownHTMLBuilder.document(for: "Just a paragraph.").contains("data-copy-kind") == false)
    }
}
