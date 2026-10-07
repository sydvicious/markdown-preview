//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import MarkdownCore

/// The document's visible text as a search sees it: list items and the blocks
/// inside a quote on lines of their own, and image descriptions included.
final class MarkdownTextOffsetMapping: TextOffsetMapping {
    let sourceText: String
    let displayText: String
    let runs: [TextOffsetRun]

    init(sourceText: String) {
        self.sourceText = sourceText

        let visible = MarkdownVisibleText(source: sourceText)
        displayText = visible.text
        runs = visible.runs.map(TextOffsetRun.init)
    }
}

/// Nothing in it changes once it is made, so one read on another thread can be
/// handed to the main actor.
extension MarkdownTextOffsetMapping: @unchecked Sendable {}

extension TextOffsetRun {
    init(_ run: MarkdownVisibleText.Run) {
        self.init(sourceRange: run.sourceRange, displayRange: run.displayRange)
    }
}
