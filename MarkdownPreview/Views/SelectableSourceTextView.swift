//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

/// The selection update the iOS source text view should apply for a given model
/// selection. Factored out of `applySelection` so the empty-vs-non-empty
/// decision — which drives whether the text view must claim first responder — is
/// unit-testable without standing up UIKit.
enum SourceSelectionUpdate: Equatable {
    /// A real, copyable selection. The text view must be first responder for iOS
    /// to render it and for Cmd-C / the edit menu to reach it.
    case select(NSRange)
    /// No selection; collapse the caret without claiming focus.
    case clear(NSRange)

    static func resolve(from ranges: [MarkdownSelectionRange], textUTF16Length: Int) -> SourceSelectionUpdate {
        let next = ranges.first?.clamped(toUTF16Length: textUTF16Length)?.nsRange
            ?? NSRange(location: 0, length: 0)
        return next.length > 0 ? .select(next) : .clear(next)
    }
}

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

struct SelectableSourceTextView: UIViewRepresentable {
    let text: String
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]
    var onSearchSelection: (String) -> Void = { _ in }

    final class Coordinator: NSObject, UITextViewDelegate {
        var selections: Binding<[MarkdownSelectionRange]>
        var onSearchSelection: (String) -> Void
        var isApplyingSelection = false

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
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.selections = $selections
        context.coordinator.onSearchSelection = onSearchSelection
        if uiView.text != text {
            context.coordinator.isApplyingSelection = true
            uiView.text = text
            context.coordinator.isApplyingSelection = false
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
    override func copy(_ sender: Any?) {
        let ranges = selectedRanges.map(\.rangeValue).map(MarkdownSelectionRange.init)
        let didWriteSelection = MarkdownSelectionClipboard.writeSelection(
            from: string,
            ranges: ranges
        )
        guard !didWriteSelection else { return }
        super.copy(sender)
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
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]
    var onSearchSelection: (String) -> Void = { _ in }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var selections: Binding<[MarkdownSelectionRange]>
        var onSearchSelection: (String) -> Void
        var isApplyingSelection = false

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
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.selections = $selections
        context.coordinator.onSearchSelection = onSearchSelection
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            context.coordinator.isApplyingSelection = true
            textView.string = text
            context.coordinator.isApplyingSelection = false
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
