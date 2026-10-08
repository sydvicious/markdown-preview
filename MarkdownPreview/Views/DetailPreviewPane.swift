//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import SwiftUI

/// Preview scaffolding: stands in for the detail pane, so that a `#Preview`
/// can show a document's rendered or source view without the whole
/// `ContentView`. The app itself never shows it, and is not meant to.
struct DetailPreviewPane: View {
    enum Mode {
        case preview
        case source
    }

    let file: MarkdownFile?
    let mode: Mode
    let textSize: DynamicTypeSize
    @StateObject private var renderer = MarkdownPreviewView.makeRenderer()

    var body: some View {
        Group {
            if let file {
                switch mode {
                case .preview:
                    MarkdownPreviewView(
                        source: file.contents,
                        baseURL: file.url.deletingLastPathComponent(),
                        textSize: textSize,
                        selections: .constant([]),
                        renderer: renderer
                    )
                case .source:
                    MarkdownSourceView(contents: file.contents, textSize: textSize, selections: .constant([]))
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dynamicTypeSize(.xSmall ... .accessibility5)
    }
}

#if DEBUG
#Preview("Detail Pane - Preview") {
    NavigationStack {
        DetailPreviewPanePreviewHost(file: MarkdownPreviewFixtures.fullFile)
            .navigationTitle(MarkdownPreviewFixtures.fullFile.fileName)
    }
}

#Preview("Detail Pane - Source") {
    NavigationStack {
        DetailPreviewPane(file: MarkdownPreviewFixtures.fullFile, mode: .source, textSize: .large)
            .navigationTitle(MarkdownPreviewFixtures.fullFile.fileName)
    }
}

#Preview("Detail Pane - Empty") {
    NavigationStack {
        DetailPreviewPane(file: nil, mode: .preview, textSize: .large)
            .navigationTitle("Markdown Preview")
    }
}

private struct DetailPreviewPanePreviewHost: View {
    let file: MarkdownFile
    @State private var mode: DetailPreviewPane.Mode = .source

    var body: some View {
        DetailPreviewPane(file: file, mode: mode, textSize: .large)
            .task {
                guard mode == .source else { return }
                try? await Task.sleep(for: .milliseconds(100))
                mode = .preview
            }
    }
}
#endif
