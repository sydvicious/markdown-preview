//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import UniformTypeIdentifiers
import os

struct MarkdownFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let contents: String

    var fileName: String {
        url.lastPathComponent
    }

    /// Thrown for a file that iCloud keeps and has not delivered to this
    /// device. It has been asked for.
    struct NotDelivered: Error {}

    /// Where a file's contents stand with iCloud.
    enum CloudState: Sendable {
        /// iCloud does not keep this file.
        case notInCloud
        /// What is here is the latest there is.
        case current
        /// What is here can be read, and iCloud has something newer.
        case outOfDate
        /// None of it is here.
        case notDelivered
    }

    /// What iCloud says of a file, and how it is asked to deliver one.
    ///
    /// The read goes through this so that a test can stand in for a file
    /// iCloud has not delivered, which no test can make.
    struct CloudDelivery: Sendable {
        var state: @Sendable (URL) throws -> CloudState
        var request: @Sendable (URL) throws -> Void

        static let system = CloudDelivery(
            state: { url in
                // A URL holds on to what it was last told, and a file that is
                // waited for is asked about again and again. What it holds is
                // thrown away first, or the answer would never change.
                var asked = url
                asked.removeAllCachedResourceValues()
                let values = try asked.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey
                ])
                guard values.isUbiquitousItem == true else { return .notInCloud }
                let status = values.ubiquitousItemDownloadingStatus
                if status == URLUbiquitousItemDownloadingStatus.current {
                    return .current
                }
                if status == URLUbiquitousItemDownloadingStatus.notDownloaded {
                    return .notDelivered
                }
                return .outOfDate
            },
            request: { url in
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        )
    }

    /// Reads `url`, once, and waits for nothing. The caller holds whatever
    /// security scope the read needs: `DocumentSessionStore` takes it around
    /// this call, and taking it a second time here would repeat a refused
    /// request the store has learned not to make.
    ///
    /// This is called on the main actor, and reading a file iCloud has not
    /// delivered waits for it to arrive. So such a file is not read. It is
    /// asked for, and `NotDelivered` is thrown; `loadWhenDelivered` is the
    /// read that waits.
    static func load(from url: URL, cloud: CloudDelivery = .system) throws -> MarkdownFile {
        let clock = ContinuousClock()
        let started = clock.now
        var attempt = Attempt()
        do {
            let file = try read(url, cloud: cloud, noting: &attempt)
            log.info("""
                [read] \(url.lastPathComponent, privacy: .public): read \(attempt.bytes ?? 0) bytes in \
                \(milliseconds(clock.now - started), format: .fixed(precision: 1)) ms on \(threadName(), privacy: .public); \
                \(describe(attempt, of: url), privacy: .public)
                """)
            return file
        } catch is NotDelivered {
            log.info("""
                [read] \(url.lastPathComponent, privacy: .public): not delivered, so asked for and not read; \
                \(milliseconds(clock.now - started), format: .fixed(precision: 1)) ms on \(threadName(), privacy: .public); \
                \(describe(attempt, of: url), privacy: .public)
                """)
            throw NotDelivered()
        } catch {
            let nsError = error as NSError
            log.info("""
                [read] \(url.lastPathComponent, privacy: .public): failed with \(nsError.domain, privacy: .public) \
                \(nsError.code) in \(milliseconds(clock.now - started), format: .fixed(precision: 1)) ms on \
                \(threadName(), privacy: .public); \(describe(attempt, of: url), privacy: .public)
                """)
            throw error
        }
    }

    /// Reads `url` when iCloud has delivered it, looking again every `pause`
    /// for as long as `patience`, and then giving up. For a file that `load`
    /// refused as `NotDelivered`; any other failure is passed up at once.
    ///
    /// The time is spent wherever this is called, so it is not called on the
    /// main actor. The caller holds the security scope, as for `load`, and
    /// for as long as this takes.
    static func loadWhenDelivered(
        from url: URL,
        cloud: CloudDelivery = .system,
        patience: Duration = .seconds(30),
        pause: Duration = .milliseconds(200)
    ) async throws -> MarkdownFile {
        let clock = ContinuousClock()
        let started = clock.now
        var tries = 0
        var lastState: CloudState?
        log.info("""
            [read] \(url.lastPathComponent, privacy: .public): waiting up to \
            \(milliseconds(patience) / 1000, format: .fixed(precision: 0)) s for iCloud to deliver it
            """)

        while true {
            tries += 1
            var attempt = Attempt()
            do {
                let file = try read(url, cloud: cloud, noting: &attempt)
                log.info("""
                    [read] \(url.lastPathComponent, privacy: .public): delivered after \
                    \(milliseconds(clock.now - started), format: .fixed(precision: 0)) ms and \(tries) tries; \
                    read \(attempt.bytes ?? 0) bytes on \(threadName(), privacy: .public); \
                    \(describe(attempt, of: url), privacy: .public)
                    """)
                return file
            } catch is NotDelivered {
                if attempt.state != lastState {
                    lastState = attempt.state
                    log.info("""
                        [read] \(url.lastPathComponent, privacy: .public): still waiting at \
                        \(milliseconds(clock.now - started), format: .fixed(precision: 0)) ms, try \(tries), on \
                        \(threadName(), privacy: .public); \(describe(attempt, of: url), privacy: .public)
                        """)
                }
                guard clock.now - started < patience else {
                    log.info("""
                        [read] \(url.lastPathComponent, privacy: .public): gave up after \
                        \(milliseconds(clock.now - started), format: .fixed(precision: 0)) ms and \(tries) tries; \
                        \(describe(attempt, of: url), privacy: .public); \
                        iCloud's reason: \(downloadingError(of: url), privacy: .public)
                        """)
                    throw CocoaError(.ubiquitousFileUnavailable)
                }
                try await Task.sleep(for: pause)
            } catch {
                let nsError = error as NSError
                log.info("""
                    [read] \(url.lastPathComponent, privacy: .public): failed while waiting, with \
                    \(nsError.domain, privacy: .public) \(nsError.code), after \
                    \(milliseconds(clock.now - started), format: .fixed(precision: 0)) ms and \(tries) tries; \
                    \(describe(attempt, of: url), privacy: .public)
                    """)
                throw error
            }
        }
    }

    /// What one try at reading a file found, for the log.
    private struct Attempt {
        var state: CloudState?
        var bytes: Int?
        var readTheCopyBeingUploaded = false
    }

    private static func read(_ url: URL, cloud: CloudDelivery, noting attempt: inout Attempt) throws -> MarkdownFile {
        let state = try cloud.state(url)
        attempt.state = state
        switch state {
        case .notInCloud, .current:
            break
        case .outOfDate:
            try cloud.request(url)
        case .notDelivered:
            try cloud.request(url)
            throw NotDelivered()
        }

        let data = try readData(from: url, state: state, cloud: cloud, noting: &attempt)
        attempt.bytes = data.count
        guard let text = decodedText(from: data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return MarkdownFile(url: url, contents: text)
    }

    // MARK: - What the log says of a read. Filter the console on `[read]`.

    private static let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "Read")

    private static func threadName() -> String {
        Thread.isMainThread ? "the main thread" : "a background thread"
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    /// What iCloud said of the file, and what the file system says: a file
    /// whose contents are somewhere else, whoever keeps them, is `dataless`.
    private static func describe(_ attempt: Attempt, of url: URL) -> String {
        var parts: [String] = []
        if let state = attempt.state {
            parts.append("iCloud=\(state)")
        } else {
            parts.append("iCloud was not asked")
        }
        var info = stat()
        if lstat(url.path, &info) == 0 {
            parts.append("dataless=\(info.st_flags & UInt32(SF_DATALESS) != 0)")
        } else {
            parts.append("dataless=unknown (errno \(errno))")
        }
        if attempt.readTheCopyBeingUploaded {
            parts.append("read the copy being uploaded")
        }
        return parts.joined(separator: ", ")
    }

    private static func downloadingError(of url: URL) -> String {
        var asked = url
        asked.removeAllCachedResourceValues()
        guard let error = try? asked.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey])
            .ubiquitousItemDownloadingError else {
            return "none given"
        }
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }

    /// The text `data` holds, or nil if it is not text the app reads.
    ///
    /// That is UTF-8, or UTF-16 beginning with a byte-order mark. The mark is
    /// required because, asked to read UTF-16 without one, Foundation makes
    /// characters of nearly any bytes: a Latin-1 file, or an image, came back
    /// as a page of CJK characters and nothing was ever refused.
    private static func decodedText(from data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        let byteOrderMarks: [[UInt8]] = [[0xFF, 0xFE], [0xFE, 0xFF]]
        guard byteOrderMarks.contains(where: { data.starts(with: $0) }) else { return nil }
        return String(data: data, encoding: .utf16)
    }

    /// One coordinated read of the file's bytes.
    private static func readData(
        from url: URL,
        state: CloudState,
        cloud: CloudDelivery,
        noting attempt: inout Attempt
    ) throws -> Data {
        do {
            return try coordinatedReadData(from: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            if let uploadedData = tryCoordinatedUploadingReadData(from: url) {
                attempt.readTheCopyBeingUploaded = true
                return uploadedData
            }
            // iCloud said the file was here, and there is nothing to read
            // where it is. It is on its way.
            guard state != .notInCloud else { throw error }
            try? cloud.request(url)
            throw NotDelivered()
        }
    }

    private static func coordinatedReadData(from url: URL) throws -> Data {
        var coordinatedData: Data?
        var coordinatedError: NSError?
        var readError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatedError) { coordinatedURL in
            do {
                coordinatedData = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }

        if let readError {
            throw readError
        }

        if let coordinatedError {
            throw coordinatedError
        }

        guard let coordinatedData else {
            throw CocoaError(.fileReadUnknown)
        }

        return coordinatedData
    }

    private static func tryCoordinatedUploadingReadData(from url: URL) -> Data? {
        var coordinatedData: Data?
        var coordinatedError: NSError?
        var readError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [.forUploading], error: &coordinatedError) { coordinatedURL in
            do {
                coordinatedData = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }

        if coordinatedError != nil || readError != nil {
            return nil
        }

        return coordinatedData
    }

    static var supportedTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.insert(markdown, at: 0)
        }
        return Array(Set(types))
    }
}
