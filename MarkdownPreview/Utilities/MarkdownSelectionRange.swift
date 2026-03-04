//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

struct MarkdownSelectionRange: Equatable, Hashable, Codable {
    var location: Int
    var length: Int

    init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    func clamped(toUTF16Length utf16Length: Int) -> MarkdownSelectionRange? {
        guard utf16Length >= 0 else { return nil }
        guard location <= utf16Length else { return nil }
        let maxLength = max(0, utf16Length - location)
        let clampedLength = min(length, maxLength)
        return MarkdownSelectionRange(location: location, length: clampedLength)
    }
}
