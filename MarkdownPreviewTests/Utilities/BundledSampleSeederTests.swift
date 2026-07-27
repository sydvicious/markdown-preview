//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct BundledSampleSeederTests {

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeTemplate(
        _ content: String,
        named name: String = "SAMPLE.md",
        in directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let sampleTemplate = """
    # MarkdownPreview by Syd Polk
    ## Version {{VERSION}} (build {{BUILD}})
    ## Copyright ©2026 Syd Polk

    # Markdown Preview — Feature Sample

    Body.
    """

    // MARK: - shouldSeed

    @Test func seedsOnlyOnAGenuinelyNewInstall() {
        #expect(BundledSampleSeeder.shouldSeed(alreadyAttempted: false, hasPersistedList: false, listIsEmpty: true))
    }

    @Test func doesNotSeedOnceAttempted() {
        #expect(!BundledSampleSeeder.shouldSeed(alreadyAttempted: true, hasPersistedList: false, listIsEmpty: true))
    }

    @Test func doesNotSeedWhenAListHasEverBeenPersisted() {
        // A returning user who removed every file has an empty *but previously
        // saved* list; it must stay empty.
        #expect(!BundledSampleSeeder.shouldSeed(alreadyAttempted: false, hasPersistedList: true, listIsEmpty: true))
    }

    @Test func doesNotSeedOntoANonEmptyList() {
        #expect(!BundledSampleSeeder.shouldSeed(alreadyAttempted: false, hasPersistedList: false, listIsEmpty: false))
    }

    // MARK: - substitute

    @Test func substitutesVersionAndBuildTokens() {
        let result = BundledSampleSeeder.substitute(
            "Version {{VERSION}} (build {{BUILD}}) — {{VERSION}}",
            version: "0.7",
            build: "1"
        )
        #expect(result == "Version 0.7 (build 1) — 0.7")
    }

    @Test func substituteLeavesTokenlessTextUntouched() {
        #expect(BundledSampleSeeder.substitute("no token here", version: "0.7", build: "1") == "no token here")
    }

    // MARK: - headerBlock

    @Test func headerBlockIsEverythingBeforeTheFirstBlankLine() {
        #expect(BundledSampleSeeder.headerBlock(of: "# A\n## B\n## C\n\nbody\nmore") == "# A\n## B\n## C")
    }

    @Test func headerBlockWithoutABlankLineIsTheWholeContent() {
        #expect(BundledSampleSeeder.headerBlock(of: "# Only header") == "# Only header")
    }

    @Test func headerBlockOfEmptyContentIsEmpty() {
        #expect(BundledSampleSeeder.headerBlock(of: "") == "")
    }

    @Test func realSampleTemplateKeepsTheVersionInsideItsHeaderBlock() throws {
        // refresh() only updates the seeded copy when the header block (everything
        // up to the first blank line) changes with the version/build. That
        // requires SAMPLE.md's version/build line to sit *inside* the header block
        // — i.e. no blank line between the title and it. Guard against the file
        // drifting back to a title-only header, which silently defeats refresh so
        // a version bump would never update the on-disk copy.
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Utilities
            .deletingLastPathComponent()   // MarkdownPreviewTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Samples/SAMPLE.md")
        let contents = try String(contentsOf: sampleURL, encoding: .utf8)
        let header = BundledSampleSeeder.headerBlock(of: contents)
        #expect(header.contains(BundledSampleSeeder.versionToken))
        #expect(header.contains(BundledSampleSeeder.buildToken))
    }

    // MARK: - materialize

    @Test func materializeWritesSubstitutedSampleAndImage() throws {
        let source = try makeTemporaryDirectory()
        let container = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: container)
        }

        let templateURL = try writeTemplate(sampleTemplate, in: source)
        let imageURL = source.appendingPathComponent("lilsyd.JPG")
        try Data("image-bytes".utf8).write(to: imageURL)

        let url = try BundledSampleSeeder.materialize(
            templateURL: templateURL,
            imageURL: imageURL,
            version: "0.7",
            build: "1",
            in: container
        )

        #expect(url == container.appendingPathComponent("SAMPLE.md"))

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("Version 0.7 (build 1)"))
        #expect(!written.contains(BundledSampleSeeder.versionToken))
        #expect(!written.contains(BundledSampleSeeder.buildToken))
        #expect(written.contains("# Markdown Preview — Feature Sample"))

        let copiedImage = try Data(contentsOf: container.appendingPathComponent("lilsyd.JPG"))
        #expect(copiedImage == Data("image-bytes".utf8))
    }

    @Test func materializeNeverOverwritesAnExistingCopy() throws {
        let source = try makeTemporaryDirectory()
        let container = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: container)
        }

        let templateURL = try writeTemplate(sampleTemplate, in: source)
        let existing = "# user's edited copy\n"
        let destination = container.appendingPathComponent("SAMPLE.md")
        try existing.write(to: destination, atomically: true, encoding: .utf8)

        let url = try BundledSampleSeeder.materialize(
            templateURL: templateURL,
            imageURL: nil,
            version: "0.7",
            build: "1",
            in: container
        )

        #expect(url == destination)
        #expect(try String(contentsOf: destination, encoding: .utf8) == existing)
    }

    @Test func materializeWithoutAnImageStillWritesTheSample() throws {
        let source = try makeTemporaryDirectory()
        let container = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: container)
        }

        let templateURL = try writeTemplate(sampleTemplate, in: source)

        let url = try BundledSampleSeeder.materialize(
            templateURL: templateURL,
            imageURL: nil,
            version: "0.7",
            build: "1",
            in: container
        )

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: container.appendingPathComponent("lilsyd.JPG").path))
    }

    @Test func materializeThrowsWhenTheTemplateCannotBeRead() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let missingTemplate = container.appendingPathComponent("does-not-exist.md")

        #expect(throws: (any Error).self) {
            try BundledSampleSeeder.materialize(
                templateURL: missingTemplate,
                imageURL: nil,
                version: "0.7",
                build: "1",
                in: container
            )
        }
    }

    // MARK: - refresh

    @Test func refreshReplacesWhenTheHeaderDiffers() throws {
        let source = try makeTemporaryDirectory()
        let container = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: container)
        }

        let templateURL = try writeTemplate(sampleTemplate, in: source)
        // On disk from an older build: a different build number in the header.
        let containerURL = container.appendingPathComponent("SAMPLE.md")
        try """
        # MarkdownPreview by Syd Polk
        ## Version 0.7 (build 1)
        ## Copyright ©2026 Syd Polk

        old body
        """
            .write(to: containerURL, atomically: true, encoding: .utf8)

        let didReplace = try BundledSampleSeeder.refresh(
            templateURL: templateURL,
            containerURL: containerURL,
            version: "0.7",
            build: "2"
        )

        #expect(didReplace)
        let updated = try String(contentsOf: containerURL, encoding: .utf8)
        #expect(updated == BundledSampleSeeder.substitute(sampleTemplate, version: "0.7", build: "2"))
    }

    @Test func refreshLeavesTheCopyAloneWhenTheHeaderMatches() throws {
        let source = try makeTemporaryDirectory()
        let container = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: container)
        }

        let templateURL = try writeTemplate(sampleTemplate, in: source)
        // Same header as the candidate would produce, but a different body: the
        // body must not trigger a rewrite — only the header (version/build) does.
        let containerURL = container.appendingPathComponent("SAMPLE.md")
        let onDisk = """
        # MarkdownPreview by Syd Polk
        ## Version 0.7 (build 1)
        ## Copyright ©2026 Syd Polk

        edited body
        """
        try onDisk.write(to: containerURL, atomically: true, encoding: .utf8)

        let didReplace = try BundledSampleSeeder.refresh(
            templateURL: templateURL,
            containerURL: containerURL,
            version: "0.7",
            build: "1"
        )

        #expect(!didReplace)
        #expect(try String(contentsOf: containerURL, encoding: .utf8) == onDisk)
    }

    @Test func refreshThrowsWhenTheTemplateCannotBeRead() throws {
        let container = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: container) }

        let containerURL = container.appendingPathComponent("SAMPLE.md")
        try "# whatever\n".write(to: containerURL, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try BundledSampleSeeder.refresh(
                templateURL: container.appendingPathComponent("missing.md"),
                containerURL: containerURL,
                version: "0.7",
                build: "1"
            )
        }
    }
}
