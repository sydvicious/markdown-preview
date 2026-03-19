//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownCodeBlockView<Content: View>: View {
    private let content: Content
    var wrapsInHorizontalScroll: Bool = true

    init(code: AttributedString, wrapsInHorizontalScroll: Bool = true) where Content == Text {
        self.content = Text(code)
        self.wrapsInHorizontalScroll = wrapsInHorizontalScroll
    }

    init(@ViewBuilder content: () -> Content, wrapsInHorizontalScroll: Bool = true) {
        self.content = content()
        self.wrapsInHorizontalScroll = wrapsInHorizontalScroll
    }

    var body: some View {
        Group {
            if wrapsInHorizontalScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    codeText
                }
            } else {
                codeText
            }
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var codeText: some View {
        content
            .font(.system(.body, design: .monospaced))
            .padding(10)
    }
}

#Preview("Code Block View") {
    MarkdownCodeBlockView(
        code: AttributedString("""
let answer = 42
print("hello")
""")
    )
    .padding(20)
}
