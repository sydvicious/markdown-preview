//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import MarkdownCore

/// A block's visible text as the page holds it: what the preview's script
/// finds when it walks the block's text nodes. Nothing separates one list item
/// or quoted block from the next, because nothing does in the page, and an
/// image's description is an attribute, not text.
final class MarkdownPreviewTextOffsetMapping: TextOffsetMapping {
    let sourceText: String
    let displayText: String
    let runs: [TextOffsetRun]

    /// - Parameter definitions: The document's link reference definitions,
    ///   when `sourceText` is one block of it. A reference in the block is a
    ///   link only if the definition, which is somewhere else, is known.
    init(sourceText: String, definitions: MarkdownLinkDefinitions? = nil) {
        self.sourceText = sourceText

        let visible = MarkdownVisibleText(
            source: sourceText,
            elementSeparator: "",
            includesImageDescriptions: false,
            definitions: definitions
        )
        displayText = visible.text
        runs = visible.runs.map(TextOffsetRun.init)
    }
}
