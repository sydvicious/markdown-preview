//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownSourceView: View {
    let contents: String
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]

    var body: some View {
        SelectableSourceTextView(text: contents, textSize: textSize, selections: $selections)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
#Preview("Markdown Source View") {
    MarkdownSourceView(
        contents: MarkdownPreviewFixtures.excerptFile.contents,
        textSize: .large,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 24)])
    )
}
#endif
