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
                    MarkdownBlocksView(source: file.contents, selections: .constant([]))
                case .source:
                    MarkdownSourceView(contents: file.contents, selections: .constant([]))
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
        DetailPreviewPanePreviewHost(file: MarkdownPreviewFixtures.fullFile)
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

private struct DetailPreviewPanePreviewHost: View {
    let file: MarkdownFile
    @State private var mode: DetailPreviewPane.Mode = .source

    var body: some View {
        DetailPreviewPane(file: file, mode: mode)
            .task {
                guard mode == .source else { return }
                try? await Task.sleep(for: .milliseconds(100))
                mode = .preview
            }
    }
}
