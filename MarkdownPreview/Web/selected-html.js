//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

window.markdownPreview = window.markdownPreview ?? {};

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
    container.appendChild(selection.getRangeAt(index).cloneContents());
  }
  container.querySelectorAll('[data-copy-button], [data-image-access-button]').forEach((button) => button.remove());

  const html = container.innerHTML;
  return html && html.trim().length > 0 ? html : null;
};
