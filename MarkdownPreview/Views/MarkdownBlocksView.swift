//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MarkdownBlocksView: View {
    let source: String
    var selections: [MarkdownSelectionRange] = []

    var body: some View {
        ScrollView {
            blocksContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blocksContent: some View {
        let blocks = MarkdownBlockParser.parse(source)
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks, id: \.id) { block in
                blockView(block)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
                case .heading(let level, let text):
                    Text(inlineAttributed(text, highlights: selectedFragments))
                        .font(headingFont(level: level))
                        .fontWeight(.semibold)
                case .paragraph(let text):
                    Text(inlineAttributed(text, highlights: selectedFragments))
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
                                Text(inlineAttributed(item.text, highlights: selectedFragments))
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
                                Text(inlineAttributed(item.text, highlights: selectedFragments))
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
                        Text(inlineAttributed(text, highlights: selectedFragments))
                            .font(.body)
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .rule:
                    Divider()
                case .code(let code):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(highlightedCodeOverlay(code))
                            .font(.system(.body, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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

    private var selectedFragments: [String] {
        sourceFragments(from: selections, source: source)
    }

    private func inlineAttributed(_ text: String, highlights: [String]) -> AttributedString {
        let base: AttributedString
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            base = attributed
        } else {
            base = AttributedString(text)
        }

        return applyHighlights(to: base, fragments: highlights)
    }

    private func highlightedCodeOverlay(_ code: String) -> AttributedString {
        applyHighlights(to: AttributedString(code), fragments: selectedFragments)
    }

    private func applyHighlights(to base: AttributedString, fragments: [String]) -> AttributedString {
        guard !fragments.isEmpty else { return base }
        var result = base
        let fullText = String(result.characters)
        guard !fullText.isEmpty else { return result }

        for fragment in fragments {
            guard !fragment.isEmpty else { continue }
            var searchRange = fullText.startIndex..<fullText.endIndex
            while let range = fullText.range(of: fragment, options: [], range: searchRange) {
                if let lower = AttributedString.Index(range.lowerBound, within: result),
                   let upper = AttributedString.Index(range.upperBound, within: result) {
                    result[lower..<upper].backgroundColor = selectionHighlightColor
                }
                searchRange = range.upperBound..<fullText.endIndex
            }
        }
        return result
    }

    private func sourceFragments(from ranges: [MarkdownSelectionRange], source: String) -> [String] {
        let maxLength = source.utf16.count
        var result: [String] = []

        for range in ranges {
            guard let clamped = range.clamped(toUTF16Length: maxLength), clamped.length > 0 else { continue }
            guard let swiftRange = Range(clamped.nsRange, in: source) else { continue }
            let selected = String(source[swiftRange])
            let lines = selected.components(separatedBy: .newlines)
            for line in lines {
                let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleaned.count >= 2 else { continue }
                result.append(cleaned)

                // Match rendered inline markdown text (for headings/paragraphs with `code`, emphasis, links, etc.).
                let rendered = renderedInlineText(from: cleaned)
                if rendered.count >= 2 {
                    result.append(rendered)
                }

                let normalized = stripMarkdownPrefix(from: cleaned)
                if normalized.count >= 2 {
                    result.append(normalized)
                    let normalizedRendered = renderedInlineText(from: normalized)
                    if normalizedRendered.count >= 2 {
                        result.append(normalizedRendered)
                    }
                }
            }
        }

        // Prefer longer fragments first so highlight matching is more stable.
        return Array(Set(result)).sorted { $0.count > $1.count }
    }

    private func stripMarkdownPrefix(from text: String) -> String {
        var line = text

        // ATX headings: "### Heading"
        if line.hasPrefix("#") {
            line = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return line
        }

        // Blockquote: "> Quote"
        if line.hasPrefix(">") {
            return line.dropFirst().trimmingCharacters(in: .whitespaces)
        }

        // Unordered list: "- item", "* item", "+ item"
        if let first = line.first, ["-", "*", "+"].contains(first) {
            return line.dropFirst().trimmingCharacters(in: .whitespaces)
        }

        // Ordered list: "12. item"
        if let dot = line.firstIndex(of: "."),
           line[..<dot].allSatisfy(\.isNumber) {
            let afterDot = line.index(after: dot)
            if afterDot < line.endIndex {
                return line[afterDot...].trimmingCharacters(in: .whitespaces)
            }
        }

        return line
    }

    private func renderedInlineText(from markdownLine: String) -> String {
        guard let attributed = try? AttributedString(
            markdown: markdownLine,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return markdownLine
        }
        return String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
private var selectionHighlightColor: Color {
    #if os(iOS)
    // Match system tint semantics instead of hardcoded color values.
    return Color(uiColor: .tintColor).opacity(0.28)
    #elseif os(macOS)
    return Color(nsColor: .selectedTextBackgroundColor)
    #else
    return Color.accentColor.opacity(0.30)
    #endif
}

#Preview("Blocks View") {
    MarkdownBlocksView(
        source: MarkdownPreviewFixtures.excerptFile.contents,
        selections: [MarkdownSelectionRange(location: 0, length: 120)]
    )
}
