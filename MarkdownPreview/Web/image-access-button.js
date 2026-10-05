//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

document.addEventListener('click', (event) => {
  const button = event.target.closest('[data-image-access-button]');
  if (!button) {
    return;
  }

  event.preventDefault();
  event.stopPropagation();

  window.webkit?.messageHandlers?.requestImageAccess?.postMessage({});
}, { capture: true });
