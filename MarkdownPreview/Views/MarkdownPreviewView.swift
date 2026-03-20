//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownPreviewView: View {
    let source: String
    @Binding var selections: [MarkdownSelectionRange]

    var body: some View {
        MarkdownBlocksView(source: source, selections: $selections)
    }
}

#if DEBUG
#Preview("Markdown Preview View") {
    MarkdownPreviewView(
        source: MarkdownPreviewFixtures.excerptFile.contents,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 120)])
    )
}
#endif
