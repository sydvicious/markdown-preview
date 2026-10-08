//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//
//  What the app and the preview's page say to each other: the calls into the
//  page's scripts, the messages the page posts back, and the arithmetic on
//  both. None of it needs a web view, which is why it is not in
//  `MarkdownPreviewWebView.swift` with the view that uses it.
//

import Foundation
import MarkdownCore

/// The calls the app makes into the preview's scripts.
///
/// The scripts themselves are files, in the `Web` folder beside `Views`, loaded
/// through `MarkdownWebResources` and installed as user scripts. What is left in
/// Swift is the calling of them: each of these invokes a function a script
/// defined on `window.markdownPreview`, and comes back with nothing, rather than
/// throwing, on a page whose scripts have not run yet.
enum PreviewScriptCall {
    /// The selection as text and display ranges, falling back to the last one
    /// that was not empty.
    static let selectionSnapshot = "window.markdownPreview?.selectionSnapshot?.() ?? null"

    /// The selection as ranges of each block's rendered text.
    static let selectedDisplayRanges = "window.markdownPreview?.selectedDisplayRanges?.() ?? null"

    /// The selection as HTML, for rich-text copy.
    static let selectedHTML = "window.markdownPreview?.selectedHTML?.() ?? null"

    /// Where the reader is, as `PreviewScrollPosition` reads it.
    static let scrollPosition = "window.markdownPreview?.scrollPosition?.() ?? null"

    /// Selects the span between two positions, each a block's source offsets
    /// and an offset into its rendered text. Six nulls clear the selection.
    static func applySelection(_ arguments: String) -> String {
        "window.markdownPreview?.applySelection?.(\(arguments))"
    }

    static func scrollToOffset(x: Double, y: Double) -> String {
        "window.markdownPreview?.scrollToOffset?.(\(x), \(y));"
    }

    static func scrollToFraction(x: Double, ofMaxY fraction: Double) -> String {
        "window.markdownPreview?.scrollToFraction?.(\(x), \(fraction));"
    }

    /// Scrolls to a place in the source: the block that shows it, and as far
    /// down that block as the place is through the block's source.
    static func scrollToSourceOffset(_ offset: Int) -> String {
        "window.markdownPreview?.scrollToSourceOffset?.(\(offset));"
    }
}

/// What of the source is at the top of the page, as the page reports it: an
/// offset into the source, in UTF-16 units.
struct PreviewSourceOffsetMessage: Equatable {
    var offset: Int

    init?(messageBody: Any) {
        guard let number = messageBody as? NSNumber,
              number.doubleValue.isFinite,
              number.doubleValue >= 0 else {
            return nil
        }
        offset = Int(number.doubleValue)
    }
}

struct PreviewDisplaySelectionRange: Equatable {
    var blockStart: Int
    var blockEnd: Int
    var displayLocation: Int
    var displayLength: Int
    /// Whether the selection goes on after this text into something else: the
    /// next block, or the next item of a list. One made by clicking three
    /// times on a line does, and has taken the line's ending with it; one
    /// dragged to the end of the line stops with the text.
    var continuesPastText = false
}

struct PreviewCopyBlockMessage: Equatable {
    var start: Int
    var end: Int
    /// What kind of block the range covers, so the handler can strip syntax that
    /// is decoration rather than content. Nil when the page predates the
    /// attribute or the value is unrecognized; the raw source is copied then.
    var kind: MarkdownCopyableBlockKind?

    init(start: Int, end: Int, kind: MarkdownCopyableBlockKind? = nil) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    init?(messageBody: Any) {
        guard let payload = messageBody as? [String: Any],
              let start = payload["start"] as? NSNumber,
              let end = payload["end"] as? NSNumber else {
            return nil
        }

        let startValue = start.intValue
        let endValue = end.intValue
        guard startValue >= 0, endValue > startValue else { return nil }

        self.start = startValue
        self.end = endValue
        self.kind = (payload["kind"] as? String).flatMap(MarkdownCopyableBlockKind.init(rawValue:))
    }
}

/// Where the reader is in the preview, as the page reports it.
struct PreviewScrollPosition: Equatable {
    var x: Double
    var y: Double
    /// How far down the page can scroll. Zero when the whole page fits.
    var maxY: Double

    init(x: Double, y: Double, maxY: Double) {
        self.x = x
        self.y = y
        self.maxY = maxY
    }

    /// Reads the `[x, y, maxY]` the page posts. Rubber-banding reports offsets
    /// past either end of the page, which are not places, so they are clamped.
    init?(messageBody: Any) {
        guard let values = (messageBody as? [NSNumber])?.map(\.doubleValue),
              values.count == 3,
              values.allSatisfy(\.isFinite) else {
            return nil
        }

        let maxY = max(0, values[2])
        self.x = max(0, values[0])
        self.y = min(max(0, values[1]), maxY)
        self.maxY = maxY
    }
}

/// Keeps the reader's place when the preview reloads.
///
/// The preview reloads the whole page whenever its HTML changes, and a reload
/// starts at the top. When the change is to the document already on screen — it
/// was edited on disk, the text size changed, a folder was granted for its
/// images — the reader should be left where they were. Reading a long plan
/// while it is being edited is the case that matters most.
enum PreviewScrollRestoration {
    /// What the preview is showing: which document, and its text.
    struct Content: Equatable {
        var documentID: String?
        var source: String
    }

    /// Where a freshly loaded page should be scrolled to.
    enum Restoration: Equatable {
        /// Leave it where a load puts it.
        case top
        /// The same distance down the page as before.
        case offset(x: Double, y: Double)
        /// The same way down the page as before, as a share of how far it scrolls.
        case fraction(x: Double, ofMaxY: Double)
        /// At a place in the source, which is where the reader was in the
        /// source pane.
        case sourceOffset(Int)

        /// The script that carries it out, or nil when there is nothing to do.
        var script: String? {
            switch self {
            case .top:
                return nil
            case let .offset(x, y):
                return PreviewScriptCall.scrollToOffset(x: x, y: y)
            case let .fraction(x, fraction):
                return PreviewScriptCall.scrollToFraction(x: x, ofMaxY: fraction)
            case let .sourceOffset(offset):
                return PreviewScriptCall.scrollToSourceOffset(offset)
            }
        }
    }

    /// Where to put the reader once `current` has replaced `previous`, given
    /// where they were.
    ///
    /// Only a reload of the same document keeps the place; anything else is a
    /// different page and starts at the top. If the text changed, the offset is
    /// kept, which stays true for everything above the edit. If the text is the
    /// same and only its drawing changed, the height did, so the same offset
    /// would land somewhere else and the proportion is kept instead.
    static func restoration(
        of position: PreviewScrollPosition?,
        from previous: Content?,
        to current: Content
    ) -> Restoration {
        guard let position,
              let documentID = current.documentID,
              previous?.documentID == documentID else {
            return .top
        }
        guard position.x > 0 || position.y > 0 else { return .top }

        if previous?.source == current.source, position.maxY > 0 {
            return .fraction(x: position.x, ofMaxY: position.y / position.maxY)
        }
        return .offset(x: position.x, y: position.y)
    }
}

/// Where the reader was in each document, for as long as the app is running.
///
/// The preview has one page, and loading another document's into it starts at
/// the top. So that going to another document and back leaves the reader where
/// they were, the place each page reports is kept here under its document,
/// with the text it was reported for.
///
/// The source pane shows the same document, and is opened where the reader
/// was in the preview, as the preview is where they were in the source. What
/// the two have in common is the source, so a place is also kept as an offset
/// into it: the page reports the one at the top of its window, and the source
/// pane the one at the top of its text.
///
/// Nothing of it is saved. A document opened in a later launch starts at the
/// top.
final class PreviewScrollMemory {
    /// The pane a place in the source was reported by.
    enum Pane {
        case preview
        case source
    }

    private struct Place {
        /// Where the reader was in the preview's page, to the pixel.
        var inPreview: (position: PreviewScrollPosition, content: PreviewScrollRestoration.Content)?
        /// What of the source was at the top of the pane they were last in.
        var sourceOffset: Int?
        /// The reader last moved in the source pane, so where the preview was
        /// is no longer where they are.
        var movedInSourceLast = false
    }

    private var places: [String: Place] = [:]

    /// Notes where the reader is in the preview of `content`. A page that is
    /// no document, as in a SwiftUI preview, is not remembered.
    func remember(_ position: PreviewScrollPosition, in content: PreviewScrollRestoration.Content) {
        guard let documentID = content.documentID else { return }
        places[documentID, default: Place()].inPreview = (position, content)
        places[documentID]?.movedInSourceLast = false
    }

    /// Notes what of the document's source is at the top of `pane`.
    func rememberSourceOffset(_ offset: Int, in documentID: String?, by pane: Pane) {
        guard let documentID, offset >= 0 else { return }
        places[documentID, default: Place()].sourceOffset = offset
        if pane == .source {
            places[documentID]?.movedInSourceLast = true
        }
    }

    /// What of the document's source the reader was last at, in either pane.
    /// The source pane opens there.
    func sourceOffset(for documentID: String?) -> Int? {
        guard let documentID else { return nil }
        return places[documentID]?.sourceOffset
    }

    /// Where to put the reader in a page of `content` that is about to load.
    ///
    /// If they last moved in the source pane, at that place in the source.
    /// Otherwise where they last were in this document's page, by the rule
    /// that keeps their place when a document on screen is redrawn: the offset
    /// if its text has changed since, the same way down the page if it has
    /// not. The top if they have not been in the document at all.
    func restoration(for content: PreviewScrollRestoration.Content) -> PreviewScrollRestoration.Restoration {
        guard let documentID = content.documentID, let place = places[documentID] else { return .top }
        if place.movedInSourceLast, let sourceOffset = place.sourceOffset {
            return sourceOffset > 0 ? .sourceOffset(sourceOffset) : .top
        }
        guard let inPreview = place.inPreview else { return .top }
        return PreviewScrollRestoration.restoration(of: inPreview.position, from: inPreview.content, to: content)
    }

    func forget(documentID: String) {
        places.removeValue(forKey: documentID)
    }
}

struct PreviewSelectionChangedMessage {
    var selectedText: String?
    var displayRangeResult: Any?

    init(messageBody: Any) {
        let payload = messageBody as? [String: Any]
        let selectedText = (payload?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedText = selectedText?.isEmpty == false ? selectedText : nil
        displayRangeResult = payload?["ranges"]
    }
}

enum PreviewSelectionBridge {
    /// The preview's current selection as a single source range, or none.
    ///
    /// A selection is a source text offset and a length — one contiguous span
    /// that both views know how to render. The preview reports its DOM selection
    /// as one range per visible run of text, which is a rendering detail, so it
    /// is collapsed here rather than leaking into the selection model.
    static func contiguousSelectionRanges(
        fromDisplayRangeResult result: Any?,
        source: String
    ) -> [MarkdownSelectionRange] {
        let mapped = mappedRanges(fromDisplayRangeResult: result, source: source)
        guard let enclosing = enclosingRange(of: mapped.map(\.range)) else { return [] }
        return [startingWithItsLine(enclosing, spanning: mapped, in: source as NSString)]
    }

    /// `enclosing` from the start of its first line, if what was selected is
    /// whole lines: nothing the reader can see comes before it on its first
    /// line, and it ends with a line.
    ///
    /// What is written before the first word of a line is the `#` of a
    /// heading, the marker of a list item or a quote. A line clicked three
    /// times is selected as a line, and is copied as one, the way it is from
    /// the source view. Words dragged over from the start of a line to the
    /// middle of one are still only those words.
    private static func startingWithItsLine(
        _ enclosing: MarkdownSelectionRange,
        spanning mapped: [MappedRange],
        in source: NSString
    ) -> MarkdownSelectionRange {
        guard let first = mapped.min(by: { $0.range.location < $1.range.location }),
              let last = mapped.max(by: { $0.range.location + $0.range.length < $1.range.location + $1.range.length }),
              first.isFirstOnItsLine else {
            return enclosing
        }

        // The last line of the source may have no ending, and is a line all
        // the same; what says so is that the selection went on past it.
        let end = enclosing.location + enclosing.length
        guard last.takesTheEndOfItsLine || source.startOfLine(containing: end) == end else {
            return enclosing
        }

        let lineStart = source.startOfLine(containing: enclosing.location)
        return MarkdownSelectionRange(location: lineStart, length: end - lineStart)
    }

    /// The single source range spanning `ranges`, from the earliest start to the
    /// latest end.
    ///
    /// A DOM selection is contiguous, but it maps back to one source range per
    /// visible run of text — the markdown syntax between them falls in the gaps.
    /// Stitching those pieces together produced plain text with every `#`, link
    /// target and blank line missing. Spanning them instead yields the raw
    /// markdown the user actually swept over.
    static func enclosingRange(of ranges: [MarkdownSelectionRange]) -> MarkdownSelectionRange? {
        guard let start = ranges.map(\.location).min(),
              let end = ranges.map({ $0.location + $0.length }).max(),
              end > start else {
            return nil
        }
        return MarkdownSelectionRange(location: start, length: end - start)
    }

    /// Whether an incoming selection is the echo of one the preview itself just
    /// reported, and so should not be pushed back into the web view.
    ///
    /// The stored range must actually exist for this to be an echo. Comparing
    /// the two optionals directly made `nil == nil` report "echo", so every
    /// transition to *no selection* was suppressed and the web view kept its old
    /// highlight — visible when a search match stopped matching as the user
    /// typed another character, and the stale match stayed highlighted.
    static func isEcho(
        ofPreviewOriginated previewOriginatedRange: MarkdownSelectionRange?,
        incoming selectedRange: MarkdownSelectionRange?
    ) -> Bool {
        guard let previewOriginatedRange else { return false }
        return previewOriginatedRange == selectedRange
    }

    static func sourceRanges(fromDisplayRangeResult result: Any?, source: String) -> [MarkdownSelectionRange] {
        mappedRanges(fromDisplayRangeResult: result, source: source).map(\.range)
    }

    /// A range of a block's rendered text, as the stretch of source it shows.
    private struct MappedRange {
        var range: MarkdownSelectionRange
        /// Nothing the reader can see comes before it on its line.
        var isFirstOnItsLine: Bool
        /// The selection went on past it, and nothing the reader can see comes
        /// after it on its line.
        var takesTheEndOfItsLine: Bool
    }

    private static func mappedRanges(fromDisplayRangeResult result: Any?, source: String) -> [MappedRange] {
        let displayRanges = displayRanges(from: result)
        guard !displayRanges.isEmpty else { return [] }

        let nsSource = source as NSString
        let sourceLength = nsSource.length
        // Each block is read on its own, but a reference in it is a link only
        // by a definition elsewhere in the document.
        let definitions = MarkdownLinkDefinitions(source: source)
        return displayRanges.compactMap { displayRange -> MappedRange? in
            guard displayRange.blockStart >= 0,
                  displayRange.blockEnd <= sourceLength,
                  displayRange.blockEnd > displayRange.blockStart else {
                return nil
            }

            let blockRange = NSRange(
                location: displayRange.blockStart,
                length: displayRange.blockEnd - displayRange.blockStart
            )
            let blockSource = nsSource.substring(with: blockRange) as NSString
            let mapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource as String, definitions: definitions)
            let localDisplayRange = MarkdownSelectionRange(
                location: displayRange.displayLocation,
                length: displayRange.displayLength
            )
            guard let localSourceRange = mapping.sourceRange(forDisplayRange: localDisplayRange),
                  localSourceRange.length > 0 else {
                return nil
            }

            // A block starts where a line does, so a line of the block is a
            // line of the source.
            let localStart = localSourceRange.location
            let localEnd = localStart + localSourceRange.length
            let shown = mapping.runs.filter { $0.displayRange.length > 0 }.map(\.sourceRange)
            func showsAnything(from lower: Int, to upper: Int) -> Bool {
                shown.contains { $0.location < upper && $0.location + $0.length > lower }
            }

            let start = displayRange.blockStart + localStart
            var end = displayRange.blockStart + localEnd
            let takesTheEndOfItsLine = displayRange.continuesPastText
                && !showsAnything(from: localEnd, to: blockSource.endOfLineText(from: localEnd))
            // What is written between the last thing the reader can see and
            // the end of the line, the `**` that closes bold or the address of
            // a link, is on the line too, so it comes along with the ending.
            //
            // An end already at the start of a line stays where it is. The
            // text of a code block ends with a line ending of its own, and the
            // line after it is the closing fence.
            if takesTheEndOfItsLine, nsSource.startOfLine(containing: end) != end {
                end = nsSource.startOfLine(after: end) ?? sourceLength
            }

            return MappedRange(
                range: MarkdownSelectionRange(location: start, length: end - start),
                isFirstOnItsLine: !showsAnything(from: blockSource.startOfLine(containing: localStart), to: localStart),
                takesTheEndOfItsLine: takesTheEndOfItsLine
            )
        }
    }

    static func displayRanges(from result: Any?) -> [PreviewDisplaySelectionRange] {
        guard let dictionaries = result as? [[String: Any]] else { return [] }
        return dictionaries.compactMap { dictionary -> PreviewDisplaySelectionRange? in
            guard let blockStart = dictionary["blockStart"] as? NSNumber,
                  let blockEnd = dictionary["blockEnd"] as? NSNumber,
                  let displayLocation = dictionary["displayLocation"] as? NSNumber,
                  let displayLength = dictionary["displayLength"] as? NSNumber else {
                return nil
            }
            let blockStartValue = blockStart.intValue
            let blockEndValue = blockEnd.intValue
            let displayLocationValue = displayLocation.intValue
            let displayLengthValue = displayLength.intValue
            guard blockEndValue > blockStartValue,
                  displayLocationValue >= 0,
                  displayLengthValue > 0 else {
                return nil
            }
            return PreviewDisplaySelectionRange(
                blockStart: blockStartValue,
                blockEnd: blockEndValue,
                displayLocation: displayLocationValue,
                displayLength: displayLengthValue,
                // Left out by the page when the selection stays in the block.
                continuesPastText: (dictionary["continuesPastText"] as? Bool) ?? false
            )
        }
    }
}

/// Lines as markdown has them: ended by a newline, a carriage return, or a
/// carriage return and the newline after it, as `MarkdownSourceLineTable`
/// splits them. These look only as far as the line they are asked about, where
/// the table reads the whole source.
private extension NSString {
    private func isLineEnding(at index: Int) -> Bool {
        let codeUnit = character(at: index)
        return codeUnit == 10 || codeUnit == 13
    }

    /// Where the line that holds `offset` starts.
    func startOfLine(containing offset: Int) -> Int {
        var index = Swift.min(Swift.max(offset, 0), length)
        while index > 0, !isLineEnding(at: index - 1) {
            index -= 1
        }
        return index
    }

    /// Where the text of the line that holds `offset` ends, which is before
    /// its line ending.
    func endOfLineText(from offset: Int) -> Int {
        var index = Swift.min(Swift.max(offset, 0), length)
        while index < length, !isLineEnding(at: index) {
            index += 1
        }
        return index
    }

    /// Where the line after the one that holds `offset` starts, or nil if
    /// that line is the last and has no ending.
    func startOfLine(after offset: Int) -> Int? {
        let ending = endOfLineText(from: offset)
        guard ending < length else { return nil }
        let isCarriageReturnAndNewline = character(at: ending) == 13
            && ending + 1 < length
            && character(at: ending + 1) == 10
        return ending + (isCarriageReturnAndNewline ? 2 : 1)
    }
}
