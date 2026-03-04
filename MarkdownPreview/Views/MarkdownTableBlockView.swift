//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

#Preview("Table Block View") {
    ScrollView {
        MarkdownTableBlockView(table: MarkdownPreviewFixtures.table)
            .padding(20)
    }
}

struct MarkdownTableBlockView: View {
    let table: MarkdownTable
    @State private var contentHeight: CGFloat = 120
    @State private var contentWidth: CGFloat = 320

    var body: some View {
        GeometryReader { geometry in
            let targetWidth = max(120, min(contentWidth, max(120, geometry.size.width)))
            MarkdownTableWebView(
                html: htmlDocument,
                contentHeight: $contentHeight,
                contentWidth: $contentWidth
            )
            .frame(width: targetWidth, height: max(contentHeight, 44), alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: max(contentHeight, 44))
    }

    private var htmlDocument: String {
        MarkdownTableHTMLBuilder.document(for: table)
    }
}
