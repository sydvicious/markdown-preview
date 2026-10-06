//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownCore

struct MarkdownSelectionRangeTests {

    @Test func keepsTheLocationAndLengthItIsGiven() async throws {
        let range = MarkdownSelectionRange(location: 4, length: 8)

        #expect(range.location == 4)
        #expect(range.length == 8)
    }

    // A range that starts before the text or runs backwards means nothing, and
    // an `NSRange` built from one traps further on.
    @Test func aNegativeLocationOrLengthBecomesZero() async throws {
        #expect(MarkdownSelectionRange(location: -3, length: 5) == MarkdownSelectionRange(location: 0, length: 5))
        #expect(MarkdownSelectionRange(location: 3, length: -5) == MarkdownSelectionRange(location: 3, length: 0))
        #expect(MarkdownSelectionRange(location: -3, length: -5) == MarkdownSelectionRange(location: 0, length: 0))
    }

    @Test func roundTripsThroughNSRange() async throws {
        let nsRange = NSRange(location: 12, length: 7)

        #expect(MarkdownSelectionRange(nsRange) == MarkdownSelectionRange(location: 12, length: 7))
        #expect(MarkdownSelectionRange(nsRange).nsRange == nsRange)
    }

    // What AppKit and UIKit hand back for "nothing found". It is a location past
    // any text there could be, so it must not survive as a selection.
    @Test func aNotFoundNSRangeSelectsNothingInAnyText() async throws {
        let range = MarkdownSelectionRange(NSRange(location: NSNotFound, length: 0))

        #expect(range.range(in: "some text") == nil)
        #expect(range.clamped(toUTF16Length: 9) == nil)
    }

    @Test func roundTripsThroughJSON() async throws {
        let ranges = [
            MarkdownSelectionRange(location: 0, length: 0),
            MarkdownSelectionRange(location: 12, length: 7),
        ]

        let data = try JSONEncoder().encode(ranges)

        #expect(try JSONDecoder().decode([MarkdownSelectionRange].self, from: data) == ranges)
    }

    @Test func equalRangesHashAlike() async throws {
        let ranges: Set = [
            MarkdownSelectionRange(location: 1, length: 2),
            MarkdownSelectionRange(location: 1, length: 2),
            MarkdownSelectionRange(location: 1, length: 3),
        ]

        #expect(ranges.count == 2)
    }

    // MARK: - range(in:)

    @Test func findsTheTextItCovers() async throws {
        let text = "alpha beta gamma"
        let range = try #require(MarkdownSelectionRange(location: 6, length: 4).range(in: text))

        #expect(text[range] == "beta")
    }

    // Offsets count UTF-16 code units, which is what the text views and the web
    // view report. An emoji is two of them and an accented letter may be one or
    // two, so counting characters would land in the wrong place after either.
    @Test func offsetsCountUTF16CodeUnitsNotCharacters() async throws {
        let text = "a😀 cafe\u{301} z"

        let emoji = try #require(MarkdownSelectionRange(location: 1, length: 2).range(in: text))
        let word = try #require(MarkdownSelectionRange(location: 4, length: 5).range(in: text))
        let last = try #require(MarkdownSelectionRange(location: 10, length: 1).range(in: text))

        #expect(text[emoji] == "😀")
        #expect(text[word] == "cafe\u{301}")
        #expect(text[last] == "z")
    }

    @Test func anEmptyRangeAtTheEndOfTheTextIsStillInIt() async throws {
        let text = "alpha"
        let range = try #require(MarkdownSelectionRange(location: 5, length: 0).range(in: text))

        #expect(range == text.endIndex..<text.endIndex)
    }

    @Test func aRangeReachingPastTheEndOfTheTextIsNotInIt() async throws {
        #expect(MarkdownSelectionRange(location: 3, length: 5).range(in: "alpha") == nil)
        #expect(MarkdownSelectionRange(location: 6, length: 0).range(in: "alpha") == nil)
        #expect(MarkdownSelectionRange(location: 0, length: 1).range(in: "") == nil)
    }

    // An emoji is two code units, so an offset can fall between them. Such a
    // range is not refused: an offset inside a character counts as the start of
    // that character, at either end of the range. Nothing in the app is known
    // to make one, and this says what happens if something does, so that a
    // change to it is noticed.
    @Test func anOffsetInsideACharacterCountsAsTheStartOfThatCharacter() async throws {
        let text = "a😀b"

        let startingInsideTheEmoji = try #require(MarkdownSelectionRange(location: 2, length: 1).range(in: text))
        let endingInsideTheEmoji = try #require(MarkdownSelectionRange(location: 0, length: 2).range(in: text))

        #expect(text[startingInsideTheEmoji] == "😀")
        #expect(text[endingInsideTheEmoji] == "a")
    }

    // MARK: - clamped(toUTF16Length:)

    @Test func aRangeInsideTheTextIsLeftAlone() async throws {
        let range = MarkdownSelectionRange(location: 2, length: 3)

        #expect(range.clamped(toUTF16Length: 10) == range)
        #expect(range.clamped(toUTF16Length: 5) == range)
    }

    // The text got shorter under a selection: a file reloaded from disk, say.
    @Test func aRangeRunningPastTheEndIsCutShort() async throws {
        let range = MarkdownSelectionRange(location: 2, length: 30)

        #expect(range.clamped(toUTF16Length: 10) == MarkdownSelectionRange(location: 2, length: 8))
    }

    @Test func aRangeStartingAtTheEndBecomesAnInsertionPointThere() async throws {
        let range = MarkdownSelectionRange(location: 10, length: 4)

        #expect(range.clamped(toUTF16Length: 10) == MarkdownSelectionRange(location: 10, length: 0))
    }

    @Test func aRangeStartingPastTheEndIsDropped() async throws {
        #expect(MarkdownSelectionRange(location: 11, length: 4).clamped(toUTF16Length: 10) == nil)
        #expect(MarkdownSelectionRange(location: 11, length: 0).clamped(toUTF16Length: 10) == nil)
    }

    @Test func emptyTextKeepsOnlyAnInsertionPointAtItsStart() async throws {
        #expect(MarkdownSelectionRange(location: 0, length: 4).clamped(toUTF16Length: 0)
            == MarkdownSelectionRange(location: 0, length: 0))
        #expect(MarkdownSelectionRange(location: 1, length: 0).clamped(toUTF16Length: 0) == nil)
    }

    @Test func aNegativeTextLengthDropsTheRange() async throws {
        #expect(MarkdownSelectionRange(location: 0, length: 0).clamped(toUTF16Length: -1) == nil)
    }

    // What comes out of clamping must itself be usable on text of that length.
    @Test func aClampedRangeIsAlwaysInTheText() async throws {
        let text = "a😀 cafe\u{301} z"
        let length = text.utf16.count

        for location in 0...(length + 2) {
            for rangeLength in [0, 1, 4, length, length * 2] {
                let range = MarkdownSelectionRange(location: location, length: rangeLength)
                guard let clamped = range.clamped(toUTF16Length: length) else {
                    #expect(location > length, "dropped \(range) from text of length \(length)")
                    continue
                }

                #expect(clamped.location == location)
                #expect(clamped.location + clamped.length <= length, "\(range) clamped to \(clamped)")
                #expect(clamped.range(in: text) != nil, "\(clamped) is not in the text")
            }
        }
    }
}
