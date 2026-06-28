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
    var onSelectedTextChange: (String?) -> Void = { _ in }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastSelectedRange: MarkdownSelectionRange?
        fileprivate weak var webView: MarkdownCopyWebView?
        var onSelectedTextChange: (String?) -> Void = { _ in }

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
        context.coordinator.onSelectedTextChange = onSelectedTextChange
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
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        let shouldApplySelection = context.coordinator.lastSelectedRange != selectedRange
        context.coordinator.lastSelectedRange = selectedRange
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        } else if shouldApplySelection {
            (webView as? MarkdownCopyWebView)?.applySelection(selectedRange)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
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
    var onSelectedTextChange: (String?) -> Void = { _ in }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        var lastSelectedRange: MarkdownSelectionRange?
        fileprivate weak var webView: MarkdownCopyWebView?
        var onSelectedTextChange: (String?) -> Void = { _ in }

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
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        (webView as? MarkdownCopyWebView)?.markdownSource = source
        context.coordinator.onSelectedTextChange = onSelectedTextChange
        let shouldApplySelection = context.coordinator.lastSelectedRange != selectedRange
        context.coordinator.lastSelectedRange = selectedRange
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        } else if shouldApplySelection {
            (webView as? MarkdownCopyWebView)?.applySelection(selectedRange)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
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

  const selectedText = () => {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
      return null;
    }

    const text = selection.toString().replace(/\\s+/g, ' ').trim();
    return text.length > 0 ? text : null;
  };

  const publishSelection = () => {
    pendingSelectionUpdate = null;
    window.webkit?.messageHandlers?.previewSelectionChanged?.postMessage({
      text: selectedText()
    });
  };

  document.addEventListener('selectionchange', () => {
    if (pendingSelectionUpdate !== null) {
      clearTimeout(pendingSelectionUpdate);
    }
    pendingSelectionUpdate = setTimeout(publishSelection, 0);
  });
})();
"""

private let previewSelectionBlockRangesScript = """
(() => {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
    return null;
  }

  const ranges = [];
  const blocks = Array.from(document.querySelectorAll('[data-source-start][data-source-end]'));
  for (const block of blocks) {
    let intersects = false;
    for (let index = 0; index < selection.rangeCount; index += 1) {
      const range = selection.getRangeAt(index);
      if (range.intersectsNode(block)) {
        intersects = true;
        break;
      }
    }

    if (!intersects) {
      continue;
    }

    const start = Number(block.getAttribute('data-source-start'));
    const end = Number(block.getAttribute('data-source-end'));
    if (Number.isFinite(start) && Number.isFinite(end) && end > start) {
      ranges.push({ start, end });
    }
  }

  return ranges;
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
  let combinedText = '';
  let currentNode;
  while ((currentNode = walker.nextNode())) {
    const text = currentNode.textContent ?? '';
    textNodes.push({ node: currentNode, start: combinedText.length, end: combinedText.length + text.length });
    combinedText += text;
  }

  if (combinedText.length === 0) {
    return false;
  }

  const startOffset = displayLocation;
  const endOffset = displayLocation + displayLength;
  if (startOffset < 0 || endOffset > combinedText.length || endOffset <= startOffset) {
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

#if os(iOS)
private final class MarkdownCopyWebView: WKWebView {
    var markdownSource = ""

    override func copy(_ sender: Any?) {
        copySelectionToPasteboard {
            self.performNativeCopy(sender)
        }
    }

    private func performNativeCopy(_ sender: Any?) {
        super.copy(sender)
    }
}
#elseif os(macOS)
private final class MarkdownCopyWebView: WKWebView {
    var markdownSource = ""

    @objc func copy(_ sender: Any?) {
        copySelectionToPasteboard {}
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
        evaluateJavaScript(previewSelectionBlockRangesScript) { result, _ in
            guard let blockRanges = Self.blockRanges(from: result), !blockRanges.isEmpty else {
                fallback()
                return
            }

            let selectionRanges = blockRanges.map { MarkdownSelectionRange(location: $0.start, length: $0.end - $0.start) }
            guard MarkdownSelectionClipboard.writeSelection(from: source, ranges: selectionRanges) else {
                fallback()
                return
            }
        }
    }

    static func blockRanges(from result: Any?) -> [(start: Int, end: Int)]? {
        guard let dictionaries = result as? [[String: Any]] else { return nil }
        let ranges = dictionaries.compactMap { dictionary -> (start: Int, end: Int)? in
            guard let start = dictionary["start"] as? NSNumber,
                  let end = dictionary["end"] as? NSNumber else {
                return nil
            }
            let startValue = start.intValue
            let endValue = end.intValue
            guard endValue > startValue else { return nil }
            return (start: startValue, end: endValue)
        }
        return ranges.isEmpty ? nil : ranges
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
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case copyBlockMessageHandlerName:
            guard let payload = message.body as? [String: Any],
                  let start = payload["start"] as? NSNumber,
                  let end = payload["end"] as? NSNumber else {
                return
            }

            webView?.writeBlockRangeToPasteboard(start: start.intValue, end: end.intValue)
        case previewSelectionChangedMessageHandlerName:
            let payload = message.body as? [String: Any]
            let selectedText = (payload?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            onSelectedTextChange(selectedText?.isEmpty == false ? selectedText : nil)
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
