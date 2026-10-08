//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownCore

/// Every source offset in the app starts here: a block is a range of lines, and
/// this table turns that into a range of the source. A line ends at a newline,
/// a carriage return, or the two together (CommonMark 2.1), and the parser has
/// to split the source at exactly the same places or the two disagree about
/// which line is which.
struct MarkdownSourceLineTableTests {

    /// The text the table says each line holds.
    private func lines(of source: String) -> [String] {
        let table = MarkdownSourceLineTable(source: source)
        let nsSource = source as NSString
        return table.lineStartOffsets.indices.map { line in
            table.range(forLine: line).map { nsSource.substring(with: $0.nsRange) } ?? "<no range>"
        }
    }

    @Test func aLineIsItsTextWithoutTheLineEnding() {
        #expect(lines(of: "one\ntwo\nthree") == ["one", "two", "three"])
    }

    @Test func aTrailingLineEndingLeavesAnEmptyLastLine() {
        #expect(lines(of: "one\n") == ["one", ""])
    }

    @Test func anEmptySourceIsOneEmptyLine() {
        #expect(lines(of: "") == [""])
    }

    @Test func blankLinesAreLines() {
        #expect(lines(of: "one\n\n\ntwo") == ["one", "", "", "two"])
    }

    @Test func aWindowsLineEndingIsOneLineEndingAndNotPartOfTheLine() {
        #expect(lines(of: "one\r\ntwo\r\n\r\nthree\r\n") == ["one", "two", "", "three", ""])
    }

    @Test func aCarriageReturnAloneEndsALine() {
        #expect(lines(of: "one\rtwo\r\rthree") == ["one", "two", "", "three"])
    }

    @Test func lineEndingsMayBeMixed() {
        #expect(lines(of: "one\r\ntwo\nthree\rfour") == ["one", "two", "three", "four"])
    }

    @Test func aRangeOfSeveralLinesKeepsTheLineEndingsBetweenThem() throws {
        let source = "one\r\ntwo\nthree\r\nfour"
        let range = try #require(MarkdownSourceLineTable(source: source).range(for: 1..<3))

        #expect((source as NSString).substring(with: range.nsRange) == "two\nthree")
    }

    @Test func offsetsAreCountedInUTF16() {
        // The emoji is two units, so the second line starts at three.
        let table = MarkdownSourceLineTable(source: "😀\nwörld")

        #expect(table.range(forLine: 0) == MarkdownSelectionRange(location: 0, length: 2))
        #expect(table.range(forLine: 1) == MarkdownSelectionRange(location: 3, length: 5))
    }

    @Test func linesOutsideTheSourceHaveNoRange() {
        let table = MarkdownSourceLineTable(source: "one\ntwo")

        #expect(table.range(forLine: 2) == nil)
        #expect(table.range(for: 1..<3) == nil)
        #expect(table.range(for: 1..<1) == nil)
        #expect(table.range(for: -1..<1) == nil)
    }

    /// The parser splits the source with `markdownLines`. Line for line, that
    /// has to be what this table holds.
    @Test(arguments: [
        "",
        "one",
        "one\n",
        "one\ntwo\n\nthree",
        "one\r\ntwo\r\n\r\nthree\r\n",
        "one\rtwo\r\rthree",
        "one\r\ntwo\nthree\rfour\n\r\n\r",
        "😀\r\nwörld 👍🏽\nlast",
        "\r\n",
        "\n\r",
        // A combining mark after a line ending starts the next line. It does
        // not join the line ending to make something that is not one.
        "a\n\u{0301}b\r\n\u{0301}c\r\u{0301}d",
    ])
    func theParsersLinesAreTheTablesLines(source: String) {
        #expect(source.markdownLines == lines(of: source))
    }
}
