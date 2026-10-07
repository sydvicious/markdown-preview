//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Testing

/// The preview builds its HTML through one of these, so that a body that runs
/// again with nothing changed does not build the HTML again.
struct LastValueCacheTests {

    @Test func theFirstAskMakesTheValue() {
        let cache = LastValueCache<String, Int>()
        var timesMade = 0

        let value = cache.value(for: "plan") {
            timesMade += 1
            return 7
        }

        #expect(value == 7)
        #expect(timesMade == 1)
    }

    @Test func askingAgainForTheSameKeyDoesNotMakeItAgain() {
        let cache = LastValueCache<String, Int>()
        var timesMade = 0
        let make = {
            timesMade += 1
            return timesMade
        }

        let first = cache.value(for: "plan", make: make)
        let second = cache.value(for: "plan", make: make)
        let third = cache.value(for: "plan", make: make)

        #expect([first, second, third] == [1, 1, 1])
        #expect(timesMade == 1)
    }

    @Test func aKeyThatHasChangedMakesAnotherValue() {
        let cache = LastValueCache<String, Int>()
        var timesMade = 0
        let make = {
            timesMade += 1
            return timesMade
        }

        let first = cache.value(for: "plan", make: make)
        let second = cache.value(for: "plan, edited", make: make)

        #expect([first, second] == [1, 2])
        #expect(timesMade == 2)
    }

    /// One value, the last. Going back to an earlier key makes its value again.
    @Test func onlyTheLastValueIsKept() {
        let cache = LastValueCache<String, Int>()
        var timesMade = 0
        let make = {
            timesMade += 1
            return timesMade
        }

        _ = cache.value(for: "plan", make: make)
        _ = cache.value(for: "notes", make: make)
        let back = cache.value(for: "plan", make: make)

        #expect(back == 3)
        #expect(timesMade == 3)
    }
}
