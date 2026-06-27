//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownPreviewView: View {
    let source: String
    let baseURL: URL?
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]

    var body: some View {
        MarkdownPreviewWebView(
            source: source,
            html: MarkdownHTMLBuilder.document(for: source, textSize: textSize),
            baseURL: baseURL
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
#Preview("Markdown Preview View") {
    MarkdownPreviewView(
        source: MarkdownPreviewFixtures.excerptFile.contents,
        baseURL: nil,
        textSize: .large,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 120)])
    )
}
#endif
