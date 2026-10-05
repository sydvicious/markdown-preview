//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

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
