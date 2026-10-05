//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//
//  Per-feature conformance tests for the markdown renderer.
//
//  Expectations here come from the CommonMark specification, version 0.31.2
//  (https://spec.commonmark.org/0.31.2/), NOT from what the renderer currently
//  produces. Section numbers in the test names refer to that document. Tests
//  are deliberately written against correct behavior, so a failure means the
//  renderer is wrong and the bug is waiting to be fixed. Do not weaken, skip,
//  or disable a case to make the run green.
//
//  Three deviations from the spec are intentional and are asserted in the
//  app's shape rather than the spec's:
//    - every block is wrapped in a `md-block` div carrying source offsets that
//      the preview's selection mapping depends on;
//    - tables and task lists are GitHub extensions the app supports, and are
//      not described by CommonMark at all;
//    - ordered lists number each item with `value` instead of putting `start`
//      on the list, so non-sequential numbering survives as written.
//
//  Three more follow from how the preview uses the markup, and show up in the
//  exact strings asserted below:
//    - nothing is written between block-level tags, where the spec's reference
//      output has a newline, because the preview counts text nodes;
//    - a code block's content has no trailing newline;
//    - raw HTML is escaped rather than passed through, which is what stops a
//      document putting markup of its own into the preview.
//
//  Constructs the renderer does not implement yet — indented code blocks,
//  autolinks, link reference definitions, list items that hold more than one
//  line — are asserted here all the same, and fail until it does.
//

import Foundation
import Testing
@testable import MarkdownCore

/// Renders `source` and returns the inner HTML of its first block, with the
/// `md-block` wrapper and any copy button stripped.
private func blockHTML(_ source: String) -> String {
    allBlockHTML(source).first ?? ""
}

/// Renders `source` and returns the inner HTML of every block, in order.
private func allBlockHTML(_ source: String) -> [String] {
    let html = MarkdownHTMLBuilder.document(for: source)
    let copyButton = "<button type=\"button\" class=\"md-copy-button\" data-copy-button>Copy</button>"

    var blocks: [String] = []
    var cursor = html.startIndex

    while let open = html.range(of: "<div class=\"md-block", range: cursor..<html.endIndex) {
        guard let openEnd = html.range(of: ">", range: open.upperBound..<html.endIndex) else { break }

        // Blocks can contain nested divs (a table wraps itself in .table-wrap),
        // so match the closing tag by depth rather than by the next </div>.
        var depth = 1
        var index = openEnd.upperBound
        var contentEnd: String.Index?

        while index < html.endIndex, depth > 0 {
            if html[index...].hasPrefix("<div") {
                depth += 1
                index = html.index(index, offsetBy: 4)
            } else if html[index...].hasPrefix("</div>") {
                depth -= 1
                if depth == 0 {
                    contentEnd = index
                    break
                }
                index = html.index(index, offsetBy: 6)
            } else {
                index = html.index(after: index)
            }
        }

        guard let contentEnd else { break }

        var content = String(html[openEnd.upperBound..<contentEnd])
        if content.hasPrefix(copyButton) {
            content.removeFirst(copyButton.count)
        }
        blocks.append(content)
        cursor = contentEnd
    }

    return blocks
}

// MARK: - Leaf blocks

@Suite("ATX headings (spec 4.2)")
struct ATXHeadingTests {

    @Test func allSixLevelsRender() async throws {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            #expect(blockHTML("\(hashes) foo") == "<h\(level)>foo</h\(level)>")
        }
    }

    @Test func headingContentIsInlineRendered() async throws {
        #expect(blockHTML("# foo *bar*") == "<h1>foo <em>bar</em></h1>")
    }

    @Test func sevenHashesIsNotAHeading() async throws {
        // "#######" exceeds the six heading levels, so it is a paragraph.
        #expect(blockHTML("####### foo") == "<p>####### foo</p>")
    }

    @Test func hashWithoutFollowingSpaceIsNotAHeading() async throws {
        // The spec requires the opening sequence to be followed by a space or
        // end of line, specifically so that "#hashtag" stays text.
        #expect(blockHTML("#foo") == "<p>#foo</p>")
    }

    @Test func closingSequenceIsStripped() async throws {
        #expect(blockHTML("## foo ##") == "<h2>foo</h2>")
    }

    @Test func closingSequenceNeedNotMatchOpeningLength() async throws {
        #expect(blockHTML("# foo ##################") == "<h1>foo</h1>")
    }

    @Test func upToThreeLeadingSpacesAreAllowed() async throws {
        #expect(blockHTML("   # foo") == "<h1>foo</h1>")
    }

    @Test func emptyHeadingIsAllowed() async throws {
        #expect(blockHTML("#") == "<h1></h1>")
    }

    @Test func closingSequenceNeedsASpaceBeforeIt() async throws {
        #expect(blockHTML("# foo#") == "<h1>foo#</h1>")
    }

    @Test func escapedClosingHashIsContent() async throws {
        #expect(blockHTML("# foo \\#") == "<h1>foo #</h1>")
    }

    @Test func headingCanInterruptAParagraph() async throws {
        #expect(allBlockHTML("foo\n# bar\nbaz") == ["<p>foo</p>", "<h1>bar</h1>", "<p>baz</p>"])
    }
}

@Suite("Setext headings (spec 4.3)")
struct SetextHeadingTests {

    @Test func equalsUnderlineMakesLevelOne() async throws {
        #expect(blockHTML("foo\n===") == "<h1>foo</h1>")
    }

    @Test func dashUnderlineMakesLevelTwo() async throws {
        #expect(blockHTML("foo\n---") == "<h2>foo</h2>")
    }

    @Test func underlineOfAnyLengthIsAccepted() async throws {
        // The spec puts no minimum on the underline; a single character counts.
        #expect(blockHTML("foo\n=") == "<h1>foo</h1>")
        #expect(blockHTML("foo\n-") == "<h2>foo</h2>")
    }

    @Test func headingContentIsInlineRendered() async throws {
        #expect(blockHTML("foo *bar*\n===") == "<h1>foo <em>bar</em></h1>")
    }

    @Test func multiLineContentIsJoined() async throws {
        // A setext heading's content may span several lines.
        #expect(blockHTML("foo\nbar\n===") == "<h1>foo\nbar</h1>")
    }

    @Test func underlineCannotFollowABlankLine() async throws {
        #expect(allBlockHTML("foo\n\n===") == ["<p>foo</p>", "<p>===</p>"])
    }

    @Test func underlineMayBeIndentedAndHaveTrailingSpaces() async throws {
        #expect(blockHTML("foo\n   ===  ") == "<h1>foo</h1>")
    }

    @Test func underlineWithInteriorSpacesIsNotAnUnderline() async throws {
        #expect(blockHTML("foo\n= =") == "<p>foo\n= =</p>")
    }

    @Test func aListItemIsNotSetextContent() async throws {
        // The dashes under a list item are a thematic break, not an underline.
        #expect(allBlockHTML("- foo\n---") == ["<ul><li>foo</li></ul>", "<hr />"])
    }
}

@Suite("Paragraphs and line breaks (spec 4.8, 6.7, 6.8)")
struct ParagraphTests {

    @Test func simpleParagraph() async throws {
        #expect(blockHTML("foo") == "<p>foo</p>")
    }

    @Test func leadingWhitespaceIsStripped() async throws {
        #expect(blockHTML("  foo") == "<p>foo</p>")
    }

    @Test func blankLineSeparatesParagraphs() async throws {
        #expect(allBlockHTML("foo\n\nbar") == ["<p>foo</p>", "<p>bar</p>"])
    }

    @Test func softLineBreakIsANewlineNotABreakTag() async throws {
        // An ordinary line ending inside a paragraph is a soft break, rendered
        // as a newline. It is not <br>, and it is not collapsed to a space.
        #expect(blockHTML("foo\nbar") == "<p>foo\nbar</p>")
    }

    @Test func twoTrailingSpacesMakeAHardBreak() async throws {
        #expect(blockHTML("foo  \nbar") == "<p>foo<br />\nbar</p>")
    }

    @Test func trailingBackslashMakesAHardBreak() async throws {
        #expect(blockHTML("foo\\\nbar") == "<p>foo<br />\nbar</p>")
    }

    @Test func oneTrailingSpaceIsNotAHardBreak() async throws {
        #expect(blockHTML("foo \nbar") == "<p>foo\nbar</p>")
    }

    @Test func trailingSpacesAtTheEndOfAParagraphAreDropped() async throws {
        // A hard break needs a line after it; at the end of the block the
        // spaces are just trailing whitespace.
        #expect(blockHTML("foo  ") == "<p>foo</p>")
    }

    @Test func backslashAtTheEndOfAParagraphIsLiteral() async throws {
        #expect(blockHTML("foo\\") == "<p>foo\\</p>")
    }

    @Test func severalBlankLinesAreOneSeparator() async throws {
        #expect(allBlockHTML("foo\n\n\n\nbar") == ["<p>foo</p>", "<p>bar</p>"])
    }

    @Test func windowsLineEndingsAreLineEndings() async throws {
        // Spec 2.1: a line ending is a newline, a carriage return, or the two
        // together. A file saved with CRLF endings is the same document.
        #expect(allBlockHTML("# foo\r\n\r\nbar\r\nbaz\r\n") == ["<h1>foo</h1>", "<p>bar\nbaz</p>"])
    }
}

@Suite("Thematic breaks (spec 4.1)")
struct ThematicBreakTests {

    @Test func threeOfEachMarkerIsABreak() async throws {
        for marker in ["***", "---", "___"] {
            #expect(blockHTML(marker) == "<hr />", "\(marker) was not a thematic break")
        }
    }

    @Test func moreThanThreeCharactersIsStillABreak() async throws {
        #expect(blockHTML("_____________") == "<hr />")
    }

    @Test func spacesBetweenCharactersAreAllowed() async throws {
        #expect(blockHTML(" - - -") == "<hr />")
        #expect(blockHTML("* * *") == "<hr />")
    }

    @Test func fewerThanThreeCharactersIsNotABreak() async throws {
        #expect(blockHTML("--") == "<p>--</p>")
    }

    @Test func mixedCharactersAreNotABreak() async throws {
        #expect(blockHTML("*-*") != "<hr />")
    }

    @Test func otherCharactersAreNotBreakMarkers() async throws {
        #expect(blockHTML("+++") == "<p>+++</p>")
        #expect(blockHTML("===") == "<p>===</p>")
    }

    @Test func anythingElseOnTheLineMakesItText() async throws {
        #expect(blockHTML("_ _ _ _ a") == "<p>_ _ _ _ a</p>")
        #expect(blockHTML("a------") == "<p>a------</p>")
        #expect(blockHTML("---a---") == "<p>---a---</p>")
    }

    @Test func breakCanInterruptAParagraph() async throws {
        #expect(allBlockHTML("foo\n***\nbar") == ["<p>foo</p>", "<hr />", "<p>bar</p>"])
    }

    @Test func breakBetweenListItemsSplitsTheList() async throws {
        #expect(
            allBlockHTML("- foo\n***\n- bar")
                == ["<ul><li>foo</li></ul>", "<hr />", "<ul><li>bar</li></ul>"]
        )
    }
}

@Suite("Fenced code blocks (spec 4.5)")
struct FencedCodeTests {

    @Test func backtickFenceRendersPreCode() async throws {
        #expect(blockHTML("```\nfoo\n```") == "<pre><code>foo</code></pre>")
    }

    @Test func tildeFenceRendersPreCode() async throws {
        #expect(blockHTML("~~~\nfoo\n~~~") == "<pre><code>foo</code></pre>")
    }

    @Test func infoStringBecomesALanguageClass() async throws {
        #expect(blockHTML("```swift\nlet x = 1\n```") == "<pre><code class=\"language-swift\">let x = 1</code></pre>")
    }

    @Test func contentIsHTMLEscaped() async throws {
        #expect(blockHTML("```\n<&>\n```") == "<pre><code>&lt;&amp;&gt;</code></pre>")
    }

    @Test func contentIsNotInlineRendered() async throws {
        #expect(blockHTML("```\n*not emphasis*\n```") == "<pre><code>*not emphasis*</code></pre>")
    }

    @Test func multipleLinesArePreserved() async throws {
        #expect(blockHTML("```\none\ntwo\n```") == "<pre><code>one\ntwo</code></pre>")
    }

    @Test func fenceMayBeIndentedUpToThreeSpaces() async throws {
        #expect(blockHTML("  ```\nfoo\n  ```") == "<pre><code>foo</code></pre>")
    }

    @Test func contentIndentedLikeTheFenceLosesThatIndentation() async throws {
        // Each content line gives up as much indentation as the opening fence
        // has, which is what lets a fenced block sit under a list item.
        #expect(blockHTML("  ```\n  foo\n    bar\n  ```") == "<pre><code>foo\n  bar</code></pre>")
    }

    @Test func emptyFenceIsAnEmptyBlock() async throws {
        #expect(blockHTML("```\n```") == "<pre><code></code></pre>")
    }

    @Test func closingFenceMustBeAtLeastAsLongAsTheOpener() async throws {
        #expect(blockHTML("````\naaa\n```\n``````") == "<pre><code>aaa\n```</code></pre>")
    }

    @Test func aFenceOfTheOtherCharacterDoesNotClose() async throws {
        #expect(blockHTML("```\naaa\n~~~\n```") == "<pre><code>aaa\n~~~</code></pre>")
    }

    @Test func aFenceLineWithAnInfoStringDoesNotClose() async throws {
        #expect(blockHTML("```\nfoo\n``` bar\n```") == "<pre><code>foo\n``` bar</code></pre>")
    }

    @Test func unclosedFenceRunsToTheEndOfTheDocument() async throws {
        #expect(allBlockHTML("```\nfoo\n\nbar") == ["<pre><code>foo\n\nbar</code></pre>"])
    }

    @Test func blankLinesAndIndentationInsideAreKept() async throws {
        #expect(blockHTML("```\n\n  indented\n\n```") == "<pre><code>\n  indented\n</code></pre>")
    }

    @Test func onlyTheFirstWordOfTheInfoStringNamesTheLanguage() async throws {
        #expect(
            blockHTML("```swift startline=3\nlet x = 1\n```")
                == "<pre><code class=\"language-swift\">let x = 1</code></pre>"
        )
    }

    @Test func languageClassIsAttributeEscaped() async throws {
        #expect(blockHTML("```a\"b\nx\n```") == "<pre><code class=\"language-a&quot;b\">x</code></pre>")
    }

    @Test func backtickInfoStringCannotContainABacktick() async throws {
        // Which is what keeps a line of inline code from opening a block.
        #expect(blockHTML("``` aa ```\nfoo") == "<p><code>aa</code>\nfoo</p>")
    }

    @Test func tildeInfoStringMayContainBackticks() async throws {
        #expect(blockHTML("~~~ aa ``` ~~~\nfoo\n~~~") == "<pre><code class=\"language-aa\">foo</code></pre>")
    }

    @Test func fenceCanInterruptAParagraph() async throws {
        #expect(
            allBlockHTML("foo\n```\nbar\n```\nbaz")
                == ["<p>foo</p>", "<pre><code>bar</code></pre>", "<p>baz</p>"]
        )
    }
}

@Suite("Indented code blocks (spec 4.4)")
struct IndentedCodeTests {

    @Test func fourSpacesMakeACodeBlock() async throws {
        #expect(blockHTML("    foo") == "<pre><code>foo</code></pre>")
    }

    @Test func aTabIndentsAsFarAsFourSpaces() async throws {
        #expect(blockHTML("\tfoo") == "<pre><code>foo</code></pre>")
    }

    @Test func contentIsNotParsedAsMarkdown() async throws {
        #expect(blockHTML("    *hi*\n\n    - one") == "<pre><code>*hi*\n\n- one</code></pre>")
    }

    @Test func indentationBeyondFourSpacesIsContent() async throws {
        #expect(blockHTML("    foo\n      bar") == "<pre><code>foo\n  bar</code></pre>")
    }

    @Test func indentedLineCannotInterruptAParagraph() async throws {
        // It is a continuation of the paragraph instead.
        #expect(blockHTML("foo\n    bar") == "<p>foo\nbar</p>")
    }
}

@Suite("Block quotes (spec 5.1)")
struct BlockQuoteTests {

    @Test func simpleQuote() async throws {
        #expect(blockHTML("> foo") == "<blockquote><p>foo</p></blockquote>")
    }

    @Test func markerSpaceIsOptional() async throws {
        #expect(blockHTML(">foo") == "<blockquote><p>foo</p></blockquote>")
    }

    @Test func continuationLinesJoinAsSoftBreaks() async throws {
        // Two quoted lines are one paragraph separated by a soft break, not by
        // a <br>.
        #expect(blockHTML("> foo\n> bar") == "<blockquote><p>foo\nbar</p></blockquote>")
    }

    @Test func contentIsInlineRendered() async throws {
        #expect(blockHTML("> foo *bar*") == "<blockquote><p>foo <em>bar</em></p></blockquote>")
    }

    @Test func quotesNest() async throws {
        #expect(blockHTML("> > foo") == "<blockquote><blockquote><p>foo</p></blockquote></blockquote>")
    }

    @Test func quotesContainOtherBlocks() async throws {
        // A quote holds block structure, not just one paragraph.
        #expect(blockHTML("> # foo") == "<blockquote><h1>foo</h1></blockquote>")
        #expect(blockHTML("> - foo") == "<blockquote><ul><li>foo</li></ul></blockquote>")
    }

    @Test func upToThreeLeadingSpacesAreAllowed() async throws {
        #expect(blockHTML("   > foo") == "<blockquote><p>foo</p></blockquote>")
    }

    @Test func lazyContinuationLineStaysInTheQuote() async throws {
        // The marker may be left off a line that continues a paragraph.
        #expect(allBlockHTML("> foo\nbar") == ["<blockquote><p>foo\nbar</p></blockquote>"])
    }

    @Test func blankLineSeparatesQuotes() async throws {
        #expect(
            allBlockHTML("> foo\n\n> bar")
                == ["<blockquote><p>foo</p></blockquote>", "<blockquote><p>bar</p></blockquote>"]
        )
    }

    @Test func bareMarkerLineSeparatesParagraphsInOneQuote() async throws {
        #expect(blockHTML("> foo\n>\n> bar") == "<blockquote><p>foo</p><p>bar</p></blockquote>")
    }

    @Test func quoteCanInterruptAParagraph() async throws {
        #expect(allBlockHTML("foo\n> bar") == ["<p>foo</p>", "<blockquote><p>bar</p></blockquote>"])
    }

    @Test func hardBreakInsideAQuote() async throws {
        #expect(blockHTML("> foo  \n> bar") == "<blockquote><p>foo<br />\nbar</p></blockquote>")
    }

    @Test func quotesContainFencedCode() async throws {
        #expect(
            blockHTML("> ```\n> let x = 1\n> ```")
                == "<blockquote><pre><code>let x = 1</code></pre></blockquote>"
        )
    }

    @Test func quotesContainNestedLists() async throws {
        #expect(
            blockHTML("> - foo\n>   - bar\n> - baz")
                == "<blockquote><ul><li>foo<ul><li>bar</li></ul></li><li>baz</li></ul></blockquote>"
        )
    }

    @Test func quotesContainTables() async throws {
        #expect(
            blockHTML("> | a |\n> | --- |\n> | 1 |")
                == "<blockquote><div class=\"table-wrap\"><table><thead><tr><th class=\"a-left\">a</th></tr></thead><tbody><tr><td class=\"a-left\">1</td></tr></tbody></table></div></blockquote>"
        )
    }
}

// MARK: - Lists

@Suite("Lists (spec 5.2, 5.3, 5.4)")
struct ListTests {

    @Test func bulletMarkersAreInterchangeable() async throws {
        for marker in ["-", "*", "+"] {
            #expect(blockHTML("\(marker) foo") == "<ul><li>foo</li></ul>", "marker \(marker) failed")
        }
    }

    @Test func multipleItems() async throws {
        #expect(blockHTML("- foo\n- bar") == "<ul><li>foo</li><li>bar</li></ul>")
    }

    @Test func itemContentIsInlineRendered() async throws {
        #expect(blockHTML("- foo *bar*") == "<ul><li>foo <em>bar</em></li></ul>")
    }

    // Deliberate deviation from CommonMark, decided 2026-07-19: the spec puts
    // the starting number on the <ol> as `start` and lets the renderer number
    // the items. This app instead writes the source number onto each <li> as
    // `value`. Both render identically for sequential lists, but `value` also
    // reproduces non-sequential numbering exactly as written, which is the
    // behavior wanted here. These tests assert the app's intent, not the spec.

    @Test func orderedListNumbersEachItemFromTheSource() async throws {
        #expect(blockHTML("1. foo\n2. bar") == "<ol><li value=\"1\">foo</li><li value=\"2\">bar</li></ol>")
    }

    @Test func orderedListPreservesAStartingNumberOtherThanOne() async throws {
        #expect(blockHTML("3. foo\n4. bar") == "<ol><li value=\"3\">foo</li><li value=\"4\">bar</li></ol>")
    }

    @Test func orderedListPreservesNonSequentialNumbering() async throws {
        // The reason for the deviation: these numbers survive as written.
        #expect(blockHTML("1. foo\n1. bar\n5. baz")
            == "<ol><li value=\"1\">foo</li><li value=\"1\">bar</li><li value=\"5\">baz</li></ol>")
    }

    @Test func parenthesisDelimiterIsAccepted() async throws {
        #expect(blockHTML("1) foo") == "<ol><li value=\"1\">foo</li></ol>")
    }

    @Test func nestedListsAreNestedInsideTheParentItem() async throws {
        #expect(blockHTML("- foo\n  - bar") == "<ul><li>foo<ul><li>bar</li></ul></li></ul>")
    }

    @Test func mixedNestingKeepsEachLevelsOwnMarkerType() async throws {
        #expect(blockHTML("- foo\n  1. bar") == "<ul><li>foo<ol><li value=\"1\">bar</li></ol></li></ul>")
    }

    @Test func changingMarkerTypeStartsANewList() async throws {
        #expect(allBlockHTML("- foo\n1. bar") == ["<ul><li>foo</li></ul>", "<ol><li value=\"1\">bar</li></ol>"])
    }

    @Test func looseListItemsWrapContentInParagraphs() async throws {
        // A blank line between items makes the list loose, and every item's
        // content is then wrapped in <p>.
        #expect(blockHTML("- foo\n\n- bar") == "<ul><li><p>foo</p></li><li><p>bar</p></li></ul>")
    }

    @Test func markerNeedsAFollowingSpace() async throws {
        #expect(blockHTML("-foo") == "<p>-foo</p>")
        #expect(blockHTML("1.foo") == "<p>1.foo</p>")
    }

    @Test func extraSpacesAfterTheMarkerAreNotContent() async throws {
        #expect(blockHTML("-   foo") == "<ul><li>foo</li></ul>")
    }

    @Test func aTabMayFollowTheMarker() async throws {
        #expect(blockHTML("-\tfoo") == "<ul><li>foo</li></ul>")
    }

    @Test func emptyItemIsAllowed() async throws {
        #expect(blockHTML("- foo\n-\n- bar") == "<ul><li>foo</li><li></li><li>bar</li></ul>")
    }

    @Test func leadingZerosInTheNumberAreIgnored() async throws {
        #expect(blockHTML("003. foo") == "<ol><li value=\"3\">foo</li></ol>")
    }

    @Test func aBulletListCanInterruptAParagraph() async throws {
        #expect(allBlockHTML("foo\n- bar") == ["<p>foo</p>", "<ul><li>bar</li></ul>"])
    }

    @Test func onlyANumberedListStartingAtOneCanInterruptAParagraph() async throws {
        // Otherwise a wrapped sentence whose next line happens to begin with a
        // number and a period turns into a list.
        #expect(
            blockHTML("The number of windows in my house is\n14.  The number of doors is 6.")
                == "<p>The number of windows in my house is\n14.  The number of doors is 6.</p>"
        )
    }

    @Test func blankLineThenUnindentedTextEndsTheList() async throws {
        #expect(allBlockHTML("- foo\n\nbar") == ["<ul><li>foo</li></ul>", "<p>bar</p>"])
    }

    @Test func itemTextContinuesOnAnIndentedLine() async throws {
        // A hard-wrapped item: the second line is the same paragraph.
        #expect(allBlockHTML("- foo\n  bar") == ["<ul><li>foo\nbar</li></ul>"])
    }

    @Test func lazyContinuationLineStaysInTheItem() async throws {
        #expect(allBlockHTML("- foo\nbar") == ["<ul><li>foo\nbar</li></ul>"])
    }

    @Test func itemsMayHoldSeveralParagraphs() async throws {
        #expect(allBlockHTML("- foo\n\n  bar") == ["<ul><li><p>foo</p><p>bar</p></li></ul>"])
    }

    @Test func itemsContainOtherBlocks() async throws {
        #expect(
            allBlockHTML("- a\n  > b\n  ```\n  c\n  ```\n- d")
                == ["<ul><li>a<blockquote><p>b</p></blockquote><pre><code>c</code></pre></li><li>d</li></ul>"]
        )
    }

    @Test func changingBulletCharacterStartsANewList() async throws {
        #expect(allBlockHTML("- foo\n+ bar") == ["<ul><li>foo</li></ul>", "<ul><li>bar</li></ul>"])
    }

    @Test func changingNumberDelimiterStartsANewList() async throws {
        #expect(
            allBlockHTML("1. foo\n2) bar")
                == ["<ol><li value=\"1\">foo</li></ol>", "<ol><li value=\"2\">bar</li></ol>"]
        )
    }
}

@Suite("Task list items (GitHub extension, not CommonMark)")
struct TaskListTests {

    @Test func uncheckedItem() async throws {
        #expect(
            blockHTML("- [ ] foo")
                == "<ul><li class=\"task\"><label><input type=\"checkbox\" disabled /><span>foo</span></label></li></ul>"
        )
    }

    @Test func checkedItemAcceptsEitherCase() async throws {
        let expected = "<ul><li class=\"task\"><label><input type=\"checkbox\" disabled checked /><span>foo</span></label></li></ul>"
        #expect(blockHTML("- [x] foo") == expected)
        #expect(blockHTML("- [X] foo") == expected)
    }

    @Test func taskItemContentIsInlineRendered() async throws {
        #expect(blockHTML("- [ ] foo *bar*").contains("<span>foo <em>bar</em></span>"))
    }

    @Test func taskItemsNest() async throws {
        #expect(blockHTML("- [ ] foo\n  - [x] bar").contains("</label><ul><li class=\"task\">"))
    }

    @Test func nestedTaskItemsRenderInsideTheirParent() async throws {
        #expect(
            blockHTML("- [ ] foo\n  - [x] bar")
                == "<ul><li class=\"task\"><label><input type=\"checkbox\" disabled /><span>foo</span></label><ul><li class=\"task\"><label><input type=\"checkbox\" disabled checked /><span>bar</span></label></li></ul></li></ul>"
        )
    }

    @Test func taskAndOrdinaryItemsMixInOneList() async throws {
        #expect(
            blockHTML("- [x] foo\n- bar")
                == "<ul><li class=\"task\"><label><input type=\"checkbox\" disabled checked /><span>foo</span></label></li><li>bar</li></ul>"
        )
    }

    @Test func boxWithoutAFollowingSpaceIsText() async throws {
        #expect(blockHTML("- [x]foo") == "<ul><li>[x]foo</li></ul>")
    }

    @Test func anyOtherCharacterInTheBoxIsText() async throws {
        #expect(blockHTML("- [y] foo") == "<ul><li>[y] foo</li></ul>")
    }
}

// MARK: - Inlines

@Suite("Code spans (spec 6.1)")
struct CodeSpanTests {

    @Test func simpleCodeSpan() async throws {
        #expect(blockHTML("`foo`") == "<p><code>foo</code></p>")
    }

    @Test func contentIsHTMLEscaped() async throws {
        #expect(blockHTML("`<&>`") == "<p><code>&lt;&amp;&gt;</code></p>")
    }

    @Test func contentIsNotInlineRendered() async throws {
        #expect(blockHTML("`*foo*`") == "<p><code>*foo*</code></p>")
    }

    @Test func doubleBackticksCanContainASingleBacktick() async throws {
        #expect(blockHTML("`` foo ` bar ``") == "<p><code>foo ` bar</code></p>")
    }

    @Test func oneLeadingAndTrailingSpaceIsStripped() async throws {
        #expect(blockHTML("` foo `") == "<p><code>foo</code></p>")
    }

    @Test func unmatchedBacktickIsLiteral() async throws {
        #expect(blockHTML("`foo") == "<p>`foo</p>")
    }

    @Test func interiorSpacesAreKept() async throws {
        #expect(blockHTML("`a  b`") == "<p><code>a  b</code></p>")
    }

    @Test func lineEndingInsideIsASpace() async throws {
        #expect(blockHTML("`foo\nbar`") == "<p><code>foo bar</code></p>")
    }

    @Test func backslashIsLiteralInside() async throws {
        // So the span ends at the first backtick, escaped-looking or not.
        #expect(blockHTML("`foo\\`bar`") == "<p><code>foo\\</code>bar`</p>")
    }

    @Test func entityIsNotDecodedInside() async throws {
        #expect(blockHTML("`&amp;`") == "<p><code>&amp;amp;</code></p>")
    }

    @Test func codeSpanOutranksEmphasis() async throws {
        #expect(blockHTML("*foo`*`") == "<p>*foo<code>*</code></p>")
    }
}

@Suite("Emphasis and strong emphasis (spec 6.2)")
struct EmphasisTests {

    @Test func asteriskEmphasis() async throws {
        #expect(blockHTML("*foo*") == "<p><em>foo</em></p>")
    }

    @Test func underscoreEmphasis() async throws {
        #expect(blockHTML("_foo_") == "<p><em>foo</em></p>")
    }

    @Test func doubleAsteriskStrong() async throws {
        #expect(blockHTML("**foo**") == "<p><strong>foo</strong></p>")
    }

    @Test func doubleUnderscoreStrong() async throws {
        #expect(blockHTML("__foo__") == "<p><strong>foo</strong></p>")
    }

    @Test func intrawordUnderscoreIsNotEmphasis() async throws {
        // The rule exists to protect identifiers: snake_case_names must survive
        // rendering intact.
        #expect(blockHTML("foo_bar_baz") == "<p>foo_bar_baz</p>")
    }

    @Test func intrawordDoubleUnderscoreIsNotStrong() async throws {
        #expect(blockHTML("foo__bar__baz") == "<p>foo__bar__baz</p>")
    }

    @Test func intrawordAsteriskIsEmphasis() async throws {
        // Asterisks have no intraword restriction, unlike underscores.
        #expect(blockHTML("foo*bar*baz") == "<p>foo<em>bar</em>baz</p>")
    }

    @Test func whitespaceAfterOpeningDelimiterIsNotEmphasis() async throws {
        // The opening delimiter must be left-flanking, so a run followed by a
        // space cannot open emphasis. Written with leading text because a line
        // starting "* " is a bullet list item, not a paragraph.
        #expect(blockHTML("a * foo bar*") == "<p>a * foo bar*</p>")
    }

    @Test func tripleDelimiterIsStrongInsideEmphasis() async throws {
        #expect(blockHTML("***foo***") == "<p><em><strong>foo</strong></em></p>")
    }

    @Test func emphasisNests() async throws {
        #expect(blockHTML("*foo **bar** baz*") == "<p><em>foo <strong>bar</strong> baz</em></p>")
    }

    @Test func unmatchedDelimiterIsLiteral() async throws {
        #expect(blockHTML("*foo") == "<p>*foo</p>")
    }

    @Test func intrawordDoubleAsteriskIsStrong() async throws {
        #expect(blockHTML("foo**bar**baz") == "<p>foo<strong>bar</strong>baz</p>")
    }

    @Test func underscoreEmphasisNextToPunctuation() async throws {
        #expect(blockHTML("(_foo_)") == "<p>(<em>foo</em>)</p>")
    }

    @Test func underscoreClosingInsideAWordIsNotEmphasis() async throws {
        #expect(blockHTML("_foo_bar") == "<p>_foo_bar</p>")
    }

    @Test func asterisksWithSpacesAroundThemAreLiteral() async throws {
        // Arithmetic, not emphasis.
        #expect(blockHTML("a * b * c") == "<p>a * b * c</p>")
    }

    @Test func emphasisSpansASoftBreak() async throws {
        #expect(blockHTML("*foo\nbar*") == "<p><em>foo\nbar</em></p>")
    }

    @Test func emphasisWrapsOtherInlines() async throws {
        #expect(
            blockHTML("*[foo](/url)* **`x`**")
                == "<p><em><a href=\"/url\">foo</a></em> <strong><code>x</code></strong></p>"
        )
    }

    @Test func strongInsideEmphasisInsideAWord() async throws {
        // Spec example 413, the "multiple of three" rule: the inner `**` runs
        // can both open and close, so they may not pair with the outer `*`.
        #expect(blockHTML("*foo**bar**baz*") == "<p><em>foo<strong>bar</strong>baz</em></p>")
    }
}

@Suite("Links (spec 6.3)")
struct LinkTests {

    @Test func inlineLink() async throws {
        #expect(blockHTML("[foo](/url)") == "<p><a href=\"/url\">foo</a></p>")
    }

    @Test func linkLabelIsInlineRendered() async throws {
        #expect(blockHTML("[foo *bar*](/url)") == "<p><a href=\"/url\">foo <em>bar</em></a></p>")
    }

    @Test func linkTitleBecomesATitleAttribute() async throws {
        #expect(blockHTML("[foo](/url \"title\")") == "<p><a href=\"/url\" title=\"title\">foo</a></p>")
    }

    @Test func angleBracketDestinationIsUnwrapped() async throws {
        #expect(blockHTML("[foo](</my url>)") == "<p><a href=\"/my%20url\">foo</a></p>")
    }

    @Test func destinationIsAttributeEscaped() async throws {
        #expect(blockHTML("[foo](/url\"x)").contains("&quot;"))
    }

    @Test func unclosedLinkIsLiteral() async throws {
        #expect(blockHTML("[foo](/url") == "<p>[foo](/url</p>")
    }

    @Test func spaceBetweenTextAndDestinationIsNotALink() async throws {
        #expect(blockHTML("[foo] (/url)") == "<p>[foo] (/url)</p>")
    }

    @Test func singleQuotedTitle() async throws {
        #expect(blockHTML("[foo](/url 'title')") == "<p><a href=\"/url\" title=\"title\">foo</a></p>")
    }

    @Test func titleIsAttributeEscaped() async throws {
        #expect(
            blockHTML("[foo](/url \"a <b> & c\")")
                == "<p><a href=\"/url\" title=\"a &lt;b&gt; &amp; c\">foo</a></p>"
        )
    }

    @Test func ampersandInTheDestinationIsEscaped() async throws {
        #expect(blockHTML("[foo](/url?a=1&b=2)") == "<p><a href=\"/url?a=1&amp;b=2\">foo</a></p>")
    }

    @Test func codeSpanInTheLinkText() async throws {
        #expect(blockHTML("[`foo`](/url)") == "<p><a href=\"/url\"><code>foo</code></a></p>")
    }

    @Test func balancedParenthesesInTheDestination() async throws {
        // The shape of every Wikipedia disambiguation link.
        #expect(blockHTML("[foo](/wiki/Foo_(bar))") == "<p><a href=\"/wiki/Foo_(bar)\">foo</a></p>")
    }

    @Test func bracketsInTheLinkText() async throws {
        #expect(blockHTML("[foo [bar]](/url)") == "<p><a href=\"/url\">foo [bar]</a></p>")
    }

    @Test func imageInsideALink() async throws {
        // A badge: an image that is itself the link's text.
        #expect(
            blockHTML("[![alt](/img.png)](/url)")
                == "<p><a href=\"/url\"><img src=\"/img.png\" alt=\"alt\" /></a></p>"
        )
    }
}

@Suite("Autolinks (spec 6.5)")
struct AutolinkTests {

    @Test func uriInAngleBracketsIsALink() async throws {
        #expect(
            blockHTML("<https://example.com/a?b=c>")
                == "<p><a href=\"https://example.com/a?b=c\">https://example.com/a?b=c</a></p>"
        )
    }

    @Test func emailAddressInAngleBracketsIsAMailtoLink() async throws {
        #expect(
            blockHTML("<foo@example.com>")
                == "<p><a href=\"mailto:foo@example.com\">foo@example.com</a></p>"
        )
    }

    @Test func anythingElseInAngleBracketsIsText() async throws {
        #expect(blockHTML("<not a link>") == "<p>&lt;not a link&gt;</p>")
    }
}

@Suite("Link reference definitions (spec 4.7, 6.3)")
struct ReferenceLinkTests {

    @Test func fullReference() async throws {
        // The definition itself renders nothing.
        #expect(
            allBlockHTML("[foo][bar]\n\n[bar]: /url \"title\"")
                == ["<p><a href=\"/url\" title=\"title\">foo</a></p>"]
        )
    }

    @Test func collapsedReference() async throws {
        #expect(allBlockHTML("[foo][]\n\n[foo]: /url") == ["<p><a href=\"/url\">foo</a></p>"])
    }

    @Test func shortcutReference() async throws {
        #expect(allBlockHTML("[foo]\n\n[foo]: /url") == ["<p><a href=\"/url\">foo</a></p>"])
    }

    @Test func labelsMatchWithoutRegardToCase() async throws {
        #expect(allBlockHTML("[Foo]\n\n[FOO]: /url") == ["<p><a href=\"/url\">Foo</a></p>"])
    }

    @Test func referenceImage() async throws {
        #expect(
            allBlockHTML("![foo][bar]\n\n[bar]: /img.png")
                == ["<p><img src=\"/img.png\" alt=\"foo\" /></p>"]
        )
    }

    @Test func undefinedReferenceIsText() async throws {
        #expect(blockHTML("[foo][bar]") == "<p>[foo][bar]</p>")
    }
}

@Suite("Images (spec 6.4)")
struct ImageTests {

    @Test func inlineImage() async throws {
        #expect(blockHTML("![foo](/url)") == "<p><img src=\"/url\" alt=\"foo\" /></p>")
    }

    @Test func altTextIsPlainTextNotMarkup() async throws {
        // Emphasis inside the description contributes its text content only.
        #expect(blockHTML("![foo *bar*](/url)") == "<p><img src=\"/url\" alt=\"foo bar\" /></p>")
    }

    @Test func imageTitleBecomesATitleAttribute() async throws {
        #expect(blockHTML("![foo](/url \"title\")") == "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>")
    }

    @Test func emptyAltIsAllowed() async throws {
        #expect(blockHTML("![](/url)") == "<p><img src=\"/url\" alt=\"\" /></p>")
    }

    @Test func imageSitsInlineInText() async throws {
        #expect(blockHTML("foo ![bar](/url) baz") == "<p>foo <img src=\"/url\" alt=\"bar\" /> baz</p>")
    }

    @Test func altTextIsAttributeEscaped() async throws {
        // A description cannot close the attribute and start one of its own.
        #expect(
            blockHTML("![a \"b\" <c>](/url)")
                == "<p><img src=\"/url\" alt=\"a &quot;b&quot; &lt;c&gt;\" /></p>"
        )
    }

    @Test func sourceIsAttributeEscaped() async throws {
        #expect(blockHTML("![x](/a\"b)") == "<p><img src=\"/a&quot;b\" alt=\"x\" /></p>")
    }

    @Test func angleBracketSourceMayContainSpaces() async throws {
        #expect(blockHTML("![x](<my pic.png>)") == "<p><img src=\"my%20pic.png\" alt=\"x\" /></p>")
    }
}

@Suite("Backslash escapes and entities (spec 2.4, 2.5)")
struct EscapeTests {

    @Test func escapedAsteriskIsNotEmphasis() async throws {
        #expect(blockHTML("\\*not emphasized\\*") == "<p>*not emphasized*</p>")
    }

    @Test func escapedUnderscoreIsLiteral() async throws {
        #expect(blockHTML("\\_foo\\_") == "<p>_foo_</p>")
    }

    @Test func escapedBacktickIsLiteral() async throws {
        #expect(blockHTML("\\`foo\\`") == "<p>`foo`</p>")
    }

    @Test func escapedBracketIsNotALink() async throws {
        #expect(blockHTML("\\[foo](/url)") == "<p>[foo](/url)</p>")
    }

    @Test func backslashBeforeAnOrdinaryCharacterIsLiteral() async throws {
        #expect(blockHTML("\\A") == "<p>\\A</p>")
    }

    @Test func namedEntityIsDecoded() async throws {
        #expect(blockHTML("&amp; &lt;") == "<p>&amp; &lt;</p>")
    }

    @Test func rawAngleBracketsAreEscaped() async throws {
        #expect(blockHTML("a < b & c") == "<p>a &lt; b &amp; c</p>")
    }

    @Test func escapedBackslashIsOneBackslash() async throws {
        #expect(blockHTML("\\\\*foo*") == "<p>\\<em>foo</em></p>")
    }

    @Test func escapedBlockMarkersAreText() async throws {
        #expect(blockHTML("\\# foo") == "<p># foo</p>")
        #expect(blockHTML("\\- foo") == "<p>- foo</p>")
        #expect(blockHTML("1\\. foo") == "<p>1. foo</p>")
        #expect(blockHTML("\\> foo") == "<p>&gt; foo</p>")
    }

    @Test func numericEntitiesAreDecoded() async throws {
        #expect(blockHTML("&#35; &#x22; &#X41;") == "<p># &quot; A</p>")
    }

    @Test func commonNamedEntitiesAreDecoded() async throws {
        #expect(blockHTML("&copy; &mdash; a&nbsp;b") == "<p>© — a\u{00A0}b</p>")
    }

    @Test func unknownOrUnterminatedEntityIsLiteral() async throws {
        #expect(blockHTML("&nosuch; &amp") == "<p>&amp;nosuch; &amp;amp</p>")
    }
}

// Deliberate deviation from CommonMark: the spec passes raw HTML through
// (sections 4.6 and 6.6). This app escapes all of it, so a document cannot put
// markup of its own into the preview, and `MarkdownImageURL` relies on that to
// keep a document from forging an image URL. These assert the app's intent.
@Suite("Raw HTML is escaped (deliberate deviation from spec 4.6, 6.6)")
struct RawHTMLTests {

    @Test func inlineTagsAreEscaped() async throws {
        #expect(blockHTML("a <b>bold</b> c") == "<p>a &lt;b&gt;bold&lt;/b&gt; c</p>")
    }

    @Test func scriptBlockIsEscaped() async throws {
        #expect(blockHTML("<script>alert(1)</script>") == "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>")
    }

    @Test func htmlBlockIsAParagraphOfEscapedText() async throws {
        #expect(blockHTML("<div>\n*foo*\n</div>") == "<p>&lt;div&gt;\n<em>foo</em>\n&lt;/div&gt;</p>")
    }

    @Test func commentIsEscaped() async throws {
        #expect(blockHTML("<!-- note -->") == "<p>&lt;!-- note --&gt;</p>")
    }

    @Test func imageTagWithAnEventHandlerIsEscaped() async throws {
        #expect(
            blockHTML("<img src=\"x\" onerror=\"alert(1)\">")
                == "<p>&lt;img src=&quot;x&quot; onerror=&quot;alert(1)&quot;&gt;</p>"
        )
    }
}

// MARK: - Tables (GitHub extension, not CommonMark)

@Suite("Tables (GitHub extension, not CommonMark)")
struct TableTests {

    @Test func simpleTable() async throws {
        let source = """
        | a | b |
        | --- | --- |
        | 1 | 2 |
        """

        #expect(
            blockHTML(source)
                == "<div class=\"table-wrap\"><table><thead><tr><th class=\"a-left\">a</th><th class=\"a-left\">b</th></tr></thead><tbody><tr><td class=\"a-left\">1</td><td class=\"a-left\">2</td></tr></tbody></table></div>"
        )
    }

    @Test func alignmentMarkersSetCellClasses() async throws {
        let source = """
        | l | c | r |
        | :-- | :-: | --: |
        | 1 | 2 | 3 |
        """

        let html = blockHTML(source)
        #expect(html.contains("<th class=\"a-left\">l</th>"))
        #expect(html.contains("<th class=\"a-center\">c</th>"))
        #expect(html.contains("<th class=\"a-right\">r</th>"))
    }

    @Test func shortAlignmentMarkersAreAccepted() async throws {
        // GitHub accepts a single dash in a delimiter cell.
        let source = """
        | a | b |
        | - | - |
        | 1 | 2 |
        """

        #expect(blockHTML(source).contains("<tbody>"))
    }

    @Test func cellContentIsInlineRendered() async throws {
        let source = """
        | a |
        | --- |
        | `x` |
        """

        #expect(blockHTML(source).contains("<td class=\"a-left\"><code>x</code></td>"))
    }

    @Test func escapedPipeStaysInTheCell() async throws {
        let source = """
        | a | b |
        | --- | --- |
        | x \\| y | 2 |
        """

        #expect(blockHTML(source).contains("x | y"))
    }

    @Test func rowsShorterThanTheHeaderArePadded() async throws {
        let source = """
        | a | b |
        | --- | --- |
        | 1 |
        """

        #expect(blockHTML(source).contains("<td class=\"a-left\"></td>"))
    }

    private let simpleTableHTML = "<div class=\"table-wrap\"><table><thead><tr><th class=\"a-left\">a</th><th class=\"a-left\">b</th></tr></thead><tbody><tr><td class=\"a-left\">1</td><td class=\"a-left\">2</td></tr></tbody></table></div>"

    @Test func pipesAtTheEdgesAreOptional() async throws {
        #expect(blockHTML("a | b\n--- | ---\n1 | 2") == simpleTableHTML)
    }

    @Test func delimiterRowNeedsNoSpaces() async throws {
        #expect(blockHTML("|a|b|\n|---|---|\n|1|2|") == simpleTableHTML)
    }

    @Test func alignmentAppliesToBodyCellsToo() async throws {
        #expect(
            blockHTML("| l | c | r |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |")
                == "<div class=\"table-wrap\"><table><thead><tr><th class=\"a-left\">l</th><th class=\"a-center\">c</th><th class=\"a-right\">r</th></tr></thead><tbody><tr><td class=\"a-left\">1</td><td class=\"a-center\">2</td><td class=\"a-right\">3</td></tr></tbody></table></div>"
        )
    }

    @Test func headerAndDelimiterRowsMustHaveTheSameNumberOfCells() async throws {
        #expect(blockHTML("| a | b |\n| --- |\n| 1 | 2 |") == "<p>| a | b |\n| --- |\n| 1 | 2 |</p>")
    }

    @Test func rowsLongerThanTheHeaderAreTruncated() async throws {
        #expect(
            blockHTML("| a |\n| --- |\n| 1 | 2 |")
                == "<div class=\"table-wrap\"><table><thead><tr><th class=\"a-left\">a</th></tr></thead><tbody><tr><td class=\"a-left\">1</td></tr></tbody></table></div>"
        )
    }

    @Test func emptyCellInTheMiddleIsKept() async throws {
        #expect(
            blockHTML("| a | b | c |\n| --- | --- | --- |\n| 1 |  | 3 |")
                .contains("<tr><td class=\"a-left\">1</td><td class=\"a-left\"></td><td class=\"a-left\">3</td></tr>")
        )
    }

    @Test func aBlankLineEndsTheTable() async throws {
        #expect(allBlockHTML("| a | b |\n| --- | --- |\n| 1 | 2 |\n\nfoo") == [simpleTableHTML, "<p>foo</p>"])
    }

    @Test func cellsHoldLinksAndEmphasis() async throws {
        #expect(
            blockHTML("| a |\n| --- |\n| *x* [y](/url) **z** |")
                .contains("<td class=\"a-left\"><em>x</em> <a href=\"/url\">y</a> <strong>z</strong></td>")
        )
    }

    @Test func escapedPipeInsideACodeSpanStaysInTheCell() async throws {
        #expect(blockHTML("| a |\n| --- |\n| `x \\| y` |").contains("<td class=\"a-left\"><code>x | y</code></td>"))
    }

    @Test func otherBackslashEscapesReachTheCellIntact() async throws {
        // Only `\|` belongs to the table; any other escape is the cell's own
        // inline content, so an escaped asterisk is still not emphasis.
        #expect(blockHTML("| a |\n| --- |\n| \\*x\\* |").contains("<td class=\"a-left\">*x*</td>"))
    }

    @Test func backslashInsideACodeSpanIsKept() async throws {
        #expect(
            blockHTML("| a |\n| --- |\n| `C:\\dir` |")
                .contains("<td class=\"a-left\"><code>C:\\dir</code></td>")
        )
    }
}
