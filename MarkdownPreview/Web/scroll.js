//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

window.markdownPreview = window.markdownPreview ?? {};

(() => {
  // How far down the page can scroll. Zero when the whole page fits.
  const maxScrollY = () => Math.max(0, document.documentElement.scrollHeight - window.innerHeight);

  // Where the reader is, as [x, y, maxY].
  window.markdownPreview.scrollPosition = () => [window.scrollX, window.scrollY, maxScrollY()];

  // Puts the reader the same distance down the page as before.
  window.markdownPreview.scrollToOffset = (x, y) => {
    window.scrollTo(x, y);
  };

  // Puts the reader the same way down the page as before, as a share of how
  // far it scrolls. For a page whose height changed but whose text did not.
  window.markdownPreview.scrollToFraction = (x, fraction) => {
    window.scrollTo(x, fraction * maxScrollY());
  };

  // Tells the app where the reader is, so a reload can put them back. Scrolling
  // fires far more often than the answer is needed, so it is reported at most
  // ten times a second.
  let pendingReport = null;

  window.addEventListener('scroll', () => {
    if (pendingReport !== null) {
      return;
    }

    pendingReport = setTimeout(() => {
      pendingReport = null;
      window.webkit?.messageHandlers?.previewScrollChanged?.postMessage(window.markdownPreview.scrollPosition());
    }, 100);
  }, { passive: true });
})();
