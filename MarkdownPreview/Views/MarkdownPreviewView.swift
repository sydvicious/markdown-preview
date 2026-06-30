//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

final class PreviewSelectionSynchronizer: ObservableObject {
    private var flushSelectionHandler: ((@escaping () -> Void) -> Void)?

    func flushSelection(completion: @escaping () -> Void) {
        guard let flushSelectionHandler else {
            completion()
            return
        }

        flushSelectionHandler(completion)
    }

    func setFlushSelectionHandler(_ handler: ((@escaping () -> Void) -> Void)?) {
        flushSelectionHandler = handler
    }
}

struct MarkdownPreviewView: View {
    let source: String
    let baseURL: URL?
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]
    var selectionSynchronizer: PreviewSelectionSynchronizer?
    var onSelectedTextChange: (String?) -> Void = { _ in }
    var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }

    var body: some View {
        MarkdownPreviewWebView(
            source: source,
            html: MarkdownHTMLBuilder.document(for: source, textSize: textSize),
            baseURL: baseURL,
            selectedRange: selections.first,
            selectionSynchronizer: selectionSynchronizer,
            onSelectedTextChange: onSelectedTextChange,
            onSelectedRangesChange: onSelectedRangesChange
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
