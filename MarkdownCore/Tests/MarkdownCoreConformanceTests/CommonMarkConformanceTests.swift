//
// Copyright ©2026 Syd Polk. All Rights Reserved.
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
//  Two deviations from the spec are intentional app structure rather than
//  bugs, and are asserted in the app's shape:
//    - every block is wrapped in a `md-block` div carrying source offsets that
//      the preview's selection mapping depends on;
//    - tables and task lists are GitHub extensions the app supports, and are
//      not described by CommonMark at all.
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

    @Test func orderedListRenders() async throws {
        #expect(blockHTML("1. foo\n2. bar") == "<ol><li>foo</li><li>bar</li></ol>")
    }

    @Test func orderedListStartNumberIsCarriedOnTheList() async throws {
        // The spec puts the starting number on the <ol>; subsequent numbering
        // is the renderer's job, so items carry no value attribute.
        #expect(blockHTML("3. foo\n4. bar") == "<ol start=\"3\"><li>foo</li><li>bar</li></ol>")
    }

    @Test func orderedListStartingAtOneHasNoStartAttribute() async throws {
        #expect(blockHTML("1. foo") == "<ol><li>foo</li></ol>")
    }

    @Test func parenthesisDelimiterIsAccepted() async throws {
        #expect(blockHTML("1) foo") == "<ol><li>foo</li></ol>")
    }

    @Test func nestedListsAreNestedInsideTheParentItem() async throws {
        #expect(blockHTML("- foo\n  - bar") == "<ul><li>foo<ul><li>bar</li></ul></li></ul>")
    }

    @Test func mixedNestingKeepsEachLevelsOwnMarkerType() async throws {
        #expect(blockHTML("- foo\n  1. bar") == "<ul><li>foo<ol><li>bar</li></ol></li></ul>")
    }

    @Test func changingMarkerTypeStartsANewList() async throws {
        #expect(allBlockHTML("- foo\n1. bar") == ["<ul><li>foo</li></ul>", "<ol><li>bar</li></ol>"])
    }

    @Test func looseListItemsWrapContentInParagraphs() async throws {
        // A blank line between items makes the list loose, and every item's
        // content is then wrapped in <p>.
        #expect(blockHTML("- foo\n\n- bar") == "<ul><li><p>foo</p></li><li><p>bar</p></li></ul>")
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
        // The opening delimiter must be left-flanking: "* foo *" is literal.
        #expect(blockHTML("* foo *") == "<p>* foo *</p>")
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
}
