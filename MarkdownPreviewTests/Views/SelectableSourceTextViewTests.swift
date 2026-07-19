//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

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
}
