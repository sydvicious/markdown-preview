//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownPreviewView: View {
    let source: String

    var body: some View {
        MarkdownBlocksView(source: source)
    }
}

#Preview("Markdown Preview View") {
    MarkdownPreviewView(source: MarkdownPreviewFixtures.excerptFile.contents)
}
