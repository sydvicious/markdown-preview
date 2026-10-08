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
/// So the store does not read it. It asks for it and carries on, and opens the
/// document when the file comes. A document already in the list is left as it
/// is until then.
///
/// A document restored from the saved list whose file has not been delivered
/// is in `RestoredDocumentTests`, with the rest of what a launch reads.
@MainActor
struct UndeliveredDocumentTests {

    /// What the store said of the documents it had to wait for.
    @MainActor
    private final class Arrivals {
        private(set) var shown: [String] = []
        private(set) var failed: [String] = []
        private var watching: AnyCancellable?

        init(of store: DocumentSessionStore) {
            watching = store.lateArrivals.sink { [self] arrival in
                switch arrival {
                case .arrived(let id):
                    shown.append(URL(fileURLWithPath: id).lastPathComponent)
                case .failedToOpen(let url, _):
                    failed.append(url.lastPathComponent)
                }
            }
        }
    }

    // MARK: - Opening a document

    @Test func openingAFileICloudHasNotDeliveredListsNothingYetAndWaitsForIt() throws {
        let fixture = try SavedDocumentsFixture()
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
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        let store = fixture.makeStore()

        let opening = try store.openDocument(at: url)

        #expect(opening == .shown)
        #expect(store.nameOnScreen == "notes.md")
        #expect(fixture.reader.waitsStarted == 0)
    }

    @Test func aFileOpenedBeforeICloudDeliveredItIsListedAndShownWhenItArrives() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "other.md")
        let arrivals = Arrivals(of: store)
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        try store.openDocument(at: url)

        try fixture.reader.deliver("notes.md")

        #expect(store.listedNames == ["notes.md", "other.md"])
        #expect(store.nameOnScreen == "notes.md")
        #expect(store.currentDocument?.file.contents == "# Notes")
        #expect(store.documentMatchesListSearch(try #require(store.selectedDocumentID), query: "Notes"))
        #expect(arrivals.shown == ["notes.md"])
        #expect(arrivals.failed.isEmpty)
    }

    // The reader asked for this file and is owed the reason it never came.
    @Test func aFileOpenedThatICloudNeverDeliversIsReportedAndNotListed() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "other.md")
        let arrivals = Arrivals(of: store)
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        try store.openDocument(at: url)

        try fixture.reader.giveUp(on: "notes.md")

        #expect(store.listedNames == ["other.md"])
        #expect(store.nameOnScreen == "other.md")
        #expect(arrivals.failed == ["notes.md"])
        #expect(arrivals.shown.isEmpty)
    }

    @Test func openingAFileAgainWhileItIsOnItsWayWaitsForItOnce() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        let store = fixture.makeStore()

        try store.openDocument(at: url)
        try store.openDocument(at: url)
        try fixture.reader.deliver("notes.md")

        #expect(fixture.reader.waitsStarted == 1)
        #expect(store.listedNames == ["notes.md"])
    }

    // iCloud can take back the contents of a file the app has open, to make
    // room. The document is in the list with the text it had, and that is
    // what opening it again shows.
    @Test func openingAListedDocumentICloudHasTakenBackShowsItAsItWas() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "notes.md", "other.md")
        fixture.reader.undelivered = ["notes.md"]

        let opening = try store.openDocument(at: fixture.url(of: "notes.md"))

        #expect(opening == .shown)
        #expect(store.nameOnScreen == "notes.md")
        #expect(store.currentDocument?.file.contents == "Text of notes.md")
        #expect(fixture.reader.waitsStarted == 0)
    }

    @Test func aFileThatArrivesAfterItWasOpenedAgainIsListedOnce() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        let store = fixture.makeStore()
        try store.openDocument(at: url)

        fixture.reader.undelivered = []
        try store.openDocument(at: url)
        try fixture.reader.deliver("notes.md")

        #expect(store.listedNames == ["notes.md"])
    }

    // An empty list at launch is met with the Open panel. A list whose only
    // document is still coming is not empty.
    @Test func aStoreWithADocumentOnItsWayIsNotWithoutDocuments() throws {
        let fixture = try SavedDocumentsFixture()
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
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let url = try fixture.write("notes.md", holding: "# Notes")
        fixture.reader.undelivered = ["notes.md"]
        let scopes = SecurityScopeCount()
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

    // MARK: - Checking a listed document for changes

    // A newer version in iCloud changes the file's date before its contents
    // are here. The document has not gone anywhere: the reader keeps the text
    // they have until the new text can be read.
    @Test func aDocumentOnScreenWhoseNewTextHasNotBeenDeliveredIsLeftAsItIs() throws {
        let fixture = try SavedDocumentsFixture()
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
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "notes.md", "on-screen.md")
        try fixture.save("Newer text", over: "notes.md")
        fixture.reader.undelivered = ["notes.md"]

        store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(store.listedNames == ["notes.md", "on-screen.md"])
        #expect(store.document(named: "notes.md")?.file.contents == "Text of notes.md")

        fixture.reader.undelivered = []
        store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(store.document(named: "notes.md")?.file.contents == "Newer text")
    }

    @Test func aDocumentThatWasMovedAndHasNotBeenDeliveredIsNotTakenForMissing() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try fixture.makeStore(holding: "notes.md")
        try FileManager.default.moveItem(
            at: fixture.url(of: "notes.md"),
            to: fixture.url(of: "renamed.md")
        )
        fixture.reader.undelivered = ["renamed.md"]

        store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(store.missingActiveDocumentAlert == nil)
        #expect(store.listedNames == ["notes.md"])

        fixture.reader.undelivered = []
        store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(store.listedNames == ["renamed.md"])
        #expect(store.nameOnScreen == "renamed.md")
    }
}
