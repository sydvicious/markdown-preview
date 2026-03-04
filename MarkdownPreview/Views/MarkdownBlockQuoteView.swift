//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownBlockQuoteView: View {
    let text: AttributedString

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 4)
            Text(text)
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
