//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownPreview

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

        let restoredStore = DocumentSessionStore(disablePersistenceRestore: false, userDefaults: defaults)
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)

        #expect(restoredStore.openedDocuments.isEmpty)
        #expect(restoredStore.textSizesByDocumentID.isEmpty)
        #expect(restoredStore.selectedDocumentID == nil)
        #expect(restoredStore.textSize(for: documentID) == .large)
    }

    @MainActor
    @Test func restoreKeepsPersistedSelectionOnCompactWidth() async throws {
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

        let restoredStore = DocumentSessionStore(disablePersistenceRestore: false, userDefaults: defaults)
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: true, userDefaults: defaults)

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

        let restoredStore = DocumentSessionStore(disablePersistenceRestore: false, userDefaults: defaults)
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

        let restoredStore = DocumentSessionStore(disablePersistenceRestore: false, userDefaults: defaults)
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

        let restoredStore = DocumentSessionStore(disablePersistenceRestore: false, userDefaults: defaults)
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
    // it again from its new place: it is now in the list under both paths, and
    // the first entry's bookmark follows the file, so on the next launch both
    // resolve to the same path. Restoring that list used to trap while building
    // the search index, and went on trapping at every launch, because the saved
    // list was still the same.
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
        let restoredStore = DocumentSessionStore(disablePersistenceRestore: false, userDefaults: defaults)
        restoredStore.restorePersistedDocumentsIfNeeded(isCompactWidth: false, userDefaults: defaults)

        return restoredStore.openedDocuments.map(\.id) == [resolvedID]
            && restoredStore.selectedDocumentID == resolvedID
            && restoredStore.documentMatchesListSearch(resolvedID, query: "Notes")
    }
}
