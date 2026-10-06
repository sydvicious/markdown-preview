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

/// The calls the app makes into the preview's scripts.
///
/// The scripts themselves are files, in the `Web` folder beside `Views`, loaded
/// through `MarkdownWebResources` and installed as user scripts. What is left in
/// Swift is the calling of them: each of these invokes a function a script
/// defined on `window.markdownPreview`, and comes back with nothing, rather than
/// throwing, on a page whose scripts have not run yet.
enum PreviewScriptCall {
    /// The selection as text and display ranges, falling back to the last one
    /// that was not empty.
    static let selectionSnapshot = "window.markdownPreview?.selectionSnapshot?.() ?? null"

    /// The selection as ranges of each block's rendered text.
    static let selectedDisplayRanges = "window.markdownPreview?.selectedDisplayRanges?.() ?? null"

    /// The selection as HTML, for rich-text copy.
    static let selectedHTML = "window.markdownPreview?.selectedHTML?.() ?? null"

    /// Where the reader is, as `PreviewScrollPosition` reads it.
    static let scrollPosition = "window.markdownPreview?.scrollPosition?.() ?? null"

    /// Selects the span between two positions, each a block's source offsets
    /// and an offset into its rendered text. Six nulls clear the selection.
    static func applySelection(_ arguments: String) -> String {
        "window.markdownPreview?.applySelection?.(\(arguments))"
    }

    static func scrollToOffset(x: Double, y: Double) -> String {
        "window.markdownPreview?.scrollToOffset?.(\(x), \(y));"
    }

    static func scrollToFraction(x: Double, ofMaxY fraction: Double) -> String {
        "window.markdownPreview?.scrollToFraction?.(\(x), \(fraction));"
    }
}

struct PreviewDisplaySelectionRange: Equatable {
    var blockStart: Int
    var blockEnd: Int
    var displayLocation: Int
    var displayLength: Int
}

struct PreviewCopyBlockMessage: Equatable {
    var start: Int
    var end: Int
    /// What kind of block the range covers, so the handler can strip syntax that
    /// is decoration rather than content. Nil when the page predates the
    /// attribute or the value is unrecognized; the raw source is copied then.
    var kind: MarkdownCopyableBlockKind?

    init(start: Int, end: Int, kind: MarkdownCopyableBlockKind? = nil) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    init?(messageBody: Any) {
        guard let payload = messageBody as? [String: Any],
              let start = payload["start"] as? NSNumber,
              let end = payload["end"] as? NSNumber else {
            return nil
        }

        let startValue = start.intValue
        let endValue = end.intValue
        guard startValue >= 0, endValue > startValue else { return nil }

        self.start = startValue
        self.end = endValue
        self.kind = (payload["kind"] as? String).flatMap(MarkdownCopyableBlockKind.init(rawValue:))
    }
}

/// Where the reader is in the preview, as the page reports it.
struct PreviewScrollPosition: Equatable {
    var x: Double
    var y: Double
    /// How far down the page can scroll. Zero when the whole page fits.
    var maxY: Double

    init(x: Double, y: Double, maxY: Double) {
        self.x = x
        self.y = y
        self.maxY = maxY
    }

    /// Reads the `[x, y, maxY]` the page posts. Rubber-banding reports offsets
    /// past either end of the page, which are not places, so they are clamped.
    init?(messageBody: Any) {
        guard let values = (messageBody as? [NSNumber])?.map(\.doubleValue),
              values.count == 3,
              values.allSatisfy(\.isFinite) else {
            return nil
        }

        let maxY = max(0, values[2])
        self.x = max(0, values[0])
        self.y = min(max(0, values[1]), maxY)
        self.maxY = maxY
    }
}

/// Keeps the reader's place when the preview reloads.
///
/// The preview reloads the whole page whenever its HTML changes, and a reload
/// starts at the top. When the change is to the document already on screen — it
/// was edited on disk, the text size changed, a folder was granted for its
/// images — the reader should be left where they were. Reading a long plan
/// while it is being edited is the case that matters most.
enum PreviewScrollRestoration {
    /// What the preview is showing: which document, and its text.
    struct Content: Equatable {
        var documentID: String?
        var source: String
    }

    /// Where a freshly loaded page should be scrolled to.
    enum Restoration: Equatable {
        /// Leave it where a load puts it.
        case top
        /// The same distance down the page as before.
        case offset(x: Double, y: Double)
        /// The same way down the page as before, as a share of how far it scrolls.
        case fraction(x: Double, ofMaxY: Double)

        /// The script that carries it out, or nil when there is nothing to do.
        var script: String? {
            switch self {
            case .top:
                return nil
            case let .offset(x, y):
                return PreviewScriptCall.scrollToOffset(x: x, y: y)
            case let .fraction(x, fraction):
                return PreviewScriptCall.scrollToFraction(x: x, ofMaxY: fraction)
            }
        }
    }

    /// Where to put the reader once `current` has replaced `previous`, given
    /// where they were.
    ///
    /// Only a reload of the same document keeps the place; anything else is a
    /// different page and starts at the top. If the text changed, the offset is
    /// kept, which stays true for everything above the edit. If the text is the
    /// same and only its drawing changed, the height did, so the same offset
    /// would land somewhere else and the proportion is kept instead.
    static func restoration(
        of position: PreviewScrollPosition?,
        from previous: Content?,
        to current: Content
    ) -> Restoration {
        guard let position,
              let documentID = current.documentID,
              previous?.documentID == documentID else {
            return .top
        }
        guard position.x > 0 || position.y > 0 else { return .top }

        if previous?.source == current.source, position.maxY > 0 {
            return .fraction(x: position.x, ofMaxY: position.y / position.maxY)
        }
        return .offset(x: position.x, y: position.y)
    }
}

struct PreviewSelectionChangedMessage {
    var selectedText: String?
    var displayRangeResult: Any?

    init(messageBody: Any) {
        let payload = messageBody as? [String: Any]
        let selectedText = (payload?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.selectedText = selectedText?.isEmpty == false ? selectedText : nil
        displayRangeResult = payload?["ranges"]
    }
}

enum PreviewSelectionBridge {
    /// The preview's current selection as a single source range, or none.
    ///
    /// A selection is a source text offset and a length — one contiguous span
    /// that both views know how to render. The preview reports its DOM selection
    /// as one range per visible run of text, which is a rendering detail, so it
    /// is collapsed here rather than leaking into the selection model.
    static func contiguousSelectionRanges(
        fromDisplayRangeResult result: Any?,
        source: String
    ) -> [MarkdownSelectionRange] {
        enclosingRange(of: sourceRanges(fromDisplayRangeResult: result, source: source))
            .map { [$0] } ?? []
    }

    /// The single source range spanning `ranges`, from the earliest start to the
    /// latest end.
    ///
    /// A DOM selection is contiguous, but it maps back to one source range per
    /// visible run of text — the markdown syntax between them falls in the gaps.
    /// Stitching those pieces together produced plain text with every `#`, link
    /// target and blank line missing. Spanning them instead yields the raw
    /// markdown the user actually swept over.
    static func enclosingRange(of ranges: [MarkdownSelectionRange]) -> MarkdownSelectionRange? {
        guard let start = ranges.map(\.location).min(),
              let end = ranges.map({ $0.location + $0.length }).max(),
              end > start else {
            return nil
        }
        return MarkdownSelectionRange(location: start, length: end - start)
    }

    /// Whether an incoming selection is the echo of one the preview itself just
    /// reported, and so should not be pushed back into the web view.
    ///
    /// The stored range must actually exist for this to be an echo. Comparing
    /// the two optionals directly made `nil == nil` report "echo", so every
    /// transition to *no selection* was suppressed and the web view kept its old
    /// highlight — visible when a search match stopped matching as the user
    /// typed another character, and the stale match stayed highlighted.
    static func isEcho(
        ofPreviewOriginated previewOriginatedRange: MarkdownSelectionRange?,
        incoming selectedRange: MarkdownSelectionRange?
    ) -> Bool {
        guard let previewOriginatedRange else { return false }
        return previewOriginatedRange == selectedRange
    }

    static func sourceRanges(fromDisplayRangeResult result: Any?, source: String) -> [MarkdownSelectionRange] {
        let displayRanges = displayRanges(from: result)
        guard !displayRanges.isEmpty else { return [] }

        let nsSource = source as NSString
        let sourceLength = nsSource.length
        // Each block is read on its own, but a reference in it is a link only
        // by a definition elsewhere in the document.
        let definitions = MarkdownLinkDefinitions(source: source)
        return displayRanges.compactMap { displayRange -> MarkdownSelectionRange? in
            guard displayRange.blockStart >= 0,
                  displayRange.blockEnd <= sourceLength,
                  displayRange.blockEnd > displayRange.blockStart else {
                return nil
            }

            let blockRange = NSRange(
                location: displayRange.blockStart,
                length: displayRange.blockEnd - displayRange.blockStart
            )
            let blockSource = nsSource.substring(with: blockRange)
            let mapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource, definitions: definitions)
            let localDisplayRange = MarkdownSelectionRange(
                location: displayRange.displayLocation,
                length: displayRange.displayLength
            )
            guard let localSourceRange = mapping.sourceRange(forDisplayRange: localDisplayRange),
                  localSourceRange.length > 0 else {
                return nil
            }

            return MarkdownSelectionRange(
                location: displayRange.blockStart + localSourceRange.location,
                length: localSourceRange.length
            )
        }
    }

    static func displayRanges(from result: Any?) -> [PreviewDisplaySelectionRange] {
        guard let dictionaries = result as? [[String: Any]] else { return [] }
        return dictionaries.compactMap { dictionary -> PreviewDisplaySelectionRange? in
            guard let blockStart = dictionary["blockStart"] as? NSNumber,
                  let blockEnd = dictionary["blockEnd"] as? NSNumber,
                  let displayLocation = dictionary["displayLocation"] as? NSNumber,
                  let displayLength = dictionary["displayLength"] as? NSNumber else {
                return nil
            }
            let blockStartValue = blockStart.intValue
            let blockEndValue = blockEnd.intValue
            let displayLocationValue = displayLocation.intValue
            let displayLengthValue = displayLength.intValue
            guard blockEndValue > blockStartValue,
                  displayLocationValue >= 0,
                  displayLengthValue > 0 else {
                return nil
            }
            return PreviewDisplaySelectionRange(
                blockStart: blockStartValue,
                blockEnd: blockEndValue,
                displayLocation: displayLocationValue,
                displayLength: displayLengthValue
            )
        }
    }
}

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
