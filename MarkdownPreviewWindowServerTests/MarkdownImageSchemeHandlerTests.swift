//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import WebKit
import MarkdownCore
@testable import MarkdownPreview

/// What the preview's image handler does with a request, seen from the web
/// view's side: the calls it makes on the task it was handed.
@MainActor
struct MarkdownImageSchemeHandlerTests {

    /// Stands in for the task WebKit hands the handler, recording what the
    /// handler tells it.
    @MainActor
    private final class RecordingTask: NSObject, @preconcurrency WKURLSchemeTask {
        enum Event: Equatable {
            case response(url: URL?, mimeType: String?, expectedContentLength: Int64)
            case data(Data)
            case finished
            case failed(MarkdownImageSchemeHandler.LoadError?)
        }

        let request: URLRequest
        private(set) var events: [Event] = []
        private var waiter: CheckedContinuation<Void, Never>?

        init(url: URL) {
            request = URLRequest(url: url)
        }

        private var isOver: Bool {
            switch events.last {
            case .finished, .failed: true
            default: false
            }
        }

        /// Returns once the handler has finished or failed the task.
        func waitUntilOver() async {
            if isOver { return }
            await withCheckedContinuation { waiter = $0 }
        }

        private func record(_ event: Event) {
            events.append(event)
            if isOver {
                waiter?.resume()
                waiter = nil
            }
        }

        func didReceive(_ response: URLResponse) {
            record(.response(
                url: response.url,
                mimeType: response.mimeType,
                expectedContentLength: response.expectedContentLength
            ))
        }

        func didReceive(_ data: Data) {
            record(.data(data))
        }

        func didFinish() {
            record(.finished)
        }

        func didFailWithError(_ error: any Error) {
            record(.failed(error as? MarkdownImageSchemeHandler.LoadError))
        }
    }

    /// The web view every request here is made on behalf of. The handler is
    /// handed one and does nothing with it, so the tests share one: making a
    /// web view is slow, in a simulator most of all, and each one made here
    /// holds up every other test waiting for the main actor.
    private static let webView = WKWebView(frame: .zero)

    /// A folder of files to ask for, and a handler whose grants are its own.
    @MainActor
    private struct Fixture {
        let directory: URL
        let accessStore: DirectoryAccessStore
        let handler: MarkdownImageSchemeHandler
        private let defaults: UserDefaults
        private let suiteName: String

        init(function: String = #function) throws {
            suiteName = "MarkdownImageSchemeHandlerTests.\(function).\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            defaults.removePersistentDomain(forName: suiteName)

            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MarkdownImageSchemeHandlerTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            accessStore = DirectoryAccessStore(userDefaults: defaults)
            handler = MarkdownImageSchemeHandler(accessStore: accessStore)
        }

        func makeFile(_ name: String, holding data: Data) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }

        /// Asks the handler for `url` and returns what it told the task.
        func request(_ url: URL) async -> [RecordingTask.Event] {
            let task = RecordingTask(url: url)
            handler.webView(MarkdownImageSchemeHandlerTests.webView, start: task)
            await task.waitUntilOver()
            return task.events
        }

        /// Asks for `file` the way the preview's own markup does.
        func requestImage(at file: URL) async throws -> [RecordingTask.Event] {
            await request(try #require(MarkdownImageURL.url(for: file)))
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

    /// What the task is told when `data` is served for `url`.
    private static func served(_ data: Data, as mimeType: String, for url: URL) -> [RecordingTask.Event] {
        [
            .response(url: url, mimeType: mimeType, expectedContentLength: Int64(data.count)),
            .data(data),
            .finished,
        ]
    }

    // MARK: - Served

    @Test func anImageIsServedWithItsTypeItsLengthAndItsBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("photo.png", holding: Self.png)
        let url = try #require(MarkdownImageURL.url(for: file))

        let events = await fixture.request(url)

        #expect(events == Self.served(Self.png, as: "image/png", for: url))
    }

    // The name says what may be asked for; the bytes say what it is.
    @Test func theTypeServedComesFromTheContentNotTheName() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("photo.png", holding: Self.jpeg)
        let url = try #require(MarkdownImageURL.url(for: file))

        let events = await fixture.request(url)

        #expect(events == Self.served(Self.jpeg, as: "image/jpeg", for: url))
    }

    // The sample document that ships in the app has one of these.
    @Test func anImageWithAnUpperCaseExtensionIsServed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("lilsyd.JPG", holding: Self.jpeg)
        let url = try #require(MarkdownImageURL.url(for: file))

        let events = await fixture.request(url)

        #expect(events == Self.served(Self.jpeg, as: "image/jpeg", for: url))
    }

    @Test func anImageWithSpacesInItsNameIsServed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("my holiday photo.png", holding: Self.png)
        let url = try #require(MarkdownImageURL.url(for: file))

        let events = await fixture.request(url)

        #expect(events == Self.served(Self.png, as: "image/png", for: url))
    }

    @Test func anImageInAGrantedFolderIsServed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("photo.png", holding: Self.png)
        fixture.accessStore.grantAccess(to: fixture.directory)
        let url = try #require(MarkdownImageURL.url(for: file))

        let events = await fixture.request(url)

        #expect(events == Self.served(Self.png, as: "image/png", for: url))
    }

    // MARK: - Refused before anything is read

    // Each of these asks for a real image, so the one thing wrong with the
    // request is the thing the test is named for.

    @Test func aRequestWithoutThisLaunchsKeyIsRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("photo.png", holding: Self.png)
        let imageURL = try #require(MarkdownImageURL.url(for: file))
        var components = try #require(URLComponents(url: imageURL, resolvingAgainstBaseURL: false))
        components.queryItems = nil

        let events = await fixture.request(try #require(components.url))

        #expect(events == [.failed(.notAnImage)])
    }

    @Test func aRequestWithAnotherLaunchsKeyIsRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("photo.png", holding: Self.png)
        let url = try #require(MarkdownImageURL.url(for: file, key: UUID().uuidString))

        let events = await fixture.request(url)

        #expect(events == [.failed(.notAnImage)])
    }

    // The right key and a file full of image bytes, under a name that is not an
    // image's. The handler must not be a way to read whatever a document names.
    @Test func aRequestForAFileWithoutAnImageExtensionIsRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("notes.txt", holding: Self.png)
        let url = try #require(MarkdownImageURL.url(for: file))

        let events = await fixture.request(url)

        #expect(events == [.failed(.notAnImage)])
    }

    @Test func aRequestForAFileWithNoExtensionIsRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("passwd", holding: Self.png)
        let url = try #require(MarkdownImageURL.url(for: file))

        let events = await fixture.request(url)

        #expect(events == [.failed(.notAnImage)])
    }

    @Test func aRequestNamingAnotherHostIsRefused() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("photo.png", holding: Self.png)
        let imageURL = try #require(MarkdownImageURL.url(for: file))
        var components = try #require(URLComponents(url: imageURL, resolvingAgainstBaseURL: false))
        components.host = "elsewhere"

        let events = await fixture.request(try #require(components.url))

        #expect(events == [.failed(.notAnImage)])
    }

    // MARK: - Asked for properly, and not there to serve

    @Test func anImageThatIsNotThereFailsAsUnreadable() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        let events = try await fixture.requestImage(at: fixture.directory.appendingPathComponent("absent.png"))

        #expect(events == [.failed(.unreadable)])
    }

    @Test func anImageThatCannotBeOpenedFailsAsUnreadable() async throws {
        let fixture = try Fixture()
        let file = try fixture.makeFile("locked.png", holding: Self.png)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            fixture.cleanUp()
        }

        let events = try await fixture.requestImage(at: file)

        #expect(events == [.failed(.unreadable)])
    }

    // MARK: - Named as an image, holding something else

    // The case the content check exists for. Whatever the file holds, none of
    // it reaches the web view.
    @Test(arguments: [
        Data("ssh-rsa AAAAB3NzaC1yc2E...".utf8),
        Data("<html><body>hi</body></html>".utf8),
        Data([0x00]),
        Data(),
    ])
    func nothingIsServedFromAFileThatIsNotAnImage(contents: Data) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("secret.png", holding: contents)

        let events = try await fixture.requestImage(at: file)

        #expect(events.count == 1)
        guard case .failed = events.first else {
            Issue.record("Expected the request to fail and nothing else; the task was told \(events)")
            return
        }
    }

    // The file was read; what is wrong with it is that it is not an image.
    @Test func aFileThatIsNotAnImageFailsAsNotAnImage() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("secret.png", holding: Data("ssh-rsa AAAAB3NzaC1yc2E...".utf8))

        let events = try await fixture.requestImage(at: file)

        #expect(events == [.failed(.notAnImage)])
    }

    // MARK: - Stopped

    // WebKit stops a task when the page that asked for the image no longer
    // wants it, as a page being replaced by a re-render of the preview would
    // not. A task that has been stopped must hear nothing more: WebKit raises
    // an exception on any call made to one.
    @Test func aTaskStoppedBeforeItsImageIsReadHearsNothingMore() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("photo.png", holding: Self.png)
        let url = try #require(MarkdownImageURL.url(for: file))
        let stopped = RecordingTask(url: url)

        fixture.handler.webView(Self.webView, start: stopped)
        fixture.handler.webView(Self.webView, stop: stopped)
        // A second request, started after the first, is over only once the
        // first has had its turn.
        let later = await fixture.request(url)

        #expect(later == Self.served(Self.png, as: "image/png", for: url))
        #expect(stopped.events == [])
    }

    @Test func stoppingOneTaskLeavesAnotherForTheSameImageAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let file = try fixture.makeFile("photo.png", holding: Self.png)
        let url = try #require(MarkdownImageURL.url(for: file))
        let stopped = RecordingTask(url: url)
        let kept = RecordingTask(url: url)

        fixture.handler.webView(Self.webView, start: stopped)
        fixture.handler.webView(Self.webView, start: kept)
        fixture.handler.webView(Self.webView, stop: stopped)
        await kept.waitUntilOver()

        #expect(kept.events == Self.served(Self.png, as: "image/png", for: url))
    }
}
