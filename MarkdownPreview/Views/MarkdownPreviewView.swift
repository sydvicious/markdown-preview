//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
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
    /// Which document this is, so the preview can keep the reader's place when
    /// that same document is redrawn. Without it every redraw starts at the top.
    var documentID: String? = nil
    let textSize: DynamicTypeSize
    @Binding var selections: [MarkdownSelectionRange]
    var selectionSynchronizer: PreviewSelectionSynchronizer?
    var onSelectedTextChange: (String?) -> Void = { _ in }
    var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }
    var onSearchSelection: (String) -> Void = { _ in }

    @ObservedObject private var accessStore = DirectoryAccessStore.shared
    @State private var isRequestingFolderAccess = false

    /// Why the document's images failed, if any did.
    ///
    /// A file that is simply absent is reported plainly: offering permission for
    /// it would promise a fix that granting cannot deliver.
    private enum ImageProblem {
        case none
        case unreadable
        case missing
    }

    /// The rendered document, and what if anything is wrong with its images.
    private struct Rendering {
        let html: String
        let imageProblem: ImageProblem
    }

    /// What the button that stands in for an unreadable image says, and its
    /// tooltip. The same wording as the banner above the preview, so there is
    /// one set of strings to localize.
    private static let accessButtonLabel = String(localized: "Allow…")
    private static let accessExplanation = String(localized: "Images in this document need permission to load.")

    /// Renders the document with local image references pointed at the app's own
    /// URL scheme, and any image the app is not allowed to read replaced by a
    /// button that asks for access.
    ///
    /// `WKWebView.loadHTMLString(_:baseURL:)` gives the web content process no
    /// read access to the file system, so a relative image reference never loads
    /// however correct the base URL is. `MarkdownImageSchemeHandler` serves those
    /// URLs from the app process instead.
    private var rendering: Rendering {
        let document = MarkdownHTMLBuilder.document(for: source, contentScale: textSize.scaleFactor, softBreak: .lineBreak)
        guard let baseURL else { return Rendering(html: document, imageProblem: .none) }

        // Every step here is a privileged read: the rewrite checks each image
        // exists, and telling an unreadable file from an absent one means
        // listing the directory. So all of it happens inside the granted scope.
        // Outside it a folder grant would appear to do nothing, the listing
        // would fail, and every unresolved image would be classified
        // `.unreadable` — offering access for files that are simply not there,
        // precisely the promise the distinction exists to avoid making.
        return accessStore.withAccess(to: baseURL) {
            let rewritten = MarkdownImageURL.rewritingLocalImages(in: document, relativeTo: baseURL)
            let unresolved = MarkdownImageURL.unresolvedLocalImages(in: rewritten, relativeTo: baseURL)
            guard !unresolved.isEmpty else { return Rendering(html: rewritten, imageProblem: .none) }

            // Debug level: this renders on every preview update, so it should
            // not persist in the system log by default. Paths are the user's, so
            // they are left to the default redaction.
            Self.log.debug("""
                Unresolved images: \(unresolved.map { "\($0.source) (\($0.reason))" }.joined(separator: ", ")); \
                grants: \(accessStore.grantedDirectories.map(\.path).joined(separator: ", "))
                """)

            // Access is the actionable problem, so it wins when both are present.
            guard unresolved.contains(where: { $0.reason == .unreadable }) else {
                return Rendering(html: rewritten, imageProblem: .missing)
            }

            // The banner above the preview is easy to miss — the document
            // renders normally around the gap, and the eye goes to the content.
            // So the gap itself becomes the way to fix it.
            let html = MarkdownImageURL.replacingUnreadableImages(
                in: rewritten,
                relativeTo: baseURL,
                label: Self.accessButtonLabel,
                explanation: Self.accessExplanation
            )
            return Rendering(html: html, imageProblem: .unreadable)
        }
    }

    private static let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "Images")

    var body: some View {
        let rendering = rendering

        MarkdownPreviewWebView(
            source: source,
            html: rendering.html,
            baseURL: baseURL,
            documentID: documentID,
            selectedRange: selections.first,
            selectionSynchronizer: selectionSynchronizer,
            onSelectedTextChange: onSelectedTextChange,
            onSelectedRangesChange: onSelectedRangesChange,
            onSearchSelection: onSearchSelection,
            onRequestImageAccess: { isRequestingFolderAccess = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .top, spacing: 0) {
            switch rendering.imageProblem {
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

    /// Shown when the image is simply absent from a readable folder. It carries
    /// no action, because there is none to offer: the file is not there, and
    /// granting a folder would not bring it back.
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

    /// Offered only when an image is present but unreadable, where granting the
    /// folder is a real fix.
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
