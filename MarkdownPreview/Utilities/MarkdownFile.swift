//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import UniformTypeIdentifiers

struct MarkdownFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let contents: String

    var fileName: String {
        url.lastPathComponent
    }

    /// Reads `url`. The caller holds whatever security scope the read needs:
    /// `DocumentSessionStore` takes it around this call, and taking it a second
    /// time here would repeat a refused request the store has learned not to make.
    static func load(from url: URL) throws -> MarkdownFile {
        let data = try readData(from: url)
        guard let text = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .unicode) ??
            String(data: data, encoding: .ascii) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return MarkdownFile(url: url, contents: text)
    }

    private static func readData(from url: URL) throws -> Data {
        try ensureUbiquitousItemIsAvailable(at: url)

        let deadline = Date().addingTimeInterval(30)
        var lastError: Error?
        while Date() < deadline {
            do {
                return try coordinatedReadData(from: url)
            } catch {
                lastError = error
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
                    if let uploadedData = tryCoordinatedUploadingReadData(from: url) {
                        return uploadedData
                    }
                    try? ensureUbiquitousItemIsAvailable(at: url)
                    Thread.sleep(forTimeInterval: 0.2)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? CocoaError(.fileNoSuchFile)
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

    private static func ensureUbiquitousItemIsAvailable(at url: URL) throws {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isUbiquitousItem == true else { return }

        let status = values.ubiquitousItemDownloadingStatus
        if status != URLUbiquitousItemDownloadingStatus.current {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    static var supportedTypes: [UTType] {
        var types: [UTType] = [.plainText]
        if let markdown = UTType(filenameExtension: "md") {
            types.insert(markdown, at: 0)
        }
        return Array(Set(types))
    }
}
