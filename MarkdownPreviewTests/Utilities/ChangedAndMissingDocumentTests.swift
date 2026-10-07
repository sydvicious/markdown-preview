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
        let store = DocumentSessionStore(disablePersistenceRestore: true)
        let directory: URL
        private var saves = 0

        init() throws {
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
}
