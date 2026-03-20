//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MarkdownTableBlockView: View {
    let table: MarkdownTable
    var showChrome: Bool = true
    var wrapsInHorizontalScroll: Bool = true
    private let cellHorizontalPadding: CGFloat = 12

    var body: some View {
        Group {
            if wrapsInHorizontalScroll {
                ScrollView(.horizontal, showsIndicators: true) {
                    styledGrid
                }
            } else {
                styledGrid
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var styledGrid: some View {
        if showChrome {
            tableGrid
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tableBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            tableGrid
        }
    }

    private var tableGrid: some View {
        let widths = columnWidths
        return Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<table.headers.count, id: \.self) { column in
                    cell(
                        table.headers[column],
                        width: widths[safe: column] ?? 120,
                        alignment: table.alignments[safe: column] ?? .leading,
                        isHeader: true
                    )
                }
            }

            ForEach(0..<table.rows.count, id: \.self) { rowIndex in
                GridRow {
                    ForEach(0..<table.headers.count, id: \.self) { column in
                        let text = table.rows[rowIndex][safe: column] ?? ""
                        cell(
                            text,
                            width: widths[safe: column] ?? 120,
                            alignment: table.alignments[safe: column] ?? .leading,
                            isHeader: false
                        )
                    }
                }
            }
        }
    }

    private func cell(_ text: String, width: CGFloat, alignment: MarkdownTableAlignment, isHeader: Bool) -> some View {
        Text(inlineAttributed(text))
            .font(isHeader ? .headline : .body)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(textAlignment(for: alignment))
            .frame(width: width, alignment: swiftUIAlignment(for: alignment))
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
    }

    private var columnWidths: [CGFloat] {
        guard !table.headers.isEmpty else { return [] }
        var widths = Array(repeating: CGFloat(0), count: table.headers.count)

        for column in 0..<table.headers.count {
            let headerText = renderedInlineText(table.headers[column])
            let headerWidth = measuredWidth(headerText, isHeader: true)
            widths[column] = max(widths[column], headerWidth)
        }

        for row in table.rows {
            for column in 0..<table.headers.count {
                let text = renderedInlineText(row[safe: column] ?? "")
                let width = measuredWidth(text, isHeader: false)
                widths[column] = max(widths[column], width)
            }
        }

        return widths.map { max(80, $0 + (cellHorizontalPadding * 2)) }
    }

    private func renderedInlineText(_ markdown: String) -> String {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return String(attributed.characters)
        }
        return markdown
    }

    private func measuredWidth(_ text: String, isHeader: Bool) -> CGFloat {
        #if os(macOS)
        let font = isHeader ? NSFont.boldSystemFont(ofSize: NSFont.systemFontSize) : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return NSString(string: text).size(withAttributes: attributes).width
        #else
        let font = isHeader ? UIFont.preferredFont(forTextStyle: .headline) : UIFont.preferredFont(forTextStyle: .body)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return NSString(string: text).size(withAttributes: attributes).width
        #endif
    }

    private func swiftUIAlignment(for alignment: MarkdownTableAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
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

    private func textAlignment(for alignment: MarkdownTableAlignment) -> TextAlignment {
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

#if DEBUG
#Preview("Table Block View") {
    ScrollView {
        MarkdownTableBlockView(table: MarkdownPreviewFixtures.table)
            .padding(20)
            .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity)
}
#endif
