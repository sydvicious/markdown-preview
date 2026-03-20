//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownSourceView: View {
    let contents: String
    @Binding var selections: [MarkdownSelectionRange]

    var body: some View {
        SelectableSourceTextView(text: contents, selections: $selections)
    }
}

#if DEBUG
#Preview("Markdown Source View") {
    MarkdownSourceView(
        contents: MarkdownPreviewFixtures.excerptFile.contents,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 24)])
    )
}
#endif
