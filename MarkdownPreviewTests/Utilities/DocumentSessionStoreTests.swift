//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import SwiftUI
import Testing
import MarkdownCore

struct DocumentSessionStoreTests {

    /// Stands in for the sandbox, counting how often a document's security scope
    /// is asked for and released.
    @MainActor
    private final class ScopeRecorder {
        var grants: Bool
        private(set) var startCount = 0
        private(set) var stopCount = 0

        init(grants: Bool) {
            self.grants = grants
        }

        var scope: SecurityScope {
            SecurityScope(
                start: { [self] _ in
                    startCount += 1
                    return grants
                },
                stop: { [self] _ in
                    stopCount += 1
                }
            )
        }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // A scope the system refuses stays refused: the bookmark carries the same
    // token on every resolution. Asking again on each polling tick is what filled
    // the iPhone console with `sandbox_extension_consume failed: 22`, once a
    // second, for a document that was readable all along.
    @MainActor
    @Test func pollingDoesNotAskAgainForASecurityScopeTheSystemRefused() async throws {
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appendingPathComponent("notes.md")
        try "# Title".write(to: fileURL, atomically: true, encoding: .utf8)

        let recorder = ScopeRecorder(grants: false)
        let store = DocumentSessionStore(disablePersistenceRestore: true, securityScope: recorder.scope)
        try store.openDocument(at: fileURL)
        let askedWhileOpening = recorder.startCount

        for _ in 0..<5 {
            store.checkActiveDocumentForChanges(isCompactWidth: false)
        }

        #expect(askedWhileOpening == 1)
        #expect(recorder.startCount == askedWhileOpening)
        #expect(recorder.stopCount == 0)
        #expect(store.openedDocuments.map(\.file.fileName) == ["notes.md"])
        #expect(store.missingActiveDocumentAlert == nil)
    }

    @MainActor
    @Test func documentWithARefusedSecurityScopeStillReloadsWhenItChanges() async throws {
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appendingPathComponent("notes.md")
        try "before".write(to: fileURL, atomically: true, encoding: .utf8)

        let recorder = ScopeRecorder(grants: false)
        let store = DocumentSessionStore(disablePersistenceRestore: true, securityScope: recorder.scope)
        try store.openDocument(at: fileURL)
        store.checkActiveDocumentForChanges(isCompactWidth: false)

        try "after".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: fileURL.path
        )
        store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(store.currentDocument?.file.contents == "after")
        #expect(recorder.startCount == 1)
    }

    // The other half of not asking again: a scope that *is* granted is still
    // taken for every read, and every one taken is released.
    @MainActor
    @Test func pollingReleasesEverySecurityScopeItTakes() async throws {
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appendingPathComponent("notes.md")
        try "# Title".write(to: fileURL, atomically: true, encoding: .utf8)

        let recorder = ScopeRecorder(grants: true)
        let store = DocumentSessionStore(disablePersistenceRestore: true, securityScope: recorder.scope)
        try store.openDocument(at: fileURL)
        let askedWhileOpening = recorder.startCount

        for _ in 0..<5 {
            store.checkActiveDocumentForChanges(isCompactWidth: false)
        }

        #expect(recorder.startCount == askedWhileOpening + 5)
        #expect(recorder.stopCount == recorder.startCount)
    }

    // A refusal is remembered against the bookmark, not the file: taking the
    // document off the list and opening it again is a fresh bookmark and a fresh
    // chance.
    @MainActor
    @Test func reopeningADocumentAsksForItsSecurityScopeAgain() async throws {
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appendingPathComponent("notes.md")
        try "# Title".write(to: fileURL, atomically: true, encoding: .utf8)

        let recorder = ScopeRecorder(grants: false)
        let store = DocumentSessionStore(disablePersistenceRestore: true, securityScope: recorder.scope)
        try store.openDocument(at: fileURL)
        store.checkActiveDocumentForChanges(isCompactWidth: false)
        #expect(recorder.startCount == 1)

        let documentID = try #require(store.selectedDocumentID)
        _ = store.removeDocument(id: documentID, isCompactWidth: false)
        try store.openDocument(at: fileURL)
        store.checkActiveDocumentForChanges(isCompactWidth: false)

        #expect(recorder.startCount == 2)
    }

    @MainActor
    @Test func textSizePreferencePersistsPerDocumentAndClearsWhenRemoved() async throws {
        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let file = MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/alpha.md"), contents: "alpha")
        let documentID = file.url.standardizedFileURL.path

        let store = DocumentSessionStore(
            previewFiles: [file],
            disablePersistenceRestore: true,
            userDefaults: defaults
        )

        #expect(store.textSize(for: documentID) == .large)
        #expect(store.canIncreaseTextSize(for: documentID))
        #expect(store.canDecreaseTextSize(for: documentID))

        store.increaseTextSize(for: documentID)
        store.increaseTextSize(for: documentID)
        store.persistTextSizes(to: defaults)

        #expect(store.textSize(for: documentID) == .xxLarge)

        let restoredStore = DocumentSessionStore(
            previewFiles: [file],
            disablePersistenceRestore: true,
            userDefaults: defaults
        )

        #expect(restoredStore.textSize(for: documentID) == .xxLarge)

        _ = restoredStore.removeDocument(id: documentID, isCompactWidth: false)
        restoredStore.persistTextSizes(to: defaults)

        let cleanedStore = DocumentSessionStore(
            previewFiles: [file],
            disablePersistenceRestore: true,
            userDefaults: defaults
        )

        #expect(cleanedStore.textSize(for: documentID) == .large)
    }

    @MainActor
    @Test func sortsOpenedDocumentsByFileName() async throws {
        let files = [
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/zeta.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/alpha.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/chapter-2.md"), contents: "")
        ]

        let store = DocumentSessionStore(
            previewFiles: files,
            disablePersistenceRestore: true
        )

        #expect(store.sortedDocuments.map { $0.file.fileName } == [
            "alpha.md",
            "chapter-2.md",
            "zeta.md"
        ])
    }

    @MainActor
    @Test func deletingFromSortedListRemovesOnlyThatSessionEntry() async throws {
        let alpha = MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/alpha.md"), contents: "alpha")
        let chapter = MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/chapter-2.md"), contents: "chapter")
        let zeta = MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/zeta.md"), contents: "zeta")

        let store = DocumentSessionStore(
            previewFiles: [zeta, alpha, chapter],
            selectedPreviewFileID: chapter.url.standardizedFileURL.path,
            disablePersistenceRestore: true
        )

        store.deleteDocuments(at: IndexSet(integer: 1), isCompactWidth: false)

        #expect(store.sortedDocuments.map { $0.file.fileName } == [
            "alpha.md",
            "zeta.md"
        ])
        #expect(store.selectedDocumentID == alpha.url.standardizedFileURL.path)
    }

    @MainActor
    @Test func groupsDocumentsByParentDirectoryWithSortedSections() async throws {
        let home = UserHomeDirectory.path
        let files = [
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/zeta.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "\(home)/work/beta.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "\(home)/work/alpha.md"), contents: ""),
            MarkdownFile(url: URL(fileURLWithPath: "\(home)/root.md"), contents: "")
        ]

        let store = DocumentSessionStore(
            previewFiles: files,
            disablePersistenceRestore: true
        )

        let sections = store.groupedDocumentsByParentDirectory

        #expect(sections.map(\.label) == [
            "/tmp/notes",
            "~",
            "~/work"
        ])
        #expect(sections[0].documents.map(\.file.fileName) == ["zeta.md"])
        #expect(sections[1].documents.map(\.file.fileName) == ["root.md"])
        #expect(sections[2].documents.map(\.file.fileName) == ["alpha.md", "beta.md"])
    }

    @MainActor
    @Test func restorePrunesTextSizePreferenceForMissingFile() async throws {
        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("missing.md")
        try "# Title".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)
        try store.openDocument(at: fileURL)

        let documentID = fileURL.standardizedFileURL.path
        store.increaseTextSize(for: documentID)
        store.persistTextSizes(to: defaults)
        store.persistDocuments(to: defaults)
        store.persistSelectedDocument(to: defaults)

        try FileManager.default.removeItem(at: fileURL)

        let restoredStore = DocumentSessionStore(
            disablePersistenceRestore: false,
            userDefaults: defaults,
            documentReader: .readingAtOnce
        )
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)

        #expect(restoredStore.openedDocuments.isEmpty)
        #expect(restoredStore.textSizesByDocumentID.isEmpty)
        #expect(restoredStore.selectedDocumentID == nil)
        #expect(restoredStore.textSize(for: documentID) == .large)
    }

    // The width does not come into what the store restores: which document
    // is selected is the same at either. What a compact width changes is which
    // column shows, and that is the view model's to decide.
    @MainActor
    @Test(arguments: [true, false])
    func restoreKeepsThePersistedSelectionAtEitherWidth(isCompactWidth: Bool) async throws {
        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let alphaURL = temporaryDirectory.appendingPathComponent("alpha.md")
        let betaURL = temporaryDirectory.appendingPathComponent("beta.md")
        try "alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "beta".write(to: betaURL, atomically: true, encoding: .utf8)

        let store = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)
        try store.openDocument(at: alphaURL)
        try store.openDocument(at: betaURL)
        store.selectedDocumentID = alphaURL.standardizedFileURL.path
        store.persistDocuments(to: defaults)
        store.persistSelectedDocument(to: defaults)

        let restoredStore = DocumentSessionStore(
            disablePersistenceRestore: false,
            userDefaults: defaults,
            documentReader: .readingAtOnce
        )
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: isCompactWidth, userDefaults: defaults)

        #expect(restoredStore.openedDocuments.count == 2)
        #expect(restoredStore.selectedDocumentID == alphaURL.standardizedFileURL.path)
    }

    @MainActor
    @Test func restoreLeavesNoSelectionWhenPersistedFileIsMissing() async throws {
        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let alphaURL = temporaryDirectory.appendingPathComponent("alpha.md")
        let betaURL = temporaryDirectory.appendingPathComponent("beta.md")
        try "alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "beta".write(to: betaURL, atomically: true, encoding: .utf8)

        let store = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)
        try store.openDocument(at: alphaURL)
        try store.openDocument(at: betaURL)
        store.selectedDocumentID = betaURL.standardizedFileURL.path
        store.persistDocuments(to: defaults)
        store.persistSelectedDocument(to: defaults)

        try FileManager.default.removeItem(at: betaURL)

        let restoredStore = DocumentSessionStore(
            disablePersistenceRestore: false,
            userDefaults: defaults,
            documentReader: .readingAtOnce
        )
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)

        #expect(restoredStore.openedDocuments.map(\.id) == [alphaURL.standardizedFileURL.path])
        #expect(restoredStore.selectedDocumentID == nil)
    }

    @MainActor
    @Test func restoreMigratesPersistedDocumentIDsToResolvedBookmarkPaths() async throws {
        struct PersistedDocumentRecord: Codable {
            let id: String
            let lastOpened: Date
            let bookmarkData: Data
        }

        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("readme.md")
        try "The repository includes unit/UI test targets.".write(to: fileURL, atomically: true, encoding: .utf8)

        let originalStore = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)
        try originalStore.openDocument(at: fileURL)
        let resolvedID = fileURL.standardizedFileURL.path
        originalStore.selectedDocumentID = resolvedID
        originalStore.increaseTextSize(for: resolvedID)
        originalStore.increaseTextSize(for: resolvedID)
        originalStore.persistDocuments(to: defaults)
        originalStore.persistSelectedDocument(to: defaults)
        originalStore.persistTextSizes(to: defaults)

        let legacyID = "/legacy/readme.md"
        let persistedDocumentsData = defaults.data(forKey: "openedMarkdownDocuments")
        let persistedDocuments = try #require(
            persistedDocumentsData.flatMap {
                try? JSONDecoder().decode([PersistedDocumentRecord].self, from: $0)
            }
        )
        defaults.set(
            try JSONEncoder().encode(
                persistedDocuments.map { document in
                    PersistedDocumentRecord(
                        id: legacyID,
                        lastOpened: document.lastOpened,
                        bookmarkData: document.bookmarkData
                    )
                }
            ),
            forKey: "openedMarkdownDocuments"
        )
        defaults.set(legacyID, forKey: "selectedMarkdownDocumentID")
        defaults.set([legacyID: "xxLarge"], forKey: "markdownDocumentTextSizes")

        let restoredStore = DocumentSessionStore(
            disablePersistenceRestore: false,
            userDefaults: defaults,
            documentReader: .readingAtOnce
        )
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)

        #expect(restoredStore.openedDocuments.count == 1)
        #expect(restoredStore.openedDocuments.first?.id == resolvedID)
        #expect(restoredStore.selectedDocumentID == resolvedID)
        #expect(restoredStore.textSize(for: resolvedID) == .xxLarge)
        #expect(restoredStore.documentMatchesListSearch(resolvedID, query: "repo"))
    }

    @MainActor
    @Test func openingFinderDocumentAfterRestoreKeepsRestoredSessionDocuments() async throws {
        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let alphaURL = temporaryDirectory.appendingPathComponent("alpha.md")
        let betaURL = temporaryDirectory.appendingPathComponent("beta.md")
        let gammaURL = temporaryDirectory.appendingPathComponent("gamma.md")
        try "alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "beta".write(to: betaURL, atomically: true, encoding: .utf8)
        try "gamma".write(to: gammaURL, atomically: true, encoding: .utf8)

        let store = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)
        try store.openDocument(at: alphaURL)
        try store.openDocument(at: betaURL)
        store.selectedDocumentID = alphaURL.standardizedFileURL.path
        store.persistDocuments(to: defaults)
        store.persistSelectedDocument(to: defaults)

        let restoredStore = DocumentSessionStore(
            disablePersistenceRestore: false,
            userDefaults: defaults,
            documentReader: .readingAtOnce
        )
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)
        try restoredStore.openDocument(at: gammaURL)

        #expect(
            Set(restoredStore.openedDocuments.map(\.id)) == Set([
                alphaURL.standardizedFileURL.path,
                betaURL.standardizedFileURL.path,
                gammaURL.standardizedFileURL.path
            ])
        )
        #expect(restoredStore.selectedDocumentID == gammaURL.standardizedFileURL.path)
    }

    @MainActor
    @Test func storeListSearchUsesStrippedTextIndexAfterReload() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/notes.md")
        let initial = MarkdownFile(url: fileURL, contents: "# [Alpha](https://example.com)")
        let updated = MarkdownFile(url: fileURL, contents: "Gamma")

        let store = DocumentSessionStore(
            previewFiles: [initial],
            disablePersistenceRestore: true
        )

        #expect(store.documentMatchesListSearch(fileURL.standardizedFileURL.path, query: "Alpha"))
        #expect(store.documentMatchesListSearch(fileURL.standardizedFileURL.path, query: "https") == false)

        store.upsertDocument(updated, bookmarkData: Data(), modificationDate: nil)

        #expect(store.documentMatchesListSearch(fileURL.standardizedFileURL.path, query: "Alpha") == false)
        #expect(store.documentMatchesListSearch(fileURL.standardizedFileURL.path, query: "Gamma"))
    }

    // Two saved entries can name one file. Open a document, move it, and open
    // it again from its new place: it used to be in the list under both paths,
    // and the first entry's bookmark follows the file, so on the next launch
    // both resolved to the same path. Restoring that list used to trap while
    // building the search index, and went on trapping at every launch, because
    // the saved list was still the same. The list no longer gets that way
    // (`MovedDocumentTests`), but one saved by an earlier build can be.
    //
    // The restore runs in a child process, so that if it ever traps again it
    // fails this test and not the whole run.
    @MainActor
    @Test(.timeLimit(.minutes(1)))
    func twoSavedEntriesForOneFileRestoreAsOne() async throws {
        struct PersistedDocumentRecord: Codable {
            let id: String
            let lastOpened: Date
            let bookmarkData: Data
        }

        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let temporaryDirectory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appendingPathComponent("notes.md")
        try "# Notes".write(to: fileURL, atomically: true, encoding: .utf8)

        let originalStore = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)
        try originalStore.openDocument(at: fileURL)
        originalStore.persistDocuments(to: defaults)

        // The same bookmark saved a second time, under the path the document
        // had before it was moved, and opened earlier.
        let saved = try #require(
            defaults.data(forKey: "openedMarkdownDocuments").flatMap {
                try? JSONDecoder().decode([PersistedDocumentRecord].self, from: $0)
            }?.first
        )
        let earlierID = "/somewhere/else/notes.md"
        defaults.set(
            try JSONEncoder().encode([
                PersistedDocumentRecord(
                    id: earlierID,
                    lastOpened: saved.lastOpened.addingTimeInterval(-60),
                    bookmarkData: saved.bookmarkData
                ),
                saved,
            ]),
            forKey: "openedMarkdownDocuments"
        )
        // The reader was last looking at it under its old path.
        defaults.set(earlierID, forKey: "selectedMarkdownDocumentID")
        defaults.synchronize()

        let resolvedID = fileURL.standardizedFileURL.path
        #if os(macOS)
        await #expect(processExitsWith: .success) { [suiteName = suiteName as String, resolvedID = resolvedID as String] in
            let restoredAsOne = await MainActor.run {
                DocumentSessionStoreTests.restoresOneDocument(resolvedID, fromSuiteNamed: suiteName)
            }
            exit(restoredAsOne ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        #else
        // Exit tests are macOS only, so here a trap would take the run with it.
        #expect(Self.restoresOneDocument(resolvedID, fromSuiteNamed: suiteName))
        #endif
    }

    /// Restores the session saved in the named defaults suite, and says whether
    /// what came back is the one document `resolvedID`, selected and indexed.
    @MainActor
    private static func restoresOneDocument(_ resolvedID: String, fromSuiteNamed suiteName: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
        let restoredStore = DocumentSessionStore(
            disablePersistenceRestore: false,
            userDefaults: defaults,
            documentReader: .readingAtOnce
        )
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)

        return restoredStore.openedDocuments.map(\.id) == [resolvedID]
            && restoredStore.selectedDocumentID == resolvedID
            && restoredStore.documentMatchesListSearch(resolvedID, query: "Notes")
    }

    // A file the app cannot read as text is still there. Reporting it as
    // missing sends the reader looking for a file that has not gone anywhere.
    @MainActor
    @Test func openingAFileThatIsNotTextSaysSoAndDoesNotCallItMissing() async throws {
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appendingPathComponent("latin1.md")
        try #require("Un café, s'il vous plaît.".data(using: .isoLatin1)).write(to: fileURL)

        let store = DocumentSessionStore(disablePersistenceRestore: true)
        let error = #expect(throws: CocoaError.self) {
            try store.openDocument(at: fileURL)
        }

        #expect(error?.code == .fileReadInapplicableStringEncoding)
        #expect(store.openedDocuments.isEmpty)
    }

    // MARK: - Taking a document off the list

    /// Three documents, none of them on disk, with `beta.md` on screen.
    @MainActor
    private static func makeStoreWithBetaOnScreen() -> (store: DocumentSessionStore, ids: [String: String]) {
        let files = ["alpha.md", "beta.md", "gamma.md"].map {
            MarkdownFile(url: URL(fileURLWithPath: "/tmp/notes/\($0)"), contents: "The \($0) text")
        }
        let ids = Dictionary(uniqueKeysWithValues: files.map { ($0.fileName, $0.url.standardizedFileURL.path) })
        let store = DocumentSessionStore(
            previewFiles: files,
            selectedPreviewFileID: ids["beta.md"],
            disablePersistenceRestore: true
        )
        return (store, ids)
    }

    /// With room for the list and a document side by side, the first document
    /// left takes the place of the one that was removed.
    @MainActor
    @Test func removingTheDocumentOnScreenShowsTheFirstOneLeft() async throws {
        let (store, ids) = Self.makeStoreWithBetaOnScreen()

        let showsTheList = store.removeDocument(id: try #require(ids["beta.md"]), isCompactWidth: false)

        #expect(!showsTheList)
        #expect(store.sortedDocuments.map(\.file.fileName) == ["alpha.md", "gamma.md"])
        #expect(store.selectedDocumentID == ids["alpha.md"])
    }

    /// On a screen that shows one column at a time nothing takes its place:
    /// the reader is left with the list, and no document chosen from it.
    @MainActor
    @Test func removingTheDocumentOnScreenAtACompactWidthLeavesNothingSelected() async throws {
        let (store, ids) = Self.makeStoreWithBetaOnScreen()

        let showsTheList = store.removeDocument(id: try #require(ids["beta.md"]), isCompactWidth: true)

        #expect(!showsTheList)
        #expect(store.sortedDocuments.map(\.file.fileName) == ["alpha.md", "gamma.md"])
        #expect(store.selectedDocumentID == nil)
    }

    /// The caller may ask to be told to go back to the list, which it is when
    /// the removal took the document the reader was looking at.
    @MainActor
    @Test func removingTheDocumentOnScreenAtACompactWidthCanAskForTheList() async throws {
        let (store, ids) = Self.makeStoreWithBetaOnScreen()

        let showsTheList = store.removeDocument(
            id: try #require(ids["beta.md"]),
            forceShowSidebarOnCompact: true,
            isCompactWidth: true
        )

        #expect(showsTheList)
        #expect(store.selectedDocumentID == nil)
    }

    /// Removing some other document changes nothing the reader is looking at,
    /// at either width, so there is no call to go back to the list.
    @MainActor
    @Test(arguments: [true, false])
    func removingADocumentThatIsNotOnScreenLeavesTheOneThatIs(isCompactWidth: Bool) async throws {
        let (store, ids) = Self.makeStoreWithBetaOnScreen()

        let showsTheList = store.removeDocument(
            id: try #require(ids["gamma.md"]),
            forceShowSidebarOnCompact: true,
            isCompactWidth: isCompactWidth
        )

        #expect(!showsTheList)
        #expect(store.sortedDocuments.map(\.file.fileName) == ["alpha.md", "beta.md"])
        #expect(store.selectedDocumentID == ids["beta.md"])
    }

    @MainActor
    @Test func removingADocumentDropsWhatWasKeptForIt() async throws {
        let (store, ids) = Self.makeStoreWithBetaOnScreen()
        let gamma = try #require(ids["gamma.md"])
        store.setSelections([MarkdownSelectionRange(location: 0, length: 3)], for: gamma, text: "The gamma.md text")
        store.increaseTextSize(for: gamma)
        #expect(store.documentMatchesListSearch(gamma, query: "gamma"))

        store.removeDocument(id: gamma, isCompactWidth: false)

        #expect(store.selections(for: gamma).isEmpty)
        #expect(store.textSize(for: gamma) == .defaultValue)
        #expect(!store.documentMatchesListSearch(gamma, query: "gamma"))
    }

    @MainActor
    @Test func removingADocumentThatIsNotListedChangesNothing() async throws {
        let (store, ids) = Self.makeStoreWithBetaOnScreen()

        let showsTheList = store.removeDocument(
            id: "/tmp/notes/never-opened.md",
            forceShowSidebarOnCompact: true,
            isCompactWidth: true
        )

        #expect(!showsTheList)
        #expect(store.openedDocuments.count == 3)
        #expect(store.selectedDocumentID == ids["beta.md"])
    }

    /// Deleting from the list, by its rows as they are sorted.
    @MainActor
    @Test func deletingTheDocumentOnScreenAtACompactWidthLeavesNothingSelected() async throws {
        let (store, _) = Self.makeStoreWithBetaOnScreen()

        store.deleteDocuments(at: IndexSet(integer: 1), isCompactWidth: true)

        #expect(store.sortedDocuments.map(\.file.fileName) == ["alpha.md", "gamma.md"])
        #expect(store.selectedDocumentID == nil)
    }

    @MainActor
    @Test(arguments: [true, false])
    func deletingOtherRowsLeavesTheDocumentOnScreen(isCompactWidth: Bool) async throws {
        let (store, ids) = Self.makeStoreWithBetaOnScreen()

        store.deleteDocuments(at: IndexSet([0, 2]), isCompactWidth: isCompactWidth)

        #expect(store.sortedDocuments.map(\.file.fileName) == ["beta.md"])
        #expect(store.selectedDocumentID == ids["beta.md"])
    }

    @MainActor
    @Test func deletingEveryRowLeavesAnEmptyListAndNothingSelected() async throws {
        let (store, _) = Self.makeStoreWithBetaOnScreen()

        store.deleteDocuments(at: IndexSet(0..<3), isCompactWidth: false)

        #expect(store.openedDocuments.isEmpty)
        #expect(store.selectedDocumentID == nil)
    }

    // MARK: - Whether a list has ever been saved

    // This is what decides whether the welcome document is put in the list: it
    // goes in on a first launch, and not for someone who has closed everything.

    @MainActor
    @Test func aStoreThatHasNeverSavedAListHasNone() async throws {
        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)

        #expect(!store.hasPersistedDocumentList(in: defaults))
    }

    @MainActor
    @Test func aSavedListIsAList() async throws {
        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, _) = Self.makeStoreWithBetaOnScreen()

        store.persistDocuments(to: defaults)

        #expect(store.hasPersistedDocumentList(in: defaults))
    }

    /// A list with nothing left in it is still a list that was saved, which a
    /// first launch does not have.
    @MainActor
    @Test func aListSavedWithNothingInItIsStillAList() async throws {
        let suiteName = "DocumentSessionStoreTests.\(#function).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (store, _) = Self.makeStoreWithBetaOnScreen()

        store.deleteDocuments(at: IndexSet(0..<3), isCompactWidth: false)
        store.persistDocuments(to: defaults)

        #expect(store.hasPersistedDocumentList(in: defaults))
        // And a store made later, over the same defaults, sees it too.
        let later = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)
        #expect(later.hasPersistedDocumentList(in: defaults))
    }

    /// A search in the document on screen is handed this, so it does not work
    /// out again what the list's search already has.
    @MainActor
    @Test func theStoreKeepsEachDocumentsTextAsASearchSeesIt() throws {
        let file = MarkdownFile(
            url: URL(fileURLWithPath: "/tmp/search-mapping/notes.md"),
            contents: "# Title\n\n**alpha** beta"
        )
        let store = DocumentSessionStore(previewFiles: [file], disablePersistenceRestore: true)
        let documentID = file.url.standardizedFileURL.path

        let read = try #require(store.searchMapping(for: documentID))

        #expect(read.sourceText == file.contents)
        #expect(read.displayText.contains("alpha beta"))
        // Kept, and not made again for the next search.
        #expect(store.searchMapping(for: documentID) === read)
        #expect(store.searchMapping(for: "/tmp/search-mapping/not-listed.md") == nil)
    }

    // MARK: - Where the reader was in each preview

    /// What the preview knows a listed document by, with its text.
    @MainActor
    private static func previewContent(
        of fileName: String,
        in store: DocumentSessionStore
    ) throws -> PreviewScrollRestoration.Content {
        let document = try #require(store.openedDocuments.first { $0.file.fileName == fileName })
        return .init(documentID: document.stableID.uuidString, source: document.file.contents)
    }

    @MainActor
    @Test func aDocumentRemovedFromTheListIsForgottenByTheScrollMemory() throws {
        let (store, ids) = Self.makeStoreWithBetaOnScreen()
        let alpha = try Self.previewContent(of: "alpha.md", in: store)
        let beta = try Self.previewContent(of: "beta.md", in: store)
        let halfway = PreviewScrollPosition(x: 0, y: 600, maxY: 1200)
        store.previewScrollMemory.remember(halfway, in: alpha)
        store.previewScrollMemory.remember(halfway, in: beta)

        store.removeDocument(id: try #require(ids["beta.md"]), isCompactWidth: false)

        #expect(store.previewScrollMemory.restoration(for: beta) == .top)
        #expect(store.previewScrollMemory.restoration(for: alpha) == .fraction(x: 0, ofMaxY: 0.5))
    }

    @MainActor
    @Test func documentsDeletedFromTheListAreForgottenByTheScrollMemory() throws {
        let (store, _) = Self.makeStoreWithBetaOnScreen()
        let alpha = try Self.previewContent(of: "alpha.md", in: store)
        let beta = try Self.previewContent(of: "beta.md", in: store)
        let gamma = try Self.previewContent(of: "gamma.md", in: store)
        let halfway = PreviewScrollPosition(x: 0, y: 600, maxY: 1200)
        for content in [alpha, beta, gamma] {
            store.previewScrollMemory.remember(halfway, in: content)
        }

        // The list is in name order: alpha, beta, gamma.
        store.deleteDocuments(at: IndexSet([0, 2]), isCompactWidth: false)

        #expect(store.previewScrollMemory.restoration(for: alpha) == .top)
        #expect(store.previewScrollMemory.restoration(for: gamma) == .top)
        #expect(store.previewScrollMemory.restoration(for: beta) == .fraction(x: 0, ofMaxY: 0.5))
    }
}
