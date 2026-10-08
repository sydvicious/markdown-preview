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
    /// Builds the page off the main actor, and keeps the last few built. The
    /// body runs far more often than the document changes, for every change
    /// of selection and whenever anything in the window is redrawn, and asks
    /// each time; only something new to show is built.
    ///
    /// The last eight pages stay built, so going back to a document shows it
    /// without building it again.
    @StateObject private var renderer = LatestResult<RenderingRequest, Rendering>(keeping: 8) { request in
        await MarkdownPreviewView.render(request)
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

    /// Everything a rendering is made from, and which document it is of. While
    /// none of it has changed, the rendering is not made again.
    ///
    /// What is on disk is not among them. An image that turns up where one
    /// was missing is found when the document, its text size or the folders
    /// the app may read next change.
    private struct RenderingRequest: Equatable {
        let documentID: String?
        let source: String
        let contentScale: CGFloat
        let baseURL: URL?
        let grantedDirectories: [URL]
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
    /// The HTML is built here, off the main actor, which is most of the time
    /// it takes. What is done about the images needs the folders the app has
    /// been granted, and those are the main actor's.
    nonisolated private static func render(_ request: RenderingRequest) async -> Rendering {
        let built = PerfLog.timed {
            MarkdownHTMLBuilder.document(for: request.source, contentScale: request.contentScale, softBreak: .lineBreak)
        }
        let finished = await MainActor.run {
            PerfLog.timed { withImages(built.value, for: request) }
        }
        let name = request.documentID.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "(no document)"
        PerfLog.log.info("""
            [perf] render \(name, privacy: .public): \
            \(request.source.utf8.count, privacy: .public) bytes to HTML in \
            \(built.milliseconds, format: .fixed(precision: 1), privacy: .public) ms off the main actor, images \
            \(finished.milliseconds, format: .fixed(precision: 1), privacy: .public) ms on it
            """)
        return finished.value
    }

    /// `WKWebView.loadHTMLString(_:baseURL:)` gives the web content process no
    /// read access to the file system, so a relative image reference never loads
    /// however correct the base URL is. `MarkdownImageSchemeHandler` serves those
    /// URLs from the app process instead.
    private static func withImages(_ document: String, for request: RenderingRequest) -> Rendering {
        guard let baseURL = request.baseURL else { return Rendering(html: document, imageProblem: .none) }
        let accessStore = DirectoryAccessStore.shared

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

            // Debug level: this runs for every page built, so it should not
            // persist in the system log by default. Paths are the user's, so
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
        let request = RenderingRequest(
            documentID: documentID,
            source: source,
            contentScale: textSize.scaleFactor,
            baseURL: baseURL,
            grantedDirectories: accessStore.grantedDirectories
        )
        // The page showing is the last one built. For the moment it takes to
        // build this document's, that is the document before it: its own
        // source goes with its HTML, and what is selected in this one, and
        // what the reader selects in that one, are kept apart.
        let shown = renderer.current
        let showsThisDocument = shown?.request.documentID == documentID

        ZStack {
            if let shown {
                MarkdownPreviewWebView(
                    source: shown.request.source,
                    html: shown.result.html,
                    baseURL: shown.request.baseURL,
                    documentID: shown.request.documentID,
                    selectedRange: showsThisDocument ? selections.first : nil,
                    selectionSynchronizer: selectionSynchronizer,
                    onSelectedTextChange: showsThisDocument ? onSelectedTextChange : { _ in },
                    onSelectedRangesChange: showsThisDocument ? onSelectedRangesChange : { _ in },
                    onSearchSelection: onSearchSelection,
                    onRequestImageAccess: { isRequestingFolderAccess = true }
                )
            }
            if renderer.isTakingLong {
                // Over whatever page is there, which is not the one wanted.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: request) {
            // What was asked for and of which view's renderer, to tell why a
            // page is built twice: a renderer that is not the one before is a
            // view made anew, and the same one is something here that changed.
            let name = request.documentID.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "(no document)"
            let asked = String(UInt(bitPattern: ObjectIdentifier(renderer).hashValue), radix: 16).suffix(5)
            PerfLog.log.info("""
                [perf] render asked for \(name, privacy: .public) of renderer \(asked, privacy: .public): \
                scale \(request.contentScale, privacy: .public), \
                folder \(request.baseURL?.lastPathComponent ?? "(none)", privacy: .public), \
                \(request.grantedDirectories.count, privacy: .public) folders granted
                """)
            await renderer.ask(request)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            switch shown?.result.imageProblem ?? .none {
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
