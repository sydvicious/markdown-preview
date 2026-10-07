//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import MarkdownCore

/// The selection update the iOS source text view should apply for a given model
/// selection. Factored out of `applySelection` so the empty-vs-non-empty
/// decision — which drives whether the text view must claim first responder — is
/// unit-testable without standing up UIKit.
enum SourceSelectionUpdate: Equatable {
    /// A real, copyable selection. The text view must be first responder for iOS
    /// to render it and for Cmd-C / the edit menu to reach it.
    case select(NSRange)
    /// No selection; collapse the caret without claiming focus.
    case clear(NSRange)

    static func resolve(from ranges: [MarkdownSelectionRange], textUTF16Length: Int) -> SourceSelectionUpdate {
        let next = ranges.first?.clamped(toUTF16Length: textUTF16Length)?.nsRange
            ?? NSRange(location: 0, length: 0)
        return next.length > 0 ? .select(next) : .clear(next)
    }
}
