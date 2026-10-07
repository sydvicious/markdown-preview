//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
#if os(macOS)
import AppKit
#endif

/// The buffer the search fields share the term being searched for through.
///
/// A view model is handed the one it uses when it is made. The app hands it a
/// `SystemFindPasteboard`. A test hands it an `InMemoryFindPasteboard` of its
/// own, so that running the tests neither reads nor writes the buffer every
/// app on the machine shares.
@MainActor
protocol FindPasteboard {
    func currentQuery() -> String?
    func setQuery(_ query: String)
    /// A count that changes whenever the buffer is written to, by anyone. Used
    /// to tell that somebody has written since the last look.
    func changeCount() -> Int
}

#if os(macOS)
/// The macOS system find pasteboard, shared with every other app.
struct SystemFindPasteboard: FindPasteboard {
    func currentQuery() -> String? {
        NSPasteboard(name: .find).string(forType: .string)
    }

    func setQuery(_ query: String) {
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        pasteboard.setString(query, forType: .string)
    }

    func changeCount() -> Int {
        NSPasteboard(name: .find).changeCount
    }
}
#else
/// iOS and iPadOS have no system-wide find pasteboard, so back the shared find
/// buffer with an in-memory value. This lets the file-list search and the
/// in-document search fields share their query text within the app session,
/// mirroring the macOS find-pasteboard behavior.
struct SystemFindPasteboard: FindPasteboard {
    private static let appWide = InMemoryFindPasteboard()

    func currentQuery() -> String? { Self.appWide.currentQuery() }
    func setQuery(_ query: String) { Self.appWide.setQuery(query) }
    func changeCount() -> Int { Self.appWide.changeCount() }
}
#endif

/// A find buffer that lives and dies with whoever holds it, and shares nothing
/// with any other.
final class InMemoryFindPasteboard: FindPasteboard {
    private var storedQuery: String?
    private var writes = 0

    func currentQuery() -> String? {
        storedQuery
    }

    func setQuery(_ query: String) {
        storedQuery = query
        writes += 1
    }

    func changeCount() -> Int {
        writes
    }
}
