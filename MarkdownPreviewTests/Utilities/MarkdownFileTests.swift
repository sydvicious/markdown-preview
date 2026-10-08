//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os
import Testing
import UniformTypeIdentifiers

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

    // The store asks for every document in the list on a timer, on the main
    // thread, so a file that is not there says so at once.
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

    // MARK: - Files kept in iCloud

    /// Stands in for iCloud. It says of every file what it is told to, one
    /// answer for each time it is asked and the last of them from then on, and
    /// counts how often it is asked to deliver one.
    private final class StandInCloud: Sendable {
        private struct State {
            var answers: [MarkdownFile.CloudState]
            var requests = 0
        }

        private let state: OSAllocatedUnfairLock<State>

        init(saying answers: MarkdownFile.CloudState...) {
            state = OSAllocatedUnfairLock(initialState: State(answers: answers))
        }

        var requests: Int {
            state.withLock { $0.requests }
        }

        var delivery: MarkdownFile.CloudDelivery {
            MarkdownFile.CloudDelivery(
                state: { [state] _ in
                    state.withLock { $0.answers.count > 1 ? $0.answers.removeFirst() : $0.answers[0] }
                },
                request: { [state] _ in
                    state.withLock { $0.requests += 1 }
                }
            )
        }
    }

    // Reading a file iCloud has not delivered waits for it to arrive, on
    // whatever thread asked. So it is not read: it is asked for, and the
    // caller is told why it has nothing.
    @Test func aFileICloudHasNotDeliveredIsAskedForAndNotRead() throws {
        let url = try Self.makeFile(holding: Data(Self.text.utf8))
        defer { Self.remove(url) }
        let cloud = StandInCloud(saying: .notDelivered)

        #expect(throws: MarkdownFile.NotDelivered.self) {
            try MarkdownFile.load(from: url, cloud: cloud.delivery)
        }
        #expect(cloud.requests == 1)
    }

    // What is here is read, and the newer copy is asked for. It is found, when
    // it comes, by the check for changes on disk.
    @Test func aFileICloudHasANewerCopyOfIsReadAndTheNewerCopyAskedFor() throws {
        let url = try Self.makeFile(holding: Data(Self.text.utf8))
        defer { Self.remove(url) }
        let cloud = StandInCloud(saying: .outOfDate)

        let file = try MarkdownFile.load(from: url, cloud: cloud.delivery)

        #expect(file.contents == Self.text)
        #expect(cloud.requests == 1)
    }

    @Test(arguments: [MarkdownFile.CloudState.current, .notInCloud])
    func aFileThatIsAllHereIsReadAndNotAskedFor(state: MarkdownFile.CloudState) throws {
        let url = try Self.makeFile(holding: Data(Self.text.utf8))
        defer { Self.remove(url) }
        let cloud = StandInCloud(saying: state)

        let file = try MarkdownFile.load(from: url, cloud: cloud.delivery)

        #expect(file.contents == Self.text)
        #expect(cloud.requests == 0)
    }

    @Test func aFileIsReadOnceICloudDeliversIt() async throws {
        let url = try Self.makeFile(holding: Data(Self.text.utf8))
        defer { Self.remove(url) }
        let cloud = StandInCloud(saying: .notDelivered, .notDelivered, .current)

        let file = try await MarkdownFile.loadWhenDelivered(
            from: url,
            cloud: cloud.delivery,
            patience: .seconds(60),
            pause: .milliseconds(1)
        )

        #expect(file.contents == Self.text)
        #expect(cloud.requests == 2)
    }

    @Test func waitingForAFileICloudNeverDeliversGivesUp() async throws {
        let url = try Self.makeFile(holding: Data(Self.text.utf8))
        defer { Self.remove(url) }
        let cloud = StandInCloud(saying: .notDelivered)

        var thrown: (any Error)?
        do {
            _ = try await MarkdownFile.loadWhenDelivered(
                from: url,
                cloud: cloud.delivery,
                patience: .milliseconds(20),
                pause: .milliseconds(1)
            )
        } catch {
            thrown = error
        }

        let error = try #require(thrown) as NSError
        #expect(error.domain == NSCocoaErrorDomain)
        #expect(error.code == NSUbiquitousFileUnavailableError)
        #expect(cloud.requests > 1)
    }

    // Only a file that is on its way is waited for. One that arrived and
    // cannot be read is as unreadable in half a minute as it is now.
    @Test func aFileThatHasArrivedAndCannotBeReadIsNotWaitedFor() async throws {
        let latin1 = try #require("Un café, s'il vous plaît.".data(using: .isoLatin1))
        let url = try Self.makeFile(holding: latin1)
        defer { Self.remove(url) }
        let cloud = StandInCloud(saying: .current)

        let clock = ContinuousClock()
        let started = clock.now
        var thrown: (any Error)?
        do {
            _ = try await MarkdownFile.loadWhenDelivered(
                from: url,
                cloud: cloud.delivery,
                patience: .seconds(60),
                pause: .milliseconds(1)
            )
        } catch {
            thrown = error
        }

        #expect((thrown as? CocoaError)?.code == .fileReadInapplicableStringEncoding)
        #expect(clock.now - started < .seconds(5))
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
