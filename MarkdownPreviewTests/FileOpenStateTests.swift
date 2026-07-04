//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct FileOpenStateTests {

    @MainActor
    @Test func fileOpenStateQueuesEveryOpenedURLWithoutOverwriting() async throws {
        let fileOpenState = FileOpenState()
        let urls = (0..<3).map { URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-\($0).md") }

        for url in urls {
            fileOpenState.enqueue(url)
        }

        #expect(fileOpenState.pendingURLs == urls)
        #expect(fileOpenState.didReceiveExternalOpenRequest)
    }

    @MainActor
    @Test func fileOpenStateQueuesEveryURLFromABatchOpen() async throws {
        // Mirrors the macOS `application(_:open:)` path where a multi-file Open
        // delivers every URL at once.
        let fileOpenState = FileOpenState()
        let urls = (0..<5).map { URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-\($0).md") }

        fileOpenState.enqueue(urls)

        #expect(fileOpenState.pendingURLs == urls)
        #expect(fileOpenState.didReceiveExternalOpenRequest)
    }

    @MainActor
    @Test func openingMultipleQueuedURLsOpensEveryDocument() async throws {
        let suiteName = "FileOpenStateTests.\(#function).\(UUID().uuidString)"
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

        let urls = ["alpha", "beta", "gamma"].map { name -> URL in
            let url = temporaryDirectory.appendingPathComponent("\(name).md")
            try? name.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        let fileOpenState = FileOpenState()
        urls.forEach { fileOpenState.enqueue($0) }

        let store = DocumentSessionStore(disablePersistenceRestore: true, userDefaults: defaults)
        // Mirror the ContentView drain: open every queued URL, not just the last.
        for url in fileOpenState.pendingURLs {
            try store.openDocument(at: url)
        }

        #expect(Set(store.openedDocuments.map(\.id)) == Set(urls.map(\.standardizedFileURL.path)))
    }
}
