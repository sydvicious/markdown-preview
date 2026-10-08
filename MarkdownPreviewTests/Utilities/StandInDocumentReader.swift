//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing

/// Stands in for reading documents' files, for tests of what the store does
/// about reads that take time.
///
/// A file named as not delivered is refused the way the app's own read refuses
/// one iCloud has not delivered. Nothing happens in the background: a wait for
/// a file lasts until the test delivers it or gives up on it, and files asked
/// for in the background are read when the test says they have been.
@MainActor
final class StandInDocumentReader {
    /// The names of the files that have not been delivered.
    var undelivered: Set<String> = []
    /// The files read where the store asked, which is the main actor.
    private(set) var readsOnTheSpot: [String] = []
    /// The files asked for in the background, one list for each time of asking.
    private(set) var backgroundReads: [[String]] = []
    private(set) var waitsStarted = 0

    private var waits: [String: Wait] = [:]
    private var batches: [Batch] = []

    private struct Wait {
        let url: URL
        let deliver: @MainActor @Sendable (Result<MarkdownFile, Error>) -> Void
    }

    private struct Batch {
        let urls: [URL]
        let deliver: @MainActor @Sendable ([Result<MarkdownFile, Error>]) -> Void
    }

    var reader: DocumentReader {
        DocumentReader(
            read: { [self] url in
                readsOnTheSpot.append(url.lastPathComponent)
                return try read(url)
            },
            readWhenDelivered: { [self] url, deliver in
                waitsStarted += 1
                waits[url.lastPathComponent] = Wait(url: url, deliver: deliver)
            },
            readInBackground: { [self] urls, deliver in
                backgroundReads.append(urls.map(\.lastPathComponent))
                batches.append(Batch(urls: urls, deliver: deliver))
            }
        )
    }

    private func read(_ url: URL) throws -> MarkdownFile {
        guard !undelivered.contains(url.lastPathComponent) else {
            throw MarkdownFile.NotDelivered()
        }
        return try MarkdownFile.load(from: url)
    }

    /// iCloud delivers the file, and whoever was waiting for it reads it.
    func deliver(_ name: String) throws {
        undelivered.remove(name)
        let waiting = waits.removeValue(forKey: name)
        let wait = try #require(waiting)
        wait.deliver(.success(try MarkdownFile.load(from: wait.url)))
    }

    /// The wait for the file runs out.
    func giveUp(on name: String) throws {
        let waiting = waits.removeValue(forKey: name)
        let wait = try #require(waiting)
        wait.deliver(.failure(CocoaError(.ubiquitousFileUnavailable)))
    }

    /// The files asked for longest ago in the background have been read.
    func finishBackgroundReads() throws {
        try #require(!batches.isEmpty)
        let batch = batches.removeFirst()
        batch.deliver(batch.urls.map { url in Result { try read(url) } })
    }

    /// Everything asked for in the background has been read, and whatever
    /// that led to being asked for.
    func finishAllBackgroundReads() throws {
        while !batches.isEmpty {
            try finishBackgroundReads()
        }
    }

    /// Starts the counts again, to count what one step asks for.
    func forgetWhatWasAskedFor() {
        readsOnTheSpot = []
        backgroundReads = []
    }
}

/// Counts the security scopes held: taken, and not yet released.
@MainActor
final class SecurityScopeCount {
    private(set) var held = 0
    private(set) var mostHeld = 0

    var scope: SecurityScope {
        SecurityScope(
            start: { [self] _ in
                held += 1
                mostHeld = max(mostHeld, held)
                return true
            },
            stop: { [self] _ in
                held -= 1
            }
        )
    }
}

/// A folder of files, somewhere to save a list of them, and stores that read
/// them through a stand-in.
@MainActor
final class SavedDocumentsFixture {
    let reader = StandInDocumentReader()
    let directory: URL
    let defaults: UserDefaults
    private let suiteName: String
    private var saves = 0

    init() throws {
        let name = "SavedDocumentsFixture-\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = name
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func url(of name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    @discardableResult
    func write(_ name: String, holding contents: String) throws -> URL {
        let url = url(of: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Saves `contents` over a file, dated later than anything a store has
    /// seen of it.
    func save(_ contents: String, over name: String) throws {
        let url = try write(name, holding: contents)
        saves += 1
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(TimeInterval(60 * saves))],
            ofItemAtPath: url.path
        )
    }

    /// A store with nothing in it.
    func makeStore(scope: SecurityScope = .system) -> DocumentSessionStore {
        DocumentSessionStore(
            disablePersistenceRestore: true,
            userDefaults: defaults,
            securityScope: scope,
            documentReader: reader.reader
        )
    }

    /// A store with these files open in it, the last of them on screen. Each
    /// holds `Text of` and its name.
    func makeStore(holding names: [String]) throws -> DocumentSessionStore {
        let store = makeStore()
        for name in names {
            try store.openDocument(at: write(name, holding: "Text of \(name)"))
        }
        return store
    }

    func makeStore(holding names: String...) throws -> DocumentSessionStore {
        try makeStore(holding: names)
    }

    /// Saves what the app saves of a store: its list, which document is on
    /// screen, and the text sizes.
    func save(_ store: DocumentSessionStore) {
        store.persistDocuments(to: defaults)
        store.persistSelectedDocument(to: defaults)
        store.persistTextSizes(to: defaults)
    }

    /// A store as the app makes one at launch, with what was last saved
    /// restored into it. What was asked of the reader before is forgotten, so
    /// that its counts are of the launch.
    func relaunch(scope: SecurityScope = .system) -> DocumentSessionStore {
        reader.forgetWhatWasAskedFor()
        let store = DocumentSessionStore(
            disablePersistenceRestore: false,
            userDefaults: defaults,
            securityScope: scope,
            documentReader: reader.reader
        )
        store.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)
        return store
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

extension DocumentSessionStore {
    /// The names of the listed documents, in the order the list shows them.
    var listedNames: [String] {
        sortedDocuments.map(\.file.fileName)
    }

    /// The name of the document on screen.
    var nameOnScreen: String? {
        currentDocument?.file.fileName
    }

    func document(named name: String) -> OpenedDocument? {
        openedDocuments.first { $0.file.fileName == name }
    }
}

extension DocumentReader {
    /// Reads as the app does, except that what is asked for in the background
    /// is read on the spot. For a test of something else, which wants a
    /// restored list with its text already in it.
    @MainActor
    static var readingAtOnce: DocumentReader {
        DocumentReader(
            read: system.read,
            readWhenDelivered: system.readWhenDelivered,
            readInBackground: { urls, deliver in
                deliver(urls.map { url in Result { try MarkdownFile.load(from: url) } })
            }
        )
    }
}
