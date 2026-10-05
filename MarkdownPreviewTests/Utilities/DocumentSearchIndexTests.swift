//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
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

    // Building the index from a list that names one file twice used to trap.
    // On the Mac the index is built in a child process, so that if it ever
    // traps again it fails this test and not the whole run. Exit tests are
    // macOS only; elsewhere a trap would take the run with it.
    @Test(.timeLimit(.minutes(1)))
    func aDocumentListedTwiceIsIndexedOnce() async {
        #if os(macOS)
        await #expect(processExitsWith: .success) {
            exit(DocumentSearchIndexTests.indexesADocumentListedTwice() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        #else
        #expect(Self.indexesADocumentListedTwice())
        #endif
    }

    private static func indexesADocumentListedTwice() -> Bool {
        let file = MarkdownFile(url: URL(fileURLWithPath: "/tmp/example.md"), contents: "Alpha")
        let index = DocumentSearchIndex(documents: [file, file])
        return index.containsMatch(in: file.url.standardizedFileURL.path, query: "Alpha")
    }
}
