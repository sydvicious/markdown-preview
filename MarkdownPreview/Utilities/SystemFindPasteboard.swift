//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

#if os(macOS)
import AppKit

enum SystemFindPasteboard {
    static func currentQuery() -> String? {
        NSPasteboard(name: .find).string(forType: .string)
    }

    static func setQuery(_ query: String) {
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.clearContents()
        pasteboard.setString(query, forType: .string)
    }

    /// Monotonically increasing count that changes whenever the find pasteboard
    /// is written to, including by other apps. Used to detect external changes.
    static func changeCount() -> Int {
        NSPasteboard(name: .find).changeCount
    }
}
#else
// iOS and iPadOS have no system-wide find pasteboard, so back the shared find
// buffer with an in-memory value. This lets the file-list search and the
// in-document search fields share their query text within the app session,
// mirroring the macOS find-pasteboard behavior.
enum SystemFindPasteboard {
    private static var storedQuery: String?

    static func currentQuery() -> String? {
        storedQuery
    }

    static func setQuery(_ query: String) {
        storedQuery = query
    }
}
#endif
