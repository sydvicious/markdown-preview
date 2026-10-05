//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownPreview

struct MarkdownSearchTests {

    @Test func markdownSearchFindsCaseInsensitiveMatchesInSourceOrder() async throws {
        let source = "**Alpha** beta [ALPHA](https://example.com)\nalpha"
        let matches = MarkdownSearch.matches(in: source, query: "alpha")

        #expect(matches.count == 3)
        #expect(matches.compactMap { $0.range(in: source).map { String(source[$0]) } } == [
            "Alpha",
            "ALPHA",
            "alpha"
        ])
    }

    @Test func markdownSearchSessionWrapsOnSecondNavigationAtBoundary() async throws {
        var session = MarkdownSearchSession()
        session.updateQuery("alpha", in: "alpha beta alpha")

        #expect(session.resultPositionText == "1 of 2")

        let firstAdvance = session.move(.forward)
        #expect(firstAdvance)
        #expect(session.resultPositionText == "2 of 2")

        let boundaryAdvance = session.move(.forward)
        #expect(boundaryAdvance == false)
        #expect(session.resultPositionText == "2 of 2")

        let wrappedAdvance = session.move(.forward)
        #expect(wrappedAdvance)
        #expect(session.resultPositionText == "1 of 2")
    }
}

/// What a search finds, one markdown feature at a time.
///
/// Search runs over the document's visible text, so it should find what the
/// reader can see and nothing they cannot: not a link's destination, not the
/// characters that make something a heading or a list. Each case names the
/// stretch of source every match should select. The expectations describe the
/// rendered document, not what the search currently returns.
struct MarkdownSearchFeatureTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let source: String
        let query: String
        /// The source text each match covers, in order.
        let found: [String]

        var testDescription: String { name }

        init(_ name: String, in source: String, find query: String, _ found: [String]) {
            self.name = name
            self.source = source
            self.query = query
            self.found = found
        }
    }

    static let cases: [Case] = [
        // Text
        .init("plain text", in: "Alpha beta", find: "beta", ["beta"]),
        .init("without regard to case or accents", in: "Café ALPHA", find: "cafe alpha", ["Café ALPHA"]),
        .init("query padded with spaces", in: "Alpha beta", find: "  beta ", ["beta"]),
        .init("query of nothing but spaces", in: "Alpha beta", find: "  ", []),
        .init("every match, in order", in: "beta Alpha\n\n- alpha\n\n`ALPHA`", find: "alpha", ["Alpha", "alpha", "ALPHA"]),
        .init("text outside ASCII before the match", in: "😀 👍🏽 *Alpha*", find: "alpha", ["Alpha"]),

        // Inline markup
        .init("emphasised text", in: "one *Alpha* two", find: "alpha", ["Alpha"]),
        .init("a word partly in bold", in: "**Al**pha", find: "alpha", ["Al**pha"]),
        .init("link text", in: "[Alpha](https://example.com/beta)", find: "alpha", ["Alpha"]),
        .init("link destination is not text", in: "[Alpha](https://example.com/beta)", find: "example", []),
        .init("image description", in: "![Alpha](pic.png)", find: "alpha", ["Alpha"]),
        .init("code span", in: "Use `let alpha` here", find: "let alpha", ["let alpha"]),
        .init("underscores inside a word", in: "use snake_case_name here", find: "snake_case", ["snake_case"]),
        .init("asterisks with spaces around them", in: "2 * 3 * 4", find: "2 * 3", ["2 * 3"]),
        .init("escaped character", in: "Alpha\\_beta", find: "alpha_beta", ["Alpha\\_beta"]),
        .init("escaping backslash is not text", in: "Alpha\\_beta", find: "\\", []),
        .init("entity", in: "AT&amp;T", find: "at&t", ["AT&amp;T"]),
        .init("entity name is not text", in: "AT&amp;T", find: "amp", []),

        // Blocks
        .init("ATX heading", in: "## Alpha", find: "alpha", ["Alpha"]),
        .init("heading markers are not text", in: "## Alpha ##", find: "#", []),
        .init("second line of a setext heading", in: "Alpha\nbeta\n=====", find: "beta", ["beta"]),
        .init("setext underline is not text", in: "Alpha\n=====", find: "=", []),
        .init("bulleted item", in: "- Alpha\n- Beta", find: "beta", ["Beta"]),
        .init("numbered item", in: "1. Alpha\n2. Beta", find: "beta", ["Beta"]),
        .init("numbered item with a parenthesis", in: "1) Alpha\n2) Beta", find: "beta", ["Beta"]),
        .init("task item", in: "- [x] Alpha", find: "alpha", ["Alpha"]),
        .init("task box is not text", in: "- [x] Alpha", find: "[x]", []),
        .init("block quote", in: "> Alpha\n> beta", find: "beta", ["beta"]),
        .init("heading inside a block quote", in: "> # Alpha", find: "alpha", ["Alpha"]),
        .init("markers inside a block quote are not text", in: "> # Alpha\n> - beta", find: "#", []),
        .init("fenced code", in: "```swift\nlet alpha = 1\n```", find: "alpha", ["alpha"]),
        .init("fence and its language are not text", in: "```swift\nlet alpha = 1\n```", find: "swift", []),
        .init("fenced code with no closing fence", in: "```\nlet alpha = 1", find: "alpha", ["alpha"]),
        .init("table cell", in: "| Name | Count |\n| --- | --- |\n| Alpha | 12 |", find: "alpha", ["Alpha"]),
        .init("table delimiter row is not text", in: "| Name | Count |\n| --- | --- |\n| Alpha | 12 |", find: "---", []),
        .init(
            "escaped pipe in a table cell",
            in: "| Alpha \\| beta | gamma |\n| --- | --- |\n| 1 | 2 |",
            find: "alpha | beta",
            ["Alpha \\| beta"]
        ),
    ]

    @Test(arguments: cases)
    func searchFindsWhatTheReaderSees(searchCase: Case) {
        let source = searchCase.source as NSString
        let matches = MarkdownSearch.matches(in: searchCase.source, query: searchCase.query)

        #expect(matches.map { source.substring(with: $0.nsRange) } == searchCase.found)
    }
}
