//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Combine
import Foundation
import SwiftUI
import Testing

/// What a launch reads of the saved list of documents, and where.
///
/// The list is put back from the bookmarks alone, which say where each file is
/// and so what it is called. No file is read for that, and none is read on the
/// main actor: the text of each is read in the background, the document on
/// screen first, and until it is the document is in the list with no text.
@MainActor
struct RestoredDocumentTests {

    /// A store relaunched from a saved list of these files, the last of them
    /// on screen, unless another is named.
    private static func relaunched(
        _ fixture: SavedDocumentsFixture,
        holding names: [String],
        onScreen: String? = nil,
        scope: SecurityScope = .system
    ) throws -> DocumentSessionStore {
        let saved = try fixture.makeStore(holding: names)
        if let onScreen {
            saved.selectedDocumentID = try #require(saved.document(named: onScreen)).id
        }
        fixture.save(saved)
        return fixture.relaunch(scope: scope)
    }

    // MARK: - The list

    @Test func theWholeListIsRestoredWithoutReadingAFileOnTheMainActor() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }

        let store = try Self.relaunched(fixture, holding: ["alpha.md", "beta.md", "gamma.md"], onScreen: "beta.md")

        #expect(store.listedNames == ["alpha.md", "beta.md", "gamma.md"])
        #expect(store.nameOnScreen == "beta.md")
        #expect(fixture.reader.readsOnTheSpot.isEmpty)
        #expect(store.openedDocuments.allSatisfy { !$0.isRead && $0.file.contents.isEmpty })
    }

    @Test func aRestoredDocumentHasItsTextOnceItIsRead() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try Self.relaunched(fixture, holding: ["alpha.md", "beta.md"])

        try fixture.reader.finishAllBackgroundReads()

        #expect(store.listedNames == ["alpha.md", "beta.md"])
        #expect(store.nameOnScreen == "beta.md")
        #expect(store.openedDocuments.allSatisfy { $0.isRead })
        let alpha = try #require(store.document(named: "alpha.md"))
        #expect(alpha.file.contents == "Text of alpha.md")
        #expect(store.documentMatchesListSearch(alpha.id, query: "Text of alpha"))
        #expect(fixture.reader.readsOnTheSpot.isEmpty)
    }

    @Test func aDocumentOpenedInTheNormalWayIsRead() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }

        let store = try fixture.makeStore(holding: "alpha.md")

        #expect(store.document(named: "alpha.md")?.isRead == true)
    }

    // MARK: - The order of reading

    // The reader is waiting for the one on screen and for no other.
    @Test func theDocumentOnScreenIsReadFirstAndOnItsOwn() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try Self.relaunched(fixture, holding: ["alpha.md", "beta.md", "gamma.md"], onScreen: "beta.md")

        #expect(fixture.reader.backgroundReads == [["beta.md"]])

        try fixture.reader.finishBackgroundReads()

        #expect(store.document(named: "beta.md")?.file.contents == "Text of beta.md")
        #expect(store.document(named: "alpha.md")?.isRead == false)
        // The rest, the one opened last first.
        #expect(fixture.reader.backgroundReads == [["beta.md"], ["gamma.md", "alpha.md"]])
    }

    // Each file read in the background has its security scope held while it
    // is, and the system allows only so many at once.
    @Test func theRestAreReadSixteenAtATimeAndNoMoreScopesThanThatAreHeld() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let names = (1...20).map { "document-\($0).md" }
        let scopes = SecurityScopeCount()
        let store = try Self.relaunched(fixture, holding: names, scope: scopes.scope)

        #expect(scopes.held == 1)
        try fixture.reader.finishBackgroundReads()
        #expect(scopes.held == 16)
        try fixture.reader.finishBackgroundReads()
        #expect(scopes.held == 3)
        try fixture.reader.finishBackgroundReads()

        #expect(fixture.reader.backgroundReads.map(\.count) == [1, 16, 3])
        #expect(scopes.held == 0)
        #expect(scopes.mostHeld == 16)
        #expect(store.openedDocuments.count == 20)
        #expect(store.openedDocuments.allSatisfy { $0.isRead })
    }

    @Test func withNothingOnScreenTheListIsReadInOrder() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let saved = try fixture.makeStore(holding: "alpha.md", "beta.md")
        saved.selectedDocumentID = nil
        fixture.save(saved)

        let store = fixture.relaunch()

        #expect(store.selectedDocumentID == nil)
        #expect(fixture.reader.backgroundReads == [["beta.md", "alpha.md"]])
    }

    // MARK: - While a document has not been read

    // The checks run as soon as the window is up, for every document, and
    // would read each one there and then.
    @Test func aCheckForChangesLeavesAloneADocumentThatHasNotBeenReadYet() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try Self.relaunched(fixture, holding: ["alpha.md", "beta.md"])

        store.checkActiveDocumentForChanges(isCompactWidth: false)
        store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.reader.readsOnTheSpot.isEmpty)
        #expect(store.missingActiveDocumentAlert == nil)
        #expect(store.listedNames == ["alpha.md", "beta.md"])
        #expect(store.openedDocuments.allSatisfy { !$0.isRead })
    }

    @Test func aRestoredDocumentThatHasBeenReadIsNotReadAgainByTheNextCheck() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try Self.relaunched(fixture, holding: ["alpha.md", "beta.md"])
        try fixture.reader.finishAllBackgroundReads()

        store.checkActiveDocumentForChanges(isCompactWidth: false)
        store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.reader.readsOnTheSpot.isEmpty)
    }

    @Test func aRestoredDocumentThatChangesOnDiskOnceReadIsReadAgain() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try Self.relaunched(fixture, holding: ["alpha.md", "beta.md"])
        try fixture.reader.finishAllBackgroundReads()

        try fixture.save("Newer text", over: "alpha.md")
        store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(store.document(named: "alpha.md")?.file.contents == "Newer text")
    }

    // Opened from the Finder, say, in the moment after a launch.
    @Test func openingARestoredDocumentBeforeItIsReadReadsItThen() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try Self.relaunched(fixture, holding: ["alpha.md", "beta.md"])

        try store.openDocument(at: fixture.url(of: "alpha.md"))

        let alpha = try #require(store.document(named: "alpha.md"))
        #expect(alpha.isRead)
        #expect(alpha.file.contents == "Text of alpha.md")
        #expect(store.nameOnScreen == "alpha.md")

        try fixture.reader.finishAllBackgroundReads()

        #expect(store.listedNames == ["alpha.md", "beta.md"])
        #expect(store.document(named: "alpha.md")?.file.contents == "Text of alpha.md")
    }

    @Test func aDocumentRemovedBeforeItWasReadStaysRemoved() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let store = try Self.relaunched(fixture, holding: ["alpha.md", "beta.md"])

        store.removeDocument(id: try #require(store.document(named: "alpha.md")).id, isCompactWidth: false)
        try fixture.reader.finishAllBackgroundReads()

        #expect(store.listedNames == ["beta.md"])
    }

    // MARK: - Files that are not there, or cannot be read

    // A file that has gone is known to have gone without reading anything,
    // and its document is never in the list.
    @Test func aSavedDocumentWhoseFileHasGoneIsNotListed() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        fixture.save(try fixture.makeStore(holding: "alpha.md", "beta.md"))
        try FileManager.default.removeItem(at: fixture.url(of: "beta.md"))

        let store = fixture.relaunch()

        #expect(store.listedNames == ["alpha.md"])
        #expect(store.selectedDocumentID == nil)
    }

    // That a file is not text the app reads is only found by reading it, so
    // its document is in the list until it has been.
    @Test func aSavedDocumentThatTurnsOutNotToBeReadableIsDroppedWithItsTextSize() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let saved = try fixture.makeStore(holding: "alpha.md", "beta.md")
        let beta = try #require(saved.document(named: "beta.md")).id
        saved.increaseTextSize(for: beta)
        fixture.save(saved)
        let latin1 = try #require("Un café, s'il vous plaît.".data(using: .isoLatin1))
        try latin1.write(to: fixture.url(of: "beta.md"))

        let store = fixture.relaunch()
        #expect(store.listedNames == ["alpha.md", "beta.md"])

        try fixture.reader.finishAllBackgroundReads()

        #expect(store.listedNames == ["alpha.md"])
        #expect(store.selectedDocumentID == nil)
        #expect(store.textSize(for: beta) == .defaultValue)
        #expect(store.document(named: "alpha.md")?.isRead == true)
    }

    // MARK: - Files iCloud has not delivered

    @Test func aSavedDocumentICloudHasNotDeliveredStaysListedAndIsWaitedFor() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        fixture.save(try fixture.makeStore(holding: "alpha.md", "beta.md"))
        fixture.reader.undelivered = ["beta.md"]
        let scopes = SecurityScopeCount()

        let store = fixture.relaunch(scope: scopes.scope)
        try fixture.reader.finishAllBackgroundReads()

        #expect(store.listedNames == ["alpha.md", "beta.md"])
        #expect(store.nameOnScreen == "beta.md")
        #expect(store.document(named: "beta.md")?.isRead == false)
        #expect(store.document(named: "alpha.md")?.isRead == true)
        #expect(scopes.held == 1)

        try fixture.reader.deliver("beta.md")

        let beta = try #require(store.document(named: "beta.md"))
        #expect(beta.isRead)
        #expect(beta.file.contents == "Text of beta.md")
        #expect(store.nameOnScreen == "beta.md")
        #expect(scopes.held == 0)
    }

    // As a saved document that cannot be read is dropped. Nobody asked for
    // this one just now, so nobody is told.
    @Test func aSavedDocumentICloudNeverDeliversIsDropped() throws {
        let fixture = try SavedDocumentsFixture()
        defer { fixture.cleanUp() }
        let saved = try fixture.makeStore(holding: "alpha.md", "beta.md")
        let beta = try #require(saved.document(named: "beta.md")).id
        saved.increaseTextSize(for: beta)
        fixture.save(saved)
        fixture.reader.undelivered = ["beta.md"]
        let scopes = SecurityScopeCount()
        let store = fixture.relaunch(scope: scopes.scope)
        var told = 0
        let watching = store.lateArrivals.sink { _ in told += 1 }
        defer { watching.cancel() }
        try fixture.reader.finishAllBackgroundReads()

        try fixture.reader.giveUp(on: "beta.md")

        #expect(store.listedNames == ["alpha.md"])
        #expect(store.selectedDocumentID == nil)
        #expect(store.textSize(for: beta) == .defaultValue)
        #expect(told == 0)
        #expect(scopes.held == 0)
    }
}
