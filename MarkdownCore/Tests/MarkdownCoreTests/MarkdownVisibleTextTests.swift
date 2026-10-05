//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownCore

/// What `MarkdownVisibleText` records: the text, and for each stretch of it the
/// stretch of source it came from. The app's per-feature tests check the text
/// against WebKit and carry words there and back; these pin the records
/// themselves, where the source and what is shown are different lengths.
struct MarkdownVisibleTextTests {

    /// Each run as the source it covers and the text shown for it.
    private func pieces(
        of source: String,
        elementSeparator: String = "\n",
        includesImageDescriptions: Bool = true
    ) -> [[String]] {
        let visible = MarkdownVisibleText(
            source: source,
            elementSeparator: elementSeparator,
            includesImageDescriptions: includesImageDescriptions
        )
        let nsSource = source as NSString
        let nsText = visible.text as NSString
        return visible.runs.map {
            [nsSource.substring(with: $0.sourceRange.nsRange), nsText.substring(with: $0.displayRange.nsRange)]
        }
    }

    private func text(of source: String, elementSeparator: String = "\n") -> String {
        MarkdownVisibleText(source: source, elementSeparator: elementSeparator).text
    }

    // MARK: - Inline

    @Test func plainTextIsOneRunTheLengthOfItsSource() {
        #expect(pieces(of: "Alpha beta") == [["Alpha beta", "Alpha beta"]])
    }

    @Test func emphasisDelimitersAreInNoRun() {
        #expect(pieces(of: "one *two* **three**") == [["one ", "one "], ["two", "two"], [" ", " "], ["three", "three"]])
    }

    @Test func anEscapeIsShownAsTheCharacterAndCoversItsBackslash() {
        #expect(pieces(of: "a \\* b") == [["a ", "a "], ["\\*", "*"], [" b", " b"]])
    }

    @Test func anEntityIsShownDecodedAndCoversItsWholeName() {
        #expect(pieces(of: "AT&amp;T") == [["AT", "AT"], ["&amp;", "&"], ["T", "T"]])
    }

    @Test func aCodeSpanIsShownWithoutItsBackticksOrPadding() {
        #expect(pieces(of: "x `` a`b `` y") == [["x ", "x "], ["a`b", "a`b"], [" y", " y"]])
    }

    @Test func aLinkIsShownAsItsText() {
        #expect(pieces(of: "[*Alpha* b](https://example.com \"t\") c") == [["Alpha", "Alpha"], [" b", " b"], [" c", " c"]])
    }

    @Test func anImageDescriptionCountsOnlyWhenAsked() {
        #expect(pieces(of: "a ![Alt *text*](p.png) b") == [["a ", "a "], ["Alt ", "Alt "], ["text", "text"], [" b", " b"]])
        #expect(pieces(of: "a ![Alt *text*](p.png) b", includesImageDescriptions: false) == [["a ", "a "], [" b", " b"]])
    }

    @Test func unpairedDelimitersAreShownAndAreTheOuterOnes() {
        // The run of two opens with its inner asterisk, so the outer one is
        // what is left to show.
        #expect(pieces(of: "**a*") == [["*", "*"], ["a", "a"]])
        #expect(pieces(of: "*a**") == [["a", "a"], ["*", "*"]])
        #expect(pieces(of: "2 * 3") == [["2 * 3", "2 * 3"]])
    }

    // MARK: - Line breaks

    @Test func aSoftBreakCoversTheLineEndingAndTheNextLinesIndentation() {
        #expect(pieces(of: "one\n   two") == [["one", "one"], ["\n   ", "\n"], ["two", "two"]])
    }

    @Test func aHardBreakCoversItsSpacesOrBackslashToo() {
        #expect(pieces(of: "one  \ntwo") == [["one", "one"], ["  \n", "\n"], ["two", "two"]])
        #expect(pieces(of: "one\\\ntwo") == [["one", "one"], ["\\\n", "\n"], ["two", "two"]])
    }

    @Test func aWindowsLineEndingIsOneLineBreak() {
        #expect(pieces(of: "one\r\ntwo") == [["one", "one"], ["\r\n", "\n"], ["two", "two"]])
    }

    // MARK: - Blocks

    @Test func blocksAreSeparatedByALineBreakThatCoversWhatLiesBetweenThem() {
        #expect(pieces(of: "# One\n\n\ntwo") == [["One", "One"], ["\n\n\n", "\n"], ["two", "two"]])
    }

    @Test func aHeadingIsItsTextWithoutItsMarkers() {
        #expect(text(of: "## One ##") == "One")
        #expect(text(of: "One\ntwo\n===") == "One\ntwo")
    }

    @Test func listItemsAreSeparatedByTheElementSeparator() {
        // One list: a nested item, a numbered item nested under that, a blank
        // line, and a task.
        let list = "- one\n  - two\n    1) three\n\n- [x] four"

        #expect(text(of: list) == "one\ntwo\nthree\nfour")
        #expect(text(of: list, elementSeparator: "") == "onetwothreefour")
    }

    @Test func whatAQuoteHoldsIsReadAsADocumentOfItsOwn() {
        let quote = "> # One\n> two\n> three\n>\n> - four\n> > five\n> ```\n> six\n> ```"

        #expect(text(of: quote) == "One\ntwo\nthree\nfour\nfive\nsix")
        #expect(text(of: quote, elementSeparator: "") == "Onetwo\nthreefourfivesix")
        #expect(pieces(of: "> > *deep*") == [["deep", "deep"]])
    }

    @Test func tableCellsRunTogetherAndAnEscapedPipeIsAPipe() {
        #expect(
            pieces(of: "| a \\| b | c |\n| --- | --- |\n| 1 | 2 | 3 |")
                == [["a ", "a "], ["\\|", "|"], [" b", " b"], ["c", "c"], ["1", "1"], ["2", "2"]]
        )
    }

    @Test func aCodeBlockIsItsLinesWithoutItsFences() {
        #expect(text(of: "```swift\nlet a = 1\n\n  let b = 2\n```") == "let a = 1\n\n  let b = 2")
        #expect(text(of: "~~~\nlet a = 1\n~~~") == "let a = 1")
    }

    @Test func aCodeBlockWithNoClosingFenceKeepsItsLastLine() {
        #expect(text(of: "```\nlet a = 1\nlet b = 2") == "let a = 1\nlet b = 2")
    }

    @Test func aThematicBreakIsNoText() {
        #expect(text(of: "one\n\n---\n\ntwo") == "one\n\ntwo")
        #expect(MarkdownVisibleText(source: "---").runs.isEmpty)
    }

    @Test func offsetsAreInUTF16() {
        let visible = MarkdownVisibleText(source: "😀 *wörld* 👍🏽")

        #expect(visible.text == "😀 wörld 👍🏽")
        #expect(
            visible.runs.map(\.sourceRange) == [
                MarkdownSelectionRange(location: 0, length: 3),
                MarkdownSelectionRange(location: 4, length: 5),
                MarkdownSelectionRange(location: 10, length: 5),
            ]
        )
    }

    @Test func anEmptyDocumentIsNoText() {
        #expect(MarkdownVisibleText(source: "").text.isEmpty)
        #expect(MarkdownVisibleText(source: "\n\n  \n").runs.isEmpty)
    }

    // MARK: - Agreement with the HTML

    /// The text here has to be the text of the page: strip the tags from what
    /// the renderer writes for the same source, decode its entities, and the
    /// two are the same string. This is the property the whole type exists for,
    /// checked without a web view on inline content of every kind.
    @Test(arguments: [
        "plain text",
        "one *two* **three** ***four*** _five_ __six__",
        "snake_case_name and 2 * 3 * 4 and **unclosed",
        "a `code` b `` c`d `` e ` f ` g",
        "[link *text*](/url \"title\") and [unclosed](/url",
        "\\*escaped\\* \\_under\\_ \\\\ \\A",
        "AT&amp;T &copy; &#35; &nosuch; a < b & c > \"d\"",
        "first line\nsecond line  \nthird line\\\nfourth *line\nfifth* line",
        "<b>raw</b> <!-- comment -->",
    ])
    func visibleTextIsTheTextOfTheRenderedHTML(source: String) {
        let html = MarkdownHTMLBuilder.document(for: source, softBreak: .lineBreak)
        let visible = MarkdownVisibleText(source: source, elementSeparator: "", includesImageDescriptions: false)

        #expect(visible.text == Self.textOfFirstBlock(in: html))
    }

    private static func textOfFirstBlock(in html: String) -> String {
        guard let open = html.range(of: "<div class=\"md-block"),
              let openEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</div>", range: openEnd.upperBound..<html.endIndex) else {
            return ""
        }

        var text = ""
        var isInsideTag = false
        for character in html[openEnd.upperBound..<close.lowerBound] {
            switch character {
            case "<": isInsideTag = true
            case ">": isInsideTag = false
            default: if !isInsideTag { text.append(character) }
            }
        }
        return text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
