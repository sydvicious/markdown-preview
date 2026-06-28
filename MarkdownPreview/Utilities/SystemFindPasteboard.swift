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
}
#endif
