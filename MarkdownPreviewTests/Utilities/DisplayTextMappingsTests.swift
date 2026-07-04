//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct DisplayTextMappingsTests {

    @Test func markdownTextOffsetMappingStripsMarkdownSyntax() async throws {
        let source = "# **Alpha** [beta](https://example.com)"
        let mapping = MarkdownTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha beta")

        let alphaSourceRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 0, length: 5)
        )
        let betaSourceRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 6, length: 4)
        )

        #expect(alphaSourceRange?.range(in: source).map { String(source[$0]) } == "Alpha")
        #expect(betaSourceRange?.range(in: source).map { String(source[$0]) } == "beta")
    }

    @Test func markdownTextOffsetMappingUsesSearchVisibleTextRules() async throws {
        let source = """
        # **Alpha**

        Paragraph with [beta](https://example.com), `gamma`, and ![diagram](image.png).
        """
        let mapping = MarkdownTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha\nParagraph with beta, gamma, and diagram.")

        let alphaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 0, length: 5)
        )
        let betaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 21, length: 4)
        )
        let gammaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 27, length: 5)
        )
        let diagramRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 38, length: 7)
        )

        #expect(alphaRange?.range(in: source).map { String(source[$0]) } == "Alpha")
        #expect(betaRange?.range(in: source).map { String(source[$0]) } == "beta")
        #expect(gammaRange?.range(in: source).map { String(source[$0]) } == "gamma")
        #expect(diagramRange?.range(in: source).map { String(source[$0]) } == "diagram")
    }

    @Test func markdownTextOffsetMappingPreservesListBoundariesForSearch() async throws {
        let source = """
        - Alpha
        - Beta

        1. Gamma
        2. Delta
        """
        let mapping = MarkdownTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha\nBeta\nGamma\nDelta")

        let betaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 6, length: 4)
        )
        let gammaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 11, length: 5)
        )

        #expect(betaRange?.range(in: source).map { String(source[$0]) } == "Beta")
        #expect(gammaRange?.range(in: source).map { String(source[$0]) } == "Gamma")
    }

    @Test func markdownTextOffsetMappingHandlesSetextHeadingsChecklistTablesAndCode() async throws {
        let source = """
        Alpha Heading
        ============

        - [x] Completed item
        - [ ] Pending item

        | Name | Count |
        | --- | ---: |
        | apples | 12 |

        ```
        let value = 42
        ```
        """
        let mapping = MarkdownTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha Heading\nCompleted item\nPending item\nNameCountapples12\nlet value = 42")
    }

    @Test func markdownTextOffsetMappingRoundTripsSearchMatchesAcrossSupportedMarkdown() async throws {
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
        let mapping = MarkdownTextOffsetMapping(sourceText: source)
        let queries = [
            "Alpha",
            "beta",
            "gamma",
            "delta",
            "epsilon",
            "diagram",
            "Theta",
            "Iota",
            "Kappa",
            "Name",
            "Lambda",
            "12",
            "let value = 42"
        ]

        for query in queries {
            guard let sourceRange = MarkdownSearch.matches(in: source, query: query).first else {
                Issue.record("Expected to find source match for \(query)")
                continue
            }

            guard let displayRange = mapping.displayRange(forSourceRange: sourceRange) else {
                Issue.record("Expected search display range for \(query)")
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
