//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownSourceView: View {
    let contents: String

    var body: some View {
        ScrollView {
            Text(contents)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
        }
    }
}

#Preview("Markdown Source View") {
    MarkdownSourceView(contents: MarkdownPreviewFixtures.excerptFile.contents)
}
