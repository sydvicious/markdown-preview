//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

/// A document that is moved or renamed while it is in the list.
///
/// The list names a document by its path, and reaches it through a bookmark,
/// which follows the file. So once a file moves the two disagree: the entry
/// still says where the file was, while everything read through it comes from
/// where the file is. Opening the file again from its new place then added a
/// second entry for it, and both stayed until the next launch.
///
/// The store can find out that a file moved in two ways, and each test runs
/// both: by looking at the document again, which it does on a timer, or by
/// being asked to open the file from where it is now.
@MainActor
struct MovedDocumentTests {

    enum Noticed: Sendable, CustomTestStringConvertible {
        case byLookingAgain
        case byOpeningItAgain

        var testDescription: String {
            switch self {
            case .byLookingAgain: "noticed by looking again"
            case .byOpeningItAgain: "noticed by opening it again"
            }
        }
    }

    /// A store with `first/notes.md` open, and the folders around it.
    @MainActor
    private struct Fixture {
        let store: DocumentSessionStore
        let directory: URL
        let oldURL: URL
        let newURL: URL

        var oldID: String { oldURL.standardizedFileURL.path }
        var newID: String { newURL.standardizedFileURL.path }

        init(movingTo newPath: String = "second/notes.md", userDefaults: UserDefaults = .standard) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            oldURL = directory.appendingPathComponent("first/notes.md")
            newURL = directory.appendingPathComponent(newPath)
            for url in [oldURL, newURL] {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }
            try "# Notes\n\nAlpha beta gamma".write(to: oldURL, atomically: true, encoding: .utf8)

            store = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: userDefaults)
            try store.openDocument(at: oldURL)
        }

        /// Moves the file, and has the store find out.
        func move(_ noticed: Noticed) throws {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            switch noticed {
            case .byLookingAgain:
                store.checkActiveDocumentForChanges(isCompactWidth: false)
                store.checkAllDocumentsForChanges(isCompactWidth: false)
            case .byOpeningItAgain:
                try store.openDocument(at: newURL)
            }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test(arguments: [Noticed.byLookingAgain, .byOpeningItAgain])
    func aMovedDocumentIsListedOnceWhereItIsNow(noticed: Noticed) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.move(noticed)

        #expect(fixture.store.openedDocuments.map(\.id) == [fixture.newID])
        #expect(fixture.store.openedDocuments.map(\.file.url.standardizedFileURL.path) == [fixture.newID])
        #expect(fixture.store.selectedDocumentID == fixture.newID)
        #expect(fixture.store.currentDocument?.file.contents == "# Notes\n\nAlpha beta gamma")
        #expect(fixture.store.missingActiveDocumentAlert == nil)
        #expect(fixture.store.groupedDocumentsByParentDirectory.map(\.directoryPath) == [
            fixture.newURL.deletingLastPathComponent().standardizedFileURL.path
        ])
    }

    @Test(arguments: [Noticed.byLookingAgain, .byOpeningItAgain])
    func aRenamedDocumentIsListedUnderItsNewName(noticed: Noticed) throws {
        let fixture = try Fixture(movingTo: "first/renamed.md")
        defer { fixture.cleanUp() }

        try fixture.move(noticed)

        #expect(fixture.store.openedDocuments.map(\.id) == [fixture.newID])
        #expect(fixture.store.openedDocuments.map(\.file.fileName) == ["renamed.md"])
        #expect(fixture.store.selectedDocumentID == fixture.newID)
    }

    // What the reader set up for the document belongs to the document, not to
    // the path it had.
    @Test(arguments: [Noticed.byLookingAgain, .byOpeningItAgain])
    func aMovedDocumentKeepsWhatTheReaderSetUp(noticed: Noticed) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        let selection = [MarkdownSelectionRange(location: 9, length: 5)]
        store.increaseTextSize(for: fixture.oldID)
        store.setSelections(selection, for: fixture.oldID, text: "# Notes\n\nAlpha beta gamma")

        try fixture.move(noticed)

        #expect(store.textSize(for: fixture.newID) == .xLarge)
        #expect(store.selections(for: fixture.newID) == selection)
        #expect(store.textSizesByDocumentID.keys.sorted() == [fixture.newID])
        #expect(store.selectionsByDocumentID.keys.sorted() == [fixture.newID])
    }

    // The preview keeps the reader's place for as long as it is showing the
    // same document, and it tells by this. If it changed with the path, moving
    // a file would send whoever was reading it back to the top.
    @Test(arguments: [Noticed.byLookingAgain, .byOpeningItAgain])
    func aMovedDocumentIsStillTheSameDocumentToThePreview(noticed: Noticed) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let before = try #require(fixture.store.currentDocument?.stableID)

        try fixture.move(noticed)

        #expect(fixture.store.currentDocument?.stableID == before)
    }

    @Test(arguments: [Noticed.byLookingAgain, .byOpeningItAgain])
    func aMovedDocumentIsFoundByTheListSearchUnderItsNewPathOnly(noticed: Noticed) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try fixture.move(noticed)

        #expect(fixture.store.documentMatchesListSearch(fixture.newID, query: "gamma"))
        #expect(fixture.store.documentMatchesListSearch(fixture.oldID, query: "gamma") == false)
        #expect(fixture.store.listSearchSuggestions(prefix: "gam") == ["gamma"])
    }

    // The document on screen is looked at every second and the rest every ten,
    // by different calls. A move has to be followed from either.
    @Test func aMovedDocumentThatIsNotOnScreenIsFollowedToo() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let otherURL = fixture.directory.appendingPathComponent("first/other.md")
        try "# Other".write(to: otherURL, atomically: true, encoding: .utf8)
        try fixture.store.openDocument(at: otherURL)
        let otherID = otherURL.standardizedFileURL.path

        try FileManager.default.moveItem(at: fixture.oldURL, to: fixture.newURL)
        fixture.store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(Set(fixture.store.openedDocuments.map(\.id)) == [fixture.newID, otherID])
        #expect(fixture.store.selectedDocumentID == otherID)
    }

    // Following the file is not a one-off: an edit made after the move still
    // has to reach the reader.
    @Test(arguments: [Noticed.byLookingAgain, .byOpeningItAgain])
    func aMovedDocumentStillReloadsWhenItChanges(noticed: Noticed) throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.move(noticed)

        try "# Notes\n\nEdited".write(to: fixture.newURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: fixture.newURL.path
        )
        fixture.store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(fixture.store.openedDocuments.map(\.id) == [fixture.newID])
        #expect(fixture.store.currentDocument?.file.contents == "# Notes\n\nEdited")
    }

    // What is saved is what the next launch starts from. Before, the document
    // was saved twice, once under each path.
    @Test(arguments: [Noticed.byLookingAgain, .byOpeningItAgain])
    func aMovedDocumentIsSavedOnceUnderItsNewPath(noticed: Noticed) throws {
        struct PersistedDocumentRecord: Codable {
            let id: String
        }

        let suiteName = "MovedDocumentTests.\(#function).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fixture = try Fixture(userDefaults: defaults)
        defer { fixture.cleanUp() }
        fixture.store.increaseTextSize(for: fixture.oldID)

        try fixture.move(noticed)
        fixture.store.persistDocuments(to: defaults)
        fixture.store.persistSelectedDocument(to: defaults)
        fixture.store.persistTextSizes(to: defaults)

        let saved = try JSONDecoder().decode(
            [PersistedDocumentRecord].self,
            from: try #require(defaults.data(forKey: "openedMarkdownDocuments"))
        )
        #expect(saved.map(\.id) == [fixture.newID])
        #expect(defaults.string(forKey: "selectedMarkdownDocumentID") == fixture.newID)
        #expect(defaults.dictionary(forKey: "markdownDocumentTextSizes") as? [String: String] == [fixture.newID: "xLarge"])
    }

    // Moved onto a file that is open too, the document is in the list twice
    // over: once as the entry that followed it there, and once as the entry
    // that was there already and now reads the same file.
    @Test func aDocumentMovedOverAnotherOpenDocumentLeavesOneEntry() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.store
        try "# Replaced".write(to: fixture.newURL, atomically: true, encoding: .utf8)
        try store.openDocument(at: fixture.newURL)
        store.increaseTextSize(for: fixture.oldID)

        try FileManager.default.removeItem(at: fixture.newURL)
        try FileManager.default.moveItem(at: fixture.oldURL, to: fixture.newURL)
        store.checkActiveDocumentForChanges(isCompactWidth: false)
        store.checkAllDocumentsForChanges(isCompactWidth: false)

        #expect(store.openedDocuments.map(\.id) == [fixture.newID])
        #expect(store.selectedDocumentID == fixture.newID)
        #expect(store.currentDocument?.file.contents == "# Notes\n\nAlpha beta gamma")
        #expect(store.textSize(for: fixture.newID) == .xLarge)
        #expect(store.documentMatchesListSearch(fixture.newID, query: "gamma"))
        #expect(store.documentMatchesListSearch(fixture.newID, query: "replaced") == false)
    }

    // A second file with the first one's name, put where the first one was, is
    // a different document. Opening it must not be taken for the first one
    // coming back.
    @Test func aNewFileWhereTheMovedOneWasIsADocumentOfItsOwn() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.move(.byLookingAgain)

        try "# Replacement".write(to: fixture.oldURL, atomically: true, encoding: .utf8)
        try fixture.store.openDocument(at: fixture.oldURL)

        #expect(Set(fixture.store.openedDocuments.map(\.id)) == [fixture.oldID, fixture.newID])
        #expect(fixture.store.currentDocument?.file.contents == "# Replacement")
    }
}
