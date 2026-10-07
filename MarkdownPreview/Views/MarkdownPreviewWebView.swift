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
/// Internal so the tests can check the image-access button really reaches the
/// app.
let requestImageAccessMessageHandlerName = "requestImageAccess"

#if os(iOS)
struct MarkdownPreviewWebView: UIViewRepresentable {
    let source: String
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
        /// Where the reader last was, as the page reported it.
        var lastScrollPosition: PreviewScrollPosition?
        /// Where to put the reader when the page now loading has finished.
        var scrollRestoration: PreviewScrollRestoration.Restoration = .top
        var isLoadingPage = false

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView?.applySelection(lastSelectedRange)
            // After the selection, which centres itself: on a reload the
            // reader's place wins.
            restoreScrollPosition(in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
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
        configuration.userContentController.add(context.coordinator, name: copyBlockMessageHandlerName)
        configuration.userContentController.add(context.coordinator, name: previewSelectionChangedMessageHandlerName)
        configuration.userContentController.add(context.coordinator, name: requestImageAccessMessageHandlerName)
        configuration.userContentController.add(context.coordinator, name: previewScrollChangedMessageHandlerName)

        let webView = MarkdownCopyWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.markdownSource = source
        context.coordinator.webView = webView
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
            showing: .init(documentID: documentID, source: source),
            in: webView
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        (webView as? MarkdownCopyWebView)?.markdownSource = source
        context.coordinator.webView = webView as? MarkdownCopyWebView
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.onRequestImageAccess = onRequestImageAccess
        context.coordinator.updateFlushSelectionHandler()
        (webView as? MarkdownCopyWebView)?.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
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
                showing: .init(documentID: documentID, source: source),
                in: webView
            )
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
    }
}
#elseif os(macOS)
struct MarkdownPreviewWebView: NSViewRepresentable {
    let source: String
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
        /// Where the reader last was, as the page reported it.
        var lastScrollPosition: PreviewScrollPosition?
        /// Where to put the reader when the page now loading has finished.
        var scrollRestoration: PreviewScrollRestoration.Restoration = .top
        var isLoadingPage = false

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView?.applySelection(lastSelectedRange)
            // After the selection, which centres itself: on a reload the
            // reader's place wins.
            restoreScrollPosition(in: webView)
            self.webView?.takeFirstResponderIfUnclaimed()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
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
        configuration.userContentController.add(context.coordinator, name: copyBlockMessageHandlerName)
        configuration.userContentController.add(context.coordinator, name: previewSelectionChangedMessageHandlerName)
        configuration.userContentController.add(context.coordinator, name: requestImageAccessMessageHandlerName)
        configuration.userContentController.add(context.coordinator, name: previewScrollChangedMessageHandlerName)

        let webView = MarkdownCopyWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.markdownSource = source
        context.coordinator.webView = webView
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
            showing: .init(documentID: documentID, source: source),
            in: webView
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        (webView as? MarkdownCopyWebView)?.markdownSource = source
        context.coordinator.webView = webView as? MarkdownCopyWebView
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.onRequestImageAccess = onRequestImageAccess
        context.coordinator.updateFlushSelectionHandler()
        (webView as? MarkdownCopyWebView)?.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
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
                showing: .init(documentID: documentID, source: source),
                in: webView
            )
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
    }
}
#endif

#if os(iOS)
private final class MarkdownCopyWebView: WKWebView {
    var markdownSource = ""
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
    var markdownSource = ""
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

private extension MarkdownCopyWebView {
    func applySelection(_ selectedRange: MarkdownSelectionRange?) {
        let payload = Self.selectionInvocation(source: markdownSource, selectedRange: selectedRange)
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
        let log = Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "PrevCopy")
        evaluateJavaScript(PreviewScriptCall.selectedDisplayRanges) { [weak self] result, _ in
            guard let self else {
                fallback()
                return
            }
            let selectionRanges = PreviewSelectionBridge.contiguousSelectionRanges(
                fromDisplayRangeResult: result,
                source: source
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
        evaluateJavaScript(PreviewScriptCall.selectionSnapshot) { result, _ in
            let payload = PreviewSelectionChangedMessage(messageBody: result as Any)
            let selectionRanges = PreviewSelectionBridge.contiguousSelectionRanges(
                fromDisplayRangeResult: payload.displayRangeResult,
                source: source
            )
            completion(payload.selectedText, selectionRanges)
        }
    }

    /// Logs at `.info`, which never reaches the unified log but does show in
    /// Xcode's console — cheap to leave in, and the next person debugging a
    /// selection that does not appear gets the reflection's decision for free.
    static func selectionInvocation(source: String, selectedRange: MarkdownSelectionRange?) -> String {
        guard let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: source,
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
    /// Loads `html`, noting where to put the reader back if this is the
    /// document they were already reading.
    func load(
        _ html: String,
        baseURL: URL?,
        showing content: PreviewScrollRestoration.Content,
        in webView: WKWebView
    ) {
        scrollRestoration = PreviewScrollRestoration.restoration(
            of: lastScrollPosition,
            from: loadedContent,
            to: content
        )
        if scrollRestoration == .top {
            // The position belonged to the page being replaced.
            lastScrollPosition = nil
        }

        loadedContent = content
        lastHTML = html
        isLoadingPage = true
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Puts the reader back where `load` found them, once the page is there to
    /// be scrolled.
    func restoreScrollPosition(in webView: WKWebView) {
        isLoadingPage = false
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
            let payload = PreviewSelectionChangedMessage(messageBody: message.body)
            webView?.currentSelectionText = payload.selectedText
            let selectionRanges = webView.map {
                PreviewSelectionBridge.contiguousSelectionRanges(
                    fromDisplayRangeResult: payload.displayRangeResult,
                    source: $0.markdownSource
                )
            } ?? []
            if !selectionRanges.isEmpty {
                lastPreviewSelectionRanges = selectionRanges
                lastSelectedRange = selectionRanges.first
                previewOriginatedSelectedRange = selectionRanges.first
                onSelectedRangesChange(selectionRanges)
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
            guard !isLoadingPage,
                  let position = PreviewScrollPosition(messageBody: message.body) else {
                return
            }
            lastScrollPosition = position
        default:
            return
        }
    }
}

#if DEBUG
#Preview("Markdown Preview WebView") {
    MarkdownPreviewWebView(
        source: MarkdownPreviewFixtures.fullFile.contents,
        html: MarkdownHTMLBuilder.document(for: MarkdownPreviewFixtures.fullFile.contents, softBreak: .lineBreak),
        baseURL: nil,
        selectedRange: nil
    )
}
#endif
