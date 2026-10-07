//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

(() => {
  window.markdownPreview = window.markdownPreview ?? {};

  const buttons = '[data-copy-button], [data-image-access-button]';

  // Nothing the reader selected: one of the preview's own buttons, or the
  // whitespace the markup was laid out with.
  const isFurniture = (node) => {
    if (node.nodeType === Node.TEXT_NODE) {
      return !/\S/.test(node.textContent ?? '');
    }
    return node.nodeType === Node.ELEMENT_NODE && node.matches(buttons);
  };

  const nothingBefore = (container, offset) => {
    if (container.nodeType === Node.TEXT_NODE) {
      return offset === 0;
    }
    return Array.from(container.childNodes).slice(0, offset).every(isFurniture);
  };

  const nothingAfter = (container, offset) => {
    if (container.nodeType === Node.TEXT_NODE) {
      return offset === (container.textContent ?? '').length;
    }
    return Array.from(container.childNodes).slice(offset).every(isFurniture);
  };

  // A selection can reach into a block and take nothing from it. Clicking
  // three times on a line selects up to the start of whatever comes next, and
  // a copy of that holds the next block too, emptied: a list arrives as a
  // bullet with nothing beside it. So each end is drawn back out of whatever
  // it reaches into and takes nothing from.
  const drawnBackToWhatItTakes = (selectionRange) => {
    const range = selectionRange.cloneRange();
    while (
      !range.collapsed &&
      range.endContainer !== range.commonAncestorContainer &&
      nothingBefore(range.endContainer, range.endOffset)
    ) {
      range.setEndBefore(range.endContainer);
    }
    while (
      !range.collapsed &&
      range.startContainer !== range.commonAncestorContainer &&
      nothingAfter(range.startContainer, range.startOffset)
    ) {
      range.setStartAfter(range.startContainer);
    }
    return range;
  };

  // The current selection as HTML, or null when nothing is selected. Rich-text
  // copy hands this to the app, which turns it into what goes on the pasteboard.
  window.markdownPreview.selectedHTML = () => {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) {
      return null;
    }

    // The preview's own buttons would come along with the text, so drop them.
    const container = document.createElement('div');
    for (let index = 0; index < selection.rangeCount; index += 1) {
      container.appendChild(drawnBackToWhatItTakes(selection.getRangeAt(index)).cloneContents());
    }
    container.querySelectorAll(buttons).forEach((button) => button.remove());

    const html = container.innerHTML;
    return html && html.trim().length > 0 ? html : null;
  };
})();
