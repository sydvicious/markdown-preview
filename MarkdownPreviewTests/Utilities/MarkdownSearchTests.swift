//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore

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

/// Moving between the matches of a search, and what a session does when the
/// document it is searching changes under it.
///
/// At either end of the matches a move is refused the first time it is asked
/// for, and wraps round the second time. The refusal is the reader's notice
/// that they have reached the end.
struct MarkdownSearchSessionTests {

    /// Three matches, at 0, 11 and 23.
    private static let text = "alpha beta alpha gamma alpha"

    /// A session that has just searched `text` for "alpha", so it is at the
    /// first of three matches.
    private func makeSession(searching text: String = MarkdownSearchSessionTests.text) -> MarkdownSearchSession {
        var session = MarkdownSearchSession()
        session.updateQuery("alpha", in: text)
        return session
    }

    @Test func aNewSearchStartsAtItsFirstMatch() {
        let session = makeSession()

        #expect(session.resultCount == 3)
        #expect(session.resultPositionText == "1 of 3")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 0, length: 5))
    }

    @Test func theCurrentMatchFollowsThePosition() {
        var session = makeSession()

        session.move(.forward)
        #expect(session.currentMatch == MarkdownSelectionRange(location: 11, length: 5))

        session.move(.forward)
        #expect(session.currentMatch == MarkdownSelectionRange(location: 23, length: 5))
    }

    // MARK: - Find Previous

    @Test func findPreviousGoesToTheMatchBefore() {
        var session = makeSession()
        session.move(.forward)
        session.move(.forward)

        let moved = session.move(.backward)

        #expect(moved)
        #expect(session.resultPositionText == "2 of 3")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 11, length: 5))
    }

    /// The mirror of Find Next at the last match: refused once, and round to
    /// the last match the second time.
    @Test func findPreviousAtTheFirstMatchIsRefusedOnceAndThenWrapsToTheLast() {
        var session = makeSession()

        let refused = session.move(.backward)
        #expect(!refused)
        #expect(session.resultPositionText == "1 of 3")

        let wrapped = session.move(.backward)
        #expect(wrapped)
        #expect(session.resultPositionText == "3 of 3")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 23, length: 5))
    }

    @Test func findPreviousAfterWrappingCarriesOnBackward() {
        var session = makeSession()
        session.move(.backward)
        session.move(.backward)

        let moved = session.move(.backward)

        #expect(moved)
        #expect(session.resultPositionText == "2 of 3")
    }

    // MARK: - Changing direction at an end

    /// The refusal at the last match is a notice, not a promise. Going back
    /// instead simply goes back, and the wrap that was waiting is forgotten:
    /// coming forward to the end again is refused again.
    @Test func goingBackAfterBeingRefusedAtTheLastMatchForgetsTheWrap() {
        var session = makeSession()
        session.move(.forward)
        session.move(.forward)
        let moved1 = session.move(.forward)
        #expect(!moved1)

        let back = session.move(.backward)
        #expect(back)
        #expect(session.resultPositionText == "2 of 3")

        let forwardAgain = session.move(.forward)
        #expect(forwardAgain)
        #expect(session.resultPositionText == "3 of 3")

        let refusedAgain = session.move(.forward)
        #expect(!refusedAgain)
        #expect(session.resultPositionText == "3 of 3")
    }

    @Test func goingForwardAfterBeingRefusedAtTheFirstMatchForgetsTheWrap() {
        var session = makeSession()
        let moved2 = session.move(.backward)
        #expect(!moved2)

        let forward = session.move(.forward)
        #expect(forward)
        #expect(session.resultPositionText == "2 of 3")

        let backAgain = session.move(.backward)
        #expect(backAgain)
        #expect(session.resultPositionText == "1 of 3")

        let refusedAgain = session.move(.backward)
        #expect(!refusedAgain)
        #expect(session.resultPositionText == "1 of 3")
    }

    /// With one match it is both the first and the last, so either direction
    /// is refused once and then wraps, to the only place there is.
    @Test(arguments: [MarkdownSearchDirection.forward, .backward])
    func withOneMatchAMoveIsRefusedOnceAndThenWrapsToTheSameMatch(direction: MarkdownSearchDirection) {
        var session = makeSession(searching: "one alpha only")

        let refused = session.move(direction)
        #expect(!refused)
        #expect(session.resultPositionText == "1 of 1")

        let wrapped = session.move(direction)
        #expect(wrapped)
        #expect(session.resultPositionText == "1 of 1")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 4, length: 5))
    }

    /// A wrap is earned by asking twice for the same thing. Asked for the other
    /// direction in between, neither has been asked for twice.
    @Test func withOneMatchAlternatingDirectionsNeverWraps() {
        var session = makeSession(searching: "one alpha only")

        let moved3 = session.move(.forward)
        #expect(!moved3)
        let moved4 = session.move(.backward)
        #expect(!moved4)
        let moved5 = session.move(.forward)
        #expect(!moved5)
        #expect(session.resultPositionText == "1 of 1")
    }

    // MARK: - Nothing to find

    @Test(arguments: [MarkdownSearchDirection.forward, .backward])
    func withNoMatchesAMoveGoesNowhere(direction: MarkdownSearchDirection) {
        var session = MarkdownSearchSession()
        session.updateQuery("zucchini", in: Self.text)

        let moved = session.move(direction)

        #expect(!moved)
        #expect(session.resultCount == 0)
        #expect(session.currentMatch == nil)
        #expect(session.resultPositionText == nil)
        // And asking again is not a second request to wrap.
        let moved6 = session.move(direction)
        #expect(!moved6)
    }

    @Test func anEmptySearchFindsNothing() {
        var session = makeSession()

        session.updateQuery("   ", in: Self.text)

        #expect(session.resultCount == 0)
        #expect(session.currentMatch == nil)
        let moved7 = session.move(.forward)
        #expect(!moved7)
    }

    // MARK: - A new search

    @Test func aNewSearchStartsOverFromTheFirstMatchWithNoWrapWaiting() {
        var session = makeSession()
        session.move(.forward)
        session.move(.forward)
        let moved8 = session.move(.forward)
        #expect(!moved8)

        session.updateQuery("beta", in: Self.text)

        #expect(session.query == "beta")
        #expect(session.resultPositionText == "1 of 1")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 6, length: 4))
        // The refusal that was waiting belonged to the search before.
        let moved9 = session.move(.forward)
        #expect(!moved9)
    }

    // MARK: - The document changes under the search

    /// The reader was at the last of three matches and the document now has
    /// two, so they are at the last of two.
    @Test func whenTheMatchesShrinkPastThePositionItMovesToTheLastOneLeft() {
        var session = makeSession()
        session.move(.forward)
        session.move(.forward)
        #expect(session.resultPositionText == "3 of 3")

        session.refresh(in: "alpha beta alpha")

        #expect(session.resultCount == 2)
        #expect(session.resultPositionText == "2 of 2")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 11, length: 5))
    }

    @Test func whenTheMatchesShrinkButThePositionIsStillThereItStays() {
        var session = makeSession()
        session.move(.forward)
        #expect(session.resultPositionText == "2 of 3")

        session.refresh(in: "alpha beta alpha")

        #expect(session.resultPositionText == "2 of 2")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 11, length: 5))
    }

    @Test func whenEveryMatchGoesThereIsNoCurrentMatch() {
        var session = makeSession()
        session.move(.forward)

        session.refresh(in: "beta gamma")

        #expect(session.query == "alpha")
        #expect(session.resultCount == 0)
        #expect(session.currentMatch == nil)
        #expect(session.resultPositionText == nil)
        let moved10 = session.move(.forward)
        #expect(!moved10)
        let moved11 = session.move(.backward)
        #expect(!moved11)
    }

    @Test func whenMatchesAreAddedThePositionStays() {
        var session = makeSession(searching: "alpha beta alpha")
        session.move(.forward)
        #expect(session.resultPositionText == "2 of 2")

        session.refresh(in: Self.text)

        #expect(session.resultPositionText == "2 of 3")
        // There is now somewhere further to go.
        let moved12 = session.move(.forward)
        #expect(moved12)
        #expect(session.resultPositionText == "3 of 3")
    }

    /// A search that found nothing starts at the first match once the
    /// document has one.
    @Test func whenADocumentWithNoMatchesGainsSomeTheSearchStartsAtTheFirst() {
        var session = makeSession(searching: "beta gamma")
        #expect(session.resultCount == 0)

        session.refresh(in: Self.text)

        #expect(session.resultCount == 3)
        #expect(session.resultPositionText == "1 of 3")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 0, length: 5))
    }

    /// The matches are found again in the new text, so a match that has moved
    /// is selected where it now is.
    @Test func aMatchThatMovedIsFoundWhereItIsNow() {
        var session = makeSession()
        session.move(.forward)

        session.refresh(in: "A new first line.\n\n" + Self.text)

        #expect(session.resultPositionText == "2 of 3")
        #expect(session.currentMatch == MarkdownSelectionRange(location: 30, length: 5))
    }
}

/// The words offered under a search field as the reader types, from one
/// document's text.
struct MarkdownSearchSuggestionTests {

    private static let text = "Alphabet soup: alpha, alphabetical, ALPHABET and alpine. Also algae."

    private func suggestions(for prefix: String, in text: String = MarkdownSearchSuggestionTests.text, limit: Int = 5) -> [String] {
        MarkdownSearch.suggestedCompletions(in: text, prefix: prefix, limit: limit)
    }

    /// Words that begin with what was typed, in the order the document has
    /// them, spelled as the document spells them.
    @Test func suggestsTheWordsThatBeginWithWhatWasTyped() {
        #expect(suggestions(for: "alp") == ["Alphabet", "alpha", "alphabetical", "alpine"])
        #expect(suggestions(for: "so") == ["soup"])
        #expect(suggestions(for: "zu").isEmpty)
    }

    // MARK: - Minimum length

    /// One letter begins too many words to be worth offering any.
    @Test func suggestsNothingForFewerThanTwoCharacters() {
        #expect(suggestions(for: "").isEmpty)
        #expect(suggestions(for: "a").isEmpty)
        #expect(suggestions(for: "al").isEmpty == false)
    }

    @Test func spacesAroundWhatWasTypedDoNotCount() {
        #expect(suggestions(for: "  alp ") == suggestions(for: "alp"))
        // One letter with spaces round it is still one letter.
        #expect(suggestions(for: " a ").isEmpty)
        #expect(suggestions(for: "   ").isEmpty)
    }

    // MARK: - Limit

    @Test func suggestsNoMoreThanTheLimit() {
        // Six words begin with "al": Alphabet, alpha, alphabetical, alpine,
        // Also and algae.
        #expect(suggestions(for: "al") == ["Alphabet", "alpha", "alphabetical", "alpine", "Also"])
        #expect(suggestions(for: "al", limit: 2) == ["Alphabet", "alpha"])
        #expect(suggestions(for: "al", limit: 1) == ["Alphabet"])
        #expect(suggestions(for: "al", limit: 10) == ["Alphabet", "alpha", "alphabetical", "alpine", "Also", "algae"])
    }

    // MARK: - No repeats

    /// A word the document uses twice is offered once, as it is first spelled.
    @Test func aWordIsSuggestedOnceHoweverOftenItAppears() {
        #expect(suggestions(for: "alphab") == ["Alphabet", "alphabetical"])
        #expect(suggestions(for: "th", in: "the Theory, THE theory, and then the thesis") == ["the", "Theory", "then", "thesis"])
    }

    /// What was typed is already in the field, so it is not offered back.
    @Test func theWordAlreadyTypedIsNotSuggested() {
        #expect(suggestions(for: "alpha") == ["Alphabet", "alphabetical"])
        #expect(suggestions(for: "ALPINE").isEmpty)
    }

    // MARK: - Folding

    @Test func capitalsDoNotMatter() {
        #expect(suggestions(for: "ALP") == suggestions(for: "alp"))
        #expect(suggestions(for: "aLs") == ["Also"])
    }

    @Test func accentsDoNotMatter() {
        let text = "Café society and the CAFETERIA; a naïve Zoë."

        #expect(suggestions(for: "caf", in: text) == ["Café", "CAFETERIA"])
        #expect(suggestions(for: "nai", in: text) == ["naïve"])
        #expect(suggestions(for: "zo", in: text) == ["Zoë"])
        // An accent that was typed matters no more than one that was not.
        #expect(suggestions(for: "caféte", in: text) == ["CAFETERIA"])
    }

    /// "Café" is what was typed, give or take its accent, so it is not offered.
    @Test func theWordAlreadyTypedIsNotSuggestedWhateverItsAccents() {
        #expect(suggestions(for: "cafe", in: "Café society and the CAFETERIA") == ["CAFETERIA"])
    }

    // MARK: - What a word is

    @Test func wordsEndAtAnythingThatIsNotALetterOrADigit() {
        let text = "snake_case and well-known paths/like/this, plus version 2024 and 2025."

        #expect(suggestions(for: "sn", in: text) == ["snake"])
        #expect(suggestions(for: "ca", in: text) == ["case"])
        #expect(suggestions(for: "kn", in: text) == ["known"])
        #expect(suggestions(for: "li", in: text) == ["like"])
        #expect(suggestions(for: "20", in: text) == ["2024", "2025"])
    }

    /// The reader searches what they can see, so that is what is offered: not
    /// a link's address, nor the characters that make something a heading.
    @Test func onlyWhatTheReaderCanSeeIsSuggested() {
        let text = "# Beta notes\n\nSee the [beta test](https://example.com/hidden) and `betamax`."

        #expect(suggestions(for: "be", in: text) == ["Beta", "betamax"])
        #expect(suggestions(for: "ht", in: text).isEmpty)
        #expect(suggestions(for: "ex", in: text).isEmpty)
        #expect(suggestions(for: "hi", in: text).isEmpty)
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
        .init("after a Windows line ending", in: "Alpha\r\n\r\n- beta\r\n- gamma\r\n", find: "gamma", ["gamma"]),

        // Inline markup
        .init("emphasised text", in: "one *Alpha* two", find: "alpha", ["Alpha"]),
        .init("a word partly in bold", in: "**Al**pha", find: "alpha", ["Al**pha"]),
        .init("link text", in: "[Alpha](https://example.com/beta)", find: "alpha", ["Alpha"]),
        .init("link destination is not text", in: "[Alpha](https://example.com/beta)", find: "example", []),
        .init("image description", in: "![Alpha](pic.png)", find: "alpha", ["Alpha"]),
        .init("reference link text", in: "[Alpha][ref]\n\n[ref]: https://example.com/beta", find: "alpha", ["Alpha"]),
        .init("a reference's label is not text", in: "[Alpha][ref]\n\n[ref]: https://example.com/beta", find: "ref", []),
        .init("a definition is not text", in: "[Alpha][ref]\n\n[ref]: https://example.com/beta", find: "example", []),
        .init("autolink address", in: "see <https://example.com/alpha>", find: "example.com/alpha", ["example.com/alpha"]),
        .init("autolink brackets are not text", in: "see <https://example.com/alpha>", find: "<", []),
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
        .init("second line of a list item", in: "- Alpha\n  beta\n- gamma", find: "beta", ["beta"]),
        .init("code inside a list item", in: "- Alpha\n  ```\n  let beta = 1\n  ```", find: "let beta", ["let beta"]),
        .init("task box is not text", in: "- [x] Alpha", find: "[x]", []),
        .init("block quote", in: "> Alpha\n> beta", find: "beta", ["beta"]),
        .init("heading inside a block quote", in: "> # Alpha", find: "alpha", ["Alpha"]),
        .init("markers inside a block quote are not text", in: "> # Alpha\n> - beta", find: "#", []),
        .init("fenced code", in: "```swift\nlet alpha = 1\n```", find: "alpha", ["alpha"]),
        .init("fence and its language are not text", in: "```swift\nlet alpha = 1\n```", find: "swift", []),
        .init("indented code", in: "text\n\n    let alpha = 1\n    let beta = 2", find: "let beta", ["let beta"]),
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
