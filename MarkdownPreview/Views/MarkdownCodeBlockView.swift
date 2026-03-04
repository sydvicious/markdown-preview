//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownCodeBlockView: View {
    let code: AttributedString
    var wrapsInHorizontalScroll: Bool = true

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
        Text(code)
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
