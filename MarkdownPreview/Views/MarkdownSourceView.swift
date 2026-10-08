//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import SwiftUI
import MarkdownCore

struct MarkdownSourceView: View {
    let contents: String
    /// Which document this is, and where the reader was in each: the pane
    /// opens where they were in the preview, and says where they go from
    /// there. Without them it opens at the top and says nothing.
    var documentID: String? = nil
    var scrollMemory: PreviewScrollMemory? = nil
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]
    var onSearchSelection: (String) -> Void = { _ in }

    var body: some View {
        SelectableSourceTextView(
            text: contents,
            documentID: documentID,
            scrollMemory: scrollMemory,
            textSize: textSize,
            selections: $selections,
            onSearchSelection: onSearchSelection
        )
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
