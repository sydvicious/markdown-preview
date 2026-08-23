//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
import WebKit
import MarkdownCore
@testable import MarkdownPreview

/// Closes the last gap in the soft-break verification: whether WebKit agrees
/// with the whitespace model the rest of the selection machinery assumes.
///
/// `SoftBreakSelectionAlignmentTests` pins everything downstream of that model
/// — but it *is* a model, written in Swift. These tests ask WebKit itself, by
/// loading the real generated HTML with the real user script and calling the
/// same `acceptedTextNodesInBlock` the preview uses, then comparing the text
/// WebKit reports against `MarkdownPreviewTextOffsetMapping`.
///
/// This runs headlessly: the web view is never put in a window. It is a
/// deliberate exception to "no GUI tests" — nothing here drives an interface,
/// it interrogates a rendering engine whose behaviour we would otherwise have to
/// take on faith.
@MainActor
struct WebKitTextNodeAlignmentTests {

    /// Collects the text WebKit exposes for the document's first block, through
    /// the same walker the preview uses.
    private static let blockTextScript = """
    (() => {
      const block = document.querySelector('.md-block');
      if (!block) {
        return null;
      }
      const entries = window.markdownPreview?.acceptedTextNodesInBlock?.(block) ?? [];
      return {
        text: entries.map((entry) => entry.node.textContent).join(''),
        combinedLength: entries.reduce((length, entry) => Math.max(length, entry.end), 0)
      };
    })();
    """

    private final class LoadObserver: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var finished = false

        func wait() async throws {
            if finished { return }
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        private func complete(with result: Result<Void, Error>) {
            guard !finished else { return }
            finished = true
            continuation?.resume(with: result)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            complete(with: .success(()))
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            complete(with: .failure(error))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            complete(with: .failure(error))
        }
    }

    /// Loads `source` as the preview renders it and returns what WebKit reports
    /// for the first block: the concatenated text, and the combined length the
    /// walker computed.
    private func webKitBlockText(for source: String) async throws -> (text: String, combinedLength: Int) {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: previewSelectionChangeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let observer = LoadObserver()
        webView.navigationDelegate = observer

        webView.loadHTMLString(
            MarkdownHTMLBuilder.document(for: source, softBreak: .lineBreak),
            baseURL: nil
        )
        try await observer.wait()

        let result = try await webView.evaluateJavaScript(Self.blockTextScript)
        let payload = try #require(result as? [String: Any], "expected a block in the rendered document")
        let text = try #require(payload["text"] as? String)
        let combinedLength = try #require((payload["combinedLength"] as? NSNumber)?.intValue)
        return (text, combinedLength)
    }

    /// The model these tests exist to check: an element contributes no
    /// characters of its own, so a `<br />` adds nothing and the line break the
    /// DOM sees is the literal newline the builder emits after the tag.
    @Test(.timeLimit(.minutes(1)))
    func webKitTextNodesMatchTheSourceMappingAcrossSoftBreaks() async throws {
        let source = """
        Sincerely yours,
        Syd Polk
        Somewhere in Texas
        """

        let webKit = try await webKitBlockText(for: source)

        #expect(webKit.text == MarkdownPreviewTextOffsetMapping(sourceText: source).displayText)
        #expect(webKit.combinedLength == webKit.text.utf16.count)
    }

    /// Hard and soft breaks both emit `<br />`, so WebKit must see them the same.
    @Test(.timeLimit(.minutes(1)))
    func webKitSeesHardAndSoftBreaksIdentically() async throws {
        let soft = try await webKitBlockText(for: "First line\nSecond line")
        let hard = try await webKitBlockText(for: "First line  \nSecond line")

        #expect(soft.text == hard.text)
        #expect(soft.text == "First line\nSecond line")
    }

    /// Cells are separate elements, so nothing separates their text unless the
    /// builder emits characters between them. Whatever WebKit reports, the
    /// mapping has to agree — a table's Copy button makes this a copyable block
    /// too, so the walker's exclusion is exercised here as well.
    @Test(.timeLimit(.minutes(1)))
    func webKitTextNodesMatchTheSourceMappingForTables() async throws {
        let table = """
        | Name | Count |
        | --- | ---: |
        | apples | 12 |
        | pears | 7 |
        """

        let webKit = try await webKitBlockText(for: table)

        #expect(webKit.text == MarkdownPreviewTextOffsetMapping(sourceText: table).displayText)
        #expect(webKit.combinedLength == webKit.text.utf16.count)
        #expect(webKit.text.contains("Copy") == false)
    }

    /// List items are separate elements for the same reason. A nested item adds
    /// a level of markup between text nodes, which is where a stray character
    /// would show up if one crept in.
    @Test(.timeLimit(.minutes(1)))
    func webKitTextNodesMatchTheSourceMappingForLists() async throws {
        let list = """
        - First item
        - Second item
          - Nested item
        - Third item
        """

        let webKit = try await webKitBlockText(for: list)

        #expect(webKit.text == MarkdownPreviewTextOffsetMapping(sourceText: list).displayText)
        #expect(webKit.combinedLength == webKit.text.utf16.count)
    }

    @Test(.timeLimit(.minutes(1)))
    func webKitTextNodesMatchTheSourceMappingForOrderedListsAndTasks() async throws {
        let ordered = """
        1. Alpha step
        2. Beta step
        """
        let tasks = """
        - [x] Completed item
        - [ ] Pending item
        """

        let orderedWebKit = try await webKitBlockText(for: ordered)
        let tasksWebKit = try await webKitBlockText(for: tasks)

        #expect(orderedWebKit.text == MarkdownPreviewTextOffsetMapping(sourceText: ordered).displayText)
        #expect(tasksWebKit.text == MarkdownPreviewTextOffsetMapping(sourceText: tasks).displayText)
    }

    /// A fenced code block keeps its line breaks literally, so it is the one
    /// place where the rendered text should contain newlines from the source
    /// rather than from `<br />`.
    @Test(.timeLimit(.minutes(1)))
    func webKitTextNodesMatchTheSourceMappingForCodeBlocks() async throws {
        let code = """
        ```swift
        let value = 42
        let next = value + 1
        ```
        """

        let webKit = try await webKitBlockText(for: code)

        #expect(webKit.text == MarkdownPreviewTextOffsetMapping(sourceText: code).displayText)
        #expect(webKit.text.contains("Copy") == false)
    }

    /// The walker rejects the Copy button's label. If WebKit ever included it,
    /// every offset in a copyable block would shift by four characters.
    @Test(.timeLimit(.minutes(1)))
    func webKitExcludesTheCopyButtonLabelFromABlocksText() async throws {
        let quote = "> Quoted line one\n> Quoted line two"

        let webKit = try await webKitBlockText(for: quote)

        #expect(webKit.text.contains("Copy") == false)
        #expect(webKit.text == MarkdownPreviewTextOffsetMapping(sourceText: quote).displayText)
    }
}
