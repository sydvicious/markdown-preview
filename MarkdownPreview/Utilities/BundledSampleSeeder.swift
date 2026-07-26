//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

/// The file-and-decision logic behind putting the bundled `SAMPLE.md` in a new
/// user's document list and keeping it current across app updates.
///
/// It is deliberately free of the view model, the store, `Bundle.main`, and the
/// real container directory: every input is passed in, so the whole feature can be
/// unit-tested against temporary directories without launching the app. The
/// caller (`ContentViewModel`) supplies those live values and does the store and
/// `UserDefaults` wiring around these calls.
enum BundledSampleSeeder {

    /// Tokens the bundled template carries in place of the app version and build
    /// number; the app substitutes them when it writes the copy to disk. The
    /// copyright year is *not* a token — it is plain text maintained like any other
    /// source file's notice.
    static let versionToken = "{{VERSION}}"
    static let buildToken = "{{BUILD}}"

    /// Whether to seed on this launch. All three must hold, because none alone
    /// identifies a genuinely new install:
    /// - the one-and-only attempt has not been made,
    /// - no document list has ever been persisted (an *emptied* list is not the
    ///   same as a *never-created* one — a returning user's empty list must stay
    ///   empty), and
    /// - nothing is currently open.
    static func shouldSeed(alreadyAttempted: Bool, hasPersistedList: Bool, listIsEmpty: Bool) -> Bool {
        !alreadyAttempted && !hasPersistedList && listIsEmpty
    }

    /// The bundled template with its version and build tokens substituted.
    static func substitute(_ template: String, version: String, build: String) -> String {
        template
            .replacingOccurrences(of: versionToken, with: version)
            .replacingOccurrences(of: buildToken, with: build)
    }

    /// The title block used to tell one shipped sample from another: every line up
    /// to the first blank line. The version and build number live in there, so a
    /// bump changes it and nothing else has to. (The version is no longer on the
    /// first line, so a first-line-only compare would miss it.)
    static func headerBlock(of content: String) -> Substring {
        if let blankLine = content.range(of: "\n\n") {
            return content[content.startIndex..<blankLine.lowerBound]
        }
        return content[...]
    }

    /// Writes the substituted sample into `container` and copies its image beside it
    /// (the markdown references the image by a relative path, so it has to sit
    /// alongside), returning the sample's URL.
    ///
    /// A file already present is left exactly as it is — never overwritten, so a
    /// copy the user has edited is preserved — and still counts as success. Throws
    /// if a required read, write, or copy fails, so the caller can decline to add a
    /// document it could not fully materialize.
    @discardableResult
    static func materialize(
        templateURL: URL,
        imageURL: URL?,
        version: String,
        build: String,
        in container: URL,
        using fileManager: FileManager = .default
    ) throws -> URL {
        let sampleDestination = container.appendingPathComponent(templateURL.lastPathComponent)
        if !fileManager.fileExists(atPath: sampleDestination.path) {
            let template = try String(contentsOf: templateURL, encoding: .utf8)
            try substitute(template, version: version, build: build)
                .write(to: sampleDestination, atomically: true, encoding: .utf8)
        }

        if let imageURL {
            let imageDestination = container.appendingPathComponent(imageURL.lastPathComponent)
            if !fileManager.fileExists(atPath: imageDestination.path) {
                try fileManager.copyItem(at: imageURL, to: imageDestination)
            }
        }

        return sampleDestination
    }

    /// Brings the on-disk copy up to date when a newly shipped build carries a
    /// different sample — detected by the header block, which changes with the
    /// version or build number. Returns `true` when the copy was replaced, `false`
    /// when it was already current.
    ///
    /// The write is atomic: it lands in a temporary file and is renamed into place,
    /// so a failure throws and leaves the existing copy untouched, to be retried on
    /// the next launch. The copy is only ever rewritten here — never added back to
    /// the list — so a document the user removed is not resurrected.
    static func refresh(
        templateURL: URL,
        containerURL: URL,
        version: String,
        build: String,
        using fileManager: FileManager = .default
    ) throws -> Bool {
        let template = try String(contentsOf: templateURL, encoding: .utf8)
        let candidate = substitute(template, version: version, build: build)
        let existing = try String(contentsOf: containerURL, encoding: .utf8)

        guard headerBlock(of: candidate) != headerBlock(of: existing) else {
            return false
        }

        try candidate.write(to: containerURL, atomically: true, encoding: .utf8)
        return true
    }
}
