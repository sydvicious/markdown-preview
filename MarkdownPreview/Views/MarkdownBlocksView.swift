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

    private struct TextSegment: Identifiable {
        let id = UUID()
        let blocks: [MarkdownBlock]
    }

    private struct PreviewSegment: Identifiable {
        enum Kind {
            case text(TextSegment)
            case block(MarkdownBlock)
        }

        let id = UUID()
        let kind: Kind
    }

    var body: some View {
        ScrollView {
            blocksContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blocksContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(previewSegments) { segment in
                segmentView(segment)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var parsedBlocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(source)
    }

    private var previewSegments: [PreviewSegment] {
        var segments: [PreviewSegment] = []
        var pendingTextBlocks: [MarkdownBlock] = []

        func flushPendingTextBlocks() {
            guard !pendingTextBlocks.isEmpty else { return }
            segments.append(
                PreviewSegment(
                    kind: .text(TextSegment(blocks: pendingTextBlocks))
                )
            )
            pendingTextBlocks.removeAll()
        }

        for block in parsedBlocks {
            if block.isCoalescedPreviewTextBlock {
                pendingTextBlocks.append(block)
            } else {
                flushPendingTextBlocks()
                segments.append(PreviewSegment(kind: .block(block)))
            }
        }

        flushPendingTextBlocks()
        return segments
    }

    @ViewBuilder
    private func segmentView(_ segment: PreviewSegment) -> some View {
        switch segment.kind {
        case .text(let textSegment):
            textSegmentView(textSegment)
        case .block(let block):
            blockView(block)
        }
    }

    #if os(iOS)
    private func textSegmentView(_ segment: TextSegment) -> some View {
        SelectablePreviewTextView(
            attributedText: textSegmentAttributedString(segment)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textSegmentAttributedString(_ segment: TextSegment) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, block) in segment.blocks.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n\n"))
            }
            result.append(textBlockAttributedString(block))
        }

        return result
    }

    private func textBlockAttributedString(_ block: MarkdownBlock) -> NSAttributedString {
        switch block.kind {
        case .heading(let level, let text):
            return inlineTextAttributedString(
                text,
                font: previewUIFont(textStyle: headingTextStyle(level), weight: .semibold)
            )
        case .paragraph(let text):
            return inlineTextAttributedString(text, font: previewUIFont(textStyle: .body))
        case .list(let items):
            return listAttributedString(items, ordered: false)
        case .orderedList(let items):
            return listAttributedString(items, ordered: true)
        case .table, .blockquote, .rule, .code:
            return NSAttributedString(string: "")
        }
    }

    private func inlineTextAttributedString(_ text: String, font: UIFont) -> NSAttributedString {
        SelectablePreviewTextView.makeAttributedText(
            from: inlineAttributed(text, highlights: selectedFragments),
            baseFont: font
        )
    }

    private func listAttributedString(_ items: [MarkdownListItem], ordered: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = previewUIFont(textStyle: .body)

        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let prefix = ordered
                ? "\(item.order ?? (index + 1))."
                : unorderedListPrefix(for: item)
            let prefixFont = ordered
                ? UIFont.monospacedDigitSystemFont(ofSize: bodyFont.pointSize, weight: .regular)
                : bodyFont

            let indentWidth = CGFloat(item.indent) * 18
            let prefixWidth = ceil(
                (prefix as NSString).size(withAttributes: [.font: prefixFont]).width
            )
            let contentIndent = indentWidth + prefixWidth + 12

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = indentWidth
            paragraphStyle.headIndent = contentIndent
            paragraphStyle.tabStops = [
                NSTextTab(textAlignment: .left, location: contentIndent)
            ]
            paragraphStyle.defaultTabInterval = contentIndent

            let line = NSMutableAttributedString(
                string: "\(prefix)\t",
                attributes: [
                    .font: prefixFont,
                    .foregroundColor: UIColor.label
                ]
            )
            line.append(
                NSMutableAttributedString(
                    attributedString: inlineTextAttributedString(item.text, font: bodyFont)
                )
            )
            line.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: 0, length: line.length)
            )

            result.append(line)
        }

        return result
    }

    private func unorderedListPrefix(for item: MarkdownListItem) -> String {
        if let checked = item.checkbox {
            return checked ? "☑︎" : "☐"
        }
        return "•"
    }
    #elseif os(macOS)
    private func textSegmentView(_ segment: TextSegment) -> some View {
        textSegmentText(segment)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textSegmentText(_ segment: TextSegment) -> Text {
        segment.blocks.enumerated().reduce(Text("")) { partial, entry in
            let blockText = textBlockText(entry.element)
            if entry.offset == 0 {
                return blockText
            }
            return partial + Text("\n\n") + blockText
        }
    }

    private func textBlockText(_ block: MarkdownBlock) -> Text {
        switch block.kind {
        case .heading(let level, let text):
            return Text(inlineAttributed(text, highlights: selectedFragments))
                .font(headingFont(level: level))
                .fontWeight(.semibold)
        case .paragraph(let text):
            return Text(inlineAttributed(text, highlights: selectedFragments))
                .font(.body)
        case .list(let items):
            return listText(items, ordered: false)
        case .orderedList(let items):
            return listText(items, ordered: true)
        case .table, .blockquote, .rule, .code:
            return Text("")
        }
    }

    private func listText(_ items: [MarkdownListItem], ordered: Bool) -> Text {
        items.enumerated().reduce(Text("")) { partial, entry in
            let index = entry.offset
            let item = entry.element
            let indent = String(repeating: "    ", count: item.indent)
            let prefix: String
            if ordered {
                prefix = "\(item.order ?? (index + 1)). "
            } else if let checked = item.checkbox {
                prefix = checked ? "☑︎ " : "☐ "
            } else {
                prefix = "• "
            }

            let line = Text(indent + prefix) + Text(inlineAttributed(item.text, highlights: selectedFragments))
            if index == 0 {
                return line
            }
            return partial + Text("\n") + line
        }
    }
    #endif

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
                case .heading(let level, let text):
                    headingView(level: level, text: text)
                case .paragraph(let text):
                    bodyTextView(text)
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
                                bodyTextView(item.text)
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
                                bodyTextView(item.text)
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
                        blockQuoteView(text)
                    }
                case .rule:
                    Divider()
                case .code(let code):
                    MarkdownCopyableBlockContainerView(onCopy: {
                        copyBlockToClipboard(block)
                    }, scrollContentHorizontally: true) {
                        codeBlockView(code)
                    }
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        #if os(iOS)
        SelectablePreviewTextView(
            attributedText: inlineAttributed(text, highlights: selectedFragments),
            baseFont: previewUIFont(textStyle: headingTextStyle(level), weight: .semibold)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        Text(inlineAttributed(text, highlights: selectedFragments))
            .font(headingFont(level: level))
            .fontWeight(.semibold)
        #endif
    }

    @ViewBuilder
    private func bodyTextView(_ text: String) -> some View {
        #if os(iOS)
        SelectablePreviewTextView(
            attributedText: inlineAttributed(text, highlights: selectedFragments),
            baseFont: previewUIFont(textStyle: .body)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        Text(inlineAttributed(text, highlights: selectedFragments))
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }

    @ViewBuilder
    private func blockQuoteView(_ text: String) -> some View {
        #if os(iOS)
        MarkdownBlockQuoteView {
            SelectablePreviewTextView(
                attributedText: inlineAttributed(text, highlights: selectedFragments),
                baseFont: previewUIFont(textStyle: .body, italic: true)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #else
        MarkdownBlockQuoteView(
            text: inlineAttributed(text, highlights: selectedFragments)
        )
        #endif
    }

    @ViewBuilder
    private func codeBlockView(_ code: String) -> some View {
        #if os(iOS)
        MarkdownCodeBlockView(content: {
            SelectablePreviewTextView(
                attributedText: highlightedCodeOverlay(code),
                baseFont: previewUIFont(textStyle: .body, monospaced: true)
            )
        }, wrapsInHorizontalScroll: false)
        #else
        MarkdownCodeBlockView(
            code: highlightedCodeOverlay(code),
            wrapsInHorizontalScroll: false
        )
        #endif
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

    #if os(iOS)
    private func headingTextStyle(_ level: Int) -> UIFont.TextStyle {
        switch level {
        case 1: return .largeTitle
        case 2: return .title1
        case 3: return .title2
        case 4: return .headline
        default: return .body
        }
    }

    private func previewUIFont(
        textStyle: UIFont.TextStyle,
        weight: UIFont.Weight = .regular,
        italic: Bool = false,
        monospaced: Bool = false
    ) -> UIFont {
        let preferredSize = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        let base: UIFont

        if monospaced {
            base = UIFont.monospacedSystemFont(ofSize: preferredSize, weight: weight)
        } else {
            let weighted = UIFont.systemFont(ofSize: preferredSize, weight: weight)
            if italic,
               let descriptor = weighted.fontDescriptor.withSymbolicTraits(.traitItalic) {
                base = UIFont(descriptor: descriptor, size: preferredSize)
            } else {
                base = weighted
            }
        }

        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
    #endif
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

private extension MarkdownBlock {
    var isCoalescedPreviewTextBlock: Bool {
        switch kind {
        case .heading, .paragraph, .list, .orderedList:
            return true
        case .table, .blockquote, .rule, .code:
            return false
        }
    }
}

#Preview("Blocks View") {
    MarkdownBlocksView(
        source: MarkdownPreviewFixtures.excerptFile.contents,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 120)])
    )
}
