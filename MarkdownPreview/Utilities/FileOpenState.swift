//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Combine

final class FileOpenState: ObservableObject {
    /// Shared instance so the macOS app delegate and the SwiftUI scene enqueue
    /// into the same queue.
    static let shared = FileOpenState()

    /// Queue of URLs handed to the app by the system. A multi-file open delivers
    /// every URL together (macOS `application(_:open:)`) or one at a time (iOS
    /// `.onOpenURL`), so they are accumulated here and drained together rather
    /// than overwriting a single slot (which dropped all but one file).
    @Published var pendingURLs: [URL] = []
    @Published var didReceiveExternalOpenRequest = false

    func enqueue(_ url: URL) {
        didReceiveExternalOpenRequest = true
        pendingURLs.append(url)
    }

    func enqueue(_ urls: [URL]) {
        urls.forEach(enqueue)
    }
}
