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

    @State private var blockWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var showsCopyFeedback = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    private let cornerRadius: CGFloat = 10
    private let contentPadding: CGFloat = 10
    private let headerHeight: CGFloat = 34

    var body: some View {
        let effectiveAvailableWidth = min(availableWidth, currentScreenWidth)
        let clamped = clampedWidth(availableWidth: effectiveAvailableWidth)

        VStack(alignment: .leading, spacing: 0) {
            // Sibling width probe: measures parent width independently of clamped container width.
            Color.clear
                .frame(height: 0)
                .frame(maxWidth: .infinity)
                .background(availableWidthReader)

            container
                .onPreferenceChange(MarkdownCopyableBlockWidthPreferenceKey.self) { width in
                    if width > 0 {
                        blockWidth = width
                    }
                }
                .frame(width: clamped, alignment: .leading)
        }
        .onPreferenceChange(MarkdownCopyableAvailableWidthPreferenceKey.self) { width in
            if width > 0 {
                availableWidth = width
            }
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentScreenWidth: CGFloat {
        #if os(iOS)
        // iOS 26+: prefer scene-provided screen over UIScreen.main.
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        if let activeScene {
            return activeScene.screen.bounds.width
        }
        let anyScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        return anyScene?.screen.bounds.width ?? 0
        #elseif os(macOS)
        return NSScreen.main?.frame.width ?? 0
        #else
        return 0
        #endif
    }

    private var container: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 0, height: headerHeight)

            blockBody
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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(headerBackgroundColor)
                .frame(height: headerHeight)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            copyButton
                .padding(.trailing, contentPadding)
                .padding(.top, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    private var blockBody: some View {
        if scrollContentHorizontally {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    content
                }
                .background(blockWidthReader)
                .frame(alignment: .leading)
            }
            .overlay(alignment: .topLeading) {
                // Preview canvas sometimes reports 0 width on first pass from ScrollView content.
                // Measure an intrinsic-size copy in overlay (does not affect layout), then clamp.
                content
                    .fixedSize(horizontal: true, vertical: false)
                    .background(blockWidthReader)
                    .hidden()
                    .allowsHitTesting(false)
            }
        } else {
            content
                .background(blockWidthReader)
        }
    }

    private func clampedWidth(availableWidth: CGFloat) -> CGFloat? {
        guard availableWidth > 0 else { return nil }
        // Avoid forcing an incorrect width during the first layout pass before content is measured.
        guard blockWidth > 0 else { return nil }

        let paddedBlockWidth = blockWidth + (contentPadding * 2)
        return min(paddedBlockWidth, availableWidth)
    }

    private var blockWidthReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: MarkdownCopyableBlockWidthPreferenceKey.self,
                value: geometry.size.width
            )
        }
    }

    private var availableWidthReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: MarkdownCopyableAvailableWidthPreferenceKey.self,
                value: geometry.size.width
            )
        }
    }

    private var copyButton: some View {
        Button {
            triggerCopyFeedback()
            onCopy()
        } label: {
            HStack(spacing: 6) {
                Text(showsCopyFeedback ? "Copied" : "Copy")
                Image(systemName: showsCopyFeedback ? "checkmark.circle.fill" : "doc.on.doc")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(showsCopyFeedback ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(showsCopyFeedback ? Color.accentColor : Color.clear)
            }
            .scaleEffect(showsCopyFeedback ? 1.05 : 1.0)
            .contentTransition(.symbolEffect(.replace))
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: showsCopyFeedback)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy")
    }

    private func triggerCopyFeedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        copyFeedbackTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            showsCopyFeedback = true
        }

        copyFeedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.14)) {
                    showsCopyFeedback = false
                }
                copyFeedbackTask = nil
            }
        }
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

private struct MarkdownCopyableBlockWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MarkdownCopyableAvailableWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
#Preview("Copyable Block - Isolated Table Width") {
    ScrollView {
        MarkdownCopyableBlockContainerView(onCopy: {}, scrollContentHorizontally: true) {
            Color.red
                .frame(width: 500, height: 200)
        }
        .padding(20)
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
#endif
