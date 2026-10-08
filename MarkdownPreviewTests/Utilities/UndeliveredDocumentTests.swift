//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Combine
import Foundation
import SwiftUI
import Testing

/// Documents whose files iCloud has not delivered to this device.
///
/// Reading one waits for it to arrive, and the store reads on the main actor.
/// So the store does not read it. It asks for it and carries on, and finishes
/// what it was doing, opening the document or restoring it at launch, when the
/// file comes. A document already in the list is left as it is until then.
@MainActor
struct UndeliveredDocumentTests {

    /// Stands in for reading files. A file named as not delivered is refused
    /// the way the app's own read refuses one iCloud has not delivered, and a
    /// wait for it lasts until the test delivers it or gives up on it.
    @MainActor
    private final class StandInReader {
        /// The names of the files that have not been delivered.
        var undelivered: Set<String> = []
        private(set) var waitsStarted = 0
        private var waits: [String: Wait] = [:]

        private struct Wait {
            let url: URL
            let deliver: @MainActor @Sendable (Result<MarkdownFile, Error>) -> Void
        }

        var reader: DocumentReader {
            DocumentReader(
                read: { [self] url in
                    guard !undelivered.contains(url.lastPathComponent) else {
                        throw MarkdownFile.NotDelivered()
                    }
                    return try MarkdownFile.load(from: url)
                },
                readWhenDelivered: { [self] url, deliver in
                    waitsStarted += 1
                    waits[url.lastPathComponent] = Wait(url: url, deliver: deliver)
                }
            )
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
    }

    /// Counts how often a security scope is taken and released.
    @MainActor
    private final class ScopeCount {
        private(set) var held = 0

        var scope: SecurityScope {
            SecurityScope(
                start: { [self] _ in
                    held += 1
                    return true
                },
                stop: { [self] _ in
                    held -= 1
                }
            )
        }
    }

    /// What the store said of the documents it had to wait for.
    @MainActor
    private final class Arrivals {
        private(set) var shown: [String] = []
        private(set) var listed: [String] = []
        private(set) var failed: [String] = []
        private var watching: AnyCancellable?

        init(of store: DocumentSessionStore) {
            watching = store.lateArrivals.sink { [self] arrival in
                switch arrival {
                case .arrived(let id, let isShown):
                    let name = URL(fileURLWithPath: id).lastPathComponent
                    if isShown {
                        shown.append(name)
                    } else {
                        listed.append(name)
                    }
                case .failedToOpen(let url, _):
                    failed.append(url.lastPathComponent)
                }
            }
        }
    }

    /// A folder of files, somewhere to save a list of them, and stores that
    /// read them through the stand-in.
    @MainActor
    private final class Fixture {
        let reader = StandInReader()
        let directory: URL
        let defaults: UserDefaults
        private let suiteName: String
        private var saves = 0

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("UndeliveredDocumentTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            suiteName = "UndeliveredDocumentTests.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)
        }

        @discardableResult
        func write(_ name: String, holding contents: String) throws -> URL {
            let url = directory.appendingPathComponent(name)
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

        /// A store with these files open in it, the last of them on screen.
        func makeStore(holding names: String...) throws -> DocumentSessionStore {
            let store = makeStore()
            for name in names {
                try store.openDocument(at: write(name, holding: "Text of \(name)"))
            }
            return store
        }

        /// Saves what the app saves of a store: its list, which document is on
        /// screen, and the text sizes.
        func save(_ store: DocumentSessionStore) {
            store.persistDocuments(to: defaults)
            store.persistSelectedDocument(to: defaults)
            store.persistTextSizes(to: defaults)
        }

        /// A store as the app makes one at launch, with what was last saved
        /// restored into it.
        func relaunch() -> DocumentSessionStore {
            let store = DocumentSessionStore(
                disablePersistenceRestore: false,
                userDefaults: defaults,
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

    private static func names(in store: DocumentSessionStore) -> [String] {
        store.sortedDocuments.map(\.file.fileName)
    }

    private static func document(_ name: String, in store: DocumentSessionStore) -> DocumentSessionStore.OpenedDocument? {
        store.openedDocuments.first { $0.file.fileName == name }
    }

    private static func onScreen(in store: DocumentSessionStore) -> String? {
        store.currentDocument?.file.fileName
    }

    // MARK: - Opening a document

    @Test func openingAFileICloudHasNotDeliveredListsNothingYetAndWaitsForIt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        let store = fixture.makeStore()

        let opening = try store.openDocument(at: url)

        #expect(opening == .onItsWay)
        #expect(store.openedDocuments.isEmpty)
        #expect(fixture.reader.waitsStarted == 1)
    }

    @Test func openingAFileThatIsHereShowsItAtOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        let store = fixture.makeStore()

        let opening = try store.openDocument(at: url)

        #expect(opening == .shown)
        #expect(Self.onScreen(in: store) == "notes.md")
        #expect(fixture.reader.waitsStarted == 0)
    }

    @Test func aFileOpenedBeforeICloudDeliveredItIsListedAndShownWhenItArrives() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "other.md")
        let arrivals = Arrivals(of: store)
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        try store.openDocument(at: url)

        try fixture.reader.deliver("notes.md")

        #expect(Self.names(in: store) == ["notes.md", "other.md"])
        #expect(Self.onScreen(in: store) == "notes.md")
        #expect(store.currentDocument?.file.contents == "# Notes")
        #expect(store.documentMatchesListSearch(try #require(store.selectedDocumentID), query: "Notes"))
        #expect(arrivals.shown == ["notes.md"])
        #expect(arrivals.failed.isEmpty)
    }

    // The reader asked for this file and is owed the reason it never came.
    @Test func aFileOpenedThatICloudNeverDeliversIsReportedAndNotListed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "other.md")
        let arrivals = Arrivals(of: store)
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        try store.openDocument(at: url)

        try fixture.reader.giveUp(on: "notes.md")

        #expect(Self.names(in: store) == ["other.md"])
        #expect(Self.onScreen(in: store) == "other.md")
        #expect(arrivals.failed == ["notes.md"])
        #expect(arrivals.shown.isEmpty)
    }

    @Test func openingAFileAgainWhileItIsOnItsWayWaitsForItOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        let store = fixture.makeStore()

        try store.openDocument(at: url)
        try store.openDocument(at: url)
        try fixture.reader.deliver("notes.md")

        #expect(fixture.reader.waitsStarted == 1)
        #expect(Self.names(in: store) == ["notes.md"])
    }

    // iCloud can take back the contents of a file the app has open, to make
    // room. The document is in the list with the text it had, and that is
    // what opening it again shows.
    @Test func openingAListedDocumentICloudHasTakenBackShowsItAsItWas() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "notes.md", "other.md")
        fixture.reader.undelivered = ["notes.md"]

        let opening = try store.openDocument(at: fixture.directory.appendingPathComponent("notes.md"))

        #expect(opening == .shown)
        #expect(Self.onScreen(in: store) == "notes.md")
        #expect(store.currentDocument?.file.contents == "Text of notes.md")
        #expect(fixture.reader.waitsStarted == 0)
    }

    @Test func aFileThatArrivesAfterItWasOpenedAgainIsListedOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        let store = fixture.makeStore()
        try store.openDocument(at: url)

        fixture.reader.undelivered = []
        try store.openDocument(at: url)
        try fixture.reader.deliver("notes.md")

        #expect(Self.names(in: store) == ["notes.md"])
    }

    // An empty list at launch is met with the Open panel. A list whose only
    // document is still coming is not empty.
    @Test func aStoreWithADocumentOnItsWayIsNotWithoutDocuments() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        let store = fixture.makeStore()
        #expect(store.hasNoDocumentsHereOrOnTheirWay)

        try store.openDocument(at: url)
        #expect(!store.hasNoDocumentsHereOrOnTheirWay)

        try fixture.reader.giveUp(on: "notes.md")
        #expect(store.hasNoDocumentsHereOrOnTheirWay)
    }

    // The file is read, when it comes, somewhere other than the main actor,
    // and outside the sandbox that takes the scope its bookmark carries.
    @Test(arguments: [true, false])
    func theSecurityScopeIsHeldUntilTheWaitIsOver(arrives: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        let scopes = ScopeCount()
        let store = fixture.makeStore(scope: scopes.scope)

        try store.openDocument(at: url)
        #expect(scopes.held == 1)

        if arrives {
            try fixture.reader.deliver("notes.md")
        } else {
            try fixture.reader.giveUp(on: "notes.md")
        }
        #expect(scopes.held == 0)
    }

    // MARK: - Restoring the saved list at launch

    @Test func aSavedDocumentICloudHasNotDeliveredIsListedWhenItArrives() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let saved = try fixture.makeStore(holding: "alpha.md", "beta.md")
        let lastOpened = try #require(Self.document("beta.md", in: saved)).lastOpened
        fixture.save(saved)
        fixture.reader.undelivered = ["beta.md"]

        let store = fixture.relaunch()
        let arrivals = Arrivals(of: store)
        #expect(Self.names(in: store) == ["alpha.md"])

        try fixture.reader.deliver("beta.md")

        #expect(Self.names(in: store) == ["alpha.md", "beta.md"])
        let beta = try #require(Self.document("beta.md", in: store))
        #expect(beta.file.contents == "Text of beta.md")
        #expect(abs(beta.lastOpened.timeIntervalSince(lastOpened)) < 0.001)
        #expect(store.documentMatchesListSearch(beta.id, query: "beta"))
        #expect(arrivals.failed.isEmpty)
    }

    @Test func aSavedDocumentThatWasOnScreenIsShownWhenItArrives() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.save(try fixture.makeStore(holding: "alpha.md", "beta.md"))
        fixture.reader.undelivered = ["beta.md"]

        let store = fixture.relaunch()
        let arrivals = Arrivals(of: store)
        #expect(store.selectedDocumentID == nil)

        try fixture.reader.deliver("beta.md")

        #expect(Self.onScreen(in: store) == "beta.md")
        #expect(arrivals.shown == ["beta.md"])
    }

    @Test func aSavedDocumentThatArrivesDoesNotTakeTheScreenFromTheOneTheReaderChose() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.save(try fixture.makeStore(holding: "alpha.md", "beta.md"))
        fixture.reader.undelivered = ["beta.md"]
        let store = fixture.relaunch()
        let arrivals = Arrivals(of: store)
        store.selectedDocumentID = try #require(Self.document("alpha.md", in: store)).id

        try fixture.reader.deliver("beta.md")

        #expect(Self.onScreen(in: store) == "alpha.md")
        #expect(arrivals.listed == ["beta.md"])
        #expect(arrivals.shown.isEmpty)
    }

    @Test func ofTheSavedDocumentsThatArriveOnlyTheOneThatWasOnScreenIsShown() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.save(try fixture.makeStore(holding: "alpha.md", "beta.md", "gamma.md"))
        fixture.reader.undelivered = ["alpha.md", "gamma.md"]
        let store = fixture.relaunch()
        try fixture.reader.deliver("alpha.md")
        #expect(store.selectedDocumentID == nil)

        try fixture.reader.deliver("gamma.md")

        #expect(Self.onScreen(in: store) == "gamma.md")
        #expect(Self.names(in: store) == ["alpha.md", "beta.md", "gamma.md"])
    }

    // The app saves its list whenever the list changes, and the list changes
    // as it is restored. A document that is still coming is not in the list,
    // and is saved with it all the same: a launch that ends before the file
    // comes must not be the end of it.
    @Test func aSavedDocumentOnItsWayStaysInTheSavedList() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.save(try fixture.makeStore(holding: "alpha.md", "beta.md"))
        fixture.reader.undelivered = ["beta.md"]
        fixture.save(fixture.relaunch())

        fixture.reader.undelivered = []
        let store = fixture.relaunch()

        #expect(Self.names(in: store) == ["alpha.md", "beta.md"])
        #expect(Self.onScreen(in: store) == "beta.md")
    }

    @Test func aSavedDocumentOnItsWayKeepsItsTextSize() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let saved = try fixture.makeStore(holding: "alpha.md", "beta.md")
        let beta = try #require(Self.document("beta.md", in: saved)).id
        saved.increaseTextSize(for: beta)
        let textSize = saved.textSize(for: beta)
        fixture.save(saved)
        fixture.reader.undelivered = ["beta.md"]

        let store = fixture.relaunch()
        fixture.save(store)
        try fixture.reader.deliver("beta.md")

        #expect(textSize != .defaultValue)
        #expect(store.textSize(for: beta) == textSize)
    }

    // As a saved document that cannot be read has always been dropped. Nobody
    // asked for this one just now, so nobody is told.
    @Test func aSavedDocumentThatNeverArrivesIsDroppedFromTheList() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let saved = try fixture.makeStore(holding: "alpha.md", "beta.md")
        let beta = try #require(Self.document("beta.md", in: saved)).id
        saved.increaseTextSize(for: beta)
        fixture.save(saved)
        fixture.reader.undelivered = ["beta.md"]
        let store = fixture.relaunch()
        let arrivals = Arrivals(of: store)

        try fixture.reader.giveUp(on: "beta.md")
        fixture.save(store)

        #expect(Self.names(in: store) == ["alpha.md"])
        #expect(store.textSize(for: beta) == .defaultValue)
        #expect(arrivals.failed.isEmpty)
        fixture.reader.undelivered = []
        #expect(Self.names(in: fixture.relaunch()) == ["alpha.md"])
    }

    // MARK: - Checking a listed document for changes

    // A newer version in iCloud changes the file's date before its contents
    // are here. The document has not gone anywhere: the reader keeps the text
    // they have until the new text can be read.
    @Test func aDocumentOnScreenWhoseNewTextHasNotBeenDeliveredIsLeftAsItIs() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "notes.md")
        try fixture.save("Newer text", over: "notes.md")
        fixture.reader.undelivered = ["notes.md"]

        store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(store.missingActiveDocumentAlert == nil)
        #expect(store.currentDocument?.file.contents == "Text of notes.md")
        #expect(fixture.reader.waitsStarted == 0)

        fixture.reader.undelivered = []
        store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(store.currentDocument?.file.contents == "Newer text")
    }

    @Test func aDocumentNotOnScreenWhoseNewTextHasNotBeenDeliveredStaysInTheList() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "notes.md", "on-screen.md")
        try fixture.save("Newer text", over: "notes.md")
        fixture.reader.undelivered = ["notes.md"]

        store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(Self.names(in: store) == ["notes.md", "on-screen.md"])
        #expect(Self.document("notes.md", in: store)?.file.contents == "Text of notes.md")

        fixture.reader.undelivered = []
        store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(Self.document("notes.md", in: store)?.file.contents == "Newer text")
    }

    @Test func aDocumentThatWasMovedAndHasNotBeenDeliveredIsNotTakenForMissing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "notes.md")
        try FileManager.default.moveItem(
            at: fixture.directory.appendingPathComponent("notes.md"),
            to: fixture.directory.appendingPathComponent("renamed.md")
        )
        fixture.reader.undelivered = ["renamed.md"]

        store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(store.missingActiveDocumentAlert == nil)
        #expect(Self.names(in: store) == ["notes.md"])

        fixture.reader.undelivered = []
        store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(Self.names(in: store) == ["renamed.md"])
        #expect(Self.onScreen(in: store) == "renamed.md")
    }
}
