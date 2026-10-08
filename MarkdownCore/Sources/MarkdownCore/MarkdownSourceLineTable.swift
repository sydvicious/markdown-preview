//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

/// Where each line of a markdown source starts and ends, in UTF-16 offsets.
///
/// A line ends at a newline, a carriage return, or a carriage return followed
/// by a newline (CommonMark 2.1) — Unix, classic Mac and Windows files, or any
/// mixture of them in one file. `String.markdownLines` splits at the same
/// places; the parser numbers its lines with that and this table turns those
/// numbers back into offsets, so the two must never disagree.
public struct MarkdownSourceLineTable: Sendable {
    public let lineStartOffsets: [Int]
    /// Where each line's text ends, which is before its line ending.
    public let lineEndOffsets: [Int]
    public let sourceUTF16Length: Int

    public init(source: String) {
        let utf16 = Array(source.utf16)
        sourceUTF16Length = utf16.count

        let carriageReturn: UInt16 = 13
        let newline: UInt16 = 10

        var starts = [0]
        var ends: [Int] = []
        var index = 0
        while index < utf16.count {
            let codeUnit = utf16[index]
            if codeUnit == newline || codeUnit == carriageReturn {
                ends.append(index)
                // A carriage return and the newline after it are one ending.
                if codeUnit == carriageReturn, index + 1 < utf16.count, utf16[index + 1] == newline {
                    index += 1
                }
                starts.append(index + 1)
            }
            index += 1
        }
        ends.append(utf16.count)

        lineStartOffsets = starts
        lineEndOffsets = ends
    }

    /// The source range of `lineRange`: from the start of its first line to the
    /// end of its last line's text. Line endings between the lines are inside
    /// it; the one after the last line is not.
    public func range(for lineRange: Range<Int>) -> MarkdownSelectionRange? {
        guard !lineRange.isEmpty else { return nil }
        guard lineRange.lowerBound >= 0, lineRange.upperBound <= lineStartOffsets.count else { return nil }

        let start = lineStartOffsets[lineRange.lowerBound]
        let end = lineEndOffsets[lineRange.upperBound - 1]

        guard end >= start else { return nil }
        return MarkdownSelectionRange(location: start, length: end - start)
    }

    public func range(forLine line: Int) -> MarkdownSelectionRange? {
        range(for: line..<(line + 1))
    }
}

extension String {
    /// The lines of a markdown source, without their line endings, split where
    /// `MarkdownSourceLineTable` splits them. Each is a stretch of this string,
    /// so it still knows where in the source it is.
    ///
    /// In Swift a carriage return followed by a newline is a single
    /// `Character`, and it is not equal to `"\n"`. Splitting on `"\n"` alone
    /// therefore never splits a Windows file at all.
    ///
    /// The line endings are looked for a byte at a time. Both are ASCII, no
    /// byte of a longer character is, and a line ending is never part of a
    /// longer `Character` except the pair above. Comparing each `Character`
    /// of a document with three line endings was a seventh of the time it
    /// took to build a page.
    var markdownLineSlices: [Substring] {
        let carriageReturn = UInt8(ascii: "\r")
        let newline = UInt8(ascii: "\n")
        let bytes = utf8

        var slices: [Substring] = []
        var lineStart = bytes.startIndex
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            guard byte == newline || byte == carriageReturn else {
                index = bytes.index(after: index)
                continue
            }

            slices.append(self[lineStart..<index])
            index = bytes.index(after: index)
            // A carriage return and the newline after it are one ending.
            if byte == carriageReturn, index < bytes.endIndex, bytes[index] == newline {
                index = bytes.index(after: index)
            }
            lineStart = index
        }
        slices.append(self[lineStart..<bytes.endIndex])
        return slices
    }

    var markdownLines: [String] {
        markdownLineSlices.map(String.init)
    }
}
