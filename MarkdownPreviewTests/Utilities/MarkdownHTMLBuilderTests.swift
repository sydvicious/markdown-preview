//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

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
        #expect(html.contains("<blockquote><p>Quoted line<br>still quoted</p></blockquote>"))
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

        #expect(
            html.contains(
                "<div class=\"md-block\" data-source-start=\"0\" data-source-end=\"49\"><p>Copyright (c) 2026, Syd Polk All rights reserved.</p></div>"
            )
        )
    }
}
