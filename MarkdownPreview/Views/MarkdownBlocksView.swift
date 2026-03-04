//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

struct MarkdownBlocksView: View {
    let source: String

    var body: some View {
        ScrollView {
            blocksContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blocksContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(MarkdownBlockParser.parse(source), id: \.id) { block in
                switch block.kind {
                case .heading(let level, let text):
                    Text(inlineAttributed(text))
                        .font(headingFont(level: level))
                        .fontWeight(.semibold)
                case .paragraph(let text):
                    Text(inlineAttributed(text))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                case .list(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 8) {
                                if let checked = item.checkbox {
                                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                                        .foregroundColor(checked ? Color.accentColor : Color.secondary)
                                } else {
                                    Text("•")
                                        .font(.body)
                                }
                                Text(inlineAttributed(item.text))
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.leading, CGFloat(item.indent) * 18)
                        }
                    }
                case .orderedList(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(item.order ?? (index + 1)).")
                                    .monospacedDigit()
                                    .font(.body)
                                Text(inlineAttributed(item.text))
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.leading, CGFloat(item.indent) * 18)
                        }
                    }
                case .table(let table):
                    MarkdownTableBlockView(table: table)
                case .blockquote(let text):
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 4)
                        Text(inlineAttributed(text))
                            .font(.body)
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .rule:
                    Divider()
                case .code(let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(code)
                            .font(.system(.body, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .headline
        default: return .body
        }
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }
}

#Preview("Blocks View") {
    MarkdownBlocksView(source: MarkdownPreviewFixtures.excerptFile.contents)
}
