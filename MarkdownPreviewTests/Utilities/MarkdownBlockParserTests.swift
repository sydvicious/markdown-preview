//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct MarkdownBlockParserTests {

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
}
