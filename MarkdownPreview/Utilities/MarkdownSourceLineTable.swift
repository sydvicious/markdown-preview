//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

struct MarkdownSourceLineTable {
    let lineStartOffsets: [Int]
    let sourceUTF16Length: Int

    init(source: String) {
        let utf16 = Array(source.utf16)
        sourceUTF16Length = utf16.count

        var starts = [0]
        starts.reserveCapacity(utf16.filter { $0 == 10 }.count + 1)
        for (index, codeUnit) in utf16.enumerated() where codeUnit == 10 {
            starts.append(index + 1)
        }
        lineStartOffsets = starts
    }

    func range(for lineRange: Range<Int>) -> MarkdownSelectionRange? {
        guard !lineRange.isEmpty else { return nil }
        guard lineRange.lowerBound >= 0, lineRange.upperBound <= lineStartOffsets.count else { return nil }

        let start = lineStartOffsets[lineRange.lowerBound]
        let end: Int
        if lineRange.upperBound < lineStartOffsets.count {
            end = max(start, lineStartOffsets[lineRange.upperBound] - 1)
        } else {
            end = sourceUTF16Length
        }

        guard end >= start else { return nil }
        return MarkdownSelectionRange(location: start, length: end - start)
    }

    func range(forLine line: Int) -> MarkdownSelectionRange? {
        range(for: line..<(line + 1))
    }
}
