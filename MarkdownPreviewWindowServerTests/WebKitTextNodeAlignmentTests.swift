//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
import WebKit
import MarkdownCore
@testable import MarkdownPreview

/// Has `WebKitTextNodeAlignmentTests` load a page once, before its tests start
/// and outside the time any of them is allowed.
struct WebKitWarmUp: SuiteTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await WebKitTextNodeAlignmentTests.warmUpWebKit()
        try await function()
    }
}

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
///
/// The tests run one at a time. Each makes a web view and waits for its page,
/// all on the main actor, and each has a minute to do it in. Run together,
/// a hundred and more of them wait on one another, so the minute was being
/// spent in the queue: on an iPhone simulator every one took forty seconds
/// whatever it loaded, and the last to finish now and then ran out of time.
///
/// A page is loaded before the first of them starts; see `warmUpWebKit()`.
@MainActor
@Suite(.serialized, WebKitWarmUp())
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

    /// Waits for a page to load, and keeps a record of how the load went, so
    /// that one that stalls can say where.
    private final class LoadObserver: NSObject, WKNavigationDelegate {
        /// A load that did not finish, with what had happened to it by then.
        struct LoadFailure: Error, CustomStringConvertible {
            let reason: String
            let timeline: String

            var description: String { "\(reason). \(timeline)" }
        }

        private let clock = ContinuousClock()
        private let began = ContinuousClock().now
        private var steps: [String] = []
        private var result: Result<Void, Error>?
        private var continuation: CheckedContinuation<Void, Error>?

        /// What WebKit has reported about the load and when, counted from when
        /// the observer was made, which is just before the page is asked for.
        var timeline: String {
            let reported = steps.isEmpty ? "WebKit has reported nothing" : steps.joined(separator: ", ")
            return "The load: \(reported); now \(Self.seconds(clock.now - began)) after it was asked for"
        }

        private static func seconds(_ duration: Duration) -> String {
            let components = duration.components
            let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
            return String(format: "%.2f s", seconds)
        }

        private func mark(_ step: String) {
            steps.append("\(step) at \(Self.seconds(clock.now - began))")
        }

        /// Returns when the page has loaded, and throws if it fails to.
        ///
        /// A test that runs out of time is cancelled, and this stops waiting
        /// when that happens: the test then fails saying how far the load had
        /// got, where it used to sit until the page arrived, saying nothing.
        func wait() async throws {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if let result {
                        continuation.resume(with: result)
                    } else {
                        self.continuation = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor in
                    self.giveUp(
                        because: "The test was stopped before the page finished loading, as one that runs out of time is"
                    )
                }
            }

            if clock.now - began > .seconds(10) {
                print("[WebKit tests] A page was slow to load. \(timeline)")
            }
        }

        /// The same, giving up once `limit` has passed.
        func wait(upTo limit: Duration) async throws {
            let timeout = Task { @MainActor in
                guard (try? await Task.sleep(for: limit)) != nil else { return }
                self.giveUp(because: "The page had not finished loading after \(Self.seconds(limit))")
            }
            defer { timeout.cancel() }
            try await wait()
        }

        private func giveUp(because reason: String) {
            complete(with: .failure(LoadFailure(reason: reason, timeline: timeline)))
        }

        private func complete(with result: Result<Void, Error>) {
            guard self.result == nil else { return }
            self.result = result
            continuation?.resume(with: result)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            mark("started")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            mark("committed")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            mark("finished")
            complete(with: .success(()))
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            mark("failed")
            giveUp(because: "The page failed to load: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            mark("failed before it committed")
            giveUp(because: "The page failed to load: \(error.localizedDescription)")
        }

        /// WebKit reports neither a finish nor a failure for a page whose
        /// process dies under it, so without this the wait would never end.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            mark("web content process died")
            giveUp(because: "WebKit's web content process died while the page was loading")
        }
    }

    /// Loads a page before any test here has started.
    ///
    /// The first page a process asks WebKit for is the slow one: the engine has
    /// processes of its own to start. In an iPhone simulator that first load
    /// has taken more than the minute a test is allowed, when every load after
    /// it took about a second. Made here, it is charged to no test. A load that
    /// stalls is tried again in a new web view; if none finishes, the tests go
    /// ahead and say for themselves what happened.
    static func warmUpWebKit() async {
        var attempts: [String] = []
        defer { warmUpReport = attempts.joined(separator: " ") }

        for attempt in 1...5 {
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
            let observer = LoadObserver()
            webView.navigationDelegate = observer
            webView.loadHTMLString("<p>Warming up.</p>", baseURL: nil)

            do {
                try await observer.wait(upTo: .seconds(90))
                attempts.append("Warm-up load \(attempt) finished. \(observer.timeline).")
                print("[WebKit tests] \(attempts.last ?? "")")
                return
            } catch {
                attempts.append("Warm-up load \(attempt) did not finish. \(error).")
                print("[WebKit tests] \(attempts.last ?? "")")
            }
        }
    }

    /// How the warm-up went, one sentence per try, or nil if it has not run.
    private(set) static var warmUpReport: String?

    // MARK: - The harness itself

    /// Answers nothing, so a page asked of it never arrives.
    private final class SilentSchemeHandler: NSObject, WKURLSchemeHandler {
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {}
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
    }

    /// A web view that has been asked for a page it will never be given.
    private func webViewWaitingForAPageThatNeverArrives() throws -> (WKWebView, LoadObserver) {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(SilentSchemeHandler(), forURLScheme: "never")
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let observer = LoadObserver()
        webView.navigationDelegate = observer
        webView.load(URLRequest(url: try #require(URL(string: "never://page"))))
        return (webView, observer)
    }

    // The warm-up is what keeps WebKit's slow first load out of a test's
    // minute, so it has to have run, and to have got a page, before any test
    // here starts. If it did not, this says how each try went.
    @Test(.timeLimit(.minutes(1)))
    func aPageWasLoadedBeforeTheseTestsStarted() {
        let report = Self.warmUpReport ?? "The warm-up did not run."

        #expect(report.contains("finished at"), "\(report)")
    }

    // What a stalled load reports is only ever seen when something has gone
    // wrong, so it is checked here, where the stall is arranged.
    @Test(.timeLimit(.minutes(1)))
    func aLoadThatStallsIsGivenUpOnAndSaysHowFarItGot() async throws {
        let (webView, observer) = try webViewWaitingForAPageThatNeverArrives()

        let failure = await #expect(throws: LoadObserver.LoadFailure.self) {
            try await observer.wait(upTo: .seconds(2))
        }

        let report = try #require(failure).description
        #expect(report.contains("had not finished loading after 2.00 s"), "\(report)")
        #expect(report.contains("started at"), "\(report)")
        #expect(!report.contains("finished at"), "\(report)")
        webView.stopLoading()
    }

    // A test that runs out of time is cancelled. The wait has to end then, or
    // the test goes on sitting there and the tests after it wait for it.
    @Test(.timeLimit(.minutes(1)))
    func aTestThatIsStoppedStopsWaitingForItsPage() async throws {
        let (webView, observer) = try webViewWaitingForAPageThatNeverArrives()

        let waiting = Task { @MainActor in
            try await observer.wait()
        }
        waiting.cancel()
        let outcome = await waiting.result

        guard case .failure(let error) = outcome else {
            Issue.record("the wait ended as if the page had loaded")
            return
        }
        let report = try #require(error as? LoadObserver.LoadFailure).description
        #expect(report.contains("The test was stopped before the page finished loading"), "\(report)")
        webView.stopLoading()
    }

    @Test(.timeLimit(.minutes(1)))
    func aPageThatLoadsSaysWhenEachStepOfItHappened() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let observer = LoadObserver()
        webView.navigationDelegate = observer
        webView.loadHTMLString("<p>Here.</p>", baseURL: nil)

        try await observer.wait()

        let timeline = observer.timeline
        #expect(timeline.contains("started at"), "\(timeline)")
        #expect(timeline.contains("committed at"), "\(timeline)")
        #expect(timeline.contains("finished at"), "\(timeline)")
    }

    /// Loads `source` as the preview renders it and returns what WebKit reports
    /// for the first block: the concatenated text, and the combined length the
    /// walker computed.
    private func webKitBlockText(for source: String) async throws -> (text: String, combinedLength: Int) {
        try await webKitBlockText(forHTML: MarkdownHTMLBuilder.document(for: source, softBreak: .lineBreak))
    }

    /// The same, for markup that has been through a later stage than the builder.
    private func webKitBlockText(forHTML html: String) async throws -> (text: String, combinedLength: Int) {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MarkdownWebResources.script(.selection),
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

        webView.loadHTMLString(html, baseURL: nil)
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

    // MARK: - Every markdown feature

    /// The preview's page for `source`, with the scripts that read and set the
    /// selection running in it.
    private func loadedPreview(for source: String) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        for script in [MarkdownWebResources.Script.selection, .applySelection] {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: MarkdownWebResources.script(script),
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let observer = LoadObserver()
        webView.navigationDelegate = observer
        webView.loadHTMLString(MarkdownHTMLBuilder.document(for: source, softBreak: .lineBreak), baseURL: nil)
        try await observer.wait()
        return webView
    }

    /// The other half of `MarkdownFeatureOffsetMappingTests`, which checks the
    /// source mapping against the same hand-written text: here it is WebKit,
    /// through the preview's own walker, that has to agree with it.
    @Test(.timeLimit(.minutes(1)), arguments: MarkdownFeature.all)
    func webKitShowsTheExpectedTextForEachFeature(feature: MarkdownFeature) async throws {
        let webKit = try await webKitBlockText(for: feature.source)

        #expect(webKit.text == feature.visible)
        #expect(webKit.combinedLength == webKit.text.utf16.count)
    }

    /// The whole trip, both ways, with nothing stood in for: a range in the
    /// source is reflected into the page by the call the app makes, WebKit is
    /// asked what it then has selected, and what the page reports back is
    /// turned into a source range again.
    @Test(.timeLimit(.minutes(1)), arguments: MarkdownFeature.all.filter { !$0.words.isEmpty })
    func aSourceSelectionReachesThePageAndComesBackForEachFeature(feature: MarkdownFeature) async throws {
        let webView = try await loadedPreview(for: feature.source)

        for word in feature.words {
            let inSource = try #require(feature.sourceRange(of: word), "\(word) is not in the source")
            guard PreviewSelectionReflection.reflectedSelection(
                in: feature.source,
                selectedRange: inSource
            ) != nil else {
                Issue.record("the source selection of \(word) reflects to nothing")
                continue
            }

            let invocation = MarkdownPreviewWebView.selectionInvocation(
                source: feature.source,
                selectedRange: inSource
            )
            let result = try await webView.evaluateJavaScript("""
                (() => {
                  const applied = \(invocation);
                  return {
                    applied: applied === true,
                    text: window.getSelection()?.toString() ?? '',
                    ranges: \(PreviewScriptCall.selectedDisplayRanges)
                  };
                })();
                """)
            let payload = try #require(result as? [String: Any])

            #expect(payload["applied"] as? Bool == true, "the page made no selection for \(word)")
            #expect(payload["text"] as? String == word, "what the page selected, for \(word)")

            let reported = PreviewSelectionBridge.sourceRanges(
                fromDisplayRangeResult: payload["ranges"],
                source: feature.source
            )
            #expect(
                PreviewSelectionBridge.enclosingRange(of: reported) == inSource,
                "what came back to the source, for \(word)"
            )
        }
    }

    // MARK: - The call that reflects a selection

    /// Each end of the selection goes to the page as its block's place in the
    /// source and an offset into that block's rendered text: the start's three
    /// numbers, then the end's.
    @Test func aSelectionAcrossTwoBlocksIsSentAsItsStartAndThenItsEnd() {
        let source = "# Heading\n\nA paragraph with text."
        // "Heading", the blank line, and "A paragraph".
        let selected = MarkdownSelectionRange(location: 2, length: 20)

        #expect(
            MarkdownPreviewWebView.selectionInvocation(source: source, selectedRange: selected)
                == PreviewScriptCall.applySelection("0, 9, 0, 11, 33, 11")
        )
    }

    @Test func noSelectionIsSentAsACallThatClearsThePagesSelection() {
        #expect(
            MarkdownPreviewWebView.selectionInvocation(source: "Alpha beta", selectedRange: nil)
                == PreviewScriptCall.applySelection("null, null, null, null, null, null")
        )
    }

    /// A selection with no place in the page is not left showing as whatever
    /// was selected before it.
    @Test func aSelectionThatIsNotInTheSourceClearsThePagesSelection() {
        let source = "Alpha beta"
        let clear = PreviewScriptCall.applySelection("null, null, null, null, null, null")

        #expect(
            MarkdownPreviewWebView.selectionInvocation(
                source: source,
                selectedRange: MarkdownSelectionRange(location: 50, length: 5)
            ) == clear
        )
        #expect(
            MarkdownPreviewWebView.selectionInvocation(
                source: source,
                selectedRange: MarkdownSelectionRange(location: 4, length: 0)
            ) == clear
        )
    }

    // MARK: - Script links

    /// A `javascript:` link runs in the page when it is clicked, and WebKit
    /// does not ask the app first. The renderer writes such a link without its
    /// `href`, which the engine's own tests check as text; this asks WebKit
    /// whether anything the renderer wrote is still script to it, and clicks
    /// every link to see.
    @Test(.timeLimit(.minutes(1)))
    func clickingAScriptLinkRunsNothing() async throws {
        let source = [
            "[inline](javascript:void(document.title='ran'))",
            "<javascript:void(document.title='ran')>",
            "[mixed case](JaVaScRiPt:void(document.title='ran'))",
            "[a tab inside](<java\tscript:void(document.title='ran')>)",
            "[spaces before](<  javascript:void(document.title='ran')>)",
            "[an ordinary link](https://example.com)",
        ].joined(separator: "\n\n")
        let webView = try await loadedPreview(for: source)

        let counted = try await webView.evaluateJavaScript("""
            (() => {
              document.title = 'untouched';
              const links = Array.from(document.querySelectorAll('a'));
              return {
                links: links.length,
                scriptLinks: links.filter((link) => link.protocol === 'javascript:').length
              };
            })();
            """)
        let counts = try #require(counted as? [String: Any])
        #expect((counts["links"] as? NSNumber)?.intValue == 6)
        #expect((counts["scriptLinks"] as? NSNumber)?.intValue == 0)

        // All but the ordinary link, which would only ask to leave the page.
        _ = try await webView.evaluateJavaScript("""
            Array.from(document.querySelectorAll('a')).slice(0, 5).forEach((link) => link.click()); true
            """)
        // A script link runs a moment after the click, not during it.
        try await Task.sleep(for: .milliseconds(300))

        #expect(try await webView.evaluateJavaScript("document.title") as? String == "untouched")
    }

    // MARK: - The button that stands in for an unreadable image

    /// A folder the test cannot list, standing in for one the sandbox refuses.
    private func makeUnlistableDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageAccessButton-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        return directory
    }

    private func remove(_ directory: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    /// The document as the preview renders it when `photo.jpg` cannot be read.
    private func htmlWithAnAccessButton(for source: String, in directory: URL) -> String {
        MarkdownImageURL.replacingUnreadableImages(
            in: MarkdownHTMLBuilder.document(for: source, softBreak: .lineBreak),
            relativeTo: directory,
            label: "Allow…",
            explanation: "Images in this document need permission to load."
        )
    }

    /// An image contributes no text, and the button that replaces it must not
    /// either: its label is drawn by the stylesheet. If WebKit counted the
    /// label, every selection and search offset after an unreadable image would
    /// be out by its length.
    @Test(.timeLimit(.minutes(1)))
    func webKitSeesNoTextInTheButtonThatReplacesAnUnreadableImage() async throws {
        let directory = try makeUnlistableDirectory()
        defer { remove(directory) }
        let source = "before ![A photograph](photo.jpg) after"

        let html = htmlWithAnAccessButton(for: source, in: directory)
        try #require(html.contains(MarkdownImageURL.accessButtonAttribute))

        let withImage = try await webKitBlockText(for: source)
        let withButton = try await webKitBlockText(forHTML: html)

        #expect(withButton.text == withImage.text)
        #expect(withButton.text.contains("Allow") == false)
        #expect(withButton.text == MarkdownPreviewTextOffsetMapping(sourceText: source).displayText)
    }

    private final class MessageRecorder: NSObject, WKScriptMessageHandler {
        private var continuation: CheckedContinuation<Void, Never>?
        private var received = false

        func wait() async {
            if received { return }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            received = true
            continuation?.resume()
            continuation = nil
        }
    }

    /// Pressing the button has to reach the app, or it is a broken image with
    /// rounded corners. The time limit is the assertion: with no message the
    /// wait never returns.
    @Test(.timeLimit(.minutes(1)))
    func pressingTheImageAccessButtonAsksTheApp() async throws {
        let directory = try makeUnlistableDirectory()
        defer { remove(directory) }
        let html = htmlWithAnAccessButton(for: "![A photograph](photo.jpg)", in: directory)

        let recorder = MessageRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MarkdownWebResources.script(.imageAccessButton),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(recorder, name: requestImageAccessMessageHandlerName)

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        let observer = LoadObserver()
        webView.navigationDelegate = observer
        webView.loadHTMLString(html, baseURL: nil)
        try await observer.wait()

        let pressed = try await webView.evaluateJavaScript("""
            (() => {
              const button = document.querySelector('[data-image-access-button]');
              if (!button) {
                return false;
              }
              button.click();
              return true;
            })();
            """)
        try #require(pressed as? Bool == true, "expected the button in the rendered document")

        await recorder.wait()
    }

    // MARK: - Keeping the reader's place across a reload

    /// A page long enough to scroll, with a line in the middle that an edit can
    /// change without moving anything above it.
    private func longDocument(middle: String = "The line in the middle.") -> String {
        let before = (1...60).map { "Paragraph \($0) of the first half." }
        let after = (1...60).map { "Paragraph \($0) of the second half." }
        return (before + [middle] + after).joined(separator: "\n\n")
    }

    private func makeWebView() -> (WKWebView, LoadObserver) {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MarkdownWebResources.script(.scroll),
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
        return (webView, observer)
    }

    private func scrollPosition(in webView: WKWebView) async throws -> PreviewScrollPosition {
        let reported = try await webView.evaluateJavaScript(PreviewScriptCall.scrollPosition)
        return try #require(PreviewScrollPosition(messageBody: reported as Any))
    }

    /// The scroll position once `hasSettled` says it is where it was going, or
    /// after ten seconds whatever it is by then.
    ///
    /// A page finishes loading before it has necessarily been laid out to its
    /// full height, so a scroll asked for at that moment can fall short. The
    /// page's own restore allows for that by trying again as the page grows,
    /// which means the answer is not always there on the first look. Nor on
    /// the tenth: these web views are in no window, and a page that is not on
    /// screen has its timers held back, so its tries come far apart.
    private func scrollPosition(
        in webView: WKWebView,
        once hasSettled: (PreviewScrollPosition) -> Bool
    ) async throws -> PreviewScrollPosition {
        var position = try await scrollPosition(in: webView)
        for _ in 0..<200 where !hasSettled(position) {
            try await Task.sleep(for: .milliseconds(50))
            position = try await scrollPosition(in: webView)
        }
        return position
    }

    /// What the page's last restore did, for a failure to say: how many tries
    /// it had, how many scrolls it asked for, the last place it asked for, how
    /// far the page could scroll then, and how it ended.
    private func restoreReport(in webView: WKWebView) async -> String {
        let state = try? await webView.evaluateJavaScript(
            "JSON.stringify(window.markdownPreview.restoreState())"
        )
        return "the restore: \((state as? String) ?? "not reported")"
    }

    /// The decision is tested on its own; this checks that the scripts it
    /// produces do what they say in the engine that has to run them.
    @Test(.timeLimit(.minutes(1)))
    func anEditedDocumentIsPutBackAtTheSameOffset() async throws {
        let before = longDocument()
        let after = longDocument(middle: "The line in the middle, rewritten.")

        let (webView, observer) = makeWebView()
        webView.loadHTMLString(MarkdownHTMLBuilder.document(for: before, softBreak: .lineBreak), baseURL: nil)
        try await observer.wait()
        _ = try await webView.evaluateJavaScript(PreviewScriptCall.scrollToOffset(x: 0, y: 900) + " true")
        let position = try await scrollPosition(in: webView) { $0.y == 900 }
        try #require(
            position.y == 900,
            "the page should be long enough to scroll; it got to \(position.y) of a possible \(position.maxY)"
        )

        let restoration = PreviewScrollRestoration.restoration(
            of: position,
            from: .init(documentID: "/tmp/plan.md", source: before),
            to: .init(documentID: "/tmp/plan.md", source: after)
        )

        let (reloaded, reloadObserver) = makeWebView()
        reloaded.loadHTMLString(MarkdownHTMLBuilder.document(for: after, softBreak: .lineBreak), baseURL: nil)
        try await reloadObserver.wait()
        #expect(try await scrollPosition(in: reloaded).y == 0)

        _ = try await reloaded.evaluateJavaScript(try #require(restoration.script) + " true")

        // A failure says where the page ended up and how far it could have
        // scrolled, which tells a page that never grew tall enough from a
        // restore that went to the wrong place.
        let restored = try await scrollPosition(in: reloaded) { $0.y == 900 }
        let report = await restoreReport(in: reloaded)
        #expect(restored.y == 900, "restored to \(restored.y), of a possible \(restored.maxY); \(report)")
    }

    /// Makes the page taller after the fact, the way a page still being laid
    /// out, or one whose images are still arriving, grows under a restore.
    private static let growThePage = """
        (() => {
          const filler = document.createElement('div');
          filler.style.height = '5000px';
          document.body.appendChild(filler);
          return true;
        })();
        """

    /// The race this exists for: the app asks for the reader's place back the
    /// moment the page finishes loading, and the page may not be tall enough
    /// yet. Here it is certainly not, until the test makes it so.
    @Test(.timeLimit(.minutes(1)))
    func aRestoreMadeBeforeThePageIsTallEnoughLandsOnceItIs() async throws {
        let (webView, observer) = makeWebView()
        webView.loadHTMLString(MarkdownHTMLBuilder.document(for: "A short page.", softBreak: .lineBreak), baseURL: nil)
        try await observer.wait()

        let clock = ContinuousClock()
        let asked = clock.now
        _ = try await webView.evaluateJavaScript(PreviewScriptCall.scrollToOffset(x: 0, y: 900) + " true")
        let tooSoon = try await scrollPosition(in: webView)
        try #require(tooSoon.y == 0 && tooSoon.maxY < 900, "the page should start too short to scroll that far")

        _ = try await webView.evaluateJavaScript(Self.growThePage)
        let grew = clock.now

        let restored = try await scrollPosition(in: webView) { $0.y == 900 }
        let report = await restoreReport(in: webView)
        #expect(
            restored.y == 900,
            """
            restored to \(restored.y), of a possible \(restored.maxY); the page grew \(grew - asked) after the \
            restore was asked for, and was last looked at \(clock.now - grew) after that; \(report)
            """
        )
    }

    /// Once the reader has moved the page themselves, a restore still waiting
    /// for the page to grow must not snatch it back.
    @Test(.timeLimit(.minutes(1)))
    func aRestoreDoesNotOverrideTheReader() async throws {
        let (webView, observer) = makeWebView()
        webView.loadHTMLString(MarkdownHTMLBuilder.document(for: "A short page.", softBreak: .lineBreak), baseURL: nil)
        try await observer.wait()

        _ = try await webView.evaluateJavaScript(PreviewScriptCall.scrollToOffset(x: 0, y: 900) + " true")
        _ = try await webView.evaluateJavaScript("window.dispatchEvent(new Event('wheel')); true")
        _ = try await webView.evaluateJavaScript(Self.growThePage)
        try await Task.sleep(for: .milliseconds(400))

        let position = try await scrollPosition(in: webView)
        let report = await restoreReport(in: webView)
        try #require(position.maxY >= 900, "the page should have grown")
        #expect(position.y == 0, "\(report)")
    }

    @Test(.timeLimit(.minutes(1)))
    func theSameDocumentAtALargerTextSizeIsPutBackTheSameWayDown() async throws {
        let source = longDocument()

        let (webView, observer) = makeWebView()
        webView.loadHTMLString(
            MarkdownHTMLBuilder.document(for: source, contentScale: 1.0, softBreak: .lineBreak),
            baseURL: nil
        )
        try await observer.wait()
        _ = try await webView.evaluateJavaScript(PreviewScriptCall.scrollToFraction(x: 0, ofMaxY: 0.5) + " true")
        let position = try await scrollPosition(in: webView) { $0.maxY > 0 && abs($0.y / $0.maxY - 0.5) < 0.01 }
        try #require(position.maxY > 0, "the page should be long enough to scroll")

        let restoration = PreviewScrollRestoration.restoration(
            of: position,
            from: .init(documentID: "/tmp/plan.md", source: source),
            to: .init(documentID: "/tmp/plan.md", source: source)
        )

        let (reloaded, reloadObserver) = makeWebView()
        reloaded.loadHTMLString(
            MarkdownHTMLBuilder.document(for: source, contentScale: 1.5, softBreak: .lineBreak),
            baseURL: nil
        )
        try await reloadObserver.wait()
        _ = try await reloaded.evaluateJavaScript(try #require(restoration.script) + " true")

        let restored = try await scrollPosition(in: reloaded) {
            $0.maxY > position.maxY && abs($0.y / $0.maxY - 0.5) < 0.01
        }
        let report = await restoreReport(in: reloaded)
        try #require(restored.maxY > position.maxY, "larger text should make a taller page")
        #expect(
            abs(restored.y / restored.maxY - 0.5) < 0.01,
            "restored to \(restored.y), of a possible \(restored.maxY); \(report)"
        )
    }
}
