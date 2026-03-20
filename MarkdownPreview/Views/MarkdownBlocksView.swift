//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
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
            return Text("\(partial)\n\n\(blockText)")
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

            let line = Text("\(indent + prefix)\(Text(inlineAttributed(item.text, highlights: selectedFragments)))")
            if index == 0 {
                return line
            }
            return Text("\(partial)\n\(line)")
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

        copyToClipboard(plainText: blockText, richText: richTextForCopiedBlock(block))
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

    private func copyToClipboard(plainText: String, richText: NSAttributedString?) {
        #if os(iOS)
        var item: [String: Any] = [UTType.plainText.identifier: plainText]
        if let richText, let rtfData = rtfData(for: richText) {
            item[UTType.rtf.identifier] = rtfData
        }
        UIPasteboard.general.setItems([item], options: [:])
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
        if let richText, let rtfData = rtfData(for: richText) {
            pasteboard.setData(rtfData, forType: .rtf)
        }
        #endif
    }

    private func richTextForCopiedBlock(_ block: MarkdownBlock) -> NSAttributedString? {
        switch block.kind {
        case .blockquote(let text):
            return richInlineText(
                markdown: text,
                font: richTextFont(style: .body, italic: true)
            )
        case .code(let code):
            let rendered = NSMutableAttributedString(
                string: code,
                attributes: [
                    .font: richTextFont(style: .body, monospaced: true),
                    .foregroundColor: richTextForegroundColor,
                    .backgroundColor: richTextCodeBackgroundColor
                ]
            )
            return rendered
        case .table(let table):
            return richTextForCopiedTable(table)
        case .heading(let level, let text):
            return richInlineText(
                markdown: text,
                font: richTextFont(style: headingTextStyle(level), weight: .semibold)
            )
        case .paragraph(let text):
            return richInlineText(markdown: text, font: richTextFont(style: .body))
        case .list(let items):
            return richTextForCopiedList(items, ordered: false)
        case .orderedList(let items):
            return richTextForCopiedList(items, ordered: true)
        case .rule:
            return nil
        }
    }

    private func richTextForCopiedList(_ items: [MarkdownListItem], ordered: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = richTextFont(style: .body)

        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let indent = String(repeating: "    ", count: item.indent)
            let prefix: String
            if ordered {
                prefix = "\(item.order ?? (index + 1)). "
            } else if let checked = item.checkbox {
                prefix = checked ? "☑︎ " : "☐ "
            } else {
                prefix = "• "
            }

            result.append(
                NSAttributedString(
                    string: indent + prefix,
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: richTextForegroundColor
                    ]
                )
            )
            result.append(richInlineText(markdown: item.text, font: bodyFont))
        }

        return result
    }

    private func richTextForCopiedTable(_ table: MarkdownTable) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let headerFont = richTextFont(style: .headline, weight: .semibold)
        let bodyFont = richTextFont(style: .body)
        let tabStops = tableTabStops(table)

        if !table.headers.isEmpty {
            result.append(tableLineAttributedString(
                cells: table.headers,
                font: headerFont,
                tabStops: tabStops
            ))
        }

        for row in table.rows {
            if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            let paddedRow = Array(row.prefix(table.headers.count)) + Array(repeating: "", count: max(0, table.headers.count - row.count))
            result.append(tableLineAttributedString(
                cells: paddedRow,
                font: bodyFont,
                tabStops: tabStops
            ))
        }

        return result
    }

    private func tableLineAttributedString(
        cells: [String],
        font: PlatformFont,
        tabStops: [NSTextTab]
    ) -> NSAttributedString {
        let line = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = tabStops
        paragraphStyle.defaultTabInterval = (tabStops.last?.location ?? 0) + 24

        for index in cells.indices {
            line.append(richInlineText(markdown: cells[index], font: font))
            if index < cells.count - 1 {
                line.append(
                    NSAttributedString(
                        string: "\t",
                        attributes: [
                            .font: font,
                            .foregroundColor: richTextForegroundColor
                        ]
                    )
                )
            }
        }

        line.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: line.length)
        )
        return line
    }

    private func tableTabStops(_ table: MarkdownTable) -> [NSTextTab] {
        guard !table.headers.isEmpty else { return [] }

        var widths = Array(repeating: CGFloat(0), count: table.headers.count)
        let headerFont = richTextFont(style: .headline, weight: .semibold)
        let bodyFont = richTextFont(style: .body)

        for column in table.headers.indices {
            widths[column] = max(
                widths[column],
                measuredRichTextWidth(renderedInlineText(from: table.headers[column]), font: headerFont)
            )
        }

        for row in table.rows {
            for column in table.headers.indices {
                let cell = row.indices.contains(column) ? row[column] : ""
                widths[column] = max(
                    widths[column],
                    measuredRichTextWidth(renderedInlineText(from: cell), font: bodyFont)
                )
            }
        }

        var location: CGFloat = 0
        return widths.dropLast().map { width in
            location += max(80, ceil(width) + 24)
            return NSTextTab(textAlignment: .left, location: location)
        }
    }

    private func measuredRichTextWidth(_ text: String, font: PlatformFont) -> CGFloat {
        NSString(string: text).size(withAttributes: [.font: font]).width
    }

    private func richInlineText(markdown: String, font: PlatformFont) -> NSAttributedString {
        let base: AttributedString
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            base = attributed
        } else {
            base = AttributedString(markdown)
        }

        let rendered = NSMutableAttributedString(attributedString: NSAttributedString(base))
        let fullRange = NSRange(location: 0, length: rendered.length)

        guard rendered.length > 0 else { return rendered }

        rendered.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil {
                rendered.addAttribute(.font, value: font, range: range)
            }
        }

        rendered.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil {
                rendered.addAttribute(.foregroundColor, value: richTextForegroundColor, range: range)
            }
        }

        return rendered
    }

    private func rtfData(for attributedText: NSAttributedString) -> Data? {
        let range = NSRange(location: 0, length: attributedText.length)
        return try? attributedText.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
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

    private typealias PlatformFont = UIFont

    private func richTextFont(
        style: UIFont.TextStyle,
        weight: UIFont.Weight = .regular,
        italic: Bool = false,
        monospaced: Bool = false
    ) -> UIFont {
        previewUIFont(textStyle: style, weight: weight, italic: italic, monospaced: monospaced)
    }

    private var richTextForegroundColor: UIColor { .label }
    private var richTextCodeBackgroundColor: UIColor { .secondarySystemBackground }
    #endif

    #if os(macOS)
    private typealias PlatformFont = NSFont

    private func richTextFont(
        style: NSFont.TextStyle,
        weight: NSFont.Weight = .regular,
        italic: Bool = false,
        monospaced: Bool = false
    ) -> NSFont {
        let preferredSize = NSFont.preferredFont(forTextStyle: style).pointSize
        let base: NSFont

        if monospaced {
            base = NSFont.monospacedSystemFont(ofSize: preferredSize, weight: weight)
        } else {
            let weighted = NSFont.systemFont(ofSize: preferredSize, weight: weight)
            if italic {
                let descriptor = weighted.fontDescriptor.withSymbolicTraits(.italic)
                base = NSFont(descriptor: descriptor, size: preferredSize) ?? weighted
            } else {
                base = weighted
            }
        }

        return base
    }

    private func headingTextStyle(_ level: Int) -> NSFont.TextStyle {
        switch level {
        case 1: return .largeTitle
        case 2: return .title1
        case 3: return .title2
        case 4: return .headline
        default: return .body
        }
    }

    private var richTextForegroundColor: NSColor { .labelColor }
    private var richTextCodeBackgroundColor: NSColor { .controlBackgroundColor }
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
