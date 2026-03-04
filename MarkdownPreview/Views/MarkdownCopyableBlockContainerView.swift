//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MarkdownCopyableBlockContainerView<Content: View>: View {
    let onCopy: () -> Void
    var scrollContentHorizontally: Bool = false
    @ViewBuilder let content: Content

    private let cornerRadius: CGFloat = 10
    private let contentPadding: CGFloat = 10

    var body: some View {
        baseContainer {
            if scrollContentHorizontally {
                ScrollView(.horizontal, showsIndicators: true) {
                    content
                        .frame(alignment: .leading)
                }
            } else {
                content
            }
        }
    }

    private func baseContainer<Inner: View>(@ViewBuilder inner: () -> Inner) -> some View {
        VStack(spacing: 0) {
            copyToolbar

            inner()
                .padding(contentPadding)
                .frame(alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var copyToolbar: some View {
        HStack {
            Spacer()
            Button {
                onCopy()
            } label: {
                HStack(spacing: 4) {
                    Text("Copy")
                    Image(systemName: "doc.on.doc")
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy")
        }
        .padding(.horizontal, contentPadding)
        .padding(.vertical, 6)
        .background(headerBackgroundColor)
    }

    private var backgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var headerBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlColor)
        #else
        Color(uiColor: .tertiarySystemFill)
        #endif
    }
}

#Preview("Copyable Block - Quote") {
    ScrollView {
        MarkdownCopyableBlockContainerView(onCopy: {}) {
            MarkdownBlockQuoteView(
                text: AttributedString("Quoted text with `inline code`.")
            )
        }
        .padding(20)
    }
}

#Preview("Copyable Block - Table") {
    ScrollView {
        MarkdownCopyableBlockContainerView(onCopy: {}, scrollContentHorizontally: true) {
            MarkdownTableBlockView(
                table: MarkdownPreviewFixtures.table,
                showChrome: false,
                wrapsInHorizontalScroll: false
            )
        }
        .padding(20)
    }
}

#Preview("Copyable Block - Code") {
    ScrollView {
        MarkdownCopyableBlockContainerView(onCopy: {}, scrollContentHorizontally: true) {
            MarkdownCodeBlockView(
                code: AttributedString("""
func greet(_ name: String) -> String {
    "Hello, \\(name)"
}
"""),
                wrapsInHorizontalScroll: false
            )
        }
        .padding(20)
    }
}
