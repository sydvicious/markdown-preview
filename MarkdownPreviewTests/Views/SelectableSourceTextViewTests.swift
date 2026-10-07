//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore

struct SelectableSourceTextViewTests {

    @Test func sourceSelectionResolvesNonEmptyRangeToRealSelection() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 2, length: 5)],
            textUTF16Length: 20
        )

        #expect(update == .select(NSRange(location: 2, length: 5)))
    }

    @Test func sourceSelectionResolvesEmptyInputToClear() async throws {
        let update = SourceSelectionUpdate.resolve(from: [], textUTF16Length: 20)

        #expect(update == .clear(NSRange(location: 0, length: 0)))
    }

    @Test func sourceSelectionClampsRangeToTextLength() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 8, length: 100)],
            textUTF16Length: 10
        )

        #expect(update == .select(NSRange(location: 8, length: 2)))
    }

    @Test func sourceSelectionClearsWhenLocationIsBeyondText() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 50, length: 5)],
            textUTF16Length: 10
        )

        #expect(update == .clear(NSRange(location: 0, length: 0)))
    }

    @Test func sourceSelectionClearsWhenClampedLengthCollapsesToZero() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 10, length: 5)],
            textUTF16Length: 10
        )

        #expect(update == .clear(NSRange(location: 10, length: 0)))
    }

    @Test func sourceSelectionCoveringTheWholeTextIsSelectedWhole() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 0, length: 10)],
            textUTF16Length: 10
        )

        #expect(update == .select(NSRange(location: 0, length: 10)))
    }

    /// The source view shows one selection, so only the first range is read.
    @Test func sourceSelectionUsesOnlyTheFirstRange() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [
                MarkdownSelectionRange(location: 2, length: 5),
                MarkdownSelectionRange(location: 12, length: 3)
            ],
            textUTF16Length: 20
        )

        #expect(update == .select(NSRange(location: 2, length: 5)))
    }

    /// A first range that is not in the text is no selection. The ranges after
    /// it are not tried in its place.
    @Test func sourceSelectionDoesNotFallBackToALaterRange() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [
                MarkdownSelectionRange(location: 50, length: 5),
                MarkdownSelectionRange(location: 2, length: 5)
            ],
            textUTF16Length: 10
        )

        #expect(update == .clear(NSRange(location: 0, length: 0)))
    }

    /// An empty range inside the text selects nothing, but it is a place: the
    /// caret goes there, without the view taking the focus.
    @Test func sourceSelectionPutsTheCaretAtAnEmptyRangeInsideTheText() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 4, length: 0)],
            textUTF16Length: 10
        )

        #expect(update == .clear(NSRange(location: 4, length: 0)))
    }

    @Test func sourceSelectionInEmptyTextIsAlwaysClear() async throws {
        let none = SourceSelectionUpdate.resolve(from: [], textUTF16Length: 0)
        let some = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 0, length: 5)],
            textUTF16Length: 0
        )

        #expect(none == .clear(NSRange(location: 0, length: 0)))
        #expect(some == .clear(NSRange(location: 0, length: 0)))
    }
}
