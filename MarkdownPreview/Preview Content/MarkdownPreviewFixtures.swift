//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

enum MarkdownPreviewFixtures {
    private static let previewURL = URL(fileURLWithPath: "/tmp/MarkdownPreview.sample.md")

    static let fullFile: MarkdownFile = {
        MarkdownFile(url: previewURL, contents: fullContents)
    }()

    static let excerptFile: MarkdownFile = {
        MarkdownFile(url: previewURL, contents: excerptContents)
    }()

    static let table: MarkdownTable = .init(
        headers: ["Area", "Status", "Notes"],
        alignments: [.leading, .center, .leading],
        rows: [
            ["macOS", "✅", "Open With + drag/drop support"],
            ["iOS", "✅", "Files picker + detail/source toggle"],
            ["iPadOS", "✅", "Split view navigation + toolbar"]
        ]
    )

    private static let fullContents: String = {
        """
        # Markdown Preview

        This is sample preview content used in SwiftUI previews.

        ## Features

        - Headings and paragraphs
        - Lists and blockquotes
        - Inline `code`
        - Tables

        > Preview data is embedded so the canvas works reliably.

        ### Sample Table

        | Area | Status | Notes |
        |:-----|:------:|:------|
        | macOS | ✅ | Open With + drag/drop support |
        | iOS | ✅ | Files picker + detail/source toggle |
        | iPadOS | ✅ | Split view navigation + toolbar |
        """
    }()

    private static let excerptContents: String = {
        let lines = fullContents.components(separatedBy: .newlines)
        return lines.prefix(120).joined(separator: "\n")
    }()
}
