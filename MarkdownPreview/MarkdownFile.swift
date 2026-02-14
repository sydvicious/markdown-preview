//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import UniformTypeIdentifiers

struct MarkdownFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let contents: String

    var fileName: String {
        url.lastPathComponent
    }

    static func load(from url: URL) throws -> MarkdownFile {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .unicode) ??
            String(data: data, encoding: .ascii) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return MarkdownFile(url: url, contents: text)
    }

    static var supportedTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.insert(markdown, at: 0)
        }
        return Array(Set(types))
    }
}
