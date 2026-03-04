//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownPreviewView: View {
    let source: String
    var selections: [MarkdownSelectionRange] = []

    var body: some View {
        MarkdownBlocksView(source: source, selections: selections)
    }
}

#Preview("Markdown Preview View") {
    MarkdownPreviewView(
        source: MarkdownPreviewFixtures.excerptFile.contents,
        selections: [MarkdownSelectionRange(location: 0, length: 120)]
    )
}
