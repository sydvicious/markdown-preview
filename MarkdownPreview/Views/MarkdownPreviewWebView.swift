//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let copyBlockMessageHandlerName = "copyBlock"
private let previewSelectionChangedMessageHandlerName = "previewSelectionChanged"

#if os(iOS)
struct MarkdownPreviewWebView: UIViewRepresentable {
    let source: String
    let html: String
    let baseURL: URL?
    let selectedRange: MarkdownSelectionRange?
    var selectionSynchronizer: PreviewSelectionSynchronizer?
    var onSelectedTextChange: (String?) -> Void = { _ in }
    var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }
    var onSearchSelection: (String) -> Void = { _ in }

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
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: previewCopyButtonScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: previewSelectionChangeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: copyBlockMessageHandlerName)
        configuration.userContentController.add(context.coordinator, name: previewSelectionChangedMessageHandlerName)

        let webView = MarkdownCopyWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.markdownSource = source
        context.coordinator.webView = webView
        context.coordinator.lastSelectedRange = selectedRange
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.updateFlushSelectionHandler()
        webView.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
        }
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        (webView as? MarkdownCopyWebView)?.markdownSource = source
        context.coordinator.webView = webView as? MarkdownCopyWebView
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.updateFlushSelectionHandler()
        (webView as? MarkdownCopyWebView)?.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
        }
        let didReceivePreviewOriginatedSelection = context.coordinator.previewOriginatedSelectedRange == selectedRange
        if didReceivePreviewOriginatedSelection {
            context.coordinator.previewOriginatedSelectedRange = nil
        }
        let shouldApplySelection = context.coordinator.lastSelectedRange != selectedRange
        context.coordinator.lastSelectedRange = selectedRange
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        } else if shouldApplySelection && !didReceivePreviewOriginatedSelection {
            (webView as? MarkdownCopyWebView)?.applySelection(selectedRange)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.selectionSynchronizer?.setFlushSelectionHandler(nil)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: copyBlockMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: previewSelectionChangedMessageHandlerName)
    }
}
#elseif os(macOS)
struct MarkdownPreviewWebView: NSViewRepresentable {
    let source: String
    let html: String
    let baseURL: URL?
    let selectedRange: MarkdownSelectionRange?
    var selectionSynchronizer: PreviewSelectionSynchronizer?
    var onSelectedTextChange: (String?) -> Void = { _ in }
    var onSelectedRangesChange: ([MarkdownSelectionRange]) -> Void = { _ in }
    var onSearchSelection: (String) -> Void = { _ in }

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
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: previewCopyButtonScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: previewSelectionChangeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: copyBlockMessageHandlerName)
        configuration.userContentController.add(context.coordinator, name: previewSelectionChangedMessageHandlerName)

        let webView = MarkdownCopyWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.markdownSource = source
        context.coordinator.webView = webView
        context.coordinator.lastSelectedRange = selectedRange
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.updateFlushSelectionHandler()
        webView.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
        }
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        (webView as? MarkdownCopyWebView)?.markdownSource = source
        context.coordinator.webView = webView as? MarkdownCopyWebView
        context.coordinator.selectionSynchronizer = selectionSynchronizer
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        context.coordinator.onSelectedRangesChange = onSelectedRangesChange
        context.coordinator.onSearchSelection = onSearchSelection
        context.coordinator.updateFlushSelectionHandler()
        (webView as? MarkdownCopyWebView)?.searchSelectionHandler = { [weak coordinator = context.coordinator] text in
            coordinator?.onSearchSelection(text)
        }
        let didReceivePreviewOriginatedSelection = context.coordinator.previewOriginatedSelectedRange == selectedRange
        if didReceivePreviewOriginatedSelection {
            context.coordinator.previewOriginatedSelectedRange = nil
        }
        let shouldApplySelection = context.coordinator.lastSelectedRange != selectedRange
        context.coordinator.lastSelectedRange = selectedRange
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        } else if shouldApplySelection && !didReceivePreviewOriginatedSelection {
            (webView as? MarkdownCopyWebView)?.applySelection(selectedRange)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.selectionSynchronizer?.setFlushSelectionHandler(nil)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: copyBlockMessageHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: previewSelectionChangedMessageHandlerName)
    }
}
#endif

private let previewCopyButtonScript = """
document.addEventListener('click', (event) => {
  const button = event.target.closest('[data-copy-button]');
  if (!button) {
    return;
  }

  event.preventDefault();
  event.stopPropagation();

  const block = button.closest('[data-source-start][data-source-end]');
  if (!block) {
    return;
  }

  const start = Number(block.getAttribute('data-source-start'));
  const end = Number(block.getAttribute('data-source-end'));
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
    return;
  }

  window.getSelection()?.removeAllRanges();
  window.webkit?.messageHandlers?.copyBlock?.postMessage({ start, end });
}, { capture: true });
"""

private let previewSelectionChangeScript = """
(() => {
  let pendingSelectionUpdate = null;
  let lastNonEmptySelectionSnapshot = null;

  window.markdownPreview = window.markdownPreview ?? {};

  window.markdownPreview.acceptedTextNodesInBlock = (block) => {
    const walker = document.createTreeWalker(
      block,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode(node) {
          if (!node.textContent || node.textContent.length === 0) {
            return NodeFilter.FILTER_REJECT;
          }
          const parentElement = node.parentElement;
          if (parentElement && parentElement.closest('[data-copy-button]')) {
            return NodeFilter.FILTER_REJECT;
          }
          if (
            /^[\\s\\n\\r\\t]+$/.test(node.textContent) &&
            !(parentElement && parentElement.closest('pre, code'))
          ) {
            return NodeFilter.FILTER_REJECT;
          }
          return NodeFilter.FILTER_ACCEPT;
        }
      }
    );

    const textNodes = [];
    let displayOffset = 0;
    let currentNode;
    while ((currentNode = walker.nextNode())) {
      const text = currentNode.textContent ?? '';
      textNodes.push({
        node: currentNode,
        start: displayOffset,
        end: displayOffset + text.length
      });
      displayOffset += text.length;
    }
    return textNodes;
  };

  const selectedSpanInTextNode = (selectionRange, textNode) => {
    if (!selectionRange.intersectsNode(textNode)) {
      return null;
    }

    const nodeRange = document.createRange();
    nodeRange.selectNodeContents(textNode);
    const textLength = textNode.textContent?.length ?? 0;

    let start = 0;
    if (selectionRange.startContainer === textNode) {
      start = selectionRange.startOffset;
    } else if (selectionRange.compareBoundaryPoints(Range.START_TO_START, nodeRange) > 0) {
      const beforeSelectionStart = document.createRange();
      beforeSelectionStart.setStart(textNode, 0);
      beforeSelectionStart.setEnd(selectionRange.startContainer, selectionRange.startOffset);
      start = beforeSelectionStart.toString().length;
    }

    let end = textLength;
    if (selectionRange.endContainer === textNode) {
      end = selectionRange.endOffset;
    } else if (selectionRange.compareBoundaryPoints(Range.END_TO_END, nodeRange) < 0) {
      const beforeSelectionEnd = document.createRange();
      beforeSelectionEnd.setStart(textNode, 0);
      beforeSelectionEnd.setEnd(selectionRange.endContainer, selectionRange.endOffset);
      end = beforeSelectionEnd.toString().length;
    }

    start = Math.max(0, Math.min(start, textLength));
    end = Math.max(0, Math.min(end, textLength));
    return end > start ? { start, end } : null;
  };

  const selectedDisplayRanges = () => {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      return [];
    }

    const selectedRanges = [];
    const blocks = Array.from(document.querySelectorAll('[data-source-start][data-source-end]'));
    for (const block of blocks) {
      const blockStart = Number(block.getAttribute('data-source-start'));
      const blockEnd = Number(block.getAttribute('data-source-end'));
      if (!Number.isFinite(blockStart) || !Number.isFinite(blockEnd) || blockEnd <= blockStart) {
        continue;
      }

      const textNodes = window.markdownPreview.acceptedTextNodesInBlock(block);
      for (let rangeIndex = 0; rangeIndex < selection.rangeCount; rangeIndex += 1) {
        const selectionRange = selection.getRangeAt(rangeIndex);
        let displayStart = null;
        let displayEnd = null;

        for (const entry of textNodes) {
          const selectedSpan = selectedSpanInTextNode(selectionRange, entry.node);
          if (!selectedSpan) {
            continue;
          }

          const spanStart = entry.start + selectedSpan.start;
          const spanEnd = entry.start + selectedSpan.end;
          displayStart = displayStart === null ? spanStart : Math.min(displayStart, spanStart);
          displayEnd = displayEnd === null ? spanEnd : Math.max(displayEnd, spanEnd);
        }

        if (displayStart !== null && displayEnd !== null && displayEnd > displayStart) {
          selectedRanges.push({
            blockStart,
            blockEnd,
            displayLocation: displayStart,
            displayLength: displayEnd - displayStart
          });
        }
      }
    }

    return selectedRanges;
  };

  const selectedText = () => {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      return null;
    }

    const text = selection.toString().replace(/\\s+/g, ' ').trim();
    return text.length > 0 ? text : null;
  };

  const currentSelectionSnapshot = () => {
    return {
      text: selectedText(),
      ranges: selectedDisplayRanges()
    };
  };

  const rememberSelection = () => {
    const snapshot = currentSelectionSnapshot();
    if (snapshot.ranges.length > 0) {
      lastNonEmptySelectionSnapshot = snapshot;
    }
    return snapshot;
  };

  const publishSelection = () => {
    const snapshot = rememberSelection();
    window.webkit?.messageHandlers?.previewSelectionChanged?.postMessage(snapshot);
  };

  window.markdownPreview.selectedDisplayRanges = selectedDisplayRanges;
  window.markdownPreview.selectionSnapshot = () => {
    const snapshot = currentSelectionSnapshot();
    return snapshot.ranges.length > 0 ? snapshot : lastNonEmptySelectionSnapshot;
  };

  const scheduleSelectionPublish = () => {
    rememberSelection();

    if (pendingSelectionUpdate !== null) {
      clearTimeout(pendingSelectionUpdate);
    }

    pendingSelectionUpdate = setTimeout(() => {
      pendingSelectionUpdate = null;
      publishSelection();
    }, 0);
  };

  document.addEventListener('selectionchange', scheduleSelectionPublish);
  document.addEventListener('touchend', scheduleSelectionPublish, { passive: true });
  document.addEventListener('pointerup', scheduleSelectionPublish, { passive: true });
  document.addEventListener('keyup', scheduleSelectionPublish);
})();
"""

private let previewSelectionSnapshotScript = """
(() => {
  return window.markdownPreview?.selectionSnapshot?.() ?? null;
})()
"""

private let previewSelectedDisplayRangesScript = """
(() => {
  return window.markdownPreview?.selectedDisplayRanges?.() ?? null;
})()
"""

private let previewSelectionScript = """
((blockStart, blockEnd, displayLocation, displayLength) => {
  const selection = window.getSelection();
  if (selection) {
    selection.removeAllRanges();
  }

  if (
    !Number.isFinite(blockStart) ||
    !Number.isFinite(blockEnd) ||
    !Number.isFinite(displayLocation) ||
    !Number.isFinite(displayLength) ||
    displayLocation < 0 ||
    displayLength <= 0
  ) {
    return false;
  }

  const block = document.querySelector(
    `[data-source-start="${blockStart}"][data-source-end="${blockEnd}"]`
  );
  if (!block) {
    return false;
  }

  const textNodes = window.markdownPreview?.acceptedTextNodesInBlock?.(block) ?? [];
  const combinedTextLength = textNodes.reduce((length, entry) => Math.max(length, entry.end), 0);

  if (combinedTextLength === 0) {
    return false;
  }

  const startOffset = displayLocation;
  const endOffset = displayLocation + displayLength;
  if (startOffset < 0 || endOffset > combinedTextLength || endOffset <= startOffset) {
    return false;
  }

  const startEntry = textNodes.find((entry) => startOffset >= entry.start && startOffset < entry.end);
  const endEntry = textNodes.find((entry) => endOffset > entry.start && endOffset <= entry.end);
  if (!startEntry || !endEntry) {
    return false;
  }

  const range = document.createRange();
  range.setStart(startEntry.node, startOffset - startEntry.start);
  range.setEnd(endEntry.node, endOffset - endEntry.start);
  selection?.addRange(range);

  const boundingRect = range.getBoundingClientRect();
  if (boundingRect) {
    const top = boundingRect.top + window.scrollY - (window.innerHeight / 2) + (boundingRect.height / 2);
    window.scrollTo({ top: Math.max(top, 0), behavior: 'auto' });
  }

  return true;
})(
"""

struct PreviewDisplaySelectionRange: Equatable {
    var blockStart: Int
    var blockEnd: Int
    var displayLocation: Int
    var displayLength: Int
}

struct PreviewCopyBlockMessage: Equatable {
    var start: Int
    var end: Int

    init(start: Int, end: Int) {
        self.start = start
        self.end = end
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
    static func sourceRanges(fromDisplayRangeResult result: Any?, source: String) -> [MarkdownSelectionRange] {
        let displayRanges = displayRanges(from: result)
        guard !displayRanges.isEmpty else { return [] }

        let nsSource = source as NSString
        let sourceLength = nsSource.length
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
            let mapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource)
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

    @objc func copy(_ sender: Any?) {
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

    func writeBlockRangeToPasteboard(start: Int, end: Int) {
        guard end > start else { return }
        _ = MarkdownSelectionClipboard.writeSelection(
            from: markdownSource,
            ranges: [MarkdownSelectionRange(location: start, length: end - start)]
        )
    }

    func copySelectionToPasteboard(fallback: @escaping () -> Void) {
        let source = markdownSource
        evaluateJavaScript(previewSelectedDisplayRangesScript) { result, _ in
            let selectionRanges = PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: result, source: source)
            guard !selectionRanges.isEmpty else {
                fallback()
                return
            }

            guard MarkdownSelectionClipboard.writeSelection(from: source, ranges: selectionRanges) else {
                fallback()
                return
            }
        }
    }

    func readSelectionSnapshot(completion: @escaping (_ selectedText: String?, _ ranges: [MarkdownSelectionRange]) -> Void) {
        let source = markdownSource
        evaluateJavaScript(previewSelectionSnapshotScript) { result, _ in
            let payload = PreviewSelectionChangedMessage(messageBody: result as Any)
            let selectionRanges = PreviewSelectionBridge.sourceRanges(
                fromDisplayRangeResult: payload.displayRangeResult,
                source: source
            )
            completion(payload.selectedText, selectionRanges)
        }
    }

    static func selectionInvocation(source: String, selectedRange: MarkdownSelectionRange?) -> String {
        guard let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: source,
            selectedRange: selectedRange
        ) else {
            return previewSelectionScript + "null, null, null, null)"
        }

        return previewSelectionScript +
            "\(reflectedSelection.blockStart), " +
            "\(reflectedSelection.blockEnd), " +
            "\(reflectedSelection.displayRange.location), " +
            "\(reflectedSelection.displayRange.length))"
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
            webView?.writeBlockRangeToPasteboard(start: payload.start, end: payload.end)
        case previewSelectionChangedMessageHandlerName:
            let payload = PreviewSelectionChangedMessage(messageBody: message.body)
            webView?.currentSelectionText = payload.selectedText
            let selectionRanges = webView.map {
                PreviewSelectionBridge.sourceRanges(fromDisplayRangeResult: payload.displayRangeResult, source: $0.markdownSource)
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
        default:
            return
        }
    }
}

#if DEBUG
#Preview("Markdown Preview WebView") {
    MarkdownPreviewWebView(
        source: MarkdownPreviewFixtures.fullFile.contents,
        html: MarkdownHTMLBuilder.document(for: MarkdownPreviewFixtures.fullFile.contents),
        baseURL: nil,
        selectedRange: nil
    )
}
#endif
