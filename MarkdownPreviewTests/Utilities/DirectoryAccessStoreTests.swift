//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing

/// The folders the user has granted, across launches.
///
/// A launch is a `DirectoryAccessStore` made over the same `UserDefaults`, so a
/// test that needs the next launch makes a second store.
@MainActor
struct DirectoryAccessStoreTests {

    // The keys the grants are kept under, spelled out here and not shared with
    // the store. A build that renamed either would lose every grant its users
    // had made, and should fail a test first.
    private static let bookmarksKey = "GrantedDirectoryBookmarks"
    private static let formatVersionKey = "GrantedDirectoryBookmarksVersion"

    /// Defaults of its own and a folder to make granted folders in.
    @MainActor
    private struct Fixture {
        let defaults: UserDefaults
        let root: URL
        private let suiteName: String

        init(function: String = #function) throws {
            suiteName = "DirectoryAccessStoreTests.\(function).\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)

            let made = FileManager.default.temporaryDirectory
                .appendingPathComponent("DirectoryAccessStoreTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
            // The temporary directory is reached through a link (`/var` for
            // `/private/var`). Folders here are spelled by where they really
            // are, with nothing in the path left to resolve.
            root = URL(fileURLWithPath: try DirectoryAccessStoreTests.realPath(of: made), isDirectory: true)
        }

        /// The store as the next launch would make it.
        func launch() -> DirectoryAccessStore {
            DirectoryAccessStore(userDefaults: defaults)
        }

        func makeFolder(_ name: String) throws -> URL {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        /// A file at `path` inside `folder`, standing in for an image there.
        @discardableResult
        func makeFile(_ path: String, in folder: URL) throws -> URL {
            let file = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([0]).write(to: file)
            return file
        }

        /// The grants as they are stored, by the path each is filed under.
        var storedGrants: [String: Any] {
            defaults.dictionary(forKey: DirectoryAccessStoreTests.bookmarksKey) ?? [:]
        }

        var storedFormatVersion: Int {
            defaults.integer(forKey: DirectoryAccessStoreTests.formatVersionKey)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// Where `url` really is, with every link in its path followed, the last
    /// part included: asked about a link, the file system describes the link.
    private static func realPath(of url: URL) throws -> String {
        let followed = url.resolvingSymlinksInPath()
        return try #require(try followed.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
    }

    /// Where each URL really is, so two spellings of one folder compare equal.
    private static func paths(_ urls: [URL]) throws -> [String] {
        try urls.map { try realPath(of: $0) }
    }

    // MARK: - A first launch

    @Test func aFirstLaunchHasNoGrants() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")

        let store = fixture.launch()

        #expect(store.grantedDirectories.isEmpty)
        #expect(!store.hasAccess(to: folder))
        #expect(fixture.storedGrants.isEmpty)
    }

    @Test func aFirstLaunchRecordsTheFormatItWrites() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        _ = fixture.launch()

        #expect(fixture.storedFormatVersion != 0)
    }

    // MARK: - Granting

    @Test func aGrantCoversTheFolderAndEverythingInIt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let sibling = try fixture.makeFolder("Other")
        let photo = try fixture.makeFile("photo.png", in: folder)
        let deeper = try fixture.makeFile("images/deeper/photo.png", in: folder)
        let elsewhere = try fixture.makeFile("photo.png", in: sibling)
        let store = fixture.launch()

        store.grantAccess(to: folder)

        #expect(store.hasAccess(to: folder))
        #expect(store.hasAccess(to: photo))
        #expect(store.hasAccess(to: deeper))
        #expect(!store.hasAccess(to: sibling))
        #expect(!store.hasAccess(to: elsewhere))
        #expect(!store.hasAccess(to: fixture.root))
    }

    @Test func aGrantedFolderIsListedOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let store = fixture.launch()

        store.grantAccess(to: folder)

        #expect(try Self.paths(store.grantedDirectories) == [folder.path])
    }

    @Test func grantingAFolderAgainListsItOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let store = fixture.launch()

        store.grantAccess(to: folder)
        store.grantAccess(to: folder)

        #expect(try Self.paths(store.grantedDirectories) == [folder.path])
        #expect(fixture.storedGrants.count == 1)
    }

    // The same folder, named the two ways a path to a folder can be written.
    @Test func aFolderGrantedWithAndWithoutATrailingSlashIsListedOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let store = fixture.launch()

        store.grantAccess(to: URL(fileURLWithPath: folder.path, isDirectory: true))
        store.grantAccess(to: URL(fileURLWithPath: folder.path, isDirectory: false))

        #expect(try Self.paths(store.grantedDirectories) == [folder.path])
        #expect(fixture.storedGrants.count == 1)
    }

    // A path can reach a folder through a link, as `/tmp` does `/private/tmp`.
    @Test func aFolderGrantedThroughASymbolicLinkCoversTheFolderItself() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let link = fixture.root.appendingPathComponent("Shortcut", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder)
        try fixture.makeFile("photo.png", in: folder)
        let store = fixture.launch()

        store.grantAccess(to: link)

        #expect(store.hasAccess(to: folder.appendingPathComponent("photo.png")))
        #expect(store.hasAccess(to: link.appendingPathComponent("photo.png")))
        let listed = try Self.paths(store.grantedDirectories)
        #expect(listed == [folder.path])
    }

    @Test func eachGrantedFolderIsKept() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let docs = try fixture.makeFolder("Docs")
        let pictures = try fixture.makeFolder("Pictures")
        let store = fixture.launch()

        store.grantAccess(to: docs)
        store.grantAccess(to: pictures)

        #expect(try Set(Self.paths(store.grantedDirectories)) == [docs.path, pictures.path])
        #expect(fixture.storedGrants.count == 2)
    }

    // A grant must work at once even if it cannot be kept: failing to make the
    // bookmark is a reason to lose it at the next launch, not now.
    @Test func aGrantThatCannotBeBookmarkedStillWorksUntilTheNextLaunch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        // Nothing is at this path, so there is nothing to bookmark.
        let folder = fixture.root.appendingPathComponent("Never Made", isDirectory: true)
        let store = fixture.launch()

        store.grantAccess(to: folder)

        #expect(store.hasAccess(to: folder.appendingPathComponent("photo.png")))
        #expect(fixture.storedGrants.isEmpty)
        #expect(!fixture.launch().hasAccess(to: folder.appendingPathComponent("photo.png")))
    }

    // MARK: - The next launch

    @Test func aGrantIsStillThereAtTheNextLaunch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let photo = try fixture.makeFile("photo.png", in: folder)
        fixture.launch().grantAccess(to: folder)

        let store = fixture.launch()

        #expect(try Self.paths(store.grantedDirectories) == [folder.path])
        #expect(store.hasAccess(to: photo))
        #expect(fixture.storedGrants.count == 1)
    }

    @Test func aGrantIsStillThereManyLaunchesLater() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        fixture.launch().grantAccess(to: folder)

        for _ in 0..<5 {
            _ = fixture.launch()
        }
        let store = fixture.launch()

        #expect(try Self.paths(store.grantedDirectories) == [folder.path])
        #expect(fixture.storedGrants.count == 1)
    }

    // A bookmark follows the folder it was made for, so the grant does too.
    @Test func aGrantFollowsAFolderThatWasMoved() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let moved = fixture.root.appendingPathComponent("Archive", isDirectory: true)
        try fixture.makeFile("photo.png", in: folder)
        fixture.launch().grantAccess(to: folder)

        try FileManager.default.moveItem(at: folder, to: moved)
        let store = fixture.launch()

        #expect(store.hasAccess(to: moved.appendingPathComponent("photo.png")))
        #expect(!store.hasAccess(to: folder.appendingPathComponent("photo.png")))
        #expect(try Self.paths(store.grantedDirectories) == [moved.path])
        #expect(fixture.storedGrants.count == 1)
    }

    @Test func aGrantThatFollowedAMoveIsStillThereTheLaunchAfter() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let moved = fixture.root.appendingPathComponent("Archive", isDirectory: true)
        fixture.launch().grantAccess(to: folder)
        try FileManager.default.moveItem(at: folder, to: moved)
        _ = fixture.launch()

        let store = fixture.launch()

        #expect(try Self.paths(store.grantedDirectories) == [moved.path])
        #expect(fixture.storedGrants.count == 1)
    }

    // MARK: - Pruning

    @Test func aGrantForAFolderThatWasDeletedIsDropped() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        fixture.launch().grantAccess(to: folder)

        try FileManager.default.removeItem(at: folder)
        let store = fixture.launch()

        #expect(store.grantedDirectories.isEmpty)
        #expect(!store.hasAccess(to: folder.appendingPathComponent("photo.png")))
        #expect(fixture.storedGrants.isEmpty)
    }

    @Test func droppingOneGrantLeavesTheOthers() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let docs = try fixture.makeFolder("Docs")
        let pictures = try fixture.makeFolder("Pictures")
        let first = fixture.launch()
        first.grantAccess(to: docs)
        first.grantAccess(to: pictures)

        try FileManager.default.removeItem(at: docs)
        let store = fixture.launch()

        #expect(try Self.paths(store.grantedDirectories) == [pictures.path])
        #expect(fixture.storedGrants.count == 1)
    }

    @Test func aStoredGrantThatIsNotABookmarkIsDropped() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        fixture.launch().grantAccess(to: folder)

        var stored = fixture.storedGrants
        stored["/Users/someone/Elsewhere"] = Data("not a bookmark".utf8)
        fixture.defaults.set(stored, forKey: Self.bookmarksKey)
        let store = fixture.launch()

        #expect(try Self.paths(store.grantedDirectories) == [folder.path])
        #expect(fixture.storedGrants.count == 1)
    }

    // MARK: - Grants written by an older build

    @Test func grantsWrittenInAnOlderFormatAreDiscarded() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        fixture.launch().grantAccess(to: folder)
        let currentFormat = fixture.storedFormatVersion

        fixture.defaults.set(currentFormat - 1, forKey: Self.formatVersionKey)
        let store = fixture.launch()

        #expect(store.grantedDirectories.isEmpty)
        #expect(!store.hasAccess(to: folder))
        #expect(fixture.storedGrants.isEmpty)
        #expect(fixture.storedFormatVersion == currentFormat)
    }

    // The first builds to keep grants recorded no format at all.
    @Test func grantsWithNoFormatRecordedAreDiscarded() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        fixture.launch().grantAccess(to: folder)
        let currentFormat = fixture.storedFormatVersion

        fixture.defaults.removeObject(forKey: Self.formatVersionKey)
        let store = fixture.launch()

        #expect(store.grantedDirectories.isEmpty)
        #expect(fixture.storedGrants.isEmpty)
        #expect(fixture.storedFormatVersion == currentFormat)
    }

    // Discarding happens once. The folder granted again afterwards is kept.
    @Test func aFolderGrantedAgainAfterADiscardIsKept() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        fixture.launch().grantAccess(to: folder)
        fixture.defaults.set(fixture.storedFormatVersion - 1, forKey: Self.formatVersionKey)

        fixture.launch().grantAccess(to: folder)
        let store = fixture.launch()

        #expect(try Self.paths(store.grantedDirectories) == [folder.path])
    }

    // MARK: - Working under a grant

    @Test func workUnderAGrantRunsOnceAndHandsBackItsResult() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let store = fixture.launch()
        store.grantAccess(to: folder)

        var runs = 0
        let result = store.withAccess(to: folder.appendingPathComponent("photo.png")) {
            runs += 1
            return "read"
        }

        #expect(result == "read")
        #expect(runs == 1)
    }

    // With no grant the read is still tried: outside the sandbox it may well
    // succeed, and refusing early would make the Mac behave worse than it must.
    @Test func workWithNoGrantStillRunsOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let store = fixture.launch()

        var runs = 0
        let result = store.withAccess(to: folder.appendingPathComponent("photo.png")) {
            runs += 1
            return "read"
        }

        #expect(result == "read")
        #expect(runs == 1)
    }

    // MARK: - Working under a grant, away from the main actor

    /// The preview works out what to do about a document's images away from
    /// the main actor, with the folders that were granted when it was asked.
    /// So the same work can be done with a list of granted folders in hand,
    /// and no store.
    @Test func workUnderAGrantCanBeDoneAwayFromTheMainActor() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let store = fixture.launch()
        store.grantAccess(to: folder)
        let granted = store.grantedDirectories
        let image = folder.appendingPathComponent("photo.png")

        let result = await Task.detached {
            DirectoryAccessStore.withAccess(to: image, grantedBy: granted) {
                Thread.isMainThread ? "on the main thread" : "read"
            }
        }.value

        #expect(result == "read")
    }

    @Test func workAwayFromTheMainActorWithNoGrantStillRuns() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let folder = try fixture.makeFolder("Docs")
        let image = folder.appendingPathComponent("photo.png")

        let result = await Task.detached {
            DirectoryAccessStore.withAccess(to: image, grantedBy: []) {
                Thread.isMainThread ? "on the main thread" : "read"
            }
        }.value

        #expect(result == "read")
    }
}
