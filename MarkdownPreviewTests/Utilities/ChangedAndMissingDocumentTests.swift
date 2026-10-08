//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import SwiftUI
import Testing
import MarkdownCore

/// Documents whose files change, or go away, while they are in the list.
///
/// The store looks at its documents again on a timer. The one on screen is
/// looked at by `checkActiveDocumentForChanges`, and a file that has gone is
/// reported to the reader, who is looking at it. The rest are looked at by
/// `checkAllDocumentsForChanges`, and one of those whose file has gone is
/// dropped from the list without a word.
///
/// A file that was moved is a third case, with tests of its own in
/// `MovedDocumentTests`.
@MainActor
struct ChangedAndMissingDocumentTests {

    /// A store, and a folder of files to open in it.
    @MainActor
    private final class Fixture {
        let store: DocumentSessionStore
        let directory: URL
        private var saves = 0

        init(resolver: BookmarkResolver = .system) throws {
            store = DocumentSessionStore(disablePersistenceRestore: true, bookmarkResolver: resolver)
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ChangedAndMissingDocumentTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        /// Writes a file and opens it, which also puts it on screen. Returns
        /// what the list knows the document by.
        @discardableResult
        func open(_ name: String, holding contents: String) throws -> String {
            let url = directory.appendingPathComponent(name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            try store.openDocument(at: url)
            return url.standardizedFileURL.path
        }

        /// Saves `contents` over a document's file, dated later than anything
        /// the store has seen of it.
        func save(_ contents: String, over id: String) throws {
            try contents.write(to: URL(fileURLWithPath: id), atomically: true, encoding: .utf8)
            saves += 1
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(TimeInterval(60 * saves))],
                ofItemAtPath: id
            )
        }

        func delete(_ id: String) throws {
            try FileManager.default.removeItem(atPath: id)
        }

        func document(_ id: String) -> DocumentSessionStore.OpenedDocument? {
            store.openedDocuments.first { $0.id == id }
        }

        var listed: [String] {
            store.sortedDocuments.map(\.file.fileName)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: - A document that is not on screen

    @Test func aDocumentThatIsNotOnScreenIsReloadedWhenItsFileChanges() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let other = try fixture.open("other.md", holding: "# Notes\n\nAlpha beta")
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")

        try fixture.save("# Notes\n\nGamma delta", over: other)
        fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.document(other)?.file.contents == "# Notes\n\nGamma delta")
        #expect(fixture.store.documentMatchesListSearch(other, query: "Gamma"))
        #expect(!fixture.store.documentMatchesListSearch(other, query: "Alpha"))
        #expect(fixture.store.selectedDocumentID == onScreen)
        #expect(fixture.store.missingActiveDocumentAlert == nil)
    }

    @Test func aSelectionInADocumentThatGotShorterIsCutToFit() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let long = "alpha beta gamma delta"
        let other = try fixture.open("other.md", holding: long)
        try fixture.open("on-screen.md", holding: "On screen")
        fixture.store.setSelections([MarkdownSelectionRange(location: 6, length: 16)], for: other, text: long)

        try fixture.save("alpha beta", over: other)
        fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.store.selections(for: other) == [MarkdownSelectionRange(location: 6, length: 4)])
    }

    @Test func aSelectionPastTheEndOfADocumentThatGotShorterIsDropped() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let long = "alpha beta gamma delta"
        let other = try fixture.open("other.md", holding: long)
        try fixture.open("on-screen.md", holding: "On screen")
        fixture.store.setSelections([MarkdownSelectionRange(location: 17, length: 5)], for: other, text: long)

        try fixture.save("alpha", over: other)
        fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.store.selections(for: other).isEmpty)
    }

    /// A save that changes nothing is not a new document: the entry keeps the
    /// file it had, so nothing downstream is told that it changed.
    @Test func aFileSavedWithNothingChangedIsNotReloaded() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let other = try fixture.open("other.md", holding: "Unchanged")
        try fixture.open("on-screen.md", holding: "On screen")
        let before = try #require(fixture.document(other)).file

        try fixture.save("Unchanged", over: other)
        fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.document(other)?.file == before)
    }

    @Test func aDocumentThatIsNotOnScreenIsDroppedWhenItsFileIsDeleted() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let text = "Alpha beta"
        let other = try fixture.open("other.md", holding: text)
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")
        fixture.store.setSelections([MarkdownSelectionRange(location: 0, length: 5)], for: other, text: text)
        fixture.store.increaseTextSize(for: other)

        try fixture.delete(other)
        fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.listed == ["on-screen.md"])
        #expect(fixture.store.selectedDocumentID == onScreen)
        // Nobody was looking at it, so nobody is told.
        #expect(fixture.store.missingActiveDocumentAlert == nil)
        // What was kept for it goes with it.
        #expect(fixture.store.selections(for: other).isEmpty)
        #expect(fixture.store.textSize(for: other) == .defaultValue)
        #expect(!fixture.store.documentMatchesListSearch(other, query: "Alpha"))
    }

    @Test func droppingOneDocumentLeavesTheOthersThatAreNotOnScreen() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let gone = try fixture.open("gone.md", holding: "Gone")
        try fixture.open("kept.md", holding: "Kept")
        try fixture.open("on-screen.md", holding: "On screen")

        try fixture.delete(gone)
        fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.listed == ["kept.md", "on-screen.md"])
    }

    /// The document on screen is looked at on its own, more often, and with a
    /// different answer to a file that has gone. Looking at the others must
    /// not reach it.
    @Test func lookingAtTheOtherDocumentsLeavesTheOneOnScreenAlone() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.open("other.md", holding: "Other")
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")

        try fixture.delete(onScreen)
        fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(fixture.listed == ["on-screen.md", "other.md"])
        #expect(fixture.store.selectedDocumentID == onScreen)
        #expect(fixture.store.missingActiveDocumentAlert == nil)
    }

    // MARK: - The document on screen

    @Test func theDocumentOnScreenIsReloadedWhenItsFileChanges() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let onScreen = try fixture.open("on-screen.md", holding: "Before")

        try fixture.save("After", over: onScreen)
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(fixture.store.currentDocument?.file.contents == "After")
        #expect(fixture.store.missingActiveDocumentAlert == nil)
    }

    /// The reader is looking at it, so it is not taken away from under them.
    /// They are told, and it stays until they have answered.
    @Test func theDocumentOnScreenIsReportedMissingWhenItsFileIsDeleted() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.open("other.md", holding: "Other")
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")

        try fixture.delete(onScreen)
        for _ in 0..<3 {
            fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)
        }

        let alert = try #require(fixture.store.missingActiveDocumentAlert)
        #expect(alert.id == onScreen)
        #expect(alert.fileName == "on-screen.md")
        #expect(fixture.listed == ["on-screen.md", "other.md"])
        #expect(fixture.store.selectedDocumentID == onScreen)
        #expect(fixture.store.currentDocument?.file.contents == "On screen")
    }

    // MARK: - Answering the report

    @Test func answeringWhenNothingWasReportedChangesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")

        let showsTheList = fixture.store.acknowledgeMissingActiveDocument(isCompactWidth: true)

        #expect(!showsTheList)
        #expect(fixture.listed == ["on-screen.md"])
        #expect(fixture.store.selectedDocumentID == onScreen)
    }

    /// With room for the list and a document side by side, the first document
    /// left takes the missing one's place.
    @Test func answeringTheReportRemovesTheDocumentAndShowsTheFirstOneLeft() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let alpha = try fixture.open("alpha.md", holding: "Alpha")
        try fixture.open("beta.md", holding: "Beta")
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")
        try fixture.delete(onScreen)
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)

        let showsTheList = fixture.store.acknowledgeMissingActiveDocument(isCompactWidth: false)

        #expect(!showsTheList)
        #expect(fixture.store.missingActiveDocumentAlert == nil)
        #expect(fixture.listed == ["alpha.md", "beta.md"])
        #expect(fixture.store.selectedDocumentID == alpha)
    }

    /// On a screen that shows one column at a time there is no document to
    /// put in its place, so the reader goes back to the list.
    @Test func answeringTheReportOnACompactScreenGoesBackToTheList() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.open("alpha.md", holding: "Alpha")
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")
        try fixture.delete(onScreen)
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: true)

        let showsTheList = fixture.store.acknowledgeMissingActiveDocument(isCompactWidth: true)

        #expect(showsTheList)
        #expect(fixture.store.missingActiveDocumentAlert == nil)
        #expect(fixture.listed == ["alpha.md"])
        #expect(fixture.store.selectedDocumentID == nil)
    }

    @Test func answeringTheReportForTheOnlyDocumentLeavesAnEmptyList() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")
        try fixture.delete(onScreen)
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)

        let showsTheList = fixture.store.acknowledgeMissingActiveDocument(isCompactWidth: false)

        #expect(!showsTheList)
        #expect(fixture.store.missingActiveDocumentAlert == nil)
        #expect(fixture.listed.isEmpty)
        #expect(fixture.store.selectedDocumentID == nil)
    }

    /// Answered once, it is answered: a second answer has no report to act on
    /// and must not take another document off the list.
    @Test func answeringTheReportTwiceRemovesOneDocument() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.open("alpha.md", holding: "Alpha")
        let onScreen = try fixture.open("on-screen.md", holding: "On screen")
        try fixture.delete(onScreen)
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)

        _ = fixture.store.acknowledgeMissingActiveDocument(isCompactWidth: false)
        let showsTheList = fixture.store.acknowledgeMissingActiveDocument(isCompactWidth: false)

        #expect(!showsTheList)
        #expect(fixture.listed == ["alpha.md"])
    }

    // MARK: - A document that is still where it was

    /// Counts how often the store asks where a bookmark's file is now.
    private final class LookUps {
        private(set) var count = 0

        var resolver: BookmarkResolver {
            BookmarkResolver { [self] bookmarkData in
                count += 1
                return BookmarkResolver.system.resolve(bookmarkData)
            }
        }
    }

    /// Where a bookmark's file is now, and whether that is the Trash, are
    /// nearly all a check costs, and they are asked to find a file that has
    /// gone somewhere. One that is still where it was found has gone nowhere.
    /// The document on screen is checked every second.
    @Test func theDocumentOnScreenIsNotLookedUpAgainWhileItIsWhereItWas() throws {
        let lookUps = LookUps()
        let fixture = try Fixture(resolver: lookUps.resolver)
        defer { fixture.cleanUp() }
        try fixture.open("on-screen.md", holding: "Text")
        let afterOpening = lookUps.count

        for _ in 0..<5 {
            fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)
        }

        #expect(lookUps.count == afterOpening)
        #expect(fixture.store.missingActiveDocumentAlert == nil)
    }

    @Test func documentsNotOnScreenAreNotLookedUpAgainWhileTheyAreWhereTheyWere() throws {
        let lookUps = LookUps()
        let fixture = try Fixture(resolver: lookUps.resolver)
        defer { fixture.cleanUp() }
        try fixture.open("one.md", holding: "One")
        try fixture.open("two.md", holding: "Two")
        try fixture.open("on-screen.md", holding: "Three")
        let afterOpening = lookUps.count

        for _ in 0..<3 {
            fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)
        }

        #expect(lookUps.count == afterOpening)
        #expect(fixture.listed == ["on-screen.md", "one.md", "two.md"])
    }

    /// Saved over, as an editor saves: another file under the same name. It
    /// is where it was, and it has changed.
    @Test func aDocumentSavedOverWhereItWasIsReloadedWithoutBeingLookedUp() throws {
        let lookUps = LookUps()
        let fixture = try Fixture(resolver: lookUps.resolver)
        defer { fixture.cleanUp() }
        let onScreen = try fixture.open("on-screen.md", holding: "Before")
        let afterOpening = lookUps.count

        try fixture.save("After", over: onScreen)
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(fixture.store.currentDocument?.file.contents == "After")
        #expect(lookUps.count == afterOpening)
    }

    @Test func aDocumentWhoseFileHasGoneIsLookedUp() throws {
        let lookUps = LookUps()
        let fixture = try Fixture(resolver: lookUps.resolver)
        defer { fixture.cleanUp() }
        let onScreen = try fixture.open("on-screen.md", holding: "Text")
        let afterOpening = lookUps.count

        try fixture.delete(onScreen)
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(lookUps.count > afterOpening)
        #expect(fixture.store.missingActiveDocumentAlert != nil)
    }

    /// Looked up when it is found to have gone, followed to where it is, and
    /// from then on it is where it was again.
    @Test func aMovedDocumentIsLookedUpWhenItMovesAndNotAfter() throws {
        let lookUps = LookUps()
        let fixture = try Fixture(resolver: lookUps.resolver)
        defer { fixture.cleanUp() }
        let onScreen = try fixture.open("before.md", holding: "Text")
        let afterOpening = lookUps.count

        try FileManager.default.moveItem(
            at: URL(fileURLWithPath: onScreen),
            to: fixture.directory.appendingPathComponent("after.md")
        )
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)
        #expect(fixture.listed == ["after.md"])
        let afterMoving = lookUps.count
        #expect(afterMoving > afterOpening)

        for _ in 0..<5 {
            fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)
        }
        #expect(lookUps.count == afterMoving)
        #expect(fixture.listed == ["after.md"])
    }

    // MARK: - Opening a document, with others already listed

    /// A file being opened may be a listed document under the path it was
    /// moved to, which the list has not caught up with. To find out, each
    /// listed document's bookmark was asked where it led: once for every
    /// document in the list, every time a document was opened. One that is
    /// still where it was last found has not been moved anywhere, and is not
    /// asked about.
    @Test func openingADocumentDoesNotLookUpTheOnesThatAreWhereTheyWere() throws {
        let lookUps = LookUps()
        let fixture = try Fixture(resolver: lookUps.resolver)
        defer { fixture.cleanUp() }
        try fixture.open("one.md", holding: "One")
        try fixture.open("two.md", holding: "Two")
        try fixture.open("three.md", holding: "Three")
        let before = lookUps.count

        try fixture.open("four.md", holding: "Four")

        // Its own bookmark, to find the file it is about to read.
        #expect(lookUps.count == before + 1)
        #expect(fixture.listed == ["four.md", "one.md", "three.md", "two.md"])
    }

    /// The one that has gone from where it was is asked about, and is found
    /// to be the file now being opened.
    @Test func openingAFileThatAListedDocumentWasMovedToFindsThatDocument() throws {
        let lookUps = LookUps()
        let fixture = try Fixture(resolver: lookUps.resolver)
        defer { fixture.cleanUp() }
        try fixture.open("other.md", holding: "Other")
        let moved = try fixture.open("before.md", holding: "Moved")
        let movedTo = fixture.directory.appendingPathComponent("after.md")
        try FileManager.default.moveItem(at: URL(fileURLWithPath: moved), to: movedTo)
        let before = lookUps.count

        try fixture.store.openDocument(at: movedTo)

        #expect(fixture.listed == ["after.md", "other.md"])
        // Its own bookmark, and the bookmark of the one document that has
        // gone from where it was. Not the one that has stayed.
        #expect(lookUps.count == before + 2)
    }

    /// A list read back at launch has found each document already.
    @Test func documentsReadBackAtLaunchAreNotLookedUpAgainByTheFirstCheck() throws {
        let suiteName = "ChangedAndMissingDocumentTests.\(#function).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.open("one.md", holding: "One")
        try fixture.open("two.md", holding: "Two")
        fixture.store.persistDocuments(to: defaults)
        fixture.store.persistSelectedDocument(to: defaults)

        let lookUps = LookUps()
        let relaunched = DocumentSessionStore(userDefaults: defaults, bookmarkResolver: lookUps.resolver)
        relaunched.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)
        #expect(relaunched.sortedDocuments.map(\.file.fileName) == ["one.md", "two.md"])
        let afterReadingBack = lookUps.count

        relaunched.checkActiveDocumentForChanges(isCompactWidth: false)
        relaunched.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(lookUps.count == afterReadingBack)
    }
}
