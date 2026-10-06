//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownCore

struct DirectoryContainmentTests {

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test func findsTheGrantedDirectoryHoldingTheFile() async throws {
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs/photo.jpg"),
            from: [url("/Users/syd/Docs"), url("/Users/syd/Other")]
        )

        #expect(found == url("/Users/syd/Docs"))
    }

    @Test func findsAGrantHigherUpTheTree() async throws {
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs/Images/photo.jpg"),
            from: [url("/Users/syd")]
        )

        #expect(found == url("/Users/syd"))
    }

    @Test func prefersTheMostSpecificGrant() async throws {
        // The narrowest scope that still covers the file is the right one to open.
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs/Images/photo.jpg"),
            from: [url("/Users/syd"), url("/Users/syd/Docs/Images"), url("/Users/syd/Docs")]
        )

        #expect(found == url("/Users/syd/Docs/Images"))
    }

    @Test func returnsNilWhenNoGrantCovers() async throws {
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs/photo.jpg"),
            from: [url("/Users/syd/Other"), url("/tmp")]
        )

        #expect(found == nil)
    }

    @Test func returnsNilForAnEmptyGrantList() async throws {
        #expect(DirectoryContainment.directory(covering: url("/a/b.jpg"), from: []) == nil)
    }

    @Test func isNotFooledByASharedNamePrefix() async throws {
        // "/Users/syd/Docs2" must not be treated as containing a file in "Docs".
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs/photo.jpg"),
            from: [url("/Users/syd/Docs2")]
        )

        #expect(found == nil)
    }

    @Test func trailingSlashesDoNotMatter() async throws {
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs/photo.jpg"),
            from: [URL(fileURLWithPath: "/Users/syd/Docs", isDirectory: true)]
        )

        #expect(found != nil)
    }
}

struct DirectoryCoveringTests {

    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test func aDirectoryCoversItself() async throws {
        // The document's own folder is usually the grant, so resolving access
        // for that folder has to find it.
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs"),
            from: [url("/Users/syd/Docs")]
        )

        #expect(found == url("/Users/syd/Docs"))
    }

    @Test func aGrantHigherUpAlsoCoversADirectory() async throws {
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs/Images"),
            from: [url("/Users/syd")]
        )

        #expect(found == url("/Users/syd"))
    }

    @Test func coveringStillPrefersTheMostSpecificGrant() async throws {
        let found = DirectoryContainment.directory(
            covering: url("/Users/syd/Docs/Images"),
            from: [url("/Users/syd"), url("/Users/syd/Docs/Images"), url("/Users/syd/Docs")]
        )

        #expect(found == url("/Users/syd/Docs/Images"))
    }

    @Test func coveringFindsNothingForAnUnrelatedPath() async throws {
        #expect(DirectoryContainment.directory(covering: url("/tmp/x"), from: [url("/Users/syd")]) == nil)
    }
}

/// Folders that are really on disk, reached through a link.
///
/// The suites above name paths nothing is at. These make the folders, because a
/// link can only be followed where there is something for it to lead to.
struct LinkedDirectoryContainmentTests {

    /// `Real/Docs`, and `Shortcut`, a link to `Real`.
    private struct Folders {
        let root: URL
        let docs: URL
        let docsThroughLink: URL

        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("LinkedDirectoryContainmentTests-\(UUID().uuidString)")
            let real = root.appendingPathComponent("Real")
            let link = root.appendingPathComponent("Shortcut")
            docs = real.appendingPathComponent("Docs")
            docsThroughLink = link.appendingPathComponent("Docs")

            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test func aFileNamedThroughALinkIsInTheFolderTheLinkLeadsTo() async throws {
        let folders = try Folders()
        defer { folders.remove() }
        try Data([0]).write(to: folders.docs.appendingPathComponent("photo.png"))

        let found = DirectoryContainment.directory(
            covering: folders.docsThroughLink.appendingPathComponent("photo.png"),
            from: [folders.docs]
        )

        #expect(found == folders.docs)
    }

    @Test func aFolderGrantedThroughALinkCoversAFileNamedDirectly() async throws {
        let folders = try Folders()
        defer { folders.remove() }
        try Data([0]).write(to: folders.docs.appendingPathComponent("photo.png"))

        let found = DirectoryContainment.directory(
            covering: folders.docs.appendingPathComponent("photo.png"),
            from: [folders.docsThroughLink]
        )

        #expect(found == folders.docsThroughLink)
    }

    // The folder and the file are named the same way here, link and all, so
    // nothing about the two spellings differs. A grant covers its folder
    // whether or not the file asked about is in it: an image a document names
    // and the folder lacks is still inside the grant.
    @Test func aFileThatIsNotThereIsStillInTheFolderItIsNamedIn() async throws {
        let folders = try Folders()
        defer { folders.remove() }

        let found = DirectoryContainment.directory(
            covering: folders.docsThroughLink.appendingPathComponent("absent.png"),
            from: [folders.docsThroughLink]
        )

        #expect(found == folders.docsThroughLink)
    }

    // MARK: - The same place, spelled two ways

    @Test func aFolderIsTheSamePlaceWithOrWithoutATrailingSlash() async throws {
        let folders = try Folders()
        defer { folders.remove() }

        #expect(DirectoryContainment.isSameLocation(
            URL(fileURLWithPath: folders.docs.path, isDirectory: true),
            URL(fileURLWithPath: folders.docs.path, isDirectory: false)
        ))
    }

    @Test func aFolderIsTheSamePlaceNamedDirectlyOrThroughALink() async throws {
        let folders = try Folders()
        defer { folders.remove() }

        #expect(DirectoryContainment.isSameLocation(folders.docs, folders.docsThroughLink))
        #expect(DirectoryContainment.isSameLocation(folders.docsThroughLink, folders.docs))
    }

    @Test func aFileThatIsNotThereIsTheSamePlaceNamedDirectlyOrThroughALink() async throws {
        let folders = try Folders()
        defer { folders.remove() }

        #expect(DirectoryContainment.isSameLocation(
            folders.docs.appendingPathComponent("absent.png"),
            folders.docsThroughLink.appendingPathComponent("absent.png")
        ))
    }

    @Test func twoFoldersAreNotTheSamePlace() async throws {
        let folders = try Folders()
        defer { folders.remove() }

        #expect(!DirectoryContainment.isSameLocation(folders.docs, folders.root))
        #expect(!DirectoryContainment.isSameLocation(folders.docs, folders.docs.appendingPathComponent("Images")))
        #expect(!DirectoryContainment.isSameLocation(
            folders.docs.appendingPathComponent("a.png"),
            folders.docs.appendingPathComponent("b.png")
        ))
    }
}
