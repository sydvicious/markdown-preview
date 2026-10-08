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

    // MARK: - No selection is not a place

    /// The reader clicks in the text and nothing is left selected. That is no
    /// selection, and it is not the start of the document: the caret stays
    /// where they clicked. Sent to the start, the click took them to the top.
    @Test func noSelectionLeavesTheCaretWhereTheViewHasIt() {
        #expect(
            SourceSelectionUpdate.resolve(from: [], current: NSRange(location: 12, length: 0), textUTF16Length: 20)
                == .clear(NSRange(location: 12, length: 0))
        )
    }

    /// Something was selected in the view and the selection has been cleared
    /// elsewhere. The caret goes to where the selection began.
    @Test func noSelectionCollapsesTheViewsSelectionWhereItStarts() {
        #expect(
            SourceSelectionUpdate.resolve(from: [], current: NSRange(location: 12, length: 5), textUTF16Length: 20)
                == .clear(NSRange(location: 12, length: 0))
        )
    }

    @Test func aFirstRangeThatIsNotInTheTextLeavesTheCaretWhereTheViewHasIt() {
        #expect(
            SourceSelectionUpdate.resolve(
                from: [MarkdownSelectionRange(location: 50, length: 5)],
                current: NSRange(location: 7, length: 0),
                textUTF16Length: 10
            ) == .clear(NSRange(location: 7, length: 0))
        )
    }

    /// The text got shorter under the caret.
    @Test func aCaretLeftPastTheEndOfTheTextGoesToItsEnd() {
        #expect(
            SourceSelectionUpdate.resolve(from: [], current: NSRange(location: 30, length: 0), textUTF16Length: 10)
                == .clear(NSRange(location: 10, length: 0))
        )
    }

    // MARK: - A view that can hold several ranges

    @Test func everyRangeOfTheSelectionIsSelectedAndTheFirstBroughtIntoView() {
        let update = SourceSelectionUpdate.resolveAll(
            from: [
                MarkdownSelectionRange(location: 2, length: 5),
                MarkdownSelectionRange(location: 12, length: 100)
            ],
            current: [NSRange(location: 9, length: 0)],
            textUTF16Length: 20
        )

        #expect(update.ranges == [NSRange(location: 2, length: 5), NSRange(location: 12, length: 8)])
        #expect(update.bringsFirstIntoView)
    }

    /// As above: no selection is no place to go to. The caret stays where the
    /// reader put it, and the text is not scrolled.
    @Test func noSelectionLeavesTheCaretAndTheTextWhereTheyAre() {
        let clicked = SourceSelectionUpdate.resolveAll(
            from: [],
            current: [NSRange(location: 400, length: 0)],
            textUTF16Length: 1000
        )
        let hadASelection = SourceSelectionUpdate.resolveAll(
            from: [],
            current: [NSRange(location: 400, length: 30), NSRange(location: 700, length: 5)],
            textUTF16Length: 1000
        )

        #expect(clicked == .init(ranges: [NSRange(location: 400, length: 0)], bringsFirstIntoView: false))
        #expect(hadASelection == .init(ranges: [NSRange(location: 400, length: 0)], bringsFirstIntoView: false))
    }

    @Test func rangesThatAreNotInTheTextAreNoSelection() {
        let update = SourceSelectionUpdate.resolveAll(
            from: [MarkdownSelectionRange(location: 5000, length: 5)],
            current: [NSRange(location: 400, length: 0)],
            textUTF16Length: 1000
        )

        #expect(update == .init(ranges: [NSRange(location: 400, length: 0)], bringsFirstIntoView: false))
    }

    @Test func noSelectionInAViewThatHasNoneIsACaretAtTheStart() {
        let update = SourceSelectionUpdate.resolveAll(from: [], current: [], textUTF16Length: 1000)

        #expect(update == .init(ranges: [NSRange(location: 0, length: 0)], bringsFirstIntoView: false))
    }

    /// An empty range inside the text selects nothing, but it is a place, and
    /// the text is brought to it.
    @Test func anEmptyRangeInsideTheTextIsAPlaceToGoTo() {
        let update = SourceSelectionUpdate.resolveAll(
            from: [MarkdownSelectionRange(location: 40, length: 0)],
            current: [NSRange(location: 400, length: 0)],
            textUTF16Length: 1000
        )

        #expect(update == .init(ranges: [NSRange(location: 40, length: 0)], bringsFirstIntoView: true))
    }
}
