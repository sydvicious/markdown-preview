//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

//
//  MarkdownPreviewTests.swift
//  MarkdownPreviewTests
//
//  Created by Syd Polk on 1/25/25.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct MarkdownPreviewTests {

    @MainActor
    @Test func sortsOpenedDocumentsByFileName() async throws {
        let files = [
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/zeta.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/alpha.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/chapter-2.md"), contents: "")
        ]

        let store = DocumentSessionStore(
            previewFiles: files,
            disablePersistenceRestore: true
        )

        #expect(store.sortedDocuments.map { $0.file.fileName } == [
            "alpha.md",
            "chapter-2.md",
            "zeta.md"
        ])
    }

    @MainActor
    @Test func deletingFromSortedListRemovesOnlyThatSessionEntry() async throws {
        let alpha = MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/alpha.md"), contents: "alpha")
        let chapter = MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/chapter-2.md"), contents: "chapter")
        let zeta = MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/zeta.md"), contents: "zeta")

        let store = DocumentSessionStore(
            previewFiles: [zeta, alpha, chapter],
            selectedPreviewFileID: chapter.url.standardizedFileURL.path,
            disablePersistenceRestore: true
        )

        store.deleteDocuments(at: IndexSet(integer: 1), isCompactWidth: false)

        #expect(store.sortedDocuments.map { $0.file.fileName } == [
            "alpha.md",
            "zeta.md"
        ])
        #expect(store.selectedDocumentID == alpha.url.standardizedFileURL.path)
    }

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

}
