//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import SwiftUI
import MarkdownCore

#if os(iOS)
import UIKit

private final class MarkdownCopyTextView: UITextView {
    override func copy(_ sender: Any?) {
        let didWriteSelection = MarkdownSelectionClipboard.writeSelection(
            from: text ?? "",
            ranges: [MarkdownSelectionRange(selectedRange)]
        )
        guard !didWriteSelection else { return }
        super.copy(sender)
    }
}

private extension UITextView {
    /// How far down the text the top of what is showing is.
    private var topOfWhatIsShowing: CGFloat {
        contentOffset.y + adjustedContentInset.top
    }

    /// The offset into the text of the character at the top of what is
    /// showing.
    var characterOffsetAtTop: Int {
        guard topOfWhatIsShowing > textContainerInset.top else { return 0 }
        let point = CGPoint(x: textContainerInset.left + 1, y: topOfWhatIsShowing + 1)
        guard let position = closestPosition(to: point) else { return 0 }
        return offset(from: beginningOfDocument, to: position)
    }

    /// Scrolls so that the line the character at `offset` is on is at the top.
    func scrollToTop(characterAt offset: Int) {
        let length = (text ?? "").utf16.count
        guard let position = position(from: beginningOfDocument, offset: min(max(offset, 0), length)) else {
            return
        }
        layoutIfNeeded()
        let line = caretRect(for: position)
        guard line.minY.isFinite else { return }

        let highest = -adjustedContentInset.top
        let lowest = max(highest, contentSize.height - bounds.height + adjustedContentInset.bottom)
        let wanted = line.minY - textContainerInset.top - adjustedContentInset.top
        setContentOffset(CGPoint(x: contentOffset.x, y: min(max(wanted, highest), lowest)), animated: false)
    }
}

struct SelectableSourceTextView: UIViewRepresentable {
    let text: String
    /// Which document this is, and where the reader was in each. With both,
    /// the text opens at the place in the source they were at in the preview,
    /// and says where they go from there. With neither it opens at the top.
    var documentID: String? = nil
    var scrollMemory: PreviewScrollMemory? = nil
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]
    var onSearchSelection: (String) -> Void = { _ in }

    final class Coordinator: NSObject, UITextViewDelegate {
        var selections: Binding<[MarkdownSelectionRange]>
        var onSearchSelection: (String) -> Void
        var isApplyingSelection = false
        var documentID: String?
        var scrollMemory: PreviewScrollMemory?
        /// Counts the times the view has put the reader somewhere, so that a
        /// placing that a later one has overtaken does nothing more.
        var placings = 0

        /// Says where the reader is when it is the reader who moved. The view
        /// putting them somewhere is not that.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating,
                  let textView = scrollView as? UITextView else {
                return
            }
            scrollMemory?.rememberSourceOffset(textView.characterOffsetAtTop, in: documentID, by: .source)
        }

        init(selections: Binding<[MarkdownSelectionRange]>, onSearchSelection: @escaping (String) -> Void) {
            self.selections = selections
            self.onSearchSelection = onSearchSelection
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingSelection else { return }
            let range = textView.selectedRange
            let next = range.length > 0 ? [MarkdownSelectionRange(range)] : []
            if next != selections.wrappedValue {
                selections.wrappedValue = next
            }
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let nsText = (textView.text ?? "") as NSString
            guard range.length > 0,
                  range.location >= 0,
                  range.location + range.length <= nsText.length else {
                return nil
            }
            let selectedText = nsText.substring(with: range)
            let onSearch = onSearchSelection
            let searchAction = UIAction(
                title: "Search",
                image: UIImage(systemName: "magnifyingglass")
            ) { _ in
                onSearch(selectedText)
            }
            return UIMenu(children: suggestedActions + [searchAction])
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selections: $selections, onSearchSelection: onSearchSelection)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = MarkdownCopyTextView()
        view.delegate = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.font = Self.font(for: textSize)
        context.coordinator.isApplyingSelection = true
        view.text = text
        applySelection(to: view, from: selections, coordinator: context.coordinator)
        context.coordinator.isApplyingSelection = false
        context.coordinator.documentID = documentID
        context.coordinator.scrollMemory = scrollMemory
        placeReader(in: view, coordinator: context.coordinator, isAnotherDocument: false)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.selections = $selections
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.scrollMemory = scrollMemory
        let isAnotherDocument = context.coordinator.documentID != documentID
        context.coordinator.documentID = documentID
        if uiView.text != text {
            context.coordinator.isApplyingSelection = true
            uiView.text = text
            context.coordinator.isApplyingSelection = false
        }
        if isAnotherDocument {
            placeReader(in: uiView, coordinator: context.coordinator, isAnotherDocument: true)
        }
        if uiView.textColor != .label {
            uiView.textColor = .label
        }
        let desiredFont = Self.font(for: textSize)
        if uiView.font != desiredFont {
            uiView.font = desiredFont
        }
        applySelection(to: uiView, from: selections, coordinator: context.coordinator)
    }

    private static func font(for textSize: DynamicTypeSize) -> UIFont {
        UIFont.monospacedSystemFont(ofSize: 16 * textSize.scaleFactor, weight: .regular)
    }

    /// Puts the reader where they last were in this document, in either pane.
    /// A document they have not been in is left where a selection puts it, or
    /// at the top if the view was showing another.
    ///
    /// The text has no layout until the turn after it is set, and where a line
    /// is far down a long document is a guess until the text above it is laid
    /// out. So it is done on the next turn, and again on the one after.
    private func placeReader(in textView: UITextView, coordinator: Coordinator, isAnotherDocument: Bool) {
        coordinator.placings += 1
        let placing = coordinator.placings
        guard let offset = scrollMemory?.sourceOffset(for: documentID) else {
            if isAnotherDocument {
                textView.scrollToTop(characterAt: 0)
            }
            return
        }

        DispatchQueue.main.async {
            guard coordinator.placings == placing else { return }
            textView.scrollToTop(characterAt: offset)
            DispatchQueue.main.async {
                guard coordinator.placings == placing else { return }
                textView.scrollToTop(characterAt: offset)
            }
        }
    }

    private func applySelection(
        to textView: UITextView,
        from ranges: [MarkdownSelectionRange],
        coordinator: Coordinator
    ) {
        switch SourceSelectionUpdate.resolve(from: ranges, textUTF16Length: textView.text.utf16.count) {
        case let .clear(range):
            // An empty selection just clears the range; no need to claim focus.
            guard textView.selectedRange != range else { return }
            coordinator.isApplyingSelection = true
            textView.selectedRange = range
            coordinator.isApplyingSelection = false

        case let .select(range):
            guard textView.selectedRange != range else { return }
            // iOS only renders — and only lets you copy — a selection on the
            // first responder. A programmatic range on an unfocused text view is
            // invisible and unreachable by Cmd-C / the edit menu. So make the
            // view first responder and set the range, deferred to the next
            // runloop so this also works the moment the view is first added to
            // the window. The whole sequence runs inside isApplyingSelection so
            // the focus change can't fire textViewDidChangeSelection and clobber
            // the model with a collapsed range.
            DispatchQueue.main.async {
                guard textView.selectedRange != range else { return }
                coordinator.isApplyingSelection = true
                if !textView.isFirstResponder {
                    textView.becomeFirstResponder()
                }
                textView.selectedRange = range
                textView.scrollRangeToVisible(range)
                coordinator.isApplyingSelection = false
            }
        }
    }
}

#elseif os(macOS)
import AppKit

private final class MarkdownCopyTextView: NSTextView {
    /// Puts the keyboard in the document when nothing has a better claim on it.
    ///
    /// Without this, showing the source view leaves first responder on the
    /// app's inert focus sink, so Edit ▸ Copy has no target and ⌘C just beeps
    /// even with text selected — including a selection the search put there,
    /// which the user never clicked to create.
    ///
    /// A focused text field owns the window's field editor, itself an
    /// `NSTextView`, so seeing one means the user is typing somewhere on
    /// purpose — a search field — and focus is left alone.
    func takeFirstResponderIfUnclaimed() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            guard !(window.firstResponder is NSTextView) else { return }
            window.makeFirstResponder(self)
        }
    }

    override func copy(_ sender: Any?) {
        let ranges = selectedRanges.map(\.rangeValue).map(MarkdownSelectionRange.init)
        let didWriteSelection = MarkdownSelectionClipboard.writeSelection(
            from: string,
            ranges: ranges
        )
        guard !didWriteSelection else { return }
        super.copy(sender)
    }

    /// The offset into the text of the character at the top of what is
    /// showing.
    var characterOffsetAtTop: Int {
        let top = visibleRect.minY
        guard top > textContainerInset.height else { return 0 }
        return characterIndexForInsertion(at: NSPoint(x: textContainerInset.width + 1, y: top + 1))
    }

    /// Scrolls so that the line the character at `offset` is on is at the top.
    ///
    /// Where a line is on screen is asked of the text view as an input client
    /// would ask it, which is the same whichever text system the view is
    /// using. It needs the view to be in a window.
    func scrollToTop(characterAt offset: Int) {
        guard let window else { return }
        guard offset > 0 else {
            scroll(.zero)
            return
        }

        let length = (string as NSString).length
        let place = NSRange(location: min(offset, length), length: 0)
        let onScreen = firstRect(forCharacterRange: place, actualRange: nil)
        let inView = convert(window.convertFromScreen(onScreen), from: nil)
        guard inView.minY.isFinite else { return }
        scroll(NSPoint(x: 0, y: max(0, inView.minY - textContainerInset.height)))
    }
}

private final class WidthTrackingScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView else { return }

        let contentWidth = max(contentSize.width, 0)
        if textView.frame.width != contentWidth {
            textView.frame.size.width = contentWidth
        }

        if let textContainer = textView.textContainer {
            let desiredSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
            if textContainer.containerSize != desiredSize {
                textContainer.containerSize = desiredSize
            }
        }
    }
}

struct SelectableSourceTextView: NSViewRepresentable {
    let text: String
    /// Which document this is, and where the reader was in each. With both,
    /// the text opens at the place in the source they were at in the preview,
    /// and says where they go from there. With neither it opens at the top.
    var documentID: String? = nil
    var scrollMemory: PreviewScrollMemory? = nil
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]
    var onSearchSelection: (String) -> Void = { _ in }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var selections: Binding<[MarkdownSelectionRange]>
        var onSearchSelection: (String) -> Void
        var isApplyingSelection = false
        var documentID: String?
        var scrollMemory: PreviewScrollMemory?
        /// Set while the view is putting the reader somewhere, and while it is
        /// first laid out. What moves the text then is not the reader.
        var isPlacingReader = true
        /// Counts the times the view has put the reader somewhere, so that a
        /// placing that a later one has overtaken does nothing more.
        var placings = 0

        /// The text moved under its scroll view. If it was the reader who
        /// moved it, says where they are now.
        @objc func textDidScroll(_ notification: Notification) {
            guard !isPlacingReader,
                  let clipView = notification.object as? NSClipView,
                  let textView = clipView.documentView as? MarkdownCopyTextView else {
                return
            }
            scrollMemory?.rememberSourceOffset(textView.characterOffsetAtTop, in: documentID, by: .source)
        }

        init(selections: Binding<[MarkdownSelectionRange]>, onSearchSelection: @escaping (String) -> Void) {
            self.selections = selections
            self.onSearchSelection = onSearchSelection
        }

        func textDidChange(_ notification: Notification) {}

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingSelection else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let next = textView.selectedRanges.compactMap { value -> MarkdownSelectionRange? in
                let range = value.rangeValue
                return range.length > 0 ? MarkdownSelectionRange(range) : nil
            }
            if next != selections.wrappedValue {
                selections.wrappedValue = next
            }
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let selectedRange = view.selectedRange()
            let nsString = view.string as NSString
            guard selectedRange.length > 0,
                  selectedRange.location + selectedRange.length <= nsString.length else {
                return menu
            }
            let selectedText = nsString.substring(with: selectedRange)
            let item = NSMenuItem(
                title: "Search",
                action: #selector(searchSelectionMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = selectedText
            menu.addItem(.separator())
            menu.addItem(item)
            return menu
        }

        @objc private func searchSelectionMenuAction(_ sender: NSMenuItem) {
            guard let selectedText = sender.representedObject as? String else { return }
            onSearchSelection(selectedText)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selections: $selections, onSearchSelection: onSearchSelection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = WidthTrackingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = MarkdownCopyTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = Self.font(for: textSize)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        context.coordinator.isApplyingSelection = true
        textView.string = text

        scrollView.documentView = textView
        applySelection(to: textView, from: selections, coordinator: context.coordinator)
        context.coordinator.isApplyingSelection = false
        textView.takeFirstResponderIfUnclaimed()

        context.coordinator.documentID = documentID
        context.coordinator.scrollMemory = scrollMemory
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        placeReader(in: textView, coordinator: context.coordinator, isAnotherDocument: false)
        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.selections = $selections
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.scrollMemory = scrollMemory
        guard let textView = nsView.documentView as? MarkdownCopyTextView else { return }
        let isAnotherDocument = context.coordinator.documentID != documentID
        context.coordinator.documentID = documentID
        if textView.string != text {
            context.coordinator.isApplyingSelection = true
            textView.string = text
            context.coordinator.isApplyingSelection = false
        }
        if isAnotherDocument {
            placeReader(in: textView, coordinator: context.coordinator, isAnotherDocument: true)
        }
        let desiredFont = Self.font(for: textSize)
        if textView.font != desiredFont {
            textView.font = desiredFont
        }
        if let textContainer = textView.textContainer {
            let desiredSize = NSSize(width: nsView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            if textContainer.containerSize != desiredSize {
                textContainer.containerSize = desiredSize
            }
        }
        if textView.frame.width != nsView.contentSize.width {
            textView.frame.size.width = nsView.contentSize.width
        }
        applySelection(to: textView, from: selections, coordinator: context.coordinator)
    }

    private static func font(for textSize: DynamicTypeSize) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize * textSize.scaleFactor, weight: .regular)
    }

    /// Puts the reader where they last were in this document, in either pane.
    /// A document they have not been in is left where a selection puts it, or
    /// at the top if the view was showing another.
    ///
    /// The view has no window until the turn after it is made, and where a
    /// line is far down a long document is a guess until the text above it is
    /// laid out. So it is done on the next turn, and again on the one after.
    /// Until then nothing the text does is taken for the reader moving it.
    private func placeReader(in textView: MarkdownCopyTextView, coordinator: Coordinator, isAnotherDocument: Bool) {
        coordinator.placings += 1
        let placing = coordinator.placings
        coordinator.isPlacingReader = true

        let offset = scrollMemory?.sourceOffset(for: documentID)
        if offset == nil, isAnotherDocument {
            textView.scroll(.zero)
        }

        DispatchQueue.main.async {
            guard coordinator.placings == placing else { return }
            if let offset {
                textView.scrollToTop(characterAt: offset)
            }
            DispatchQueue.main.async {
                guard coordinator.placings == placing else { return }
                if let offset {
                    textView.scrollToTop(characterAt: offset)
                }
                coordinator.isPlacingReader = false
            }
        }
    }

    private func applySelection(
        to textView: NSTextView,
        from ranges: [MarkdownSelectionRange],
        coordinator: Coordinator
    ) {
        let textLength = textView.string.utf16.count
        var nsRanges = ranges.compactMap { $0.clamped(toUTF16Length: textLength)?.nsRange }
        if nsRanges.isEmpty {
            nsRanges = [NSRange(location: 0, length: 0)]
        }
        let current = textView.selectedRanges.compactMap { $0 as? NSRange }
        guard current != nsRanges else { return }
        coordinator.isApplyingSelection = true
        textView.selectedRanges = nsRanges.map(NSValue.init(range:))
        if let firstRange = nsRanges.first {
            textView.scrollRangeToVisible(firstRange)
        }
        coordinator.isApplyingSelection = false
    }
}
#endif

#if DEBUG
#Preview("Selectable Source Text") {
    SelectableSourceTextView(
        text: MarkdownPreviewFixtures.excerptFile.contents,
        textSize: .large,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 18)])
    )
}
#endif
