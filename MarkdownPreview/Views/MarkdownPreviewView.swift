//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownPreviewView: View {
    let source: String
    let baseURL: URL?
    @Binding var selections: [MarkdownSelectionRange]

    var body: some View {
        MarkdownPreviewWebView(
            html: MarkdownHTMLBuilder.document(for: source),
            baseURL: baseURL
        )
    }
}

#if DEBUG
#Preview("Markdown Preview View") {
    MarkdownPreviewView(
        source: MarkdownPreviewFixtures.excerptFile.contents,
        baseURL: nil,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 120)])
    )
}
#endif
