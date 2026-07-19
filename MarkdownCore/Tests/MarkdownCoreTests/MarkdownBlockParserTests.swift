//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownCore

struct MarkdownBlockParserTests {

    @Test func parserKeepsCodeFenceLinesInBlockRange() async throws {
        let source = """
        ```swift
        let value = 42
        ```
        """

        let blocks = MarkdownBlockParser.parse(source)
        guard case let .code(code, language)? = blocks.first?.kind else {
            Issue.record("Expected first block to be a code block")
            return
        }

        #expect(code == "let value = 42")
        #expect(language == "swift")
        #expect(blocks.first?.lineRange == 0..<3)
    }

    private func listItems(_ source: String) -> [MarkdownListItem] {
        for block in MarkdownBlockParser.parse(source) {
            switch block.kind {
            case let .list(items, _), let .orderedList(items, _):
                return items
            default:
                continue
            }
        }
        return []
    }

    @Test func nestingDepthIsRelativeSoAnyIndentWidthNestsOneLevel() async throws {
        // Two spaces, four spaces, and a tab are all "indented past the parent's
        // content column", so each nests exactly one level.
        for indent in ["  ", "    ", "\t"] {
            let items = listItems("- parent\n\(indent)- child")
            #expect(items.count == 2, "indent \(indent.debugDescription) did not produce two items")
            #expect(items.map(\.indent) == [0, 1], "indent \(indent.debugDescription) nested wrongly")
        }
    }

    @Test func nestingDepthDoesNotSkipLevels() async throws {
        // Eight spaces under a top-level item is still a single level deeper;
        // CommonMark has no way to jump straight to depth two.
        let items = listItems("- parent\n        - child")
        #expect(items.map(\.indent) == [0, 1])
    }

    @Test func dedentReturnsToTheMatchingLevel() async throws {
        let source = """
        - one
          - two
            - three
          - back to two
        - back to one
        """

        #expect(listItems(source).map(\.indent) == [0, 1, 2, 1, 0])
    }

    @Test func numberedListsNestTheSameWayAsBulletedOnes() async throws {
        let source = """
        1. one
           1. one point one
           2. one point two
        2. two
        """

        let items = listItems(source)
        #expect(items.map(\.indent) == [0, 1, 1, 0])
        #expect(items.map(\.isOrdered) == [true, true, true, true])
        #expect(items.map(\.order) == [1, 1, 2, 2])
    }

    @Test func aNumberedListNestsInsideABulletedOne() async throws {
        let source = """
        - parent
          1. first
          2. second
        - sibling
        """

        let blocks = MarkdownBlockParser.parse(source)
        // The mixed nesting stays one block so it can render as one nested list.
        #expect(blocks.count == 1)
        guard case let .list(items, _)? = blocks.first?.kind else {
            Issue.record("Expected a bulleted list block")
            return
        }

        #expect(items.map(\.indent) == [0, 1, 1, 0])
        #expect(items.map(\.isOrdered) == [false, true, true, false])
    }

    @Test func switchingMarkerTypeAtTopLevelStartsANewList() async throws {
        let blocks = MarkdownBlockParser.parse("- bullet\n1. numbered")
        #expect(blocks.count == 2)

        guard case .list? = blocks.first?.kind else {
            Issue.record("Expected the first block to be a bulleted list")
            return
        }
        guard case .orderedList? = blocks.last?.kind else {
            Issue.record("Expected the second block to be a numbered list")
            return
        }
    }

    @Test func wideNumberMarkersStillNestTheirChildren() async throws {
        // "10. " is a four-column marker, so the child must reach column four.
        let items = listItems("10. ten\n    - child")
        #expect(items.map(\.indent) == [0, 1])
    }
}
