//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import MarkdownCore

/// One end of a selection, as the rendered preview sees it: which block, and how
/// far into that block's rendered text.
struct PreviewReflectedSelectionPoint: Equatable {
    /// Identifies the rendered block; these match its `data-source-start` and
    /// `data-source-end` attributes in the HTML.
    let blockStart: Int
    let blockEnd: Int
    /// Offset into that block's rendered text.
    let displayOffset: Int
}

/// A source selection expressed as two points in the rendered preview.
///
/// The two ends may sit in different blocks. An earlier version carried a single
/// block and a range within it, which meant any selection spanning a paragraph
/// boundary reflected to nothing and the preview showed no selection at all —
/// dragging across two paragraphs in the source view and switching to the
/// preview left it blank.
struct PreviewReflectedSelection: Equatable {
    let start: PreviewReflectedSelectionPoint
    let end: PreviewReflectedSelectionPoint
}

enum PreviewSelectionReflection {
    private typealias Block = (range: MarkdownSelectionRange, mapping: MarkdownPreviewTextOffsetMapping)

    private enum Edge {
        case start
        case end
    }

    static func reflectedSelection(
        in source: String,
        selectedRange: MarkdownSelectionRange?
    ) -> PreviewReflectedSelection? {
        guard let clampedRange = selectedRange?.clamped(toUTF16Length: source.utf16.count),
              clampedRange.length > 0 else {
            return nil
        }

        let selectionEnd = clampedRange.location + clampedRange.length
        let sourceLineTable = MarkdownSourceLineTable(source: source)
        let sourceNSString = source as NSString

        // Every block the selection touches, in document order. A selection
        // typically also covers the blank lines between blocks, which belong to
        // no block, so overlap is the test rather than containment.
        var overlapping: [Block] = []
        for block in MarkdownBlockParser.parse(source) {
            guard let blockRange = sourceLineTable.range(for: block.lineRange) else { continue }
            let blockEnd = blockRange.location + blockRange.length
            guard blockRange.location < selectionEnd, clampedRange.location < blockEnd else { continue }
            let blockSource = sourceNSString.substring(with: blockRange.nsRange)
            overlapping.append((blockRange, MarkdownPreviewTextOffsetMapping(sourceText: blockSource)))
        }

        guard let firstBlock = overlapping.first, let lastBlock = overlapping.last else { return nil }
        let spansBlocks = overlapping.count > 1

        guard let startOffset = displayOffset(
            in: firstBlock,
            selection: clampedRange,
            selectionEnd: selectionEnd,
            edge: .start,
            allowsBlockEdgeFallback: spansBlocks
        ), let endOffset = displayOffset(
            in: lastBlock,
            selection: clampedRange,
            selectionEnd: selectionEnd,
            edge: .end,
            allowsBlockEdgeFallback: spansBlocks
        ) else {
            return nil
        }

        // Within one block the two offsets have to enclose something; across
        // blocks they are in different texts and cannot be compared.
        if !spansBlocks, endOffset <= startOffset { return nil }

        return PreviewReflectedSelection(
            start: point(for: firstBlock, displayOffset: startOffset),
            end: point(for: lastBlock, displayOffset: endOffset)
        )
    }

    private static func point(for block: Block, displayOffset: Int) -> PreviewReflectedSelectionPoint {
        PreviewReflectedSelectionPoint(
            blockStart: block.range.location,
            blockEnd: block.range.location + block.range.length,
            displayOffset: displayOffset
        )
    }

    /// Where this block's share of the selection begins or ends, in rendered
    /// text offsets.
    private static func displayOffset(
        in block: Block,
        selection: MarkdownSelectionRange,
        selectionEnd: Int,
        edge: Edge,
        allowsBlockEdgeFallback: Bool
    ) -> Int? {
        let blockEnd = block.range.location + block.range.length
        let intersectionStart = max(selection.location, block.range.location)
        let intersectionEnd = min(selectionEnd, blockEnd)
        guard intersectionEnd > intersectionStart else { return nil }

        let localRange = MarkdownSelectionRange(
            location: intersectionStart - block.range.location,
            length: intersectionEnd - intersectionStart
        )

        if let displayRange = block.mapping.displayRange(forSourceRange: localRange) {
            return edge == .start ? displayRange.location : displayRange.location + displayRange.length
        }

        // The overlap covers only markdown that renders to nothing — a heading's
        // `#`, a code fence, a trailing blank line. For an interior end of a
        // multi-block selection the block edge is the right answer; for a
        // selection inside a single block there is nothing to show.
        guard allowsBlockEdgeFallback else { return nil }
        return edge == .start ? 0 : block.mapping.displayText.utf16.count
    }
}
