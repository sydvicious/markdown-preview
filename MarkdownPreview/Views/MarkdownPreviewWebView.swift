//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import SwiftUI
import WebKit
import os
import MarkdownCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let copyBlockMessageHandlerName = "copyBlock"
private let previewSelectionChangedMessageHandlerName = "previewSelectionChanged"
private let previewScrollChangedMessageHandlerName = "previewScrollChanged"
private let previewSourceOffsetChangedMessageHandlerName = "previewSourceOffsetChanged"
/// The page's content has been read; see `content-read.js`.
private let previewContentReadMessageHandlerName = "previewContentRead"
/// Internal so the tests can check the image-access button really reaches the
/// app.
let requestImageAccessMessageHandlerName = "requestImageAccess"

#if os(iOS)
struct MarkdownPreviewWebView: UIViewRepresentable {
    /// The document as it was read to build `html`: its source, and what is
    /// needed to place a selection in it without reading it again.
    let reading: MarkdownReading
    let html: String
    let baseURL: URL?
    /// Which document this is, so a reload of the same one can keep the reader's
    /// place. Without it every reload starts at the top.
    var documentID: String? = nil
    let selectedRange: MarkdownSelectionRange?
    var selectionSynchronizer: PreviewSelectionSynchronizer?
    var onSelectedTextChange: (String?) -> Void = { _ in }
    var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }
    var onSearchSelection: (String) -> Void = { _ in }
    /// The reader pressed the button that stands in for an unreadable image.
    var onRequestImageAccess: () -> Void = {}
    /// Where the reader was in each document, kept by the session so that it
    /// outlasts this view. Without one the view keeps its own.
    var scrollMemory: PreviewScrollMemory? = nil
    /// Whether the reader can see the page. It is kept, loaded, behind Source,
    /// so that coming back to it loads nothing; while it is there it is left
    /// alone, and what it says is not listened to.
    var isShowing: Bool = true

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastSelectedRange: MarkdownSelectionRange?
        var lastPreviewSelectedText: String?
        var lastPreviewSelectionRanges: [MarkdownSelectionRange] = []
        var previewOriginatedSelectedRange: MarkdownSelectionRange?
        weak var selectionSynchronizer: PreviewSelectionSynchronizer?
        fileprivate weak var webView: MarkdownCopyWebView?
        var onSelectedTextChange: (String?) -> Void = { _ in }
        var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }
        var onSearchSelection: (String) -> Void = { _ in }
        var onRequestImageAccess: () -> Void = {}
        /// What the page now loading, or last loaded, is showing.
        var loadedContent: PreviewScrollRestoration.Content?
        /// Where the reader was in each document this view has shown, as its
        /// pages reported it. The session's, when the view is given one.
        var scrollMemory = PreviewScrollMemory()
        /// Where to put the reader when the page now loading has finished.
        var scrollRestoration: PreviewScrollRestoration.Restoration = .top
        /// The page now loading has not been given its selection and the
        /// reader's place yet.
        var isLoadingPage = false
        /// The page in the web view is the one now loading, and not still
        /// the one before it. What a page says is listened to from then.
        var hasPageBegunToArrive = false
        /// Whether the reader can see the page, or it is waiting behind Source.
        var isShowing = true
        /// What the page now loading, or last loaded, was loaded against.
        var loadedBaseURL: URL?
        /// The load of the page this view was asked to show. A web view taken
        /// from the spare may still be finishing the empty page it was started
        /// with, and that finishing is not this page having loaded.
        var pageNavigation: WKNavigation?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        /// The system has taken the page's process away, as it may with one
        /// kept out of sight. The page is loaded again.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            reloadAfterLosingThePage(in: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard navigation === pageNavigation else { return }
            hasPageBegunToArrive = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === pageNavigation else { return }
            SparePreviewWebView.warmAfterAPageHasLoaded()
            // Done already, as a rule, when the page said its content had
            // been read. This is for a page that never said so.
            placeReaderInPage(webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        // A web view takes most of a second to start, which is far longer
        // than a page takes to load, so one is kept ready and taken here.
        let webView = SparePreviewWebView.take()
        let userContent = webView.configuration.userContentController
        userContent.add(context.coordinator, name: copyBlockMessageHandlerName)
        userContent.add(context.coordinator, name: previewSelectionChangedMessageHandlerName)
        userContent.add(context.coordinator, name: requestImageAccessMessageHandlerName)
        userContent.add(context.coordinator, name: previewScrollChangedMessageHandlerName)
        userContent.add(context.coordinator, name: previewSourceOffsetChangedMessageHandlerName)
        userContent.add(context.coordinator, name: previewContentReadMessageHandlerName)
        webView.navigationDelegate = context.coordinator
        webView.markdownReading = reading
        context.coordinator.webView = webView
        context.coordinator.isShowing = isShowing
        if let scrollMemory {
            context.coordinator.scrollMemory = scrollMemory
        }
        context.coordinator.lastSelectedRange = selectedRange
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.onRequestImageAccess = onRequestImageAccess
        context.coordinator.updateFlushSelectionHandler()
        webView.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
        }
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.load(
            html,
            baseURL: baseURL,
            showing: .init(documentID: documentID, source: reading.source),
            in: webView
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        (webView as? MarkdownCopyWebView)?.markdownReading = reading
        context.coordinator.webView = webView as? MarkdownCopyWebView
        if let scrollMemory {
            context.coordinator.scrollMemory = scrollMemory
        }
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.onRequestImageAccess = onRequestImageAccess
        context.coordinator.updateFlushSelectionHandler()
        (webView as? MarkdownCopyWebView)?.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
        }
        // Out of sight behind Source. A page already on its way is loaded,
        // and nothing else is done to one nobody can see: no selection put
        // into it, which would scroll it, and no keyboard taken for it.
        let wasShowing = context.coordinator.isShowing
        context.coordinator.isShowing = isShowing
        guard isShowing else {
            if context.coordinator.lastHTML != html {
                context.coordinator.load(
                    html,
                    baseURL: baseURL,
                    showing: .init(documentID: documentID, source: reading.source),
                    in: webView
                )
            }
            return
        }

        let didReceivePreviewOriginatedSelection = PreviewSelectionBridge.isEcho(
            ofPreviewOriginated: context.coordinator.previewOriginatedSelectedRange,
            incoming: selectedRange
        )
        if didReceivePreviewOriginatedSelection {
            context.coordinator.previewOriginatedSelectedRange = nil
        }
        let shouldApplySelection = context.coordinator.lastSelectedRange != selectedRange
        context.coordinator.lastSelectedRange = selectedRange
        if context.coordinator.lastHTML != html {
            context.coordinator.load(
                html,
                baseURL: baseURL,
                showing: .init(documentID: documentID, source: reading.source),
                in: webView
            )
        } else if !wasShowing {
            // iOS draws a selection in a web view that has had the keyboard
            // only while it has it. One the reader touched to select in took
            // the keyboard then, and gave it up when it went out of sight;
            // a selection put back into it now is there and is not drawn. So
            // it takes the keyboard back for the selection it is to show.
            if selectedRange != nil {
                webView.becomeFirstResponder()
            }
            context.coordinator.comeBackIntoView(selecting: selectedRange)
        } else if shouldApplySelection && !didReceivePreviewOriginatedSelection {
            (webView as? MarkdownCopyWebView)?.applySelection(selectedRange)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.selectionSynchronizer?.setFlushSelectionHandler(nil)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: copyBlockMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: previewSelectionChangedMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: requestImageAccessMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: previewScrollChangedMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: previewSourceOffsetChangedMessageHandlerName
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: previewContentReadMessageHandlerName
        )
    }
}
#elseif os(macOS)
struct MarkdownPreviewWebView: NSViewRepresentable {
    /// The document as it was read to build `html`: its source, and what is
    /// needed to place a selection in it without reading it again.
    let reading: MarkdownReading
    let html: String
    let baseURL: URL?
    /// Which document this is, so a reload of the same one can keep the reader's
    /// place. Without it every reload starts at the top.
    var documentID: String? = nil
    let selectedRange: MarkdownSelectionRange?
    var selectionSynchronizer: PreviewSelectionSynchronizer?
    var onSelectedTextChange: (String?) -> Void = { _ in }
    var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }
    var onSearchSelection: (String) -> Void = { _ in }
    /// The reader pressed the button that stands in for an unreadable image.
    var onRequestImageAccess: () -> Void = {}
    /// Where the reader was in each document, kept by the session so that it
    /// outlasts this view. Without one the view keeps its own.
    var scrollMemory: PreviewScrollMemory? = nil
    /// Whether the reader can see the page. It is kept, loaded, behind Source,
    /// so that coming back to it loads nothing; while it is there it is left
    /// alone, and what it says is not listened to.
    var isShowing: Bool = true

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastSelectedRange: MarkdownSelectionRange?
        var lastPreviewSelectedText: String?
        var lastPreviewSelectionRanges: [MarkdownSelectionRange] = []
        var previewOriginatedSelectedRange: MarkdownSelectionRange?
        weak var selectionSynchronizer: PreviewSelectionSynchronizer?
        fileprivate weak var webView: MarkdownCopyWebView?
        var onSelectedTextChange: (String?) -> Void = { _ in }
        var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }
        var onSearchSelection: (String) -> Void = { _ in }
        var onRequestImageAccess: () -> Void = {}
        /// What the page now loading, or last loaded, is showing.
        var loadedContent: PreviewScrollRestoration.Content?
        /// Where the reader was in each document this view has shown, as its
        /// pages reported it. The session's, when the view is given one.
        var scrollMemory = PreviewScrollMemory()
        /// Where to put the reader when the page now loading has finished.
        var scrollRestoration: PreviewScrollRestoration.Restoration = .top
        /// The page now loading has not been given its selection and the
        /// reader's place yet.
        var isLoadingPage = false
        /// The page in the web view is the one now loading, and not still
        /// the one before it. What a page says is listened to from then.
        var hasPageBegunToArrive = false
        /// Whether the reader can see the page, or it is waiting behind Source.
        var isShowing = true
        /// What the page now loading, or last loaded, was loaded against.
        var loadedBaseURL: URL?
        /// The load of the page this view was asked to show. A web view taken
        /// from the spare may still be finishing the empty page it was started
        /// with, and that finishing is not this page having loaded.
        var pageNavigation: WKNavigation?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        /// The system has taken the page's process away, as it may with one
        /// kept out of sight. The page is loaded again.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            reloadAfterLosingThePage(in: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard navigation === pageNavigation else { return }
            hasPageBegunToArrive = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === pageNavigation else { return }
            SparePreviewWebView.warmAfterAPageHasLoaded()
            // Done already, as a rule, when the page said its content had
            // been read. This is for a page that never said so.
            placeReaderInPage(webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        // A web view takes most of a second to start, which is far longer
        // than a page takes to load, so one is kept ready and taken here.
        let webView = SparePreviewWebView.take()
        let userContent = webView.configuration.userContentController
        userContent.add(context.coordinator, name: copyBlockMessageHandlerName)
        userContent.add(context.coordinator, name: previewSelectionChangedMessageHandlerName)
        userContent.add(context.coordinator, name: requestImageAccessMessageHandlerName)
        userContent.add(context.coordinator, name: previewScrollChangedMessageHandlerName)
        userContent.add(context.coordinator, name: previewSourceOffsetChangedMessageHandlerName)
        userContent.add(context.coordinator, name: previewContentReadMessageHandlerName)
        webView.navigationDelegate = context.coordinator
        webView.markdownReading = reading
        context.coordinator.webView = webView
        context.coordinator.isShowing = isShowing
        if let scrollMemory {
            context.coordinator.scrollMemory = scrollMemory
        }
        context.coordinator.lastSelectedRange = selectedRange
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.onRequestImageAccess = onRequestImageAccess
        context.coordinator.updateFlushSelectionHandler()
        webView.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
        }
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(
            html,
            baseURL: baseURL,
            showing: .init(documentID: documentID, source: reading.source),
            in: webView
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        (webView as? MarkdownCopyWebView)?.markdownReading = reading
        context.coordinator.webView = webView as? MarkdownCopyWebView
        if let scrollMemory {
            context.coordinator.scrollMemory = scrollMemory
        }
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.onRequestImageAccess = onRequestImageAccess
        context.coordinator.updateFlushSelectionHandler()
        (webView as? MarkdownCopyWebView)?.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
        }
        // Out of sight behind Source. A page already on its way is loaded,
        // and nothing else is done to one nobody can see: no selection put
        // into it, which would scroll it, and no keyboard taken for it.
        let wasShowing = context.coordinator.isShowing
        context.coordinator.isShowing = isShowing
        guard isShowing else {
            if context.coordinator.lastHTML != html {
                context.coordinator.load(
                    html,
                    baseURL: baseURL,
                    showing: .init(documentID: documentID, source: reading.source),
                    in: webView
                )
            }
            return
        }

        let didReceivePreviewOriginatedSelection = PreviewSelectionBridge.isEcho(
            ofPreviewOriginated: context.coordinator.previewOriginatedSelectedRange,
            incoming: selectedRange
        )
        if didReceivePreviewOriginatedSelection {
            context.coordinator.previewOriginatedSelectedRange = nil
        }
        let shouldApplySelection = context.coordinator.lastSelectedRange != selectedRange
        context.coordinator.lastSelectedRange = selectedRange
        if context.coordinator.lastHTML != html {
            context.coordinator.load(
                html,
                baseURL: baseURL,
                showing: .init(documentID: documentID, source: reading.source),
                in: webView
            )
        } else if !wasShowing {
            context.coordinator.comeBackIntoView(selecting: selectedRange)
            (webView as? MarkdownCopyWebView)?.takeFirstResponderIfUnclaimed()
        } else if shouldApplySelection && !didReceivePreviewOriginatedSelection {
            (webView as? MarkdownCopyWebView)?.applySelection(selectedRange)
            if selectedRange != nil {
                (webView as? MarkdownCopyWebView)?.takeFirstResponderIfUnclaimed()
            }
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.selectionSynchronizer?.setFlushSelectionHandler(nil)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: copyBlockMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: previewSelectionChangedMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: requestImageAccessMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: previewScrollChangedMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: previewSourceOffsetChangedMessageHandlerName
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: previewContentReadMessageHandlerName
        )
    }
}
#endif

#if os(iOS)
private final class MarkdownCopyWebView: WKWebView {
    /// The document on the page, as it was read to build the page.
    var markdownReading = MarkdownReading(of: "")
    var markdownSource: String { markdownReading.source }
    /// Latest non-empty selected text, tracked from selection-change messages so
    /// the edit menu can offer "Search" without a synchronous JS round-trip.
    var currentSelectionText: String?
    var searchSelectionHandler: ((String) -> Void)?

    override func copy(_ sender: Any?) {
        copySelectionToPasteboard {
            self.performNativeCopy(sender)
        }
    }

    private func performNativeCopy(_ sender: Any?) {
        super.copy(sender)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard let selectionText = currentSelectionText, !selectionText.isEmpty else { return }
        let handler = searchSelectionHandler
        let searchAction = UIAction(
            title: "Search",
            image: UIImage(systemName: "magnifyingglass")
        ) { _ in
            handler?(selectionText)
        }
        builder.insertChild(
            UIMenu(title: "", options: .displayInline, children: [searchAction]),
            atEndOfMenu: .standardEdit
        )
    }
}
#elseif os(macOS)
private final class MarkdownCopyWebView: WKWebView {
    /// The document on the page, as it was read to build the page.
    var markdownReading = MarkdownReading(of: "")
    var markdownSource: String { markdownReading.source }
    /// Latest non-empty selected text, tracked from selection-change messages so
    /// the context menu can offer "Search" without a synchronous JS round-trip.
    var currentSelectionText: String?
    var searchSelectionHandler: ((String) -> Void)?

    /// Puts the keyboard in the document when nothing has a better claim on it.
    ///
    /// The mirror of the same method on the source view, and needed for the same
    /// two reasons: an unfocused web view draws no selection, so a selection
    /// carried over from the source view would be invisible, and Edit ▸ Copy
    /// would have no target.
    ///
    /// A focused text field owns the window's field editor, itself an
    /// `NSTextView`, so seeing one means the user is deliberately typing in a
    /// search field and focus is left alone.
    func takeFirstResponderIfUnclaimed() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            guard !(window.firstResponder is NSTextView) else { return }
            window.makeFirstResponder(self)
        }
    }

    @objc func copy(_ sender: Any?) {
        Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "PrevCopy").info(
            "PREVCOPY copy(_:) reached the web view"
        )
        copySelectionToPasteboard {}
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let selectionText = currentSelectionText, !selectionText.isEmpty else { return }
        let item = NSMenuItem(
            title: "Search",
            action: #selector(searchSelectionMenuAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(.separator())
        menu.addItem(item)
    }

    @objc private func searchSelectionMenuAction(_ sender: Any?) {
        guard let selectionText = currentSelectionText, !selectionText.isEmpty else { return }
        searchSelectionHandler?(selectionText)
    }
}
#endif

/// A web view kept ready for the next preview that needs one.
///
/// Starting a web view takes most of a second before it shows anything, on
/// top of whatever the page takes, and a page takes very little: 23 ms for a
/// short document and under half a second for a 1.86 MB one. Each document
/// has a preview of its own, so every first look at a document would pay that
/// start. So one web view is started ahead of need, with an empty page to
/// make it start its process. A preview takes it, and another is started for
/// the next.
///
/// None is started at launch. The first page's web view is made when its page
/// is ready, as it always was: a spare started first thing, to be ready by
/// then, was measured and made a launch slower. Making it held the main actor
/// for up to a second just when the list was being read, and the page then
/// took longer to begin arriving in it than in a web view made for it.
@MainActor
enum SparePreviewWebView {
    private static var spare: MarkdownCopyWebView?

    /// Starts a spare, if there is not one already.
    ///
    /// Making a web view is work for the main actor, not only for the process
    /// it starts, so this is done when the main actor has least else to do:
    /// after a page has finished loading.
    static func warm() {
        guard spare == nil else { return }
        let webView = make()
        webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        spare = webView
    }

    /// Starts the next spare once the page that took the last one has had
    /// its turn. Started sooner, it would be made, and its process started,
    /// just as that page was loading.
    static func warmAfterAPageHasLoaded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            warm()
        }
    }

    /// A web view for a preview: the spare if there is one, and a new one if
    /// not.
    fileprivate static func take() -> MarkdownCopyWebView {
        let webView = spare ?? make()
        spare = nil
        return webView
    }

    private static func make() -> MarkdownCopyWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Local images are served from the app process; the web content process
        // cannot read files itself. Must be set before the web view is created.
        configuration.setURLSchemeHandler(
            MarkdownImageSchemeHandler(accessStore: .shared),
            forURLScheme: MarkdownImageURL.scheme
        )
        for script in MarkdownWebResources.Script.allCases {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: MarkdownWebResources.script(script),
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }
        return MarkdownCopyWebView(frame: .zero, configuration: configuration)
    }
}

private extension MarkdownCopyWebView {
    func applySelection(_ selectedRange: MarkdownSelectionRange?) {
        let payload = MarkdownPreviewWebView.selectionInvocation(in: markdownReading, selectedRange: selectedRange)
        evaluateJavaScript(payload)
    }

    func writeBlockRangeToPasteboard(start: Int, end: Int, kind: MarkdownCopyableBlockKind?) {
        guard end > start else { return }
        let ranges = [MarkdownSelectionRange(location: start, length: end - start)]

        guard !MarkdownBlockCopyText.offersRichText(for: kind) else {
            // Tables (and anything unrecognized) keep the existing behavior:
            // raw source, in both plain and rich flavors.
            _ = MarkdownSelectionClipboard.writeSelection(from: markdownSource, ranges: ranges)
            return
        }

        // Quotes and code: the syntax is decoration, so hand over the text
        // itself as plain text only. Selecting the block by hand and copying is
        // a different path and still yields the raw source, markers and all.
        guard let blockSource = MarkdownSelectionClipboard.selectedMarkdown(
            in: markdownSource,
            ranges: ranges
        ) else { return }
        _ = MarkdownSelectionClipboard.writePlainText(
            MarkdownBlockCopyText.copyText(fromBlockSource: blockSource, kind: kind)
        )
    }

    func copySelectionToPasteboard(fallback: @escaping () -> Void) {
        let source = markdownSource
        let definitions = markdownReading.definitions
        let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "PrevCopy")
        evaluateJavaScript(PreviewScriptCall.selectedDisplayRanges) { [weak self] result, _ in
            guard let self else {
                fallback()
                return
            }
            let selectionRanges = PreviewSelectionBridge.contiguousSelectionRanges(
                fromDisplayRangeResult: result,
                source: source,
                definitions: definitions
            )
            log.info("PREVCOPY ranges=\(selectionRanges.count, privacy: .public)")
            guard !selectionRanges.isEmpty else {
                log.info("PREVCOPY falling back: no ranges")
                fallback()
                return
            }

            self.evaluateJavaScript(PreviewScriptCall.selectedHTML) { htmlResult, _ in
                let selectionHTML = htmlResult as? String
                // Plain text is the raw markdown under the selection; rich text
                // is the rendered HTML the user can see.
                log.info("PREVCOPY selectionHTML=\(selectionHTML?.count ?? -1, privacy: .public) chars")
                guard MarkdownSelectionClipboard.writeSelection(
                    from: source,
                    ranges: selectionRanges,
                    richTextHTML: selectionHTML
                ) else {
                    log.info("PREVCOPY falling back: write failed")
                    fallback()
                    return
                }
                log.info("PREVCOPY wrote markdown and rich text")
            }
        }
    }

    func readSelectionSnapshot(completion: @escaping (_ selectedText: String?, _ ranges: [MarkdownSelectionRange]) -> Void) {
        let source = markdownSource
        let definitions = markdownReading.definitions
        evaluateJavaScript(PreviewScriptCall.selectionSnapshot) { result, _ in
            let payload = PreviewSelectionChangedMessage(messageBody: result as Any)
            let selectionRanges = PreviewSelectionBridge.contiguousSelectionRanges(
                fromDisplayRangeResult: payload.displayRangeResult,
                source: source,
                definitions: definitions
            )
            completion(payload.selectedText, selectionRanges)
        }
    }
}

extension MarkdownPreviewWebView {
    /// The call that puts a source selection into the page, or clears the
    /// page's selection when there is none to put there.
    ///
    /// Logs at `.info`, which never reaches the unified log but does show in
    /// Xcode's console — cheap to leave in, and the next person debugging a
    /// selection that does not appear gets the reflection's decision for free.
    ///
    /// Takes the document as it was read to build the page. Placing a
    /// selection needs the whole of it read, and this is the main actor.
    static func selectionInvocation(in reading: MarkdownReading, selectedRange: MarkdownSelectionRange?) -> String {
        guard let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: reading,
            selectedRange: selectedRange
        ) else {
            // No selection is not a failure, and it is the case on every load.
            if let selectedRange {
                Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "PrevSel").info(
                    "PREVSEL reflection FAILED for \(String(describing: selectedRange), privacy: .public)"
                )
            }
            return PreviewScriptCall.applySelection("null, null, null, null, null, null")
        }

        let start = reflectedSelection.start
        let end = reflectedSelection.end
        Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "PrevSel").info(
            "PREVSEL reflection ok start=\(start.blockStart, privacy: .public)-\(start.blockEnd, privacy: .public)+\(start.displayOffset, privacy: .public) end=\(end.blockStart, privacy: .public)-\(end.blockEnd, privacy: .public)+\(end.displayOffset, privacy: .public)"
        )

        return PreviewScriptCall.applySelection(
            "\(start.blockStart), \(start.blockEnd), \(start.displayOffset), " +
            "\(end.blockStart), \(end.blockEnd), \(end.displayOffset)"
        )
    }
}

extension MarkdownPreviewWebView.Coordinator {
    /// Loads `html`, noting where to put the reader back if they have been in
    /// this document before: reading it now, or before they went to another.
    func load(
        _ html: String,
        baseURL: URL?,
        showing content: PreviewScrollRestoration.Content,
        in webView: WKWebView
    ) {
        scrollRestoration = scrollMemory.restoration(for: content)
        loadedContent = content
        lastHTML = html
        loadedBaseURL = baseURL
        isLoadingPage = true
        hasPageBegunToArrive = false
        pageNavigation = webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Puts the selection into the page now loading, and the reader back
    /// where they were. Done once for each page: when the page says its
    /// content has been read, or, for one that never says so, when it has
    /// loaded.
    ///
    /// It used to wait for the page to have loaded, which a page does not say
    /// until everything it refers to has arrived. An image from the network
    /// keeps that back for as long as the network takes, with the text on
    /// screen all the while and the reader not yet where they were. What an
    /// image moves when it does arrive, the page puts right itself; see
    /// `notePlacing` in the scrolling script.
    func placeReaderInPage(_ webView: WKWebView) {
        guard isLoadingPage else { return }
        self.webView?.applySelection(lastSelectedRange)
        // After the selection, which centres itself: on a reload the
        // reader's place wins.
        restoreScrollPosition(in: webView)
        #if os(macOS)
        if isShowing {
            self.webView?.takeFirstResponderIfUnclaimed()
        }
        #endif
    }

    /// Loads the page again after its process has gone. Where the reader was
    /// is put back as for any other load of the same document.
    func reloadAfterLosingThePage(in webView: WKWebView) {
        guard let lastHTML, let loadedContent else { return }
        load(lastHTML, baseURL: loadedBaseURL, showing: loadedContent, in: webView)
    }

    /// The page is in front of the reader again, after a spell behind Source
    /// with nothing loaded in the meantime.
    ///
    /// WebKit lets go of a page's selection when the page loses the keyboard,
    /// so the selection is put back. Putting it back brings it to the middle
    /// of the window, so the reader is then put back where they were: where
    /// they left the page, or where they went to in the source if they moved
    /// there. A page still loading does both of these itself when it is done.
    func comeBackIntoView(selecting selectedRange: MarkdownSelectionRange?) {
        guard let webView, !isLoadingPage else { return }
        webView.applySelection(selectedRange)
        // Unless the selection is one they made in the source since: then the
        // middle of the window, where putting it back has brought it, is
        // where they want to be.
        if selectedRange != nil,
           scrollMemory.takeSelectionToShow(in: loadedContent?.documentID, for: .preview) {
            return
        }
        let place = loadedContent.map { scrollMemory.restoration(for: $0) } ?? .top
        webView.evaluateJavaScript(place.script ?? PreviewScriptCall.scrollToOffset(x: 0, y: 0))
    }

    /// Puts the reader back where `load` found them, once the page is there to
    /// be scrolled.
    func restoreScrollPosition(in webView: WKWebView) {
        isLoadingPage = false
        // A selection the reader has made in the source since comes before
        // the place: it was put into the page as it loaded, which brought it
        // to the middle of the window, and it is left there. A page nobody
        // can see leaves that for when it is shown.
        if isShowing, lastSelectedRange != nil,
           scrollMemory.takeSelectionToShow(in: loadedContent?.documentID, for: .preview) {
            scrollRestoration = .top
            return
        }
        guard let script = scrollRestoration.script else { return }
        scrollRestoration = .top
        webView.evaluateJavaScript(script)
    }
}

extension MarkdownPreviewWebView.Coordinator: WKScriptMessageHandler {
    func updateFlushSelectionHandler() {
        selectionSynchronizer?.setFlushSelectionHandler { [weak self] completion in
            guard let self, let webView else {
                completion()
                return
            }

            webView.readSelectionSnapshot { [weak self] selectedText, selectionRanges in
                guard let self else {
                    completion()
                    return
                }

                let effectiveSelectionRanges = selectionRanges.isEmpty ? lastPreviewSelectionRanges : selectionRanges
                let effectiveSelectedText = selectedText ?? lastPreviewSelectedText

                if !effectiveSelectionRanges.isEmpty {
                    lastPreviewSelectionRanges = effectiveSelectionRanges
                    lastSelectedRange = effectiveSelectionRanges.first
                    previewOriginatedSelectedRange = effectiveSelectionRanges.first
                    onSelectedRangesChange(effectiveSelectionRanges)
                }
                if effectiveSelectedText != nil {
                    lastPreviewSelectedText = effectiveSelectedText
                }
                onSelectedTextChange(effectiveSelectedText)
                completion()
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case copyBlockMessageHandlerName:
            guard let payload = PreviewCopyBlockMessage(messageBody: message.body) else { return }
            webView?.writeBlockRangeToPasteboard(start: payload.start, end: payload.end, kind: payload.kind)
        case previewSelectionChangedMessageHandlerName:
            // Behind Source the selection is the source pane's to change.
            guard isShowing else { return }
            let payload = PreviewSelectionChangedMessage(messageBody: message.body)
            webView?.currentSelectionText = payload.selectedText
            let selectionRanges = webView.map {
                PreviewSelectionBridge.contiguousSelectionRanges(
                    fromDisplayRangeResult: payload.displayRangeResult,
                    source: $0.markdownSource,
                    definitions: $0.markdownReading.definitions
                )
            } ?? []
            if !selectionRanges.isEmpty {
                lastPreviewSelectionRanges = selectionRanges
                lastSelectedRange = selectionRanges.first
                previewOriginatedSelectedRange = selectionRanges.first
                onSelectedRangesChange(selectionRanges)
                if !payload.wasApplied {
                    // The reader's own: where the source pane goes next.
                    scrollMemory.rememberSelection(in: loadedContent?.documentID, by: .preview)
                }
            }
            if payload.selectedText != nil {
                lastPreviewSelectedText = payload.selectedText
            }
            onSelectedTextChange(payload.selectedText)
        case requestImageAccessMessageHandlerName:
            onRequestImageAccess()
        case previewScrollChangedMessageHandlerName:
            // A page that is still loading is not where the reader left it;
            // what it reports would overwrite the place being kept for them.
            // Nor is a page behind Source where the reader is: what moves it
            // there is the app, and the reader is moving in the source.
            guard !isLoadingPage,
                  isShowing,
                  let loadedContent,
                  let position = PreviewScrollPosition(messageBody: message.body) else {
                return
            }
            scrollMemory.remember(position, in: loadedContent)
        case previewContentReadMessageHandlerName:
            // Said by the page now loading, and not by the one it is taking
            // the place of, which may still have been saying things when
            // this one was asked for.
            guard hasPageBegunToArrive, let webView = message.webView else { return }
            placeReaderInPage(webView)
        case previewSourceOffsetChangedMessageHandlerName:
            // The same place again, as the source pane will want it.
            guard !isLoadingPage,
                  isShowing,
                  let loadedContent,
                  let place = PreviewSourceOffsetMessage(messageBody: message.body) else {
                return
            }
            scrollMemory.rememberSourceOffset(place.offset, in: loadedContent.documentID, by: .preview)
        default:
            return
        }
    }
}

#if DEBUG
#Preview("Markdown Preview WebView") {
    let reading = MarkdownReading(of: MarkdownPreviewFixtures.fullFile.contents)
    MarkdownPreviewWebView(
        reading: reading,
        html: MarkdownHTMLBuilder.document(for: reading, softBreak: .lineBreak),
        baseURL: nil,
        selectedRange: nil
    )
}
#endif
