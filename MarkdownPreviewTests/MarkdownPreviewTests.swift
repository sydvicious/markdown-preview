//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

//
//  MarkdownPreviewTests.swift
//  MarkdownPreviewTests
//
//  Created by Syd Polk on 1/25/25.
//

import Foundation
import Testing
@testable import MarkdownPreview

struct MarkdownPreviewTests {

    @MainActor
    @Test func textSizePreferencePersistsPerDocumentAndClearsWhenRemoved() async throws {
        let suiteName = "MarkdownPreviewTests.\(#function).\(UUID().uuidString)"
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
        let home = NSHomeDirectory()
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
        let suiteName = "MarkdownPreviewTests.\(#function).\(UUID().uuidString)"
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
        let suiteName = "MarkdownPreviewTests.\(#function).\(UUID().uuidString)"
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
        let suiteName = "MarkdownPreviewTests.\(#function).\(UUID().uuidString)"
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

        let suiteName = "MarkdownPreviewTests.\(#function).\(UUID().uuidString)"
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
        let suiteName = "MarkdownPreviewTests.\(#function).\(UUID().uuidString)"
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

    @Test func initialOpenPresentationUsesFileImporterOnMacWhenRestoreIsEmpty() async throws {
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: false,
                didRestoreDocuments: true,
                openedDocumentsEmpty: true,
                allowsFileImporter: true
            ) == .fileImporter
        )
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: true,
                didRestoreDocuments: true,
                openedDocumentsEmpty: true,
                allowsFileImporter: true
            ) == .none
        )
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: false,
                didRestoreDocuments: false,
                openedDocumentsEmpty: true,
                allowsFileImporter: true
            ) == .none
        )
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: false,
                didRestoreDocuments: true,
                openedDocumentsEmpty: false,
                allowsFileImporter: true
            ) == .none
        )
        #expect(
            ContentViewModel.initialOpenPresentation(
                hasPresentedPrompt: false,
                didRestoreDocuments: true,
                openedDocumentsEmpty: true,
                allowsFileImporter: false
            ) == .none
        )
    }

    @Test func htmlBuilderRendersCoreMarkdownBlocks() async throws {
        let source = """
        # Title

        Paragraph with **bold** text, `code`, and [a link](https://example.com).

        > Quoted line
        > still quoted

        | Name | Count |
        | --- | ---: |
        | apples | 12 |

        ```
        let value = 42
        ```
        """

        let html = MarkdownHTMLBuilder.document(for: source)

        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<code>code</code>"))
        #expect(html.contains("<a href=\"https://example.com\">a link</a>"))
        #expect(html.contains("<blockquote><p>Quoted line<br>still quoted</p></blockquote>"))
        #expect(html.contains("<table>"))
        #expect(html.contains("class=\"a-right\">12</td>"))
        #expect(html.contains("<pre><code>let value = 42</code></pre>"))
    }

    @Test func clipboardPayloadIncludesMarkdownAndRichText() async throws {
        let source = """
        # Title

        Paragraph with **bold** text.
        """

        let payload = MarkdownSelectionClipboard.payload(
            for: source,
            ranges: [MarkdownSelectionRange(location: 0, length: source.utf16.count)]
        )

        #expect(payload?.markdown == source)
        #expect(payload?.rtf?.isEmpty == false)
    }

    @Test func selectedMarkdownUsesSelectionRangesInSourceOrder() async throws {
        let source = "alpha beta gamma"
        let ranges = [
            MarkdownSelectionRange(location: 11, length: 5),
            MarkdownSelectionRange(location: 0, length: 5)
        ]

        #expect(MarkdownSelectionClipboard.selectedMarkdown(in: source, ranges: ranges) == "alpha\ngamma")
    }

    @Test func sourceSelectionResolvesNonEmptyRangeToRealSelection() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 2, length: 5)],
            textUTF16Length: 20
        )

        #expect(update == .select(NSRange(location: 2, length: 5)))
    }

    @Test func sourceSelectionResolvesEmptyInputToClear() async throws {
        let update = SourceSelectionUpdate.resolve(from: [], textUTF16Length: 20)

        #expect(update == .clear(NSRange(location: 0, length: 0)))
    }

    @Test func sourceSelectionClampsRangeToTextLength() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 8, length: 100)],
            textUTF16Length: 10
        )

        #expect(update == .select(NSRange(location: 8, length: 2)))
    }

    @Test func sourceSelectionClearsWhenLocationIsBeyondText() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 50, length: 5)],
            textUTF16Length: 10
        )

        #expect(update == .clear(NSRange(location: 0, length: 0)))
    }

    @Test func sourceSelectionClearsWhenClampedLengthCollapsesToZero() async throws {
        let update = SourceSelectionUpdate.resolve(
            from: [MarkdownSelectionRange(location: 10, length: 5)],
            textUTF16Length: 10
        )

        #expect(update == .clear(NSRange(location: 10, length: 0)))
    }

    @Test func parserKeepsCodeFenceLinesInBlockRange() async throws {
        let source = """
        ```swift
        let value = 42
        ```
        """

        let blocks = MarkdownBlockParser.parse(source)
        guard case let .code(code)? = blocks.first?.kind else {
            Issue.record("Expected first block to be a code block")
            return
        }

        #expect(code == "let value = 42")
        #expect(blocks.first?.lineRange == 0..<3)
    }

    @Test func htmlBuilderEmbedsSourceRangeMetadata() async throws {
        let source = """
        # Title

        Paragraph text.
        """

        let html = MarkdownHTMLBuilder.document(for: source)

        #expect(html.contains("data-source-start="))
        #expect(html.contains("data-source-end="))
        #expect(html.contains("class=\"md-block\""))
    }

    @Test func htmlBuilderAddsCopyButtonsToCopyableBlockTypes() async throws {
        let source = """
        > Quoted line

        | Name | Count |
        | --- | ---: |
        | apples | 12 |

        ```
        let value = 42
        ```
        """

        let html = MarkdownHTMLBuilder.document(for: source)

        #expect(html.contains("class=\"md-copy-button\""))
        #expect(html.contains("data-copy-button"))
        #expect(html.contains("class=\"md-block md-copyable-block\""))
    }

    @Test func htmlBuilderAvoidsLeadingWhitespaceInsideParagraphBlocks() async throws {
        let source = """
        Copyright (c) 2026, Syd Polk
        All rights reserved.
        """

        let html = MarkdownHTMLBuilder.document(for: source)

        #expect(
            html.contains(
                "<div class=\"md-block\" data-source-start=\"0\" data-source-end=\"49\"><p>Copyright (c) 2026, Syd Polk All rights reserved.</p></div>"
            )
        )
    }

    @Test func previewSelectionReflectionFindsSydInLicenseParagraph() async throws {
        let source = """
        Copyright (c) 2026, Syd Polk
        All rights reserved.
        """
        let selection = MarkdownSearch.matches(in: source, query: "Syd").first

        let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: source,
            selectedRange: selection
        )

        #expect(reflectedSelection?.blockStart == 0)
        #expect(reflectedSelection?.blockEnd == 49)
        #expect(reflectedSelection?.displayRange == MarkdownSelectionRange(location: 20, length: 3))
    }

    @Test func previewSelectionReflectionAdjustsForOrderedListOffsets() async throws {
        let source = """
        1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
        2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
        3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
        """
        let selection = MarkdownSearch.matches(in: source, query: "be").first

        let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: source,
            selectedRange: selection
        )

        #expect(reflectedSelection?.blockStart == 0)
        #expect(reflectedSelection?.blockEnd == source.utf16.count)
        #expect(reflectedSelection?.displayRange == MarkdownSelectionRange(location: 405, length: 2))
    }

    @Test func previewSelectionBridgeParsesOnlyValidDisplayRangePayloads() async throws {
        let payload: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: 20),
                "displayLocation": NSNumber(value: 4),
                "displayLength": NSNumber(value: 8)
            ],
            [
                "blockStart": NSNumber(value: 20),
                "blockEnd": NSNumber(value: 20),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 4)
            ],
            [
                "blockStart": NSNumber(value: 25),
                "blockEnd": NSNumber(value: 40),
                "displayLocation": NSNumber(value: -1),
                "displayLength": NSNumber(value: 4)
            ],
            [
                "blockStart": NSNumber(value: 45),
                "blockEnd": NSNumber(value: 60),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 0)
            ],
            [
                "blockStart": NSNumber(value: 65),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 4)
            ]
        ]

        #expect(PreviewSelectionBridge.displayRanges(from: payload) == [
            PreviewDisplaySelectionRange(blockStart: 0, blockEnd: 20, displayLocation: 4, displayLength: 8)
        ])
        #expect(PreviewSelectionBridge.displayRanges(from: nil).isEmpty)
        #expect(PreviewSelectionBridge.displayRanges(from: ["not": "an array"]).isEmpty)
    }

    @Test func previewCopyBlockMessageRequiresValidIncreasingSourceOffsets() async throws {
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: 4),
            "end": NSNumber(value: 12)
        ]) == PreviewCopyBlockMessage(start: 4, end: 12))

        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: 4),
            "end": NSNumber(value: 4)
        ]) == nil)
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": NSNumber(value: -1),
            "end": NSNumber(value: 4)
        ]) == nil)
        #expect(PreviewCopyBlockMessage(messageBody: [
            "start": "4",
            "end": NSNumber(value: 12)
        ]) == nil)
        #expect(PreviewCopyBlockMessage(messageBody: "not a payload") == nil)
    }

    @Test func previewSelectionChangedMessageNormalizesTextAndKeepsRawRangePayload() async throws {
        let ranges: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: 10),
                "displayLocation": NSNumber(value: 2),
                "displayLength": NSNumber(value: 4)
            ]
        ]
        let message = PreviewSelectionChangedMessage(messageBody: [
            "text": "  beta  ",
            "ranges": ranges
        ])

        #expect(message.selectedText == "beta")
        #expect(PreviewSelectionBridge.displayRanges(from: message.displayRangeResult) == [
            PreviewDisplaySelectionRange(blockStart: 0, blockEnd: 10, displayLocation: 2, displayLength: 4)
        ])

        let emptyTextMessage = PreviewSelectionChangedMessage(messageBody: [
            "text": "   ",
            "ranges": ranges
        ])
        #expect(emptyTextMessage.selectedText == nil)

        let malformedMessage = PreviewSelectionChangedMessage(messageBody: "not a payload")
        #expect(malformedMessage.selectedText == nil)
        #expect(PreviewSelectionBridge.displayRanges(from: malformedMessage.displayRangeResult).isEmpty)
    }

    @Test func previewSelectionBridgeMapsPartialParagraphSelectionWithoutExpandingToWholeBlock() async throws {
        let source = "Alpha beta gamma"
        let payload = displayRangePayload(in: source, visibleText: "beta")

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.count == 1)
        #expect(ranges.first?.range(in: source).map { String(source[$0]) } == "beta")
        #expect(MarkdownSelectionClipboard.selectedMarkdown(in: source, ranges: ranges) == "beta")
    }

    @Test func previewSelectionBridgeMapsInlineMarkdownSelectionsToVisibleSourceTextOnly() async throws {
        let source = "Paragraph with [beta](https://example.com), **gamma**, and `delta`."
        let payload = displayRangePayloads(in: source, visibleTexts: ["beta", "gamma", "delta"])

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.compactMap { $0.range(in: source).map { String(source[$0]) } } == [
            "beta",
            "gamma",
            "delta"
        ])
        #expect(MarkdownSelectionClipboard.selectedMarkdown(in: source, ranges: ranges) == "beta\ngamma\ndelta")
    }

    @Test func previewSelectionBridgeMapsSelectionsAcrossRenderedBlocks() async throws {
        let source = """
        # Alpha Heading

        Paragraph with beta.

        > Quote gamma

        ```
        let delta = 4
        ```
        """
        let payload = displayRangePayloads(in: source, visibleTexts: [
            "Alpha",
            "beta",
            "gamma",
            "delta"
        ])

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.compactMap { $0.range(in: source).map { String(source[$0]) } } == [
            "Alpha",
            "beta",
            "gamma",
            "delta"
        ])
    }

    @Test func previewSelectionBridgeIgnoresOutOfBoundsSourceBlocks() async throws {
        let source = "Alpha beta"
        let payload: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: 10),
                "displayLocation": NSNumber(value: 6),
                "displayLength": NSNumber(value: 4)
            ],
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: source.utf16.count + 20),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 5)
            ],
            [
                "blockStart": NSNumber(value: source.utf16.count + 1),
                "blockEnd": NSNumber(value: source.utf16.count + 5),
                "displayLocation": NSNumber(value: 0),
                "displayLength": NSNumber(value: 4)
            ]
        ]

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.count == 1)
        #expect(ranges.first?.range(in: source).map { String(source[$0]) } == "beta")
    }

    @Test func previewSelectionBridgeIgnoresDisplayRangesThatDoNotMapToSourceText() async throws {
        let source = "Alpha beta"
        let payload: [[String: Any]] = [
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: source.utf16.count),
                "displayLocation": NSNumber(value: 6),
                "displayLength": NSNumber(value: 4)
            ],
            [
                "blockStart": NSNumber(value: 0),
                "blockEnd": NSNumber(value: source.utf16.count),
                "displayLocation": NSNumber(value: 50),
                "displayLength": NSNumber(value: 3)
            ]
        ]

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.count == 1)
        #expect(ranges.first?.range(in: source).map { String(source[$0]) } == "beta")
    }

    @Test func previewSelectionBridgeHandlesDisplayRangesInsideListAndTableBlocks() async throws {
        let source = """
        - Alpha item
        - Beta item

        | Name | Count |
        | --- | ---: |
        | Gamma | 12 |
        """
        let payload = displayRangePayloads(in: source, visibleTexts: [
            "Beta",
            "Gamma",
            "12"
        ])

        let ranges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload, source: source)

        #expect(ranges.compactMap { $0.range(in: source).map { String(source[$0]) } } == [
            "Beta",
            "Gamma",
            "12"
        ])
    }

    @Test func markdownPreviewTextOffsetMappingUsesPreviewVisibleTextRules() async throws {
        let source = """
        # **Alpha**

        Paragraph with [beta](https://example.com), `gamma`, and ![diagram](image.png).
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha\nParagraph with beta, gamma, and .")

        let alphaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 0, length: 5)
        )
        let betaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 21, length: 4)
        )
        let gammaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 27, length: 5)
        )

        #expect(alphaRange?.range(in: source).map { String(source[$0]) } == "Alpha")
        #expect(betaRange?.range(in: source).map { String(source[$0]) } == "beta")
        #expect(gammaRange?.range(in: source).map { String(source[$0]) } == "gamma")
        #expect(mapping.displayText.contains("diagram") == false)
    }

    @Test func markdownPreviewTextOffsetMappingCollapsesListBoundariesLikePreview() async throws {
        let source = """
        - Alpha
        - Beta

        1. Gamma
        2. Delta
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "AlphaBeta\nGammaDelta")

        let betaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 5, length: 4)
        )
        let gammaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 10, length: 5)
        )

        #expect(betaRange?.range(in: source).map { String(source[$0]) } == "Beta")
        #expect(gammaRange?.range(in: source).map { String(source[$0]) } == "Gamma")
    }

    @Test func markdownPreviewTextOffsetMappingHandlesBlockquotesTablesAndCode() async throws {
        let source = """
        > Quote line
        > second line

        | Name | Count |
        | --- | ---: |
        | apples | 12 |

        ```
        let value = 42
        next line
        ```
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Quote linesecond line\nNameCountapples12\nlet value = 42\nnext line")
    }

    @Test func markdownPreviewTextOffsetMappingHandlesSetextHeadingsAndChecklistSyntax() async throws {
        let source = """
        Alpha Heading
        ============

        - [x] Completed item
        - [ ] Pending item
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha Heading\nCompleted itemPending item")

        let headingRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 0, length: 13)
        )
        let completedRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 14, length: 14)
        )
        let pendingRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 28, length: 12)
        )

        #expect(headingRange?.range(in: source).map { String(source[$0]) } == "Alpha Heading")
        #expect(completedRange?.range(in: source).map { String(source[$0]) } == "Completed item")
        #expect(pendingRange?.range(in: source).map { String(source[$0]) } == "Pending item")
    }

    @Test func markdownPreviewTextOffsetMappingRoundTripsSearchMatchesAcrossSupportedMarkdown() async throws {
        let source = """
        Alpha Heading
        ============

        Paragraph with [beta](https://example.com), **gamma**, _delta_, `epsilon`, and ![diagram](image.png).

        - [x] Theta item
        - [ ] Iota item

        > Kappa quote

        | Name | Count |
        | --- | ---: |
        | Lambda | 12 |

        ```
        let value = 42
        ```
        """
        let mapping = MarkdownPreviewTextOffsetMapping(sourceText: source)
        let queries = [
            "Alpha",
            "beta",
            "gamma",
            "delta",
            "epsilon",
            "Theta",
            "Iota",
            "Kappa",
            "Name",
            "Lambda",
            "12",
            "let value = 42"
        ]

        #expect(mapping.displayText.contains("diagram") == false)

        for query in queries {
            guard let sourceRange = MarkdownSearch.matches(in: source, query: query).first else {
                Issue.record("Expected to find source match for \(query)")
                continue
            }

            guard let displayRange = mapping.displayRange(forSourceRange: sourceRange) else {
                Issue.record("Expected preview display range for \(query)")
                continue
            }

            let displaySnippet = (mapping.displayText as NSString).substring(with: displayRange.nsRange)
            #expect(displaySnippet == query)

            guard let roundTrippedSourceRange = mapping.sourceRange(forDisplayRange: displayRange) else {
                Issue.record("Expected round-tripped source range for \(query)")
                continue
            }

            let sourceSnippet = (source as NSString).substring(with: roundTrippedSourceRange.nsRange)
            #expect(sourceSnippet == query)
        }
    }

    @Test func previewSelectionReflectionMapsVisibleSearchMatchesInsideMixedMarkdownBlocks() async throws {
        let source = """
        Paragraph with [beta](https://example.com), **gamma**, and `delta`.

        1. Theta item
        2. Iota item

        | Name | Count |
        | --- | ---: |
        | Lambda | 12 |
        """
        let queries = ["beta", "gamma", "delta", "Iota", "Lambda", "12"]

        for query in queries {
            guard let selection = MarkdownSearch.matches(in: source, query: query).first else {
                Issue.record("Expected source match for \(query)")
                continue
            }

            guard let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
                in: source,
                selectedRange: selection
            ) else {
                Issue.record("Expected reflected selection for \(query)")
                continue
            }

            let blockSource = (source as NSString).substring(
                with: NSRange(
                    location: reflectedSelection.blockStart,
                    length: reflectedSelection.blockEnd - reflectedSelection.blockStart
                )
            )
            let previewMapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource)
            let previewSnippet = (previewMapping.displayText as NSString).substring(
                with: reflectedSelection.displayRange.nsRange
            )

            #expect(previewSnippet == query)
        }
    }

    @Test func markdownSearchFindsCaseInsensitiveMatchesInSourceOrder() async throws {
        let source = "**Alpha** beta [ALPHA](https://example.com)\nalpha"
        let matches = MarkdownSearch.matches(in: source, query: "alpha")

        #expect(matches.count == 3)
        #expect(matches.compactMap { $0.range(in: source).map { String(source[$0]) } } == [
            "Alpha",
            "ALPHA",
            "alpha"
        ])
    }

    @Test func markdownTextOffsetMappingStripsMarkdownSyntax() async throws {
        let source = "# **Alpha** [beta](https://example.com)"
        let mapping = MarkdownTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha beta")

        let alphaSourceRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 0, length: 5)
        )
        let betaSourceRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 6, length: 4)
        )

        #expect(alphaSourceRange?.range(in: source).map { String(source[$0]) } == "Alpha")
        #expect(betaSourceRange?.range(in: source).map { String(source[$0]) } == "beta")
    }

    @Test func markdownTextOffsetMappingUsesSearchVisibleTextRules() async throws {
        let source = """
        # **Alpha**

        Paragraph with [beta](https://example.com), `gamma`, and ![diagram](image.png).
        """
        let mapping = MarkdownTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha\nParagraph with beta, gamma, and diagram.")

        let alphaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 0, length: 5)
        )
        let betaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 21, length: 4)
        )
        let gammaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 27, length: 5)
        )
        let diagramRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 38, length: 7)
        )

        #expect(alphaRange?.range(in: source).map { String(source[$0]) } == "Alpha")
        #expect(betaRange?.range(in: source).map { String(source[$0]) } == "beta")
        #expect(gammaRange?.range(in: source).map { String(source[$0]) } == "gamma")
        #expect(diagramRange?.range(in: source).map { String(source[$0]) } == "diagram")
    }

    @Test func markdownTextOffsetMappingPreservesListBoundariesForSearch() async throws {
        let source = """
        - Alpha
        - Beta

        1. Gamma
        2. Delta
        """
        let mapping = MarkdownTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha\nBeta\nGamma\nDelta")

        let betaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 6, length: 4)
        )
        let gammaRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 11, length: 5)
        )

        #expect(betaRange?.range(in: source).map { String(source[$0]) } == "Beta")
        #expect(gammaRange?.range(in: source).map { String(source[$0]) } == "Gamma")
    }

    @Test func markdownTextOffsetMappingHandlesSetextHeadingsChecklistTablesAndCode() async throws {
        let source = """
        Alpha Heading
        ============

        - [x] Completed item
        - [ ] Pending item

        | Name | Count |
        | --- | ---: |
        | apples | 12 |

        ```
        let value = 42
        ```
        """
        let mapping = MarkdownTextOffsetMapping(sourceText: source)

        #expect(mapping.displayText == "Alpha Heading\nCompleted item\nPending item\nNameCountapples12\nlet value = 42")
    }

    @Test func markdownTextOffsetMappingRoundTripsSearchMatchesAcrossSupportedMarkdown() async throws {
        let source = """
        Alpha Heading
        ============

        Paragraph with [beta](https://example.com), **gamma**, _delta_, `epsilon`, and ![diagram](image.png).

        - [x] Theta item
        - [ ] Iota item

        > Kappa quote

        | Name | Count |
        | --- | ---: |
        | Lambda | 12 |

        ```
        let value = 42
        ```
        """
        let mapping = MarkdownTextOffsetMapping(sourceText: source)
        let queries = [
            "Alpha",
            "beta",
            "gamma",
            "delta",
            "epsilon",
            "diagram",
            "Theta",
            "Iota",
            "Kappa",
            "Name",
            "Lambda",
            "12",
            "let value = 42"
        ]

        for query in queries {
            guard let sourceRange = MarkdownSearch.matches(in: source, query: query).first else {
                Issue.record("Expected to find source match for \(query)")
                continue
            }

            guard let displayRange = mapping.displayRange(forSourceRange: sourceRange) else {
                Issue.record("Expected search display range for \(query)")
                continue
            }

            let displaySnippet = (mapping.displayText as NSString).substring(with: displayRange.nsRange)
            #expect(displaySnippet == query)

            guard let roundTrippedSourceRange = mapping.sourceRange(forDisplayRange: displayRange) else {
                Issue.record("Expected round-tripped source range for \(query)")
                continue
            }

            let sourceSnippet = (source as NSString).substring(with: roundTrippedSourceRange.nsRange)
            #expect(sourceSnippet == query)
        }
    }

    @Test func htmlTextOffsetMappingStripsTagsAndDecodesEntities() async throws {
        let html = "<html><body><p>Alpha &amp; <strong>beta</strong></p></body></html>"
        let mapping = HTMLTextOffsetMapping(sourceText: html)

        #expect(mapping.displayText == "Alpha & beta")

        let ampersandRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 6, length: 1)
        )
        #expect(ampersandRange?.range(in: html).map { String(html[$0]) } == "&amp;")
    }

    @Test func documentSearchIndexMatchesAgainstStrippedText() async throws {
        let file = MarkdownFile(
            url: URL(fileURLWithPath: "/tmp/example.md"),
            contents: "# **Alpha** [beta](https://example.com)"
        )
        let index = DocumentSearchIndex(documents: [file])
        let documentID = file.url.standardizedFileURL.path

        #expect(index.containsMatch(in: documentID, query: "Alpha"))
        #expect(index.containsMatch(in: documentID, query: "beta"))
        #expect(index.containsMatch(in: documentID, query: "example.md"))
        #expect(index.containsMatch(in: documentID, query: "https") == false)
    }

    @Test func documentSearchIndexMatchesSubstringsWithinWords() async throws {
        let file = MarkdownFile(
            url: URL(fileURLWithPath: "/tmp/readme.md"),
            contents: "The repository includes unit/UI test targets."
        )
        let index = DocumentSearchIndex(documents: [file])
        let documentID = file.url.standardizedFileURL.path

        #expect(index.containsMatch(in: documentID, query: "repo"))
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

    @Test func markdownSearchSessionWrapsOnSecondNavigationAtBoundary() async throws {
        var session = MarkdownSearchSession()
        session.updateQuery("alpha", in: "alpha beta alpha")

        #expect(session.resultPositionText == "1 of 2")

        let firstAdvance = session.move(.forward)
        #expect(firstAdvance)
        #expect(session.resultPositionText == "2 of 2")

        let boundaryAdvance = session.move(.forward)
        #expect(boundaryAdvance == false)
        #expect(session.resultPositionText == "2 of 2")

        let wrappedAdvance = session.move(.forward)
        #expect(wrappedAdvance)
        #expect(session.resultPositionText == "1 of 2")
    }

    private func displayRangePayload(in source: String, visibleText: String) -> [[String: Any]] {
        displayRangePayloads(in: source, visibleTexts: [visibleText])
    }

    private func displayRangePayloads(in source: String, visibleTexts: [String]) -> [[String: Any]] {
        let blocks = MarkdownBlockParser.parse(source)
        let lineTable = MarkdownSourceLineTable(source: source)

        return visibleTexts.compactMap { visibleText -> [String: Any]? in
            for block in blocks {
                guard let blockRange = lineTable.range(for: block.lineRange) else { continue }
                let blockSource = (source as NSString).substring(with: blockRange.nsRange)
                let mapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource)
                let displayRange = (mapping.displayText as NSString).range(of: visibleText)
                guard displayRange.location != NSNotFound else { continue }

                return [
                    "blockStart": NSNumber(value: blockRange.location),
                    "blockEnd": NSNumber(value: blockRange.location + blockRange.length),
                    "displayLocation": NSNumber(value: displayRange.location),
                    "displayLength": NSNumber(value: displayRange.length)
                ]
            }

            Issue.record("Expected visible text \(visibleText) in preview display text")
            return nil
        }
    }

}
