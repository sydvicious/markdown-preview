//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

window.markdownPreview = window.markdownPreview ?? {};

// Selects a span of the rendered document and brings it into view. Each end is
// a block, named by its source offsets, and an offset into that block's
// rendered text. Called with nulls, it clears the selection. Returns whether a
// selection was made.
window.markdownPreview.applySelection = (
  startBlockStart, startBlockEnd, startOffset, endBlockStart, endBlockEnd, endOffset
) => {
  const selection = window.getSelection();
  if (selection) {
    selection.removeAllRanges();
  }
  // What the app last selected here, so that the page can say of a selection
  // whether it is that or one the reader has made since.
  window.markdownPreview.appliedRange = null;

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
  window.markdownPreview.appliedRange = range.cloneRange();

  const boundingRect = range.getBoundingClientRect();
  if (boundingRect) {
    const top = boundingRect.top + window.scrollY - (window.innerHeight / 2) + (boundingRect.height / 2);
    // The app's doing, which the page's scrolling script is told, so that
    // the source pane is not sent after it as if the reader had gone there.
    window.markdownPreview?.noteAppScroll?.(Math.max(top, 0));
    window.scrollTo({ top: Math.max(top, 0), behavior: 'auto' });
  }

  return true;
};
