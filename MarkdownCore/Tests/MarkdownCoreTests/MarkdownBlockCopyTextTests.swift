//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Testing
@testable import MarkdownCore

struct MarkdownBlockCopyTextTests {

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
