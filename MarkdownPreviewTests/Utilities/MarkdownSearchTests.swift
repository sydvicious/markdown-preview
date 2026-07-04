//
// Copyright ©2026 Syd Polk. All Rights Reserved.
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
