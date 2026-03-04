//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

#Preview("Table Block View") {
    ScrollView {
        MarkdownTableBlockView(table: MarkdownPreviewFixtures.table)
            .padding(20)
    }
}

struct MarkdownTableBlockView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<table.headers.count, id: \.self) { column in
                        cell(table.headers[column], alignment: table.alignments[safe: column] ?? .leading, isHeader: true)
                    }
                }

                ForEach(0..<table.rows.count, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(0..<table.headers.count, id: \.self) { column in
                            let text = table.rows[rowIndex][safe: column] ?? ""
                            cell(text, alignment: table.alignments[safe: column] ?? .leading, isHeader: false)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tableBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func cell(_ text: String, alignment: MarkdownTableAlignment, isHeader: Bool) -> some View {
        Text(inlineAttributed(text))
            .font(isHeader ? .headline : .body)
            .frame(maxWidth: .infinity, alignment: swiftUIAlignment(for: alignment))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHeader ? headerBackgroundColor : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(height: 1)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(width: 1)
            }
            .fixedSize(horizontal: false, vertical: true)
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

    private func swiftUIAlignment(for alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private var tableBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var headerBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlColor)
        #else
        Color(uiColor: .tertiarySystemFill)
        #endif
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
