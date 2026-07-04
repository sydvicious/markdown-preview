//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

final class MarkdownPreviewTextOffsetMapping: TextOffsetMapping {
    let sourceText: String
    let displayText: String
    let runs: [TextOffsetRun]

    init(sourceText: String) {
        self.sourceText = sourceText

        let builder = MarkdownDisplayBuilder(
            sourceText: sourceText,
            listItemSeparator: "",
            includesImageAltText: false
        )
        builder.build()
        displayText = builder.displayText
        runs = builder.runs
    }
}
