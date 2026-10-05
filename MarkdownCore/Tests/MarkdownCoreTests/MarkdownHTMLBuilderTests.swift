//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownCore

struct MarkdownHTMLBuilderTests {

    @Test func htmlBuilderRendersCoreMarkdownBlocks() async throws {
        let source = """
        # Title

        Paragraph with **bold** text, `code`, and [a link](https://example.com).

        > Quoted line
        > still quoted

        | Name | Count |
        | --- | ---: |
        | apples | 12 |

        ```
        let value = 42
        ```
        """

        let html = MarkdownHTMLBuilder.document(for: source)

        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<code>code</code>"))
        #expect(html.contains("<a href=\"https://example.com\">a link</a>"))
        // Two quoted lines are one paragraph joined by a soft break, which is a
        // newline rather than a <br>.
        #expect(html.contains("<blockquote><p>Quoted line\nstill quoted</p></blockquote>"))
        #expect(html.contains("<table>"))
        #expect(html.contains("class=\"a-right\">12</td>"))
        #expect(html.contains("<pre><code>let value = 42</code></pre>"))
    }

    @Test func htmlBuilderEmbedsSourceRangeMetadata() async throws {
        let source = """
        # Title

        Paragraph text.
        """

        let html = MarkdownHTMLBuilder.document(for: source)

        #expect(html.contains("data-source-start="))
        #expect(html.contains("data-source-end="))
        #expect(html.contains("class=\"md-block\""))
    }

    @Test func htmlBuilderAddsCopyButtonsToCopyableBlockTypes() async throws {
        let source = """
        > Quoted line

        | Name | Count |
        | --- | ---: |
        | apples | 12 |

        ```
        let value = 42
        ```
        """

        let html = MarkdownHTMLBuilder.document(for: source)

        #expect(html.contains("class=\"md-copy-button\""))
        #expect(html.contains("data-copy-button"))
        #expect(html.contains("class=\"md-block md-copyable-block\""))
    }

    @Test func htmlBuilderAvoidsLeadingWhitespaceInsideParagraphBlocks() async throws {
        let source = """
        Copyright (c) 2026, Syd Polk
        All rights reserved.
        """

        let html = MarkdownHTMLBuilder.document(for: source)

        // The line ending between the two lines is a soft break, so it survives
        // as a newline; what must not appear is the second line's indentation.
        #expect(
            html.contains(
                "<div class=\"md-block\" data-source-start=\"0\" data-source-end=\"49\"><p>Copyright (c) 2026, Syd Polk\nAll rights reserved.</p></div>"
            )
        )
    }

    // MARK: - Soft break rendering (SoftBreak option)

    @Test func softBreakDefaultsToNewlineNotABreakTag() async throws {
        // The default is CommonMark: a soft break survives as a newline and no
        // <br> appears. This guards the conformance default against the option
        // below leaking in.
        let html = MarkdownHTMLBuilder.document(for: "foo\nbar")

        #expect(html.contains("<p>foo\nbar</p>"))
        #expect(!html.contains("<br"))
    }

    @Test func lineBreakOptionRendersSoftBreakAsABreakTag() async throws {
        // GitHub "hardbreaks": an ordinary line ending inside a paragraph turns
        // into a <br> so the text lands as it was typed.
        let html = MarkdownHTMLBuilder.document(for: "foo\nbar", softBreak: .lineBreak)

        #expect(html.contains("<p>foo<br />\nbar</p>"))
    }

    @Test func lineBreakOptionAlsoConvertsASingleTrailingSpaceSoftBreak() async throws {
        // A lone trailing space is normally dropped and the line ending is a
        // soft break; under .lineBreak that break still becomes a <br>, and the
        // space is not carried into the output.
        let html = MarkdownHTMLBuilder.document(for: "foo \nbar", softBreak: .lineBreak)

        #expect(html.contains("<p>foo<br />\nbar</p>"))
    }

    @Test func lineBreakOptionLeavesTwoTrailingSpaceHardBreaksIntact() async throws {
        let html = MarkdownHTMLBuilder.document(for: "foo  \nbar", softBreak: .lineBreak)

        #expect(html.contains("<p>foo<br />\nbar</p>"))
    }

    @Test func lineBreakOptionStillSeparatesParagraphsOnABlankLine() async throws {
        // Only the within-paragraph newline changes meaning. A blank line is
        // still a paragraph boundary, not a <br>.
        let html = MarkdownHTMLBuilder.document(for: "foo\n\nbar", softBreak: .lineBreak)

        #expect(html.contains("<p>foo</p>"))
        #expect(html.contains("<p>bar</p>"))
        #expect(!html.contains("<br"))
    }

    @Test func lineBreakOptionAppliesInsideBlockquotes() async throws {
        let html = MarkdownHTMLBuilder.document(for: "> first\n> second", softBreak: .lineBreak)

        #expect(html.contains("<blockquote><p>first<br />\nsecond</p></blockquote>"))
    }

    @Test func htmlBuilderNestsSubListsInsideTheirParentItem() async throws {
        let html = MarkdownHTMLBuilder.document(for: "- parent\n  - child\n- sibling")

        #expect(html.contains("<ul><li>parent<ul><li>child</li></ul></li><li>sibling</li></ul>"))
    }

    @Test func htmlBuilderNestsNumberedSubListsInsideBulletedItems() async throws {
        let html = MarkdownHTMLBuilder.document(for: "- parent\n  1. first\n  2. second")

        #expect(
            html.contains(
                "<ul><li>parent<ol><li value=\"1\">first</li><li value=\"2\">second</li></ol></li></ul>"
            )
        )
    }

    @Test func htmlBuilderEmitsNoWhitespaceBetweenListTags() async throws {
        // The preview walks text nodes to build display offsets, so whitespace
        // between list tags would become a text node and shift every offset
        // after the list.
        let html = MarkdownHTMLBuilder.document(for: "- parent\n  - child\n- sibling")

        guard let start = html.range(of: "<ul>"),
              let end = html.range(of: "</ul>", options: .backwards) else {
            Issue.record("Expected the document to contain a list")
            return
        }

        let listMarkup = String(html[start.lowerBound..<end.upperBound])
        for separator in ["> <", ">\n<", ">\t<"] {
            #expect(
                !listMarkup.contains(separator),
                "found a whitespace text node at \(separator.debugDescription) in \(listMarkup)"
            )
        }
    }

    @Test func htmlBuilderNestsBulletedSubListsInsideNumberedItems() async throws {
        let html = MarkdownHTMLBuilder.document(for: "1. parent\n   - child\n2. second")

        #expect(
            html.contains(
                "<ol><li value=\"1\">parent<ul><li>child</li></ul></li><li value=\"2\">second</li></ol>"
            )
        )
    }

    @Test func htmlBuilderNestsTabIndentedItems() async throws {
        let html = MarkdownHTMLBuilder.document(for: "- parent\n\t- child")

        #expect(html.contains("<ul><li>parent<ul><li>child</li></ul></li></ul>"))
    }

    @Test func htmlBuilderNestsChecklistItems() async throws {
        let html = MarkdownHTMLBuilder.document(for: "- [ ] parent\n  - [x] child")

        #expect(html.contains("<ul><li class=\"task\">"))
        #expect(html.contains("</label><ul><li class=\"task\">"))
    }

    @Test func htmlBuilderNestsDeeplyIndentedItemsOneLevelPerStep() async throws {
        let html = MarkdownHTMLBuilder.document(for: "- one\n  - two\n    - three")

        #expect(html.contains("<ul><li>one<ul><li>two<ul><li>three</li></ul></li></ul></li></ul>"))
    }

    // MARK: - No whitespace between tags, for every block type

    /// The markup of the document's blocks, from the first block's opening tag
    /// to the last one's closing tag.
    private func blockMarkup(for source: String) -> String {
        let html = MarkdownHTMLBuilder.document(for: source)
        guard let start = html.range(of: "<div class=\"md-block"),
              let article = html.range(of: "</article>"),
              let end = html.range(of: "</div>", options: .backwards, range: start.upperBound..<article.lowerBound) else {
            return ""
        }
        return String(html[start.lowerBound..<end.upperBound])
    }

    /// The same rule the list test above holds lists to, for the rest: a block
    /// made of several elements must not put whitespace between them, or the
    /// preview's text walker meets a text node the source mapping never
    /// counted. Each source here is one block, so the newline the builder puts
    /// between blocks does not come into it.
    @Test(arguments: [
        "# heading",
        "heading\n===",
        "plain paragraph",
        "---",
        "```swift\nlet x = 1\n\nlet y = 2\n```",
        "- parent\n  - child\n- sibling",
        "1. one\n   1. nested\n2. two",
        "- one\n\n- two",
        "- [ ] task\n  - [x] nested task\n- plain",
        "> quoted",
        "> first paragraph\n>\n> second paragraph",
        "> > nested quote",
        "> # heading\n> text\n> - item\n> - item\n>\n> ```\n> code\n> ```\n> ---",
        "> | a | b |\n> | --- | --- |\n> | 1 | 2 |",
        "| a | b |\n| :-- | --: |\n| 1 | 2 |\n| 3 | 4 |",
    ])
    func blockMarkupHasNoWhitespaceBetweenTags(source: String) throws {
        let markup = blockMarkup(for: source)
        try #require(!markup.isEmpty, "expected \(source.debugDescription) to render a block")
        #expect(
            markup.components(separatedBy: "class=\"md-block").count == 2,
            "expected \(source.debugDescription) to be one block"
        )

        let between = try NSRegularExpression(pattern: ">\\s+<")
        let found = between.matches(in: markup, range: NSRange(markup.startIndex..., in: markup))
            .compactMap { Range($0.range, in: markup).map { String(markup[$0]) } }
        #expect(found.isEmpty, "whitespace between tags \(found) in \(markup)")
    }

    // MARK: - Source ranges on the blocks

    /// The stretch of `source` each rendered block says it came from, read back
    /// out of the `data-source-start` and `data-source-end` attributes.
    private func blockSources(in source: String) throws -> [String] {
        let html = MarkdownHTMLBuilder.document(for: source)
        let attributes = try NSRegularExpression(
            pattern: "data-source-start=\"(\\d+)\" data-source-end=\"(\\d+)\""
        )
        let nsHTML = html as NSString
        let nsSource = source as NSString

        return attributes.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).map { match in
            let start = Int(nsHTML.substring(with: match.range(at: 1))) ?? -1
            let end = Int(nsHTML.substring(with: match.range(at: 2))) ?? -1
            guard start >= 0, end >= start, end <= nsSource.length else {
                return "<out of bounds \(start)..<\(end)>"
            }
            return nsSource.substring(with: NSRange(location: start, length: end - start))
        }
    }

    @Test func everyBlockCarriesTheRangeOfItsOwnSource() throws {
        let source = """
        # Title

        First line
        second line

        - one
          - two


        > quoted
        > again

        | a | b |
        | --- | --- |
        | 1 | 2 |

        ---

        ```swift
        let x = 1
        ```

        Underlined
        ----------
        """

        #expect(
            try blockSources(in: source) == [
                "# Title",
                "First line\nsecond line",
                "- one\n  - two",
                "> quoted\n> again",
                "| a | b |\n| --- | --- |\n| 1 | 2 |",
                "---",
                "```swift\nlet x = 1\n```",
                "Underlined\n----------",
            ]
        )
    }

    @Test func sourceRangesAreCountedInUTF16LikeTheTextViewsCountThem() throws {
        // The source view's selection is an NSRange, so the offsets written on
        // the blocks have to be UTF-16 too. An emoji is two units and a
        // skin-toned one four, where a Swift `Character` count says one each.
        let source = "# Héllo 😀\n\nwörld 👍🏽 text\n\n- naïve ✅"

        #expect(try blockSources(in: source) == ["# Héllo 😀", "wörld 👍🏽 text", "- naïve ✅"])
    }

    @Test func sourceRangesInAFileWithWindowsLineEndings() throws {
        // A block's range runs to the end of its last line's text; the line
        // ending after it is not part of the block, whichever kind it is.
        let source = "# Title\r\n\r\nFirst line\r\nsecond line\r\n\r\n- one\r\n- two\r\n"

        #expect(try blockSources(in: source) == ["# Title", "First line\r\nsecond line", "- one\r\n- two"])
    }

    @Test func blocksNestedInAQuoteAreNotWrappedOnTheirOwn() throws {
        // A nested block's line numbers are relative to the quote's stripped
        // content, so offsets written on it would point at the wrong text.
        #expect(try blockSources(in: "> # heading\n> text\n> - item") == ["> # heading\n> text\n> - item"])
    }

    @Test func anUnclosedFenceRunsToTheEndOfTheSource() throws {
        #expect(try blockSources(in: "text\n\n```\nlet x = 1\nlet y = 2") == ["text", "```\nlet x = 1\nlet y = 2"])
    }

    // MARK: - The document around the blocks

    @Test func aDocumentWithNothingToRenderGetsAnEmptyPlaceholder() async throws {
        for source in ["", "\n", "  \n\n\t\n"] {
            let html = MarkdownHTMLBuilder.document(for: source)

            #expect(html.contains("<p class=\"empty\"></p>"), "no placeholder for \(source.debugDescription)")
            #expect(!html.contains("class=\"md-block"), "a block was rendered for \(source.debugDescription)")
        }
    }

    @Test func blocksAreSeparatedByASingleNewline() async throws {
        // Outside any block, so it is never counted as text; pinned because
        // the page's markup is what the copy and selection scripts walk.
        let html = MarkdownHTMLBuilder.document(for: "one\n\ntwo")

        #expect(
            html.contains(
                "<div class=\"md-block\" data-source-start=\"0\" data-source-end=\"3\"><p>one</p></div>\n<div class=\"md-block\" data-source-start=\"5\" data-source-end=\"8\"><p>two</p></div>"
            )
        )
    }

    @Test func contentScaleReachesTheStylesheet() async throws {
        let html = MarkdownHTMLBuilder.document(for: "text", contentScale: 1.5)

        #expect(html.contains("--content-scale: 1.5;"))
        #expect(!html.contains("{{content-scale}}"))
    }
}
