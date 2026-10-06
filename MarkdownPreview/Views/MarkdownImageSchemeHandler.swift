//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os
import WebKit
import MarkdownCore

/// Serves local images to the preview web view.
///
/// `WKWebView.loadHTMLString(_:baseURL:)` gives the web content process no read
/// access to the file system, so a relative `<img src="…">` never loads however
/// correct the base URL is. Rewriting those references to a custom scheme lets
/// the app process — which can read the file — hand the bytes back on demand.
///
/// The read itself has to be as careful as the one that loads the document:
/// hold the security scope of whichever folder the user granted, materialise the
/// file if it lives in iCloud, and read under file coordination.
final class MarkdownImageSchemeHandler: NSObject, WKURLSchemeHandler {

    private static let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "Images")

    enum LoadError: Error {
        case notAnImage
        case unreadable
    }

    private let accessStore: DirectoryAccessStore

    /// Tasks that have been started and neither answered nor stopped.
    ///
    /// An image is read a turn of the main actor after its task starts, and
    /// WebKit may stop the task in between. It raises an exception on any call
    /// made to a task it has stopped, so only a task still listed here is
    /// answered.
    private var pendingTasks: Set<ObjectIdentifier> = []

    /// `accessStore` holds the folder grants an image is read under. The app
    /// passes the one it has; a test passes its own, so it neither depends on
    /// the grants the user has made nor disturbs them.
    init(accessStore: DirectoryAccessStore) {
        self.accessStore = accessStore
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        // The extension governs what may be asked for; the content governs what
        // is served, so a file merely named `.png` is refused below.
        guard let url = urlSchemeTask.request.url,
              let fileURL = MarkdownImageURL.fileURL(for: url) else {
            Self.log.error("Refused an image request that was not an allowed image URL")
            urlSchemeTask.didFailWithError(LoadError.notAnImage)
            return
        }

        let taskID = ObjectIdentifier(urlSchemeTask)
        pendingTasks.insert(taskID)

        Task { @MainActor in
            // Everything from here to the answer happens without giving up the
            // main actor, so a task still pending now cannot be stopped before
            // it has been answered.
            guard pendingTasks.remove(taskID) != nil else { return }

            let store = accessStore
            let data = store.withAccess(to: fileURL, perform: {
                Self.readImageData(at: fileURL)
            })

            guard let data else {
                Self.log.error("Could not read \(fileURL.lastPathComponent); covered by a folder grant: \(store.hasAccess(to: fileURL), privacy: .public)")
                urlSchemeTask.didFailWithError(LoadError.unreadable)
                return
            }

            guard let format = MarkdownImageURL.detectedFormat(of: data) else {
                Self.log.error("\(fileURL.lastPathComponent) is not an image: \(data.count, privacy: .public) bytes read, no recognised signature")
                urlSchemeTask.didFailWithError(LoadError.notAnImage)
                return
            }

            Self.log.debug("Served \(data.count, privacy: .public) bytes of \(format.rawValue, privacy: .public) for \(fileURL.lastPathComponent)")

            let response = URLResponse(
                url: url,
                mimeType: format.mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )

            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        pendingTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    /// Reads an image, coping with the file living in iCloud and not yet being
    /// downloaded.
    private static func readImageData(at fileURL: URL) -> Data? {
        // A per-file scope may also apply, if the image itself came from a picker.
        let opened = fileURL.startAccessingSecurityScopedResource()
        defer {
            if opened {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        }

        var coordinatedData: Data?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: fileURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { readURL in
            coordinatedData = try? Data(contentsOf: readURL, options: .mappedIfSafe)
        }

        return coordinatedData
    }
}
