//
// Copyright ©2026 Syd Polk. All Rights Reserved.
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
        // Local images are served from the app process; the web content process
        // cannot read files itself. Must be set before the web view is created.
        configuration.setURLSchemeHandler(
            MarkdownImageSchemeHandler(),
            forURLScheme: MarkdownImageURL.scheme
        )
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
            MarkdownImageSchemeHandler(),
            forURLScheme: MarkdownImageURL.scheme
        )
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
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
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

  const kind = block.getAttribute('data-copy-kind');

  window.getSelection()?.removeAllRanges();
  window.webkit?.messageHandlers?.copyBlock?.postMessage({ start, end, kind });
}, { capture: true });
"""

private let previewSelectedHTMLScript = """
(() => {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) {
    return null;
  }

  // The Copy button's own markup would come along with the text, so drop it.
  const container = document.createElement('div');
  for (let index = 0; index < selection.rangeCount; index += 1) {
    container.appendChild(selection.getRangeAt(index).cloneContents());
  }
  container.querySelectorAll('[data-copy-button]').forEach((button) => button.remove());

  const html = container.innerHTML;
  return html && html.trim().length > 0 ? html : null;
})();
"""

/// Installed as a user script; also loaded directly by
/// `WebKitTextNodeAlignmentTests`, which checks WebKit's own text nodes against
/// the source-side offset mapping — hence internal rather than private.
let previewSelectionChangeScript = """
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
((startBlockStart, startBlockEnd, startOffset, endBlockStart, endBlockEnd, endOffset) => {
  const selection = window.getSelection();
  if (selection) {
    selection.removeAllRanges();
  }

  const args = [startBlockStart, startBlockEnd, startOffset, endBlockStart, endBlockEnd, endOffset];
  if (!args.every((value) => Number.isFinite(value))) {
    return false;
  }

  // Finds the text node and offset within it for a position in one block's
  // rendered text. `isEnd` decides which side a boundary between two nodes
  // belongs to, so a range ending exactly where a node ends stays inside it.
  const locate = (blockStart, blockEnd, offset, isEnd) => {
    const block = document.querySelector(
      `[data-source-start="${blockStart}"][data-source-end="${blockEnd}"]`
    );
    if (!block) {
      return null;
    }

    const textNodes = window.markdownPreview?.acceptedTextNodesInBlock?.(block) ?? [];
    const combinedTextLength = textNodes.reduce((length, entry) => Math.max(length, entry.end), 0);
    if (combinedTextLength === 0 || offset < 0 || offset > combinedTextLength) {
      return null;
    }

    const entry = isEnd
      ? textNodes.find((candidate) => offset > candidate.start && offset <= candidate.end)
      : textNodes.find((candidate) => offset >= candidate.start && offset < candidate.end);
    if (!entry) {
      return null;
    }

    return { node: entry.node, offset: offset - entry.start };
  };

  const start = locate(startBlockStart, startBlockEnd, startOffset, false);
  const end = locate(endBlockStart, endBlockEnd, endOffset, true);
  if (!start || !end) {
    return false;
  }

  const range = document.createRange();
  range.setStart(start.node, start.offset);
  range.setEnd(end.node, end.offset);
  if (range.collapsed) {
    return false;
  }
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
        evaluateJavaScript(previewSelectedDisplayRangesScript) { [weak self] result, _ in
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

            self.evaluateJavaScript(previewSelectedHTMLScript) { htmlResult, _ in
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
        evaluateJavaScript(previewSelectionSnapshotScript) { result, _ in
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
            Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "PrevSel").info(
                "PREVSEL reflection FAILED for \(String(describing: selectedRange), privacy: .public)"
            )
            return previewSelectionScript + "null, null, null, null, null, null)"
        }

        let start = reflectedSelection.start
        let end = reflectedSelection.end
        Logger(subsystem: "com.sydpolk.MarkdownPreview", category: "PrevSel").info(
            "PREVSEL reflection ok start=\(start.blockStart, privacy: .public)-\(start.blockEnd, privacy: .public)+\(start.displayOffset, privacy: .public) end=\(end.blockStart, privacy: .public)-\(end.blockEnd, privacy: .public)+\(end.displayOffset, privacy: .public)"
        )

        return previewSelectionScript +
            "\(start.blockStart), \(start.blockEnd), \(start.displayOffset), " +
            "\(end.blockStart), \(end.blockEnd), \(end.displayOffset))"
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
