//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownBlockQuoteView<Content: View>: View {
    private let content: Content

    init(text: AttributedString) where Content == Text {
        self.content = Text(text)
    }

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 4)
            content
                .font(.body)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Block Quote View") {
    MarkdownBlockQuoteView(
        text: AttributedString("This is a quoted markdown block.")
    )
    .padding(20)
}
