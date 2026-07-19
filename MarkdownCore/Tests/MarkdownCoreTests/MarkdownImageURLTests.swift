//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownCore

struct MarkdownImageURLTests {

    private func makeDirectory(containing names: [String]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MarkdownImageURLTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for name in names {
            try Data([0]).write(to: directory.appendingPathComponent(name))
        }
        return directory
    }

    @Test func rewritesALocalImageToTheCustomScheme() async throws {
        let directory = try makeDirectory(containing: ["photo.jpg"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let html = MarkdownImageURL.rewritingLocalImages(
            in: "<p><img src=\"photo.jpg\" alt=\"a photo\" /></p>",
            relativeTo: directory
        )

        #expect(html.contains("src=\"mdimage://local"))
        // The path is followed by this launch's key rather than closing straight
        // away, so the whole reference has to be checked, not just the name.
        #expect(html.contains("photo.jpg?key=\(MarkdownImageURL.sessionKey)\""))
        #expect(html.contains("alt=\"a photo\""))
    }

    @Test func theRewrittenURLRoundTripsBackToTheFile() async throws {
        let directory = try makeDirectory(containing: ["photo.jpg"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("photo.jpg").standardizedFileURL
        let url = try #require(MarkdownImageURL.url(for: fileURL))

        #expect(MarkdownImageURL.fileURL(for: url) == fileURL)
    }

    @Test func roundTripsNamesContainingSpaces() async throws {
        let directory = try makeDirectory(containing: ["my photo.png"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("my photo.png").standardizedFileURL
        let url = try #require(MarkdownImageURL.url(for: fileURL))

        #expect(url.absoluteString.contains("%20"))
        #expect(MarkdownImageURL.fileURL(for: url) == fileURL)
    }

    @Test func rewritesPercentEncodedSources() async throws {
        let directory = try makeDirectory(containing: ["my photo.png"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let html = MarkdownImageURL.rewritingLocalImages(
            in: "<img src=\"my%20photo.png\" />",
            relativeTo: directory
        )

        #expect(html.contains("mdimage://local"))
    }

    @Test func leavesRemoteSourcesAlone() async throws {
        let directory = try makeDirectory(containing: [])
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = "<img src=\"https://example.com/a.png\" />"
        #expect(MarkdownImageURL.rewritingLocalImages(in: source, relativeTo: directory) == source)
    }

    @Test func leavesMissingFilesAlone() async throws {
        let directory = try makeDirectory(containing: [])
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = "<img src=\"absent.png\" />"
        #expect(MarkdownImageURL.rewritingLocalImages(in: source, relativeTo: directory) == source)
    }

    @Test func refusesDisallowedExtensionsWhenRewriting() async throws {
        let directory = try makeDirectory(containing: ["secret.txt"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = "<img src=\"secret.txt\" />"
        #expect(MarkdownImageURL.rewritingLocalImages(in: source, relativeTo: directory) == source)
    }

    @Test func refusesDisallowedExtensionsWhenServing() async throws {
        // The handler applies the same restriction, so a hand-written mdimage://
        // URL cannot be used to read an arbitrary file either.
        let url = try #require(URL(string: "mdimage://local/etc/passwd"))
        #expect(MarkdownImageURL.fileURL(for: url) == nil)
    }

    @Test func refusesForeignSchemes() async throws {
        let url = try #require(URL(string: "https://example.com/a.png"))
        #expect(MarkdownImageURL.fileURL(for: url) == nil)
    }

    @Test func mimeTypesCoverTheAllowedExtensions() async throws {
        #expect(MarkdownImageURL.mimeType(forPathExtension: "PNG") == "image/png")
        #expect(MarkdownImageURL.mimeType(forPathExtension: "jpeg") == "image/jpeg")
        #expect(MarkdownImageURL.mimeType(forPathExtension: "svg") == "image/svg+xml")
        #expect(MarkdownImageURL.mimeType(forPathExtension: "xyz") == "application/octet-stream")
    }

    @Test func aNilBaseURLLeavesTheHTMLUnchanged() async throws {
        let source = "<img src=\"photo.png\" />"
        #expect(MarkdownImageURL.rewritingLocalImages(in: source, relativeTo: nil) == source)
    }
}

struct MarkdownImageFormatTests {

    @Test func detectsTheCommonRasterSignatures() async throws {
        #expect(MarkdownImageURL.detectedFormat(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) == .png)
        #expect(MarkdownImageURL.detectedFormat(of: Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(MarkdownImageURL.detectedFormat(of: Data("GIF89a...".utf8)) == .gif)
        #expect(MarkdownImageURL.detectedFormat(of: Data("BM______".utf8)) == .bmp)
        #expect(MarkdownImageURL.detectedFormat(of: Data([0x49, 0x49, 0x2A, 0x00])) == .tiff)
        #expect(MarkdownImageURL.detectedFormat(of: Data([0x4D, 0x4D, 0x00, 0x2A])) == .tiff)
    }

    @Test func detectsWebPOnlyWithBothMarkers() async throws {
        var webp = Data("RIFF".utf8)
        webp.append(Data([0, 0, 0, 0]))
        webp.append(Data("WEBP".utf8))
        #expect(MarkdownImageURL.detectedFormat(of: webp) == .webp)

        var wav = Data("RIFF".utf8)
        wav.append(Data([0, 0, 0, 0]))
        wav.append(Data("WAVE".utf8))
        #expect(MarkdownImageURL.detectedFormat(of: wav) == nil)
    }

    @Test func detectsHeicByBrandAndRejectsOtherISOMedia() async throws {
        func isoMedia(brand: String) -> Data {
            var data = Data([0, 0, 0, 0x18])
            data.append(Data("ftyp".utf8))
            data.append(Data(brand.utf8))
            return data
        }

        #expect(MarkdownImageURL.detectedFormat(of: isoMedia(brand: "heic")) == .heic)
        #expect(MarkdownImageURL.detectedFormat(of: isoMedia(brand: "mif1")) == .heic)
        // An MP4 is the same container shape and must not be served as an image.
        #expect(MarkdownImageURL.detectedFormat(of: isoMedia(brand: "isom")) == nil)
    }

    @Test func detectsSVGText() async throws {
        let svg = Data("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)
        #expect(MarkdownImageURL.detectedFormat(of: svg) == .svg)
    }

    @Test func refusesContentThatIsNotAnImage() async throws {
        // The case the check exists for: a file named .png holding something else.
        #expect(MarkdownImageURL.detectedFormat(of: Data("ssh-rsa AAAAB3NzaC1yc2E...".utf8)) == nil)
        #expect(MarkdownImageURL.detectedFormat(of: Data("<html><body>hi</body></html>".utf8)) == nil)
        #expect(MarkdownImageURL.detectedFormat(of: Data()) == nil)
        #expect(MarkdownImageURL.detectedFormat(of: Data([0x00])) == nil)
    }

    @Test func everyFormatReportsAnImageMimeType() async throws {
        for format in MarkdownImageURL.ImageFormat.allCases {
            #expect(format.mimeType.hasPrefix("image/"), "\(format) reported \(format.mimeType)")
        }
    }
}

struct UnresolvedImageSourceTests {

    private func makeDirectory(containing names: [String]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UnresolvedImageSourceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            try Data([0]).write(to: directory.appendingPathComponent(name))
        }
        return directory
    }

    @Test func reportsNothingWhenEveryImageResolved() async throws {
        let directory = try makeDirectory(containing: ["photo.png"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let html = MarkdownImageURL.rewritingLocalImages(
            in: "<img src=\"photo.png\" />",
            relativeTo: directory
        )

        #expect(MarkdownImageURL.unresolvedLocalImageSources(in: html).isEmpty)
    }

    @Test func reportsImagesThatCouldNotBeResolved() async throws {
        let directory = try makeDirectory(containing: ["there.png"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let html = MarkdownImageURL.rewritingLocalImages(
            in: "<img src=\"there.png\" /><img src=\"missing.png\" />",
            relativeTo: directory
        )

        #expect(MarkdownImageURL.unresolvedLocalImageSources(in: html) == ["missing.png"])
    }

    @Test func doesNotCountRemoteImages() async throws {
        let html = "<img src=\"https://example.com/a.png\" />"
        #expect(MarkdownImageURL.unresolvedLocalImageSources(in: html).isEmpty)
    }
}

struct ImageReadabilityTests {

    private func makeDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ImageReadabilityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func aFileThatExistsButCannotBeReadIsNotResolved() async throws {
        // The case that matters on iOS: after a folder grant lapses the path is
        // still visible through the file provider while its contents are
        // refused. Treating that as resolvable renders a broken image and
        // suppresses the prompt that would fix it.
        let directory = try makeDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: directory.appendingPathComponent("locked.png").path)
            try? FileManager.default.removeItem(at: directory)
        }

        let file = directory.appendingPathComponent("locked.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)

        #expect(!MarkdownImageURL.isReadable(file))

        let html = MarkdownImageURL.rewritingLocalImages(
            in: "<img src=\"locked.png\" />",
            relativeTo: directory
        )

        #expect(html == "<img src=\"locked.png\" />")
        #expect(MarkdownImageURL.unresolvedLocalImageSources(in: html) == ["locked.png"])
    }

    @Test func areadableFileIsResolved() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("open.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: file)

        #expect(MarkdownImageURL.isReadable(file))
    }

    @Test func anEmptyFileIsTreatedAsUnreadable() async throws {
        // The probe reads a byte, and an empty file yields nothing. Harmless:
        // an empty file is not an image, so refusing it early only skips work
        // the content check would do anyway.
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("empty.png")
        try Data().write(to: file)

        #expect(!MarkdownImageURL.isReadable(file))
        #expect(MarkdownImageURL.detectedFormat(of: Data()) == nil)
    }

    @Test func aMissingFileIsNotReadable() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(!MarkdownImageURL.isReadable(directory.appendingPathComponent("absent.png")))
    }
}


struct ImageURLKeyTests {

    private func makeDirectory(containing names: [String]) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ImageURLKeyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            try Data([0]).write(to: directory.appendingPathComponent(name))
        }
        return directory
    }

    @Test func aURLWithTheWrongKeyIsRefused() async throws {
        // The point of the key: markup this app did not generate cannot ask the
        // handler for a file, even a permitted one.
        let file = URL(fileURLWithPath: "/tmp/photo.png")
        let url = try #require(MarkdownImageURL.url(for: file, key: "an-old-key"))

        #expect(MarkdownImageURL.fileURL(for: url, key: "the-current-key") == nil)
    }

    @Test func aURLWithNoKeyIsRefused() async throws {
        let url = try #require(URL(string: "mdimage://local/tmp/photo.png"))
        #expect(MarkdownImageURL.fileURL(for: url, key: "the-current-key") == nil)
    }

    @Test func aURLCarryingTheCurrentKeyIsAccepted() async throws {
        let file = URL(fileURLWithPath: "/tmp/photo.png")
        let url = try #require(MarkdownImageURL.url(for: file, key: "the-current-key"))

        #expect(MarkdownImageURL.fileURL(for: url, key: "the-current-key") == file)
    }

    @Test func rewrittenMarkupRoundTripsWithTheSameKey() async throws {
        let directory = try makeDirectory(containing: ["photo.png"])
        defer { try? FileManager.default.removeItem(at: directory) }

        let html = MarkdownImageURL.rewritingLocalImages(
            in: "<img src=\"photo.png\" />",
            relativeTo: directory,
            key: "session-key"
        )

        let sources = MarkdownImageURL.unresolvedLocalImageSources(in: html)
        #expect(sources.isEmpty)
        #expect(html.contains("key=session-key"))
    }
}

struct UnresolvedImageReasonTests {

    private func makeDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UnresolvedReasonTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func aFileNotInAReadableFolderIsMissing() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let results = MarkdownImageURL.unresolvedLocalImages(
            in: "<img src=\"absent.png\" />",
            relativeTo: directory
        )

        #expect(results.map(\.source) == ["absent.png"])
        #expect(results.map(\.reason) == [.missing])
    }

    @Test func aFilePresentButUnopenableIsUnreadable() async throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("locked.png")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: directory)
        }

        try Data([0x89, 0x50]).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)

        let results = MarkdownImageURL.unresolvedLocalImages(
            in: "<img src=\"locked.png\" />",
            relativeTo: directory
        )

        #expect(results.map(\.reason) == [.unreadable])
    }

    @Test func anUnlistableFolderMakesEverythingUnreadable() async throws {
        // Nothing can be said about a file in a folder that cannot be listed,
        // so it is reported as an access problem rather than as missing.
        let directory = try makeDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)

        let results = MarkdownImageURL.unresolvedLocalImages(
            in: "<img src=\"whatever.png\" />",
            relativeTo: directory
        )

        #expect(results.map(\.reason) == [.unreadable])
    }

    @Test func resolvedAndRemoteImagesAreNotReported() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data([0x89, 0x50]).write(to: directory.appendingPathComponent("there.png"))

        let html = MarkdownImageURL.rewritingLocalImages(
            in: "<img src=\"there.png\" /><img src=\"https://example.com/a.png\" />",
            relativeTo: directory
        )

        #expect(MarkdownImageURL.unresolvedLocalImages(in: html, relativeTo: directory).isEmpty)
    }
}
