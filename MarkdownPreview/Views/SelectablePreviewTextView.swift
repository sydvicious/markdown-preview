//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

#if os(iOS)
import UIKit

struct SelectablePreviewTextView: UIViewRepresentable {
    let attributedText: AttributedString
    let baseFont: UIFont
    var foregroundColor: UIColor = .label

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = renderedText()
        uiView.textColor = foregroundColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let fittingSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let measured = uiView.sizeThatFits(fittingSize)
        return CGSize(width: width, height: ceil(measured.height))
    }

    private func renderedText() -> NSAttributedString {
        let rendered = NSMutableAttributedString(attributedString: NSAttributedString(attributedText))
        let fullRange = NSRange(location: 0, length: rendered.length)

        guard rendered.length > 0 else { return rendered }

        rendered.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            if value == nil {
                rendered.addAttribute(.font, value: baseFont, range: range)
            }
        }
        rendered.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            if value == nil {
                rendered.addAttribute(.foregroundColor, value: foregroundColor, range: range)
            }
        }

        return rendered
    }
}

#Preview("Selectable Preview Text") {
    ScrollView {
        SelectablePreviewTextView(
            attributedText: {
                (try? AttributedString(markdown: "Preview **selection** with `inline code`.")) ?? AttributedString("Preview selection")
            }(),
            baseFont: UIFont.preferredFont(forTextStyle: .body)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}
#endif
