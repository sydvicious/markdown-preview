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
  // landed, the reader takes over, or it has had its share of tries.
  //
  // The share is a count and not a length of time. At one try every fifty
  // milliseconds it comes to a couple of seconds, but timers are held back in a
  // page that is not on screen, and a clock would run out there before a second
  // try had been made.
  const restoreTries = 40;
  const restoreInterval = 50;
  let restoreTimer = null;

  // What the last restore did, for a test to say when one does not end where
  // it should. Nothing in the app reads it.
  let restoreState = null;
  window.markdownPreview.restoreState = () => restoreState;

  const stopRestoring = (reason) => {
    if (restoreTimer !== null) {
      clearTimeout(restoreTimer);
      restoreTimer = null;
      restoreState.ended = reason;
    }
  };

  // `target` says where to scroll given how far the page can scroll now, and
  // `hasLanded` whether that was far enough to be the final answer.
  //
  // Each scroll goes no further than the page can scroll at that moment. Asking
  // for more is not harmless: on iOS the scrolling happens outside the page,
  // the request is sent there as it was made, and it is carried out against
  // the height the page has when it gets there. A request for more than there
  // is can then come true later, after the page has grown and after the reader
  // has taken over, which is when nothing should be moving the page any more.
  //
  // For the same reason a scroll is not taken on trust. Carried out against a
  // page the other side still thinks is short, it goes nowhere. So each try
  // looks at where the page is, and only one that finds it in place counts.
  const restore = (x, target, hasLanded) => {
    stopRestoring('replaced');
    const state = { tries: 0, scrolls: 0, askedForY: null, maxY: null, ended: null };
    restoreState = state;
    let isInPlace = false;

    const attempt = () => {
      restoreTimer = null;
      state.tries += 1;

      const maxY = maxScrollY();
      const y = Math.min(target(maxY), maxY);
      if (maxY !== state.maxY) {
        state.maxY = maxY;
        isInPlace = false;
      }
      if (!isInPlace) {
        if (Math.abs(window.scrollY - y) <= 1) {
          isInPlace = true;
        } else {
          window.scrollTo(x, y);
          state.scrolls += 1;
          state.askedForY = y;
        }
      }

      if (isInPlace && hasLanded(maxY)) {
        state.ended = 'landed';
      } else if (state.tries >= restoreTries) {
        state.ended = 'gave up';
      } else {
        restoreTimer = setTimeout(attempt, restoreInterval);
      }
    };
    attempt();
  };

  // Once the reader moves the page themselves, it is theirs.
  for (const type of ['wheel', 'touchstart', 'mousedown', 'keydown']) {
    window.addEventListener(type, () => stopRestoring('the reader took over'), { passive: true });
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
