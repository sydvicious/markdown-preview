//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

struct TextOffsetRun: Equatable {
    let sourceRange: MarkdownSelectionRange
    let displayRange: MarkdownSelectionRange
}

protocol TextOffsetMapping {
    var sourceText: String { get }
    var displayText: String { get }
    var runs: [TextOffsetRun] { get }

    func displayRange(forSourceRange sourceRange: MarkdownSelectionRange) -> MarkdownSelectionRange?
    func sourceRange(forDisplayRange displayRange: MarkdownSelectionRange) -> MarkdownSelectionRange?
}

extension TextOffsetMapping {
    func displayRange(forSourceRange sourceRange: MarkdownSelectionRange) -> MarkdownSelectionRange? {
        mappedRange(
            sourceRange,
            in: \.sourceRange,
            to: \.displayRange,
            sourceLength: sourceText.utf16.count
        )
    }

    func sourceRange(forDisplayRange displayRange: MarkdownSelectionRange) -> MarkdownSelectionRange? {
        mappedRange(
            displayRange,
            in: \.displayRange,
            to: \.sourceRange,
            sourceLength: displayText.utf16.count
        )
    }

    private func mappedRange(
        _ range: MarkdownSelectionRange,
        in fromKeyPath: KeyPath<TextOffsetRun, MarkdownSelectionRange>,
        to toKeyPath: KeyPath<TextOffsetRun, MarkdownSelectionRange>,
        sourceLength: Int
    ) -> MarkdownSelectionRange? {
        guard let clamped = range.clamped(toUTF16Length: sourceLength), clamped.length > 0 else {
            return nil
        }

        let end = clamped.location + clamped.length
        let overlappingRuns = runs.filter { run in
            let runRange = run[keyPath: fromKeyPath]
            let runEnd = runRange.location + runRange.length
            return clamped.location < runEnd && end > runRange.location
        }

        guard let firstRun = overlappingRuns.first, let lastRun = overlappingRuns.last else {
            return nil
        }

        let mappedStart = mappedOffset(
            clamped.location,
            within: firstRun[keyPath: fromKeyPath],
            target: firstRun[keyPath: toKeyPath],
            biasTowardEnd: false
        )
        let mappedEnd = mappedOffset(
            end,
            within: lastRun[keyPath: fromKeyPath],
            target: lastRun[keyPath: toKeyPath],
            biasTowardEnd: true
        )

        guard mappedEnd >= mappedStart else { return nil }
        return MarkdownSelectionRange(location: mappedStart, length: mappedEnd - mappedStart)
    }

    private func mappedOffset(
        _ offset: Int,
        within sourceRange: MarkdownSelectionRange,
        target targetRange: MarkdownSelectionRange,
        biasTowardEnd: Bool
    ) -> Int {
        let sourceStart = sourceRange.location
        let sourceEnd = sourceRange.location + sourceRange.length
        let clampedOffset = min(max(offset, sourceStart), sourceEnd)

        guard sourceRange.length > 0 else {
            return targetRange.location
        }

        if sourceRange.length == targetRange.length {
            return targetRange.location + (clampedOffset - sourceStart)
        }

        guard targetRange.length > 0 else {
            return targetRange.location
        }

        let relative = clampedOffset - sourceStart
        if relative <= 0 {
            return targetRange.location
        }
        if relative >= sourceRange.length {
            return targetRange.location + targetRange.length
        }

        if targetRange.length == 1 {
            return targetRange.location + (biasTowardEnd ? 1 : 0)
        }

        let scaled = Int((Double(relative) / Double(sourceRange.length)) * Double(targetRange.length))
        return targetRange.location + min(max(scaled, 0), targetRange.length)
    }
}
