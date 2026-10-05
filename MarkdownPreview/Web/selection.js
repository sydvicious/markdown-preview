//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

(() => {
  let pendingSelectionUpdate = null;
  let lastNonEmptySelectionSnapshot = null;

  window.markdownPreview = window.markdownPreview ?? {};

  // Elements that hold other elements and no text of their own. Whitespace
  // directly inside one is how the markup was laid out, not something the
  // reader sees.
  const elementOnlyTags = new Set([
    'ARTICLE', 'BLOCKQUOTE', 'DIV', 'OL', 'TABLE', 'TBODY', 'TFOOT', 'THEAD', 'TR', 'UL'
  ]);

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
          // Whitespace on its own is still text wherever text can be: the
          // space between two emphasised words, the line break before a line
          // that starts in bold, the blank lines in a code block. The source
          // mapping counts each of those, so dropping one here puts every
          // offset after it out by one.
          if (
            /^[\s\n\r\t]+$/.test(node.textContent) &&
            (!parentElement || elementOnlyTags.has(parentElement.tagName))
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

    const text = selection.toString().replace(/\s+/g, ' ').trim();
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
