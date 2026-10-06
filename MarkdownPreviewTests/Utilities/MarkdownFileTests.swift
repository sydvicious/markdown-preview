//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarkdownPreview

/// What `MarkdownFile.load` makes of the bytes in a file.
///
/// It reads UTF-8, and UTF-16 that begins with a byte-order mark, and refuses
/// everything else. Each test here writes the bytes a file would hold and says
/// what the document should then contain.
struct MarkdownFileTests {

    private static let text = "# Café 😀\n\nÀ bientôt."

    /// A file holding exactly `data`, in a folder of its own.
    private static func makeFile(named name: String = "notes.md", holding data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// `string` as UTF-16 code units in the given byte order, with nothing in
    /// front of them.
    private static func utf16Bytes(of string: String, littleEndian: Bool) -> Data {
        var data = Data()
        for unit in string.utf16 {
            let high = UInt8(unit >> 8)
            let low = UInt8(unit & 0xFF)
            data.append(contentsOf: littleEndian ? [low, high] : [high, low])
        }
        return data
    }

    // MARK: - UTF-8

    @Test func readsUTF8Text() throws {
        let url = try Self.makeFile(holding: Data(Self.text.utf8))
        defer { Self.remove(url) }

        let file = try MarkdownFile.load(from: url)

        #expect(file.contents == Self.text)
        #expect(file.url == url)
    }

    @Test func anEmptyFileIsAnEmptyDocument() throws {
        let url = try Self.makeFile(holding: Data())
        defer { Self.remove(url) }

        #expect(try MarkdownFile.load(from: url).contents == "")
    }

    // Editors on Windows put a byte-order mark in front of UTF-8 text. Left in
    // the contents it sits before the first `#`, and the document's opening
    // heading is no longer at the start of its line.
    @Test func aUTF8ByteOrderMarkIsNotPartOfTheDocument() throws {
        let url = try Self.makeFile(holding: Data([0xEF, 0xBB, 0xBF]) + Data(Self.text.utf8))
        defer { Self.remove(url) }

        #expect(try MarkdownFile.load(from: url).contents == Self.text)
    }

    // MARK: - UTF-16

    @Test func readsLittleEndianUTF16TextWithAByteOrderMark() throws {
        let bytes = Data([0xFF, 0xFE]) + Self.utf16Bytes(of: Self.text, littleEndian: true)
        let url = try Self.makeFile(holding: bytes)
        defer { Self.remove(url) }

        #expect(try MarkdownFile.load(from: url).contents == Self.text)
    }

    @Test func readsBigEndianUTF16TextWithAByteOrderMark() throws {
        let bytes = Data([0xFE, 0xFF]) + Self.utf16Bytes(of: Self.text, littleEndian: false)
        let url = try Self.makeFile(holding: bytes)
        defer { Self.remove(url) }

        #expect(try MarkdownFile.load(from: url).contents == Self.text)
    }

    // MARK: - Bytes that are not text the app reads

    private static func expectRefused(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = try makeFile(holding: data)
        defer { remove(url) }

        let error = #expect(throws: CocoaError.self, sourceLocation: sourceLocation) {
            try MarkdownFile.load(from: url)
        }
        #expect(error?.code == .fileReadInapplicableStringEncoding, sourceLocation: sourceLocation)
    }

    // Text from before UTF-8 was everywhere: one byte to a letter, the accented
    // ones above 0x7F. It is not UTF-8, UTF-16 or ASCII, so there is nothing to
    // show for it but the error.
    @Test func textInAnEncodingTheAppDoesNotReadIsRefused() throws {
        let latin1 = try #require("Un café, s'il vous plaît.".data(using: .isoLatin1))

        try Self.expectRefused(latin1)
    }

    @Test func textInMacRomanIsRefused() throws {
        let macRoman = try #require("Un café, s'il vous plaît.".data(using: .macOSRoman))

        try Self.expectRefused(macRoman)
    }

    // A file that is not text at all, whatever it is called.
    @Test func aFileThatIsNotTextIsRefused() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52])

        try Self.expectRefused(png)
    }

    // UTF-16 is read only when the file says that is what it is, with a
    // byte-order mark. Without one there is no telling it from any other bytes.
    @Test(arguments: [true, false])
    func utf16TextWithNoByteOrderMarkIsRefused(littleEndian: Bool) throws {
        try Self.expectRefused(Self.utf16Bytes(of: Self.text, littleEndian: littleEndian))
    }

    @Test func aByteOrderMarkFollowedByHalfACharacterIsRefused() throws {
        // A UTF-16 high surrogate with no low surrogate after it.
        try Self.expectRefused(Data([0xFF, 0xFE, 0x00, 0xD8]))
    }

    // MARK: - Files that are not there

    // The read retries for half a minute when a file is reported absent, which
    // is for a file in iCloud that has not arrived yet. A file that is simply
    // not there must not wait that out: the store asks for every document in
    // the list on a timer, on the main thread.
    @Test func aMissingFileFailsWithoutWaiting() throws {
        let url = try Self.makeFile(holding: Data("gone".utf8))
        Self.remove(url)

        let clock = ContinuousClock()
        var thrown: (any Error)?
        let elapsed = clock.measure {
            do {
                _ = try MarkdownFile.load(from: url)
            } catch {
                thrown = error
            }
        }

        let error = try #require(thrown) as NSError
        #expect(error.domain == NSCocoaErrorDomain)
        #expect(error.code == NSFileReadNoSuchFileError)
        #expect(elapsed < .seconds(5))
    }

    // MARK: - The rest of the type

    @Test func theFileNameIsTheLastPartOfThePath() {
        let file = MarkdownFile(url: URL(fileURLWithPath: "/Users/syd/Docs/My Notes.md"), contents: "")

        #expect(file.fileName == "My Notes.md")
    }

    @Test func thePickerOffersMarkdownAndPlainTextOnceEach() throws {
        let types = MarkdownFile.supportedTypes
        let markdown = try #require(UTType(filenameExtension: "md"))

        #expect(types.contains(markdown))
        #expect(types.contains(.plainText))
        #expect(Set(types).count == types.count)
    }
}
