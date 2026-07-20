//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import os
import MarkdownCore

/// Remembers folders the user has granted the app access to.
///
/// A document is reached through a security-scoped bookmark covering that file
/// alone, so anything beside it — an image a markdown document references — is
/// unreadable until the user grants the enclosing folder. Those grants are
/// persisted as their own bookmarks and reopened on later launches.
///
/// On unsandboxed macOS none of this is needed to read a file, but the grants are
/// still recorded so behavior does not change when the app is sandboxed for the
/// App Store.
///
/// A limitation worth knowing: on iOS the security scope a bookmark carries is
/// implicit and ephemeral, documented as "valid until reboot at the latest", so
/// a grant cannot survive a restart of the device. The user has to grant the
/// folder again after rebooting.
@MainActor
final class DirectoryAccessStore: ObservableObject {

    static let shared = DirectoryAccessStore()

    private static let defaultsKey = "GrantedDirectoryBookmarks"
    private static let formatVersionKey = "GrantedDirectoryBookmarksVersion"

    /// Bump when the way grants are created or resolved changes.
    ///
    /// Bookmarks written by an older build can carry assumptions the current one
    /// no longer holds — version 1 leaked an open security scope on every
    /// resolution, and the only way to recover was deleting the app. Discarding
    /// grants on a format change costs the user one re-grant instead.
    ///
    /// Version 2 could contain a grant that is not security-scoped at all: it was
    /// written when a failure to make a scoped bookmark quietly fell back to a
    /// plain one. Those resolve without complaint and then yield a URL the sandbox
    /// refuses, so they must not be carried into a sandboxed build.
    private static let formatVersion = 3

    private let userDefaults: UserDefaults

    /// Resolved directories, newest first, paired with the bookmark that produced
    /// them so a stale bookmark can be refreshed.
    @Published private(set) var grantedDirectories: [URL] = []

    private var bookmarksByPath: [String: Data] = [:]

    /// Directories granted during this launch, held separately from the
    /// persisted bookmarks.
    ///
    /// A grant must work immediately even if it cannot be persisted — bookmark
    /// creation or resolution failing is a reason to lose the grant on the next
    /// launch, not a reason to lose it now.
    private var sessionDirectories: [URL] = []

    private static let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "DirectoryAccess")

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        discardGrantsFromAnOlderFormat()
        restore()
    }

    private func discardGrantsFromAnOlderFormat() {
        let stored = userDefaults.integer(forKey: Self.formatVersionKey)
        guard stored != Self.formatVersion else { return }

        if stored != 0 || userDefaults.object(forKey: Self.defaultsKey) != nil {
            Self.log.notice("Discarding folder grants written in format \(stored, privacy: .public)")
        }

        userDefaults.removeObject(forKey: Self.defaultsKey)
        userDefaults.set(Self.formatVersion, forKey: Self.formatVersionKey)
    }

    /// Records access to `directory`, which must have come from a picker so the
    /// app actually holds a scope for it.
    func grantAccess(to directory: URL) {
        // The URL arrives from a picker already carrying a scope; open it while
        // the bookmark is made so the bookmark records that access.
        let opened = directory.startAccessingSecurityScopedResource()
        defer {
            if opened {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        // Take effect now, whatever happens to the bookmark below.
        if !sessionDirectories.contains(directory) {
            sessionDirectories.append(directory)
        }

        do {
            let data = try makeBookmarkData(for: directory)
            bookmarksByPath[directory.standardizedFileURL.path] = data
            persist()
        } catch {
            Self.log.error("Could not bookmark \(directory.lastPathComponent): \(error.localizedDescription)")
        }

        restore()
    }

    /// Whether a grant covers `url`, which may be a file or a directory.
    func hasAccess(to url: URL) -> Bool {
        DirectoryContainment.directory(covering: url, from: grantedDirectories) != nil
    }

    /// Runs `body` with the security scope of whichever grant covers `url` held
    /// open, releasing it afterwards. `url` may be a file or a directory.
    ///
    /// If no grant covers it, `body` still runs — on an unsandboxed system the
    /// read may well succeed anyway, and failing early would make macOS behave
    /// worse than it needs to.
    func withAccess<T>(to url: URL, perform body: () -> T) -> T {
        guard let directory = DirectoryContainment.directory(
            covering: url,
            from: grantedDirectories
        ) else {
            return body()
        }

        let opened = directory.startAccessingSecurityScopedResource()
        if !opened {
            Self.log.error("startAccessingSecurityScopedResource failed for \(directory.lastPathComponent)")
        }
        defer {
            if opened {
                directory.stopAccessingSecurityScopedResource()
            }
        }
        return body()
    }

    // MARK: - Persistence

    private func restore() {
        let stored = userDefaults.dictionary(forKey: Self.defaultsKey) as? [String: Data] ?? [:]

        var resolved: [URL] = []
        var refreshed: [String: Data] = [:]

        for (path, data) in stored {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: resolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                // Drop grants that no longer resolve; the folder is gone or the
                // bookmark can no longer be honoured.
                Self.log.error("A stored folder grant did not resolve and was dropped")
                continue
            }

            resolved.append(url)
            if isStale, let fresh = try? makeBookmarkData(for: url) {
                refreshed[url.standardizedFileURL.path] = fresh
            } else {
                refreshed[path] = data
            }
        }

        bookmarksByPath = refreshed

        // Keep anything granted this launch even if its bookmark did not
        // resolve, so a persistence failure does not revoke live access.
        var combined = resolved
        for directory in sessionDirectories where !combined.contains(directory) {
            combined.append(directory)
        }

        grantedDirectories = combined
        userDefaults.set(refreshed, forKey: Self.defaultsKey)
    }

    private func persist() {
        userDefaults.set(bookmarksByPath, forKey: Self.defaultsKey)
    }

    private func makeBookmarkData(for url: URL) throws -> Data {
        #if os(macOS)
        // A non-scoped bookmark is not a usable fallback here. It resolves
        // perfectly well and then yields a URL the sandbox refuses, so the grant
        // looks healthy for the rest of the launch and silently evaporates on the
        // next one. Failing here instead means the caller learns at the point the
        // grant is made — the entitlement is missing, or the scope this URL
        // arrived with has already been reclaimed.
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        // Security-scoped bookmarks are a macOS concept; the option is declared
        // API_UNAVAILABLE(ios) in the SDK.
        [.withSecurityScope]
        #else
        // On iOS a bookmark made without security scope carries an implicit
        // ephemeral scope, and resolving it *starts accessing* that scope unless
        // this option is passed. Resolution happens on every launch and after
        // every grant, and the system permits only a limited number of open
        // security-scoped URLs — so without this, each restore leaks one until
        // further access is refused. Access is taken explicitly in `withAccess`.
        [.withoutImplicitStartAccessing]
        #endif
    }
}
