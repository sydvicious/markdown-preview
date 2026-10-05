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

  // A restore is asked for the moment the page finishes loading, which can be
  // before the page has its full height. Scrolling then goes only as far as
  // there is page, and the reader lands short of where they were. So a restore
  // is not a single scroll: it is repeated as the page grows, until it has
  // landed, the reader takes over, or a couple of seconds have gone by.
  const restoreWindow = 2000;
  const restoreInterval = 50;
  let restoreTimer = null;

  const stopRestoring = () => {
    if (restoreTimer !== null) {
      clearTimeout(restoreTimer);
      restoreTimer = null;
    }
  };

  // `target` says where to scroll given how far the page can scroll now, and
  // `hasLanded` whether that was far enough to be the final answer.
  const restore = (x, target, hasLanded) => {
    stopRestoring();
    const deadline = Date.now() + restoreWindow;
    let lastMaxY = null;

    const attempt = () => {
      restoreTimer = null;
      const maxY = maxScrollY();
      if (maxY !== lastMaxY) {
        lastMaxY = maxY;
        window.scrollTo(x, target(maxY));
      }
      if (hasLanded(maxY) || Date.now() >= deadline) {
        return;
      }
      restoreTimer = setTimeout(attempt, restoreInterval);
    };
    attempt();
  };

  // Once the reader moves the page themselves, it is theirs.
  for (const type of ['wheel', 'touchstart', 'mousedown', 'keydown']) {
    window.addEventListener(type, stopRestoring, { passive: true });
  }

  // Puts the reader the same distance down the page as before. That has landed
  // once the page can scroll that far.
  window.markdownPreview.scrollToOffset = (x, y) => {
    restore(x, () => y, (maxY) => maxY >= y);
  };

  // Puts the reader the same way down the page as before, as a share of how
  // far it scrolls. For a page whose height changed but whose text did not.
  // There is no telling when a page has finished growing, so this keeps the
  // share right for as long as a restore lasts.
  window.markdownPreview.scrollToFraction = (x, fraction) => {
    restore(x, (maxY) => fraction * maxY, () => false);
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
