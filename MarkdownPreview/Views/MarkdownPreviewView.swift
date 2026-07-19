//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
import os
import MarkdownCore

final class PreviewSelectionSynchronizer: ObservableObject {
    private var flushSelectionHandler: ((@escaping () -> Void) -> Void)?

    func flushSelection(completion: @escaping () -> Void) {
        guard let flushSelectionHandler else {
            completion()
            return
        }

        flushSelectionHandler(completion)
    }

    func setFlushSelectionHandler(_ handler: ((@escaping () -> Void) -> Void)?) {
        flushSelectionHandler = handler
    }
}

struct MarkdownPreviewView: View {
    let source: String
    let baseURL: URL?
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]
    var selectionSynchronizer: PreviewSelectionSynchronizer?
    var onSelectedTextChange: (String?) -> Void = { _ in }
    var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }
    var onSearchSelection: (String) -> Void = { _ in }

    @ObservedObject private var accessStore = DirectoryAccessStore.shared
    @State private var isRequestingFolderAccess = false

    /// The rendered document, with local image references pointed at the app's
    /// own URL scheme.
    ///
    /// `WKWebView.loadHTMLString(_:baseURL:)` gives the web content process no
    /// read access to the file system, so a relative image reference never loads
    /// however correct the base URL is. `MarkdownImageSchemeHandler` serves those
    /// URLs from the app process instead.
    private var html: String {
        let document = MarkdownHTMLBuilder.document(for: source, contentScale: textSize.scaleFactor)
        guard let baseURL else { return document }

        // The rewrite checks each image exists, which is itself a privileged
        // read, so it has to happen inside the granted scope. Without this a
        // folder grant would appear to do nothing.
        return accessStore.withAccess(to: baseURL) {
            MarkdownImageURL.rewritingLocalImages(in: document, relativeTo: baseURL)
        }
    }

    /// Why the document's images failed, if any did.
    ///
    /// A file that is simply absent is reported plainly: offering permission for
    /// it would promise a fix that granting cannot deliver.
    private enum ImageProblem {
        case none
        case unreadable
        case missing
    }

    private var imageProblem: ImageProblem {
        guard let baseURL else { return .none }

        let unresolved = MarkdownImageURL.unresolvedLocalImages(in: html, relativeTo: baseURL)
        guard !unresolved.isEmpty else { return .none }

        // Debug level: this renders on every preview update, so it should not
        // persist in the system log by default. Paths are the user's, so they
        // are left to the default redaction.
        Self.log.debug("""
            Unresolved images: \(unresolved.map { "\($0.source) (\($0.reason))" }.joined(separator: ", ")); \
            grants: \(accessStore.grantedDirectories.map(\.path).joined(separator: ", "))
            """)

        // Access is the actionable problem, so it wins when both are present.
        return unresolved.contains { $0.reason == .unreadable } ? .unreadable : .missing
    }

    private static let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "Images")

    var body: some View {
        MarkdownPreviewWebView(
            source: source,
            html: html,
            baseURL: baseURL,
            selectedRange: selections.first,
            selectionSynchronizer: selectionSynchronizer,
            onSelectedTextChange: onSelectedTextChange,
            onSelectedRangesChange: onSelectedRangesChange,
            onSearchSelection: onSearchSelection
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .top, spacing: 0) {
            switch imageProblem {
            case .none:
                EmptyView()
            case .unreadable:
                imageAccessPrompt
            case .missing:
                imageMissingNotice
            }
        }
        .fileImporter(
            isPresented: $isRequestingFolderAccess,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(folder) = result {
                accessStore.grantAccess(to: folder)
            }
        }
        .fileDialogDefaultDirectory(baseURL)
    }

    /// Offered only when an image is present but unreadable, where granting the
    /// folder is a real fix.
    private var imageMissingNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.secondary)
            Text("One or more images could not be loaded.")
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var imageAccessPrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.secondary)
            Text("Images in this document need permission to load.")
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Allow…") {
                isRequestingFolderAccess = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#if DEBUG
#Preview("Markdown Preview View") {
    MarkdownPreviewView(
        source: MarkdownPreviewFixtures.excerptFile.contents,
        baseURL: nil,
        textSize: .large,
        selections: .constant([MarkdownSelectionRange(location: 0, length: 120)])
    )
}
#endif
