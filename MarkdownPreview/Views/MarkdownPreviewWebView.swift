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

#if os(iOS)
struct MarkdownPreviewWebView: UIViewRepresentable {
    let source: String
    let html: String
    let baseURL: URL?

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        fileprivate weak var webView: MarkdownCopyWebView?

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
        configuration.userContentController.add(context.coordinator, name: copyBlockMessageHandlerName)

        let webView = MarkdownCopyWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.markdownSource = source
        context.coordinator.webView = webView
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
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: copyBlockMessageHandlerName)
    }
}
#elseif os(macOS)
struct MarkdownPreviewWebView: NSViewRepresentable {
    let source: String
    let html: String
    let baseURL: URL?

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        fileprivate weak var webView: MarkdownCopyWebView?

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
        configuration.userContentController.add(context.coordinator, name: copyBlockMessageHandlerName)

        let webView = MarkdownCopyWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.markdownSource = source
        context.coordinator.webView = webView
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        (webView as? MarkdownCopyWebView)?.markdownSource = source
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: copyBlockMessageHandlerName)
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
}

extension MarkdownPreviewWebView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == copyBlockMessageHandlerName else { return }
        guard let payload = message.body as? [String: Any],
              let start = payload["start"] as? NSNumber,
              let end = payload["end"] as? NSNumber else {
            return
        }

        webView?.writeBlockRangeToPasteboard(start: start.intValue, end: end.intValue)
    }
}

#if DEBUG
#Preview("Markdown Preview WebView") {
    MarkdownPreviewWebView(
        source: MarkdownPreviewFixtures.fullFile.contents,
        html: MarkdownHTMLBuilder.document(for: MarkdownPreviewFixtures.fullFile.contents),
        baseURL: nil
    )
}
#endif
