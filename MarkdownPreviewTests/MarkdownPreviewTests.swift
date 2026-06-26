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

    @MainActor
    @Test func groupsDocumentsByParentDirectoryWithSortedSections() async throws {
        let home = NSHomeDirectory()
        let files = [
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/zeta.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "\(home)/work/beta.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "\(home)/work/alpha.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "\(home)/root.md"), contents: "")
        ]

        let store = DocumentSessionStore(
            previewFiles: files,
            disablePersistenceRestore: true
        )

        let sections = store.groupedDocumentsByParentDirectory

        #expect(sections.map(\.label) == [
            "/tmp/notes",
            "~",
            "~/work"
        ])
        #expect(sections[0].documents.map(\.file.fileName) == ["zeta.md"])
        #expect(sections[1].documents.map(\.file.fileName) == ["root.md"])
        #expect(sections[2].documents.map(\.file.fileName) == ["alpha.md", "beta.md"])
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

    @Test func clipboardPayloadIncludesMarkdownAndRichText() async throws {
        let source = """
        # Title

        Paragraph with **bold** text.
        """

        let payload = MarkdownSelectionClipboard.payload(
            for: source,
            ranges: [MarkdownSelectionRange(location: 0, length: source.utf16.count)]
        )

        #expect(payload?.markdown == source)
        #expect(payload?.rtf?.isEmpty == false)
    }

    @Test func selectedMarkdownUsesSelectionRangesInSourceOrder() async throws {
        let source = "alpha beta gamma"
        let ranges = [
            MarkdownSelectionRange(location: 11, length: 5),
            MarkdownSelectionRange(location: 0, length: 5)
        ]

        #expect(MarkdownSelectionClipboard.selectedMarkdown(in: source, ranges: ranges) == "alpha\ngamma")
    }

    @Test func parserKeepsCodeFenceLinesInBlockRange() async throws {
        let source = """
        ```swift
        let value = 42
        ```
        """

        let blocks = MarkdownBlockParser.parse(source)
        guard case let .code(code)? = blocks.first?.kind else {
            Issue.record("Expected first block to be a code block")
            return
        }

        #expect(code == "let value = 42")
        #expect(blocks.first?.lineRange == 0..<3)
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

}
