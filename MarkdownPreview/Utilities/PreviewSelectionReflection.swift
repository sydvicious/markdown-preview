//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

struct PreviewReflectedSelection: Equatable {
    let blockStart: Int
    let blockEnd: Int
    let displayRange: MarkdownSelectionRange
}

enum PreviewSelectionReflection {
    static func reflectedSelection(
        in source: String,
        selectedRange: MarkdownSelectionRange?
    ) -> PreviewReflectedSelection? {
        guard let clampedRange = selectedRange?.clamped(toUTF16Length: source.utf16.count),
              clampedRange.length > 0 else {
            return nil
        }

        let sourceLineTable = MarkdownSourceLineTable(source: source)
        let selectionEnd = clampedRange.location + clampedRange.length
        guard let reflectedBlock = MarkdownBlockParser.parse(source).compactMap({ block -> PreviewReflectedSelection? in
            guard let blockRange = sourceLineTable.range(for: block.lineRange) else { return nil }
            let blockEnd = blockRange.location + blockRange.length
            guard clampedRange.location >= blockRange.location, selectionEnd <= blockEnd else { return nil }
            let localSourceRange = MarkdownSelectionRange(
                location: clampedRange.location - blockRange.location,
                length: clampedRange.length
            )
            let blockSource = (source as NSString).substring(with: blockRange.nsRange)
            let previewMapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource)
            guard let displayRange = previewMapping.displayRange(forSourceRange: localSourceRange),
                  displayRange.length > 0 else {
                return nil
            }

            return PreviewReflectedSelection(
                blockStart: blockRange.location,
                blockEnd: blockEnd,
                displayRange: displayRange
            )
        }).first else {
            return nil
        }

        return reflectedBlock
    }
}
