//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct MarkdownPreviewTextOffsetMappingTests {

    @Test func markdownPreviewTextOffsetMappingUsesPreviewVisibleTextRules() async throws {
        let source = """
        # **Alpha**

        Paragraph with [beta](https://example.com), `gamma`, and ![diagram](image.png).
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha\nParagraph with beta, gamma, and .")

        let alphaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 0, length: 5)
        )
        let betaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 21, length: 4)
        )
        let gammaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 27, length: 5)
        )

        #expect(alphaRange?.range(in: source).map { String(source[$0]) } == "Alpha")
        #expect(betaRange?.range(in: source).map { String(source[$0]) } == "beta")
        #expect(gammaRange?.range(in: source).map { String(source[$0]) } == "gamma")
        #expect(mapping.displayText.contains("diagram") == false)
    }

    @Test func markdownPreviewTextOffsetMappingCollapsesListBoundariesLikePreview() async throws {
        let source = """
        - Alpha
        - Beta

        1. Gamma
        2. Delta
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "AlphaBeta\nGammaDelta")

        let betaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 5, length: 4)
        )
        let gammaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 10, length: 5)
        )

        #expect(betaRange?.range(in: source).map { String(source[$0]) } == "Beta")
        #expect(gammaRange?.range(in: source).map { String(source[$0]) } == "Gamma")
    }

    @Test func markdownPreviewTextOffsetMappingHandlesBlockquotesTablesAndCode() async throws {
        let source = """
        > Quote line
        > second line

        | Name | Count |
        | --- | ---: |
        | apples | 12 |

        ```
        let value = 42
        next line
        ```
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Quote linesecond line\nNameCountapples12\nlet value = 42\nnext line")
    }

    @Test func markdownPreviewTextOffsetMappingHandlesSetextHeadingsAndChecklistSyntax() async throws {
        let source = """
        Alpha Heading
        ============

        - [x] Completed item
        - [ ] Pending item
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha Heading\nCompleted itemPending item")

        let headingRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 0, length: 13)
        )
        let completedRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 14, length: 14)
        )
        let pendingRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 28, length: 12)
        )

        #expect(headingRange?.range(in: source).map { String(source[$0]) } == "Alpha Heading")
        #expect(completedRange?.range(in: source).map { String(source[$0]) } == "Completed item")
        #expect(pendingRange?.range(in: source).map { String(source[$0]) } == "Pending item")
    }

    @Test func markdownPreviewTextOffsetMappingRoundTripsSearchMatchesAcrossSupportedMarkdown() async throws {
        let source = """
        Alpha Heading
        ============

        Paragraph with [beta](https://example.com), **gamma**, _delta_, `epsilon`, and ![diagram](image.png).

        - [x] Theta item
        - [ ] Iota item

        > Kappa quote

        | Name | Count |
        | --- | ---: |
        | Lambda | 12 |

        ```
        let value = 42
        ```
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)
        let queries = [
            "Alpha",
            "beta",
            "gamma",
            "delta",
            "epsilon",
            "Theta",
            "Iota",
            "Kappa",
            "Name",
            "Lambda",
            "12",
            "let value = 42"
        ]

        #expect(mapping.displayText.contains("diagram") == false)

        for query in queries {
            guard let sourceRange = MarkdownSearch.matches(in: source, query: query).first else {
                Issue.record("Expected to find source match for \(query)")
                continue
            }

            guard let displayRange = mapping.displayRange(forSourceRange: sourceRange) else {
                Issue.record("Expected preview display range for \(query)")
                continue
            }

            let displaySnippet = (mapping.displayText as NSString).substring(with: displayRange.nsRange)
            #expect(displaySnippet == query)

            guard let roundTrippedSourceRange = mapping.sourceRange(forDisplayRange: displayRange) else {
                Issue.record("Expected round-tripped source range for \(query)")
                continue
            }

            let sourceSnippet = (source as NSString).substring(with: roundTrippedSourceRange.nsRange)
            #expect(sourceSnippet == query)
        }
    }
}
