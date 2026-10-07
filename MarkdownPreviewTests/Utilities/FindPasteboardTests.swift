//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Testing

/// The find buffer held in memory: the one iOS and iPadOS search through,
/// having no system-wide one, and the one a test gives a view model so that it
/// neither reads nor writes the machine's.
@MainActor
struct InMemoryFindPasteboardTests {

    @Test func holdsNothingUntilATermIsWritten() {
        #expect(InMemoryFindPasteboard().currentQuery() == nil)
    }

    @Test func holdsTheLastTermWritten() {
        let findPasteboard = InMemoryFindPasteboard()

        findPasteboard.setQuery("alpha")
        findPasteboard.setQuery("beta")

        #expect(findPasteboard.currentQuery() == "beta")
    }

    /// Every write counts, the same term written twice included: that is how
    /// a view model tells that somebody has written since it last looked.
    @Test func everyWriteMovesTheChangeCount() {
        let findPasteboard = InMemoryFindPasteboard()
        let atFirst = findPasteboard.changeCount()

        findPasteboard.setQuery("alpha")
        let afterOneWrite = findPasteboard.changeCount()
        findPasteboard.setQuery("alpha")

        #expect(afterOneWrite != atFirst)
        #expect(findPasteboard.changeCount() != afterOneWrite)
    }

    @Test func readingDoesNotMoveTheChangeCount() {
        let findPasteboard = InMemoryFindPasteboard()
        findPasteboard.setQuery("alpha")
        let afterTheWrite = findPasteboard.changeCount()

        _ = findPasteboard.currentQuery()

        #expect(findPasteboard.changeCount() == afterTheWrite)
    }

    /// What keeps one test's term out of another's.
    @Test func twoOfThemShareNothing() {
        let one = InMemoryFindPasteboard()
        let other = InMemoryFindPasteboard()

        one.setQuery("alpha")

        #expect(other.currentQuery() == nil)
    }
}
