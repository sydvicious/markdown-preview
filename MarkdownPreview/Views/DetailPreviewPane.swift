//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct DetailPreviewPane: View {
    enum Mode {
        case preview
        case source
    }

    let file: MarkdownFile?
    let mode: Mode

    var body: some View {
        Group {
            if let file {
                switch mode {
                case .preview:
                    MarkdownBlocksView(source: file.contents)
                case .source:
                    ScrollView {
                        Text(file.contents)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Color.clear
            }
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }
}

#Preview("Detail Pane - Preview") {
    NavigationStack {
        DetailPreviewPane(file: MarkdownPreviewFixtures.fullFile, mode: .preview)
            .navigationTitle(MarkdownPreviewFixtures.fullFile.fileName)
    }
}

#Preview("Detail Pane - Source") {
    NavigationStack {
        DetailPreviewPane(file: MarkdownPreviewFixtures.fullFile, mode: .source)
            .navigationTitle(MarkdownPreviewFixtures.fullFile.fileName)
    }
}

#Preview("Detail Pane - Empty") {
    NavigationStack {
        DetailPreviewPane(file: nil, mode: .preview)
            .navigationTitle("Markdown Preview")
    }
}
