//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//
//  One small fragment per markdown feature, each checked for the thing find and
//  selection depend on: that the app's idea of a block's visible text is the
//  text the rendered block actually has, and that an offset in one can be
//  turned into an offset in the other and back.
//
//  `MarkdownFeature.visible` is written out by hand for each fragment. It is
//  NOT derived from what either side currently produces, so a failure here
//  means the source mapping is wrong, and a failure of the same fragment in
//  `WebKitTextNodeAlignmentTests` means the rendered side is. Do not weaken,
//  skip, or disable a case to make the run green.
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

/// A fragment of markdown that renders as a single block.
struct MarkdownFeature: Sendable, CustomTestStringConvertible {
    let name: String
    let source: String
    /// The block's text as the reader sees it in the preview, which renders a
    /// line ending inside a paragraph as a line break.
    let visible: String
    /// Words to carry from the source to the preview and back. Each appears
    /// once in `visible`, and its first appearance in `source` is the visible
    /// one.
    let words: [String]

    var testDescription: String { name }

    init(_ name: String, _ source: String, visible: String, words: [String] = []) {
        self.name = name
        self.source = source
        self.visible = visible
        self.words = words
    }

    func sourceRange(of word: String) -> MarkdownSelectionRange? {
        let range = (source as NSString).range(of: word)
        return range.location == NSNotFound ? nil : MarkdownSelectionRange(range)
    }

    func visibleRange(of word: String) -> MarkdownSelectionRange? {
        let range = (visible as NSString).range(of: word)
        return range.location == NSNotFound ? nil : MarkdownSelectionRange(range)
    }

    static let all: [MarkdownFeature] =
        headings + paragraphs + emphasis + codeSpans + linksAndImages + escapes
        + lists + blockQuotes + codeBlocks + tables + wholeDocumentConcerns

    static let headings: [MarkdownFeature] = [
        .init("ATX heading", "## Alpha beta", visible: "Alpha beta", words: ["Alpha", "beta"]),
        .init(
            "ATX heading with a closing sequence",
            "## Alpha beta ##",
            visible: "Alpha beta",
            words: ["Alpha", "beta"]
        ),
        .init(
            "ATX heading with inline markup",
            "# **Alpha** and `beta`",
            visible: "Alpha and beta",
            words: ["Alpha", "beta"]
        ),
        .init("setext heading", "Alpha beta\n==========", visible: "Alpha beta", words: ["Alpha", "beta"]),
        .init(
            "setext heading over two lines",
            "Alpha\nbeta\n-----",
            visible: "Alpha\nbeta",
            words: ["Alpha", "beta"]
        ),
    ]

    static let paragraphs: [MarkdownFeature] = [
        .init("paragraph", "Alpha beta gamma", visible: "Alpha beta gamma", words: ["Alpha", "gamma"]),
        .init("soft line break", "Alpha\nbeta", visible: "Alpha\nbeta", words: ["Alpha", "beta"]),
        .init("hard break from two spaces", "Alpha  \nbeta", visible: "Alpha\nbeta", words: ["Alpha", "beta"]),
        .init("hard break from a backslash", "Alpha\\\nbeta", visible: "Alpha\nbeta", words: ["Alpha", "beta"]),
        .init("indented continuation line", "Alpha\n   beta", visible: "Alpha\nbeta", words: ["Alpha", "beta"]),
        .init(
            "line break before bold text",
            "**Name:** Alpha\n**Place:** beta",
            visible: "Name: Alpha\nPlace: beta",
            words: ["Name", "Alpha", "Place", "beta"]
        ),
        .init("thematic break", "---", visible: ""),
    ]

    static let emphasis: [MarkdownFeature] = [
        .init(
            "emphasis and strong inside a sentence",
            "one *Alpha* two **beta** three _gamma_ four __delta__ five",
            visible: "one Alpha two beta three gamma four delta five",
            words: ["Alpha", "beta", "gamma", "delta", "five"]
        ),
        .init(
            "emphasised words with only a space between them",
            "*Alpha* **beta**",
            visible: "Alpha beta",
            words: ["Alpha", "beta"]
        ),
        .init(
            "strong nested in emphasis",
            "*Alpha **beta** gamma*",
            visible: "Alpha beta gamma",
            words: ["Alpha", "beta", "gamma"]
        ),
        .init("triple delimiter", "***Alpha*** beta", visible: "Alpha beta", words: ["Alpha", "beta"]),
        .init(
            "underscores inside a word",
            "use snake_case_name here",
            visible: "use snake_case_name here",
            words: ["snake_case_name", "here"]
        ),
        .init(
            "asterisks with spaces around them",
            "2 * 3 * 4 is Alpha",
            visible: "2 * 3 * 4 is Alpha",
            words: ["3", "Alpha"]
        ),
        .init("unmatched delimiter", "*Alpha beta", visible: "*Alpha beta", words: ["Alpha", "beta"]),
    ]

    static let codeSpans: [MarkdownFeature] = [
        .init("code span", "Use `let alpha` here", visible: "Use let alpha here", words: ["alpha", "here"]),
        .init(
            "code span holding markup characters",
            "Type `*Alpha*` here",
            visible: "Type *Alpha* here",
            words: ["Alpha", "here"]
        ),
        .init(
            "code span over a line ending",
            "Use `let alpha\nbeta` here",
            visible: "Use let alpha beta here",
            words: ["alpha", "beta", "here"]
        ),
        .init(
            "double-backtick code span",
            "Type `` a`b `` here",
            visible: "Type a`b here",
            words: ["a`b", "here"]
        ),
    ]

    static let linksAndImages: [MarkdownFeature] = [
        .init(
            "link",
            "See [Alpha](https://example.com/x) now",
            visible: "See Alpha now",
            words: ["Alpha", "now"]
        ),
        .init(
            "link with a title",
            "See [Alpha](/url \"Title\") now",
            visible: "See Alpha now",
            words: ["Alpha", "now"]
        ),
        .init(
            "link text with markup",
            "[*Alpha* `beta`](/url) gamma",
            visible: "Alpha beta gamma",
            words: ["Alpha", "beta", "gamma"]
        ),
        .init("unclosed link", "[Alpha](/url", visible: "[Alpha](/url", words: ["Alpha"]),
        .init(
            "autolink",
            "See <https://example.com/alpha_beta> now",
            visible: "See https://example.com/alpha_beta now",
            words: ["https://example.com/alpha_beta", "now"]
        ),
        .init(
            "email autolink",
            "Mail <syd@example.com> today",
            visible: "Mail syd@example.com today",
            words: ["syd@example.com", "today"]
        ),
        .init(
            "link with parentheses in its destination",
            "See [Alpha](/wiki/Alpha_(letter)) now",
            visible: "See Alpha now",
            words: ["Alpha", "now"]
        ),
        .init(
            "link text with brackets in it",
            "[Alpha [beta]](/url) gamma",
            visible: "Alpha [beta] gamma",
            words: ["Alpha", "beta", "gamma"]
        ),
        .init(
            "image inside a link",
            "[![Alt](pic.png)](/url) after",
            visible: " after",
            words: ["after"]
        ),
        .init(
            "image",
            "before ![Alt](pic.png) after",
            visible: "before  after",
            words: ["before", "after"]
        ),
    ]

    static let escapes: [MarkdownFeature] = [
        .init(
            "backslash escapes",
            "\\*Alpha\\* and \\_beta\\_",
            visible: "*Alpha* and _beta_",
            words: ["Alpha", "beta"]
        ),
        .init(
            "entities",
            "Alpha &amp; beta &copy; gamma",
            visible: "Alpha & beta © gamma",
            words: ["Alpha", "beta", "gamma"]
        ),
        .init(
            "characters HTML has to escape",
            "Alpha < beta & gamma > \"delta\"",
            visible: "Alpha < beta & gamma > \"delta\"",
            words: ["Alpha", "beta", "gamma", "delta"]
        ),
        .init(
            "raw HTML, which is shown as text",
            "Alpha <b>beta</b> gamma",
            visible: "Alpha <b>beta</b> gamma",
            words: ["Alpha", "beta", "gamma"]
        ),
    ]

    // Nothing separates one item's text from the next: they are separate
    // elements, and the renderer writes no characters between them.
    static let lists: [MarkdownFeature] = [
        .init(
            "bulleted list",
            "- Alpha\n- Beta\n- Gamma",
            visible: "AlphaBetaGamma",
            words: ["Alpha", "Beta", "Gamma"]
        ),
        .init("bulleted list with asterisks", "* Alpha\n* Beta", visible: "AlphaBeta", words: ["Alpha", "Beta"]),
        .init("numbered list", "1. Alpha\n2. Beta", visible: "AlphaBeta", words: ["Alpha", "Beta"]),
        .init(
            "numbered list with parentheses",
            "1) Alpha\n2) Beta",
            visible: "AlphaBeta",
            words: ["Alpha", "Beta"]
        ),
        .init(
            "nested and mixed list",
            "- Alpha\n  - Beta\n    1. Gamma\n- Delta",
            visible: "AlphaBetaGammaDelta",
            words: ["Alpha", "Beta", "Gamma", "Delta"]
        ),
        .init("loose list", "- Alpha\n\n- Beta", visible: "AlphaBeta", words: ["Alpha", "Beta"]),
        .init("task list", "- [x] Alpha\n- [ ] Beta", visible: "AlphaBeta", words: ["Alpha", "Beta"]),
        .init(
            "list items with inline markup",
            "- **Alpha** and `beta`\n- [Gamma](/url)",
            visible: "Alpha and betaGamma",
            words: ["Alpha", "beta", "Gamma"]
        ),
        .init("list with an empty item", "- Alpha\n-\n- Beta", visible: "AlphaBeta", words: ["Alpha", "Beta"]),
        .init("list with a tab after the marker", "-\tAlpha\n-\tBeta", visible: "AlphaBeta", words: ["Alpha", "Beta"]),
        .init(
            "nested lists with different markers",
            "- Alpha\n  - Beta\n  + Gamma\n- Delta",
            visible: "AlphaBetaGammaDelta",
            words: ["Alpha", "Beta", "Gamma", "Delta"]
        ),
        .init(
            "list with extra space after the marker",
            "-   Alpha\n-   Beta",
            visible: "AlphaBeta",
            words: ["Alpha", "Beta"]
        ),
    ]

    static let blockQuotes: [MarkdownFeature] = [
        .init("block quote", "> Alpha\n> beta", visible: "Alpha\nbeta", words: ["Alpha", "beta"]),
        .init("block quote with no space after the marker", ">Alpha beta", visible: "Alpha beta", words: ["Alpha", "beta"]),
        .init(
            "block quote with inline markup",
            "> **Alpha** and `beta`",
            visible: "Alpha and beta",
            words: ["Alpha", "beta"]
        ),
        .init(
            "block quote with two paragraphs",
            "> Alpha\n>\n> Beta",
            visible: "AlphaBeta",
            words: ["Alpha", "Beta"]
        ),
        .init("nested block quote", "> > Alpha beta", visible: "Alpha beta", words: ["Alpha", "beta"]),
        .init(
            "block quote holding a heading",
            "> # Alpha\n> beta",
            visible: "Alphabeta",
            words: ["Alpha", "beta"]
        ),
        .init(
            "block quote holding a list",
            "> - Alpha\n> - Beta",
            visible: "AlphaBeta",
            words: ["Alpha", "Beta"]
        ),
        .init(
            "block quote holding fenced code",
            "> ```\n> let alpha = 1\n> ```",
            visible: "let alpha = 1",
            words: ["alpha"]
        ),
    ]

    static let codeBlocks: [MarkdownFeature] = [
        .init(
            "fenced code",
            "```swift\nlet alpha = 1\n  let beta = 2\n```",
            visible: "let alpha = 1\n  let beta = 2",
            words: ["alpha", "beta"]
        ),
        .init(
            "fenced code indented with its fence",
            "  ```\n  let alpha = 1\n    let beta = 2\n  ```",
            visible: "let alpha = 1\n  let beta = 2",
            words: ["alpha", "beta"]
        ),
        .init("tilde-fenced code", "~~~\nlet alpha = 1\n~~~", visible: "let alpha = 1", words: ["alpha"]),
        .init(
            "fenced code with a blank line",
            "```\nalpha\n\nbeta\n```",
            visible: "alpha\n\nbeta",
            words: ["alpha", "beta"]
        ),
        .init(
            "fenced code holding markdown and HTML characters",
            "```\n*alpha* <b> & `beta`\n```",
            visible: "*alpha* <b> & `beta`",
            words: ["alpha", "beta"]
        ),
        .init(
            "fenced code with no closing fence",
            "```\nlet alpha = 1\nlet beta = 2",
            visible: "let alpha = 1\nlet beta = 2",
            words: ["alpha", "beta"]
        ),
    ]

    // Cells run together for the same reason list items do.
    static let tables: [MarkdownFeature] = [
        .init(
            "table",
            "| Name | Count |\n| --- | ---: |\n| apples | 12 |",
            visible: "NameCountapples12",
            words: ["Name", "Count", "apples", "12"]
        ),
        .init(
            "table without pipes at the edges",
            "Name | Count\n--- | ---\napples | 12",
            visible: "NameCountapples12",
            words: ["Name", "Count", "apples", "12"]
        ),
        .init(
            "table cells with inline markup",
            "| **Alpha** | `beta` |\n| --- | --- |\n| [gamma](/url) | *delta* |",
            visible: "Alphabetagammadelta",
            words: ["Alpha", "beta", "gamma", "delta"]
        ),
        .init(
            "table with an empty cell",
            "| Alpha | Beta |\n| --- | --- |\n|  | gamma |",
            visible: "AlphaBetagamma",
            words: ["Alpha", "Beta", "gamma"]
        ),
        .init(
            "table cells with other backslash escapes",
            "| \\*Alpha\\* | `C:\\beta` |\n| --- | --- |\n| 1 | 2 |",
            visible: "*Alpha*C:\\beta12",
            words: ["Alpha", "beta"]
        ),
        .init(
            "table with an escaped pipe in a cell",
            "| Alpha \\| beta | gamma |\n| --- | --- |\n| 1 | 2 |",
            visible: "Alpha | betagamma12",
            words: ["Alpha", "beta", "gamma"]
        ),
    ]

    static let wholeDocumentConcerns: [MarkdownFeature] = [
        // Offsets are UTF-16, as the text views count them: the emoji are two
        // and four units each.
        .init(
            "text outside ASCII",
            "Héllo 😀 *wörld* 👍🏽 done",
            visible: "Héllo 😀 wörld 👍🏽 done",
            words: ["Héllo", "wörld", "done"]
        ),
        .init("Windows line endings", "Alpha\r\nbeta", visible: "Alpha\nbeta", words: ["Alpha", "beta"]),
    ]
}

struct MarkdownFeatureOffsetMappingTests {

    /// Every fragment is meant to be one block, covering the whole of its
    /// source. If the parser disagrees, the offsets below are measured against
    /// the wrong thing, so say so before anything else does.
    @Test(arguments: MarkdownFeature.all)
    func fragmentIsOneBlockSpanningItsSource(feature: MarkdownFeature) throws {
        let blocks = MarkdownBlockParser.parse(feature.source)
        try #require(blocks.count == 1, "parsed into \(blocks.count) blocks")

        let range = MarkdownSourceLineTable(source: feature.source).range(for: blocks[0].lineRange)
        #expect(range == MarkdownSelectionRange(location: 0, length: feature.source.utf16.count))
    }

    // MARK: - Source to display text, and back

    @Test(arguments: MarkdownFeature.all)
    func sourceMappingShowsWhatTheRenderedBlockShows(feature: MarkdownFeature) {
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: feature.source)

        #expect(mapping.displayText == feature.visible)
    }

    @Test(arguments: MarkdownFeature.all.filter { !$0.words.isEmpty })
    func wordsRoundTripBetweenSourceAndDisplayText(feature: MarkdownFeature) throws {
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: feature.source)

        for word in feature.words {
            let inSource = try #require(feature.sourceRange(of: word), "\(word) is not in the source")
            let inVisible = try #require(feature.visibleRange(of: word), "\(word) is not in the visible text")

            // Source to display, and back to where it started.
            let displayed = mapping.displayRange(forSourceRange: inSource)
            #expect(displayed == inVisible, "source to display, for \(word)")
            if let displayed {
                #expect(mapping.sourceRange(forDisplayRange: displayed) == inSource, "and back, for \(word)")
            }

            // Display to source, and back to where it started.
            let sourced = mapping.sourceRange(forDisplayRange: inVisible)
            #expect(sourced == inSource, "display to source, for \(word)")
            if let sourced {
                #expect(mapping.displayRange(forSourceRange: sourced) == inVisible, "and back, for \(word)")
            }
        }
    }

    // MARK: - Source to the rendered block, and back, as the app does it

    /// The two calls the preview makes: `PreviewSelectionReflection` to place a
    /// source selection in a rendered block, and `PreviewSelectionBridge` to
    /// turn what the page reports back into a source selection. The page's own
    /// half of each trip is exercised in `WebKitTextNodeAlignmentTests`.
    @Test(arguments: MarkdownFeature.all.filter { !$0.words.isEmpty })
    func wordsRoundTripBetweenSourceAndTheRenderedBlock(feature: MarkdownFeature) throws {
        let blockEnd = feature.source.utf16.count

        for word in feature.words {
            let inSource = try #require(feature.sourceRange(of: word), "\(word) is not in the source")
            let inVisible = try #require(feature.visibleRange(of: word), "\(word) is not in the visible text")

            let reflected = PreviewSelectionReflection.reflectedSelection(
                in: feature.source,
                selectedRange: inSource
            )
            #expect(
                reflected == PreviewReflectedSelection(
                    start: .init(blockStart: 0, blockEnd: blockEnd, displayOffset: inVisible.location),
                    end: .init(
                        blockStart: 0,
                        blockEnd: blockEnd,
                        displayOffset: inVisible.location + inVisible.length
                    )
                ),
                "source to rendered block, for \(word)"
            )

            let reported: [[String: Any]] = [[
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: blockEnd),
                "displayLocation": NSNumber(value: inVisible.location),
                "displayLength": NSNumber(value: inVisible.length),
            ]]
            #expect(
                PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: reported, source: feature.source)
                    == [inSource],
                "rendered block to source, for \(word)"
            )
        }
    }

    // MARK: - Blocks after the first

    /// Everything above is measured in a block that starts at offset zero.
    /// Here the same fragments sit one after another in a single document, so
    /// each block's offsets have to be found relative to its own start, with
    /// text outside ASCII ahead of it.
    @Test func wordsRoundTripInBlocksFurtherDownADocument() throws {
        let fragments = [
            "# Héllo 😀 title",
            "First *Alpha* paragraph\nwith a second line",
            "- one\n- **Beta** two",
            "> quoted `Gamma` text",
            "| Name | Count |\n| --- | --- |\n| Delta | 12 |",
            "```\nlet epsilon = 1\n```",
            "Last [Zeta](/url) paragraph",
        ]
        let source = fragments.joined(separator: "\n\n")
        let nsSource = source as NSString

        for (fragment, word) in zip(fragments, ["title", "Alpha", "Beta", "Gamma", "Delta", "epsilon", "Zeta"]) {
            let blockRange = nsSource.range(of: fragment)
            let inSource = MarkdownSelectionRange(nsSource.range(of: word))
            let blockText = MarkdownPreviewTextOffsetMapping(sourceText: fragment).displayText as NSString
            let inBlock = blockText.range(of: word)
            try #require(inBlock.location != NSNotFound, "\(word) is not in its block's display text")

            let reflected = try #require(
                PreviewSelectionReflection.reflectedSelection(in: source, selectedRange: inSource),
                "no reflection for \(word)"
            )
            #expect(reflected.start.blockStart == blockRange.location, "block start, for \(word)")
            #expect(reflected.start.blockEnd == blockRange.location + blockRange.length, "block end, for \(word)")
            #expect(reflected.end.blockStart == reflected.start.blockStart)
            #expect(reflected.start.displayOffset == inBlock.location, "display start, for \(word)")
            #expect(reflected.end.displayOffset == inBlock.location + inBlock.length, "display end, for \(word)")

            let reported: [[String: Any]] = [[
                "blockStart": NSNumber(value: reflected.start.blockStart),
                "blockEnd": NSNumber(value: reflected.start.blockEnd),
                "displayLocation": NSNumber(value: reflected.start.displayOffset),
                "displayLength": NSNumber(value: reflected.end.displayOffset - reflected.start.displayOffset),
            ]]
            #expect(
                PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: reported, source: source) == [inSource],
                "and back to the source, for \(word)"
            )
        }
    }
}
