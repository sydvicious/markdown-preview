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

    /// - Parameter current: what the view has selected now. No selection in
    ///   the model is not a place: the caret is left where the view has it,
    ///   which is where the reader clicked. Sent to the start of the text
    ///   instead, a click that left nothing selected took the reader to the
    ///   top of the document.
    static func resolve(
        from ranges: [MarkdownSelectionRange],
        current: NSRange = NSRange(location: 0, length: 0),
        textUTF16Length: Int
    ) -> SourceSelectionUpdate {
        guard let next = ranges.first?.clamped(toUTF16Length: textUTF16Length)?.nsRange else {
            return .clear(caret(whereSelectionStarts: current, textUTF16Length: textUTF16Length))
        }
        return next.length > 0 ? .select(next) : .clear(next)
    }

    /// What a text view that can hold several ranges should have selected, and
    /// whether its text should be scrolled to show the first of them.
    struct Ranges: Equatable {
        var ranges: [NSRange]
        var bringsFirstIntoView: Bool
    }

    /// The Mac's text view holds every range of the selection. As in
    /// `resolve`, no selection leaves the caret where the view has it, and the
    /// text where it is.
    static func resolveAll(
        from ranges: [MarkdownSelectionRange],
        current: [NSRange],
        textUTF16Length: Int
    ) -> Ranges {
        let selected = ranges.compactMap { $0.clamped(toUTF16Length: textUTF16Length)?.nsRange }
        guard selected.isEmpty else {
            return Ranges(ranges: selected, bringsFirstIntoView: true)
        }

        let caret = caret(
            whereSelectionStarts: current.first ?? NSRange(location: 0, length: 0),
            textUTF16Length: textUTF16Length
        )
        return Ranges(ranges: [caret], bringsFirstIntoView: false)
    }

    private static func caret(whereSelectionStarts selection: NSRange, textUTF16Length: Int) -> NSRange {
        NSRange(location: min(max(selection.location, 0), textUTF16Length), length: 0)
    }
}
