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
    @Binding var selections: [MarkdownSelectionRange]

    var body: some View {
        ScrollView {
            blocksContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blocksContent: some View {
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(parsedBlocks, id: \.id) { block in
                blockView(block)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var parsedBlocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(source)
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
                    MarkdownCopyableBlockContainerView(onCopy: {
                        copyBlockToClipboard(block)
                    }, scrollContentHorizontally: true) {
                        MarkdownTableBlockView(
                            table: table,
                            showChrome: false,
                            wrapsInHorizontalScroll: false
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                case .blockquote(let text):
                    MarkdownCopyableBlockContainerView(onCopy: {
                        copyBlockToClipboard(block)
                    }) {
                        MarkdownBlockQuoteView(
                            text: inlineAttributed(text, highlights: selectedFragments)
                        )
                    }
                case .rule:
                    Divider()
                case .code(let code):
                    MarkdownCopyableBlockContainerView(onCopy: {
                        copyBlockToClipboard(block)
                    }, scrollContentHorizontally: true) {
                        MarkdownCodeBlockView(
                            code: highlightedCodeOverlay(code),
                            wrapsInHorizontalScroll: false
                        )
                    }
        }
    }

    private func copyBlockToClipboard(_ block: MarkdownBlock) {
        guard let range = nsRangeForBlock(block) else { return }
        guard let swiftRange = Range(range, in: source) else { return }
        let blockText = String(source[swiftRange])
        guard !blockText.isEmpty else { return }

        copyToClipboard(blockText)
    }

    private func nsRangeForBlock(_ block: MarkdownBlock) -> NSRange? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let effectiveRange = effectiveLineRangeForCopy(block, lines: lines)
        let lower = effectiveRange.lowerBound
        let upper = effectiveRange.upperBound

        guard lower >= 0, upper >= lower, upper <= lines.count else { return nil }

        var starts: [Int] = []
        starts.reserveCapacity(lines.count)
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += line.utf16.count + 1
        }

        guard lower < starts.count else { return nil }
        let start = starts[lower]
        let end: Int
        if upper < starts.count {
            end = max(start, starts[upper] - 1)
        } else {
            end = source.utf16.count
        }

        return NSRange(location: start, length: max(0, end - start))
    }

    private func effectiveLineRangeForCopy(_ block: MarkdownBlock, lines: [String]) -> Range<Int> {
        guard case .code = block.kind else { return block.lineRange }
        guard !lines.isEmpty else { return block.lineRange }

        var lower = block.lineRange.lowerBound
        var upper = block.lineRange.upperBound

        // Include opening fence if parser lineRange starts at first code-content line.
        if lower > 0, isFenceLine(lines[lower - 1]) {
            lower -= 1
        }
        // Include closing fence if present.
        if upper < lines.count, isFenceLine(lines[upper]) {
            upper += 1
        }

        return lower..<upper
    }

    private func isFenceLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private func copyToClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #endif
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
        selections: .constant([MarkdownSelectionRange(location: 0, length: 120)])
    )
}
