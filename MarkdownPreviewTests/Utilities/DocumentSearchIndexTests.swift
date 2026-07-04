//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct DocumentSearchIndexTests {

    @Test func documentSearchIndexMatchesAgainstStrippedText() async throws {
        let file = MarkdownFile(
            url: URL(fileURLWithPath: "/tmp/example.md"),
            contents: "# **Alpha** [beta](https://example.com)"
        )
        let index = DocumentSearchIndex(documents: [file])
        let documentID = file.url.standardizedFileURL.path

        #expect(index.containsMatch(in: documentID, query: "Alpha"))
        #expect(index.containsMatch(in: documentID, query: "beta"))
        #expect(index.containsMatch(in: documentID, query: "example.md"))
        #expect(index.containsMatch(in: documentID, query: "https") == false)
    }

    @Test func documentSearchIndexMatchesSubstringsWithinWords() async throws {
        let file = MarkdownFile(
            url: URL(fileURLWithPath: "/tmp/readme.md"),
            contents: "The repository includes unit/UI test targets."
        )
        let index = DocumentSearchIndex(documents: [file])
        let documentID = file.url.standardizedFileURL.path

        #expect(index.containsMatch(in: documentID, query: "repo"))
    }
}
