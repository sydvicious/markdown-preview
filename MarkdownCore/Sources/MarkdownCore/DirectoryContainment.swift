//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation

/// Decides which granted directory, if any, covers a file.
///
/// A sandboxed app reaches a document through a security-scoped bookmark that
/// covers that file alone. Reading anything beside it — an image referenced by a
/// markdown document, say — needs the user to have granted the enclosing folder.
/// This works out which grant applies.
public enum DirectoryContainment {

    /// The most specific granted directory that contains `fileURL`, or nil when
    /// none does.
    ///
    /// Where grants nest, the deepest one wins: it is the narrowest scope that
    /// still covers the file.
    public static func directory(containing fileURL: URL, from directories: [URL]) -> URL? {
        let target = pathComponents(of: fileURL)

        return directories
            .filter { contains(pathComponents(of: $0), target) }
            .max { pathComponents(of: $0).count < pathComponents(of: $1).count }
    }

    /// Whether `directory` contains `fileURL` at any depth.
    public static func directory(_ directory: URL, contains fileURL: URL) -> Bool {
        contains(pathComponents(of: directory), pathComponents(of: fileURL))
    }

    /// The most specific granted directory that covers `url`, counting `url`
    /// itself.
    ///
    /// Use this when the thing needing access may be a directory rather than a
    /// file — resolving a document's own folder, say, where the grant and the
    /// folder are the same path.
    public static func directory(covering url: URL, from directories: [URL]) -> URL? {
        let target = pathComponents(of: url)

        return directories
            .filter { directory in
                let components = pathComponents(of: directory)
                return components == target || contains(components, target)
            }
            .max { pathComponents(of: $0).count < pathComponents(of: $1).count }
    }

    private static func contains(_ directory: [String], _ file: [String]) -> Bool {
        // A directory does not contain itself, and cannot contain a shorter path.
        guard file.count > directory.count else { return false }
        return Array(file.prefix(directory.count)) == directory
    }

    /// Path components with symlinks resolved and the root's empty component
    /// dropped, so comparison is not thrown off by "/a/b" versus "/a/b/" or by
    /// "/tmp" versus "/private/tmp".
    private static func pathComponents(of url: URL) -> [String] {
        url.resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents
            .filter { $0 != "/" }
    }
}
