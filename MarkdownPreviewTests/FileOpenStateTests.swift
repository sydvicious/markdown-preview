//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing

struct FileOpenStateTests {

    /// Nothing asked for yet is what lets the app offer its own file importer
    /// at launch.
    @MainActor
    @Test func fileOpenStateStartsWithNothingQueuedAndNothingAskedFor() async throws {
        let fileOpenState = FileOpenState()

        #expect(fileOpenState.pendingURLs.isEmpty)
        #expect(fileOpenState.didReceiveExternalOpenRequest == false)
    }

    @MainActor
    @Test func fileOpenStateTreatsAnEmptyBatchAsNoRequest() async throws {
        let fileOpenState = FileOpenState()

        fileOpenState.enqueue([])

        #expect(fileOpenState.pendingURLs.isEmpty)
        #expect(fileOpenState.didReceiveExternalOpenRequest == false)
    }

    @MainActor
    @Test func fileOpenStateAddsEachBatchToWhatIsAlreadyQueued() async throws {
        let fileOpenState = FileOpenState()
        let urls = (0..<5).map { URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-\($0).md") }

        fileOpenState.enqueue(Array(urls[0..<2]))
        fileOpenState.enqueue(urls[2])
        fileOpenState.enqueue(Array(urls[3..<5]))

        #expect(fileOpenState.pendingURLs == urls)
    }

    @MainActor
    @Test func fileOpenStateQueuesTheSameURLEachTimeItIsOpened() async throws {
        let fileOpenState = FileOpenState()
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).md")

        fileOpenState.enqueue(url)
        fileOpenState.enqueue([url, url])

        #expect(fileOpenState.pendingURLs == [url, url, url])
    }

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

    // MARK: - Taking what is queued

    @MainActor
    @Test func takingThePendingURLsHandsOverEveryOneInOrderAndEmptiesTheQueue() async throws {
        let fileOpenState = FileOpenState()
        let urls = (0..<3).map { URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-\($0).md") }
        fileOpenState.enqueue(urls)

        let taken = fileOpenState.takePendingURLs()

        #expect(taken == urls)
        #expect(fileOpenState.pendingURLs.isEmpty)
    }

    /// A URL is handed over once. Whoever asks again, with nothing queued
    /// since, is handed nothing.
    @MainActor
    @Test func takingThePendingURLsTwiceHandsOverNothingTheSecondTime() async throws {
        let fileOpenState = FileOpenState()
        fileOpenState.enqueue(URL(fileURLWithPath: "/tmp/\(UUID().uuidString).md"))

        _ = fileOpenState.takePendingURLs()

        #expect(fileOpenState.takePendingURLs().isEmpty)
    }

    @MainActor
    @Test func takingThePendingURLsHandsOverOnlyWhatWasQueuedSinceTheLastTime() async throws {
        let fileOpenState = FileOpenState()
        let first = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-first.md")
        let later = (0..<2).map { URL(fileURLWithPath: "/tmp/\(UUID().uuidString)-later-\($0).md") }

        fileOpenState.enqueue(first)
        _ = fileOpenState.takePendingURLs()
        fileOpenState.enqueue(later)

        #expect(fileOpenState.takePendingURLs() == later)
    }

    @MainActor
    @Test func takingThePendingURLsWithNothingQueuedIsNotARequest() async throws {
        let fileOpenState = FileOpenState()

        #expect(fileOpenState.takePendingURLs().isEmpty)
        #expect(fileOpenState.didReceiveExternalOpenRequest == false)
    }

    /// The queue is emptied once its files are open. That the app was asked to
    /// open something stays true for as long as it runs.
    @MainActor
    @Test func fileOpenStateRemembersTheRequestAfterItsURLsAreTaken() async throws {
        let fileOpenState = FileOpenState()
        fileOpenState.enqueue(URL(fileURLWithPath: "/tmp/\(UUID().uuidString).md"))

        _ = fileOpenState.takePendingURLs()

        #expect(fileOpenState.pendingURLs.isEmpty)
        #expect(fileOpenState.didReceiveExternalOpenRequest)
    }
}
