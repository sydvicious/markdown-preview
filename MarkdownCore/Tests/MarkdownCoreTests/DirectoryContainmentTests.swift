//
// Copyright ©2026 Syd Polk. All Rights Reserved.
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
            containing: url("/Users/syd/Docs/photo.jpg"),
            from: [url("/Users/syd/Docs"), url("/Users/syd/Other")]
        )

        #expect(found == url("/Users/syd/Docs"))
    }

    @Test func findsAGrantHigherUpTheTree() async throws {
        let found = DirectoryContainment.directory(
            containing: url("/Users/syd/Docs/Images/photo.jpg"),
            from: [url("/Users/syd")]
        )

        #expect(found == url("/Users/syd"))
    }

    @Test func prefersTheMostSpecificGrant() async throws {
        // The narrowest scope that still covers the file is the right one to open.
        let found = DirectoryContainment.directory(
            containing: url("/Users/syd/Docs/Images/photo.jpg"),
            from: [url("/Users/syd"), url("/Users/syd/Docs/Images"), url("/Users/syd/Docs")]
        )

        #expect(found == url("/Users/syd/Docs/Images"))
    }

    @Test func returnsNilWhenNoGrantCovers() async throws {
        let found = DirectoryContainment.directory(
            containing: url("/Users/syd/Docs/photo.jpg"),
            from: [url("/Users/syd/Other"), url("/tmp")]
        )

        #expect(found == nil)
    }

    @Test func returnsNilForAnEmptyGrantList() async throws {
        #expect(DirectoryContainment.directory(containing: url("/a/b.jpg"), from: []) == nil)
    }

    @Test func isNotFooledByASharedNamePrefix() async throws {
        // "/Users/syd/Docs2" must not be treated as containing a file in "Docs".
        let found = DirectoryContainment.directory(
            containing: url("/Users/syd/Docs/photo.jpg"),
            from: [url("/Users/syd/Docs2")]
        )

        #expect(found == nil)
    }

    @Test func trailingSlashesDoNotMatter() async throws {
        let found = DirectoryContainment.directory(
            containing: url("/Users/syd/Docs/photo.jpg"),
            from: [URL(fileURLWithPath: "/Users/syd/Docs", isDirectory: true)]
        )

        #expect(found != nil)
    }

    @Test func aDirectoryDoesNotContainItself() async throws {
        #expect(!DirectoryContainment.directory(url("/a/b"), contains: url("/a/b")))
    }

    @Test func containsReportsNestedFiles() async throws {
        #expect(DirectoryContainment.directory(url("/a"), contains: url("/a/b/c.jpg")))
        #expect(!DirectoryContainment.directory(url("/a/b"), contains: url("/a/c.jpg")))
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
