//
// Copyright ©2026 Syd Polk. All Rights Reserved.
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
}
