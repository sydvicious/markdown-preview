//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

#if os(iOS)
import UIKit

struct SelectableSourceTextView: UIViewRepresentable {
    let text: String
    @Binding var selections: [MarkdownSelectionRange]

    final class Coordinator: NSObject, UITextViewDelegate {
        var selections: Binding<[MarkdownSelectionRange]>
        var isApplyingSelection = false

        init(selections: Binding<[MarkdownSelectionRange]>) {
            self.selections = selections
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingSelection else { return }
            let range = textView.selectedRange
            let next = range.length > 0 ? [MarkdownSelectionRange(range)] : []
            if next != selections.wrappedValue {
                selections.wrappedValue = next
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selections: $selections)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        view.alwaysBounceVertical = true
        view.backgroundColor = .clear
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        )
        context.coordinator.isApplyingSelection = true
        view.text = text
        applySelection(to: view, from: selections, coordinator: context.coordinator)
        context.coordinator.isApplyingSelection = false
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.selections = $selections
        if uiView.text != text {
            context.coordinator.isApplyingSelection = true
            uiView.text = text
            context.coordinator.isApplyingSelection = false
        }
        if uiView.textColor != .label {
            uiView.textColor = .label
        }
        applySelection(to: uiView, from: selections, coordinator: context.coordinator)
    }

    private func applySelection(
        to textView: UITextView,
        from ranges: [MarkdownSelectionRange],
        coordinator: Coordinator
    ) {
        // Don't fight native selection gestures while user is editing selection.
        if textView.isFirstResponder { return }
        guard let desired = ranges.first else { return }
        let textLength = textView.text.utf16.count
        let next = desired.clamped(toUTF16Length: textLength)?.nsRange ?? NSRange(location: 0, length: 0)
        guard textView.selectedRange != next else { return }
        coordinator.isApplyingSelection = true
        textView.selectedRange = next
        coordinator.isApplyingSelection = false
    }
}

#elseif os(macOS)
import AppKit

struct SelectableSourceTextView: NSViewRepresentable {
    let text: String
    @Binding var selections: [MarkdownSelectionRange]

    final class Coordinator: NSObject, NSTextViewDelegate {
        var selections: Binding<[MarkdownSelectionRange]>
        var isApplyingSelection = false

        init(selections: Binding<[MarkdownSelectionRange]>) {
            self.selections = selections
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selections: $selections)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
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
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            context.coordinator.isApplyingSelection = true
            textView.string = text
            context.coordinator.isApplyingSelection = false
        }
        applySelection(to: textView, from: selections, coordinator: context.coordinator)
    }

    private func applySelection(
        to textView: NSTextView,
        from ranges: [MarkdownSelectionRange],
        coordinator: Coordinator
    ) {
        // Avoid resetting selection while the text view is actively focused.
        if textView.window?.firstResponder === textView { return }
        let textLength = textView.string.utf16.count
        var nsRanges = ranges.compactMap { $0.clamped(toUTF16Length: textLength)?.nsRange }
        if nsRanges.isEmpty {
            nsRanges = [NSRange(location: 0, length: 0)]
        }
        let current = textView.selectedRanges.compactMap { $0 as? NSRange }
        guard current != nsRanges else { return }
        coordinator.isApplyingSelection = true
        textView.selectedRanges = nsRanges.map(NSValue.init(range:))
        coordinator.isApplyingSelection = false
    }
}
#endif

#Preview("Selectable Source Text") {
    SelectableSourceTextView(
        text: MarkdownPreviewFixtures.excerptFile.contents,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 18)])
    )
}
