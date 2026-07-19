//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

/// Rewrites local image references to a custom URL scheme the app can serve.
///
/// A web view loaded from an HTML string cannot read local files, so image
/// references are rewritten to `mdimage://` URLs and served by a scheme handler
/// running in the app process. The markup stays small, which matters because the
/// document is re-rendered on every preview update.
public enum MarkdownImageURL {

    /// The scheme the preview's handler is registered for. It must not be one
    /// WebKit handles itself — `file` and `https` cannot be overridden.
    public static let scheme = "mdimage"

    private static let host = "local"

    private static let keyQueryItem = "key"

    /// A nonce minted once per launch and required on every `mdimage://` URL.
    ///
    /// Only markup this app generated can carry the current key, so content in a
    /// document cannot ask the handler for a file of its own choosing. Today the
    /// renderer escapes raw HTML, which already prevents that, but this keeps the
    /// guarantee if raw HTML is ever supported. Firefox for iOS gates its own
    /// `internal://` scheme the same way.
    public static let sessionKey = UUID().uuidString

    /// File extensions that may be served. Restricting this means a document
    /// cannot coax the handler into reading arbitrary files by pointing an
    /// `<img>` at them.
    public static let allowedPathExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "heif", "bmp", "tif", "tiff",
    ]

    /// Returns `html` with local image references rewritten to `mdimage://` URLs.
    ///
    /// References that are already absolute URLs, that name an extension outside
    /// `allowedPathExtensions`, or that do not resolve to an existing file are
    /// left untouched, so they fail visibly as a broken image rather than
    /// silently becoming something else.
    public static func rewritingLocalImages(
        in html: String,
        relativeTo baseURL: URL?,
        fileManager: FileManager = .default,
        key: String = sessionKey
    ) -> String {
        guard let directory = resolveDirectory(baseURL, fileManager: fileManager) else { return html }

        return rewritingImageSources(in: html) { source in
            guard let fileURL = resolveFile(source, in: directory, fileManager: fileManager) else {
                return nil
            }
            return url(for: fileURL, key: key)?.absoluteString
        }
    }

    /// Why a local image reference could not be resolved.
    public enum UnresolvedReason: Equatable, Sendable {
        /// The folder can be read and the file is not in it.
        case missing
        /// The file is there but cannot be opened, or the folder itself cannot
        /// be read — both mean access is the problem and a grant may fix it.
        case unreadable
    }

    /// Classifies each unresolved image reference so the reason can be reported
    /// accurately.
    ///
    /// Existence alone cannot tell these apart: a sandboxed app refused a
    /// directory sees its files as absent. So the directory listing is the
    /// deciding evidence — if the folder can be listed and the name is not
    /// there, the file is genuinely missing; if the folder cannot be listed at
    /// all, this is an access problem.
    public static func unresolvedLocalImages(
        in html: String,
        relativeTo baseURL: URL?,
        fileManager: FileManager = .default
    ) -> [(source: String, reason: UnresolvedReason)] {
        let sources = unresolvedLocalImageSources(in: html)
        guard !sources.isEmpty,
              let directory = resolveDirectory(baseURL, fileManager: fileManager) else {
            return []
        }

        let listing = try? fileManager.contentsOfDirectory(atPath: directory.path)

        return sources.map { source in
            guard let listing else {
                // The folder itself is unreadable, so nothing can be said about
                // the file beyond that access is missing.
                return (source, .unreadable)
            }

            let name = (source.removingPercentEncoding ?? source)
            let leaf = URL(fileURLWithPath: name).lastPathComponent
            return (source, listing.contains(leaf) ? .unreadable : .missing)
        }
    }

    /// Image references in `html` that still point at a local path.
    ///
    /// Run against already-rewritten markup, this is the list of images that
    /// could not be resolved — because the file is missing, or because the app
    /// has no access to the folder holding it. An empty result means every local
    /// image was resolved.
    public static func unresolvedLocalImageSources(in html: String) -> [String] {
        var sources: [String] = []

        _ = rewritingImageSources(in: html) { source in
            if !source.isEmpty, URL(string: source)?.scheme == nil {
                sources.append(source)
            }
            return nil
        }

        return sources
    }

    /// The `mdimage://` URL that serves `fileURL`.
    public static func url(for fileURL: URL, key: String = sessionKey) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = fileURL.standardizedFileURL.path
        components.queryItems = [URLQueryItem(name: keyQueryItem, value: key)]
        return components.url
    }

    /// The file a `mdimage://` URL refers to, or nil if it is not one of ours or
    /// names a disallowed extension.
    public static func fileURL(for url: URL, key: String = sessionKey) -> URL? {
        guard url.scheme == scheme, url.host == host else { return nil }

        // Reject anything not carrying this launch's key.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let provided = components?.queryItems?.first { $0.name == keyQueryItem }?.value
        guard provided == key else { return nil }

        let path = url.path
        guard !path.isEmpty else { return nil }

        let fileURL = URL(fileURLWithPath: path)
        guard allowedPathExtensions.contains(fileURL.pathExtension.lowercased()) else { return nil }
        return fileURL
    }

    /// An image format identified from a file's leading bytes.
    public enum ImageFormat: String, CaseIterable, Sendable {
        case png, jpeg, gif, webp, heic, bmp, tiff, svg

        public var mimeType: String {
            switch self {
            case .png: return "image/png"
            case .jpeg: return "image/jpeg"
            case .gif: return "image/gif"
            case .webp: return "image/webp"
            case .heic: return "image/heic"
            case .bmp: return "image/bmp"
            case .tiff: return "image/tiff"
            case .svg: return "image/svg+xml"
            }
        }
    }

    /// Identifies an image format from `data`'s signature, or nil if the content
    /// is not a recognised image.
    ///
    /// The extension check decides what may be *requested*; this decides what may
    /// actually be *served*. Without it a file merely named `.png` would be handed
    /// to the web view whatever it really contained.
    public static func detectedFormat(of data: Data) -> ImageFormat? {
        func matches(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard data.count >= offset + signature.count else { return false }
            let start = data.index(data.startIndex, offsetBy: offset)
            return Array(data[start..<data.index(start, offsetBy: signature.count)]) == signature
        }

        if matches([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if matches([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if matches(Array("GIF87a".utf8)) || matches(Array("GIF89a".utf8)) { return .gif }
        if matches(Array("RIFF".utf8)), matches(Array("WEBP".utf8), at: 8) { return .webp }
        if matches(Array("BM".utf8)) { return .bmp }
        if matches([0x49, 0x49, 0x2A, 0x00]) || matches([0x4D, 0x4D, 0x00, 0x2A]) { return .tiff }
        // HEIC and its relatives are ISO base media files: a box length, then
        // "ftyp", then a brand.
        if matches(Array("ftyp".utf8), at: 4) {
            let brandStart = data.index(data.startIndex, offsetBy: 8)
            guard data.count >= 12 else { return nil }
            let brand = String(decoding: data[brandStart..<data.index(brandStart, offsetBy: 4)], as: UTF8.self)
            if ["heic", "heix", "heim", "heis", "hevc", "mif1", "msf1"].contains(brand) { return .heic }
            return nil
        }

        // SVG is text; look for the root element near the start, past any
        // declaration or leading whitespace.
        let prefix = String(decoding: data.prefix(1024), as: UTF8.self)
        if prefix.contains("<svg") { return .svg }

        return nil
    }

    public static func mimeType(forPathExtension pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "bmp": return "image/bmp"
        case "tif", "tiff": return "image/tiff"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Shared helpers

    /// The directory a relative image reference resolves against. Call sites pass
    /// either the document's directory or the document itself, and
    /// `hasDirectoryPath` only reports whether the URL string ends in a slash, so
    /// ask the file system instead.
    static func resolveDirectory(_ baseURL: URL?, fileManager: FileManager) -> URL? {
        guard let baseURL else { return nil }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: baseURL.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue ? baseURL : baseURL.deletingLastPathComponent()
    }

    /// Resolves one `src` attribute to a readable image file.
    static func resolveFile(
        _ source: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL? {
        // Anything carrying a scheme is remote, or already rewritten.
        guard !source.isEmpty, URL(string: source)?.scheme == nil else { return nil }

        let path = source.removingPercentEncoding ?? source
        let fileURL = directory.appendingPathComponent(path).standardizedFileURL

        guard allowedPathExtensions.contains(fileURL.pathExtension.lowercased()) else { return nil }
        guard isReadable(fileURL) else { return nil }
        return fileURL
    }

    /// Whether the file can actually be read, established by reading from it.
    ///
    /// Existence is not the same as readability. A sandboxed app can see a path
    /// through a file provider while being refused its contents — which is what
    /// happens on iOS once a folder grant has lapsed. Treating "exists" as
    /// "readable" there produces a reference that resolves, renders as a broken
    /// image, and never prompts for the access that would fix it.
    static func isReadable(_ url: URL) -> Bool {
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if (try? handle.read(upToCount: 1)) != nil {
                return true
            }
        }

        // A file in iCloud that has not been downloaded yet cannot be read, but
        // it is still servable — whoever serves it starts the download first.
        // Treating it as unreadable would raise the permission prompt for what
        // is really a materialisation problem, and no amount of granting would
        // clear it.
        //
        // Reading the resource value is itself denied when access is the real
        // problem, so this does not paper over a genuine permission failure.
        if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
           let status = values.ubiquitousItemDownloadingStatus,
           status != .current {
            return true
        }

        return false
    }

    /// Walks every `<img src="…">` in `html`, replacing the attribute value with
    /// whatever `transform` returns, or leaving it alone when it returns nil.
    static func rewritingImageSources(
        in html: String,
        transform: (String) -> String?
    ) -> String {
        var result = ""
        var cursor = html.startIndex

        while let match = html.range(of: "<img src=\"", range: cursor..<html.endIndex) {
            guard let closingQuote = html.range(of: "\"", range: match.upperBound..<html.endIndex) else {
                break
            }

            let source = String(html[match.upperBound..<closingQuote.lowerBound])
            result += html[cursor..<match.upperBound]
            result += transform(source) ?? source
            cursor = closingQuote.lowerBound
        }

        result += html[cursor...]
        return result
    }
}
