//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// Keeping the reader's place: the page says where the reader is, and can be
// told to put them back after a reload. The decision about where "back" is
// belongs to the app; these are the two things the page does for it.

import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPage, plain, setScrollGeometry, tick } from './preview-page.mjs';

const page = () => loadPage('<p class="md-block">A long document.</p>', ['scroll']);

test('the position is where the reader is and how far the page can scroll', () => {
  const { window, preview } = page();
  setScrollGeometry(window, { x: 12, y: 900, pageHeight: 3000, viewportHeight: 600 });

  assert.deepEqual(plain(preview.scrollPosition()), [12, 900, 2400]);
});

test('a page that fits has nowhere to scroll', () => {
  const { window, preview } = page();
  setScrollGeometry(window, { y: 0, pageHeight: 400, viewportHeight: 600 });

  assert.deepEqual(plain(preview.scrollPosition()), [0, 0, 0]);
});

test('the reader can be put back at the same distance down the page', () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });

  preview.scrollToOffset(0, 900);

  assert.deepEqual(plain(scrolls), [[0, 900]]);
});

// The same text drawn larger makes a taller page, so the same distance down
// would be somewhere else. Half way down the old page is half way down the new.
test('the reader can be put back the same way down a page that changed height', () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 4600, viewportHeight: 600 });

  preview.scrollToFraction(0, 0.5);

  assert.deepEqual(plain(scrolls), [[0, 2000]]);
});

// A restore is asked for as soon as the page finishes loading, and the page may
// not have its full height yet. Scrolling then stops where the page does, so
// the restore has to be made again as the page grows.

test('a restore that falls short is made again when the page grows', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 700, viewportHeight: 600 });

  preview.scrollToOffset(0, 900);
  assert.deepEqual(plain(scrolls), [[0, 100]], 'as far as the page goes, for now');

  await tick(120);
  assert.deepEqual(plain(scrolls), [[0, 100]], 'not repeated while nothing has changed');

  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
  await tick(120);
  assert.deepEqual(plain(scrolls), [[0, 100], [0, 900]], 'made again once there is page to scroll');

  setScrollGeometry(window, { pageHeight: 5000, viewportHeight: 600 });
  await tick(120);
  assert.deepEqual(plain(scrolls), [[0, 100], [0, 900]], 'and left alone after it has landed');
});

// The page is never asked to scroll further than it can. A browser would stop
// at the bottom anyway, but WebKit on iOS does not throw the rest away: the
// scrolling is done outside the page, the request goes there as it was made,
// and it is carried out against whatever height the page has by then. So a
// request for 900 made of a short page could come true after the page grew,
// and after the reader had taken over and this had stopped trying.
test('a restore never asks for more than the page can scroll', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 400, viewportHeight: 600 });

  preview.scrollToOffset(0, 900);
  assert.deepEqual(plain(scrolls), [], 'a page that cannot scroll is not asked to');

  setScrollGeometry(window, { pageHeight: 1100, viewportHeight: 600 });
  await tick(120);
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
  await tick(120);

  assert.deepEqual(plain(scrolls), [[0, 500], [0, 900]]);
});

// Asking is not the same as getting there. Where the scrolling is done outside
// the page, a request is carried out later and against what is known there,
// which may be an older, shorter page. So a restore does not take a scroll on
// trust: it looks where the page is on its next try, and asks again.
test('a scroll that did not take is made again until it does', async () => {
  const { window, preview, scrolls, scrolling } = page();
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });

  scrolling.ignored = true;
  preview.scrollToOffset(0, 900);
  await tick(170);
  assert.ok(scrolls.length >= 3, `asked again while the page had not moved, ${scrolls.length} times`);
  assert.ok(plain(scrolls).every(([x, y]) => x === 0 && y === 900));

  scrolling.ignored = false;
  await tick(120);
  assert.equal(window.scrollY, 900);

  const asked = scrolls.length;
  await tick(170);
  assert.equal(scrolls.length, asked, 'and left alone once it is there');
});

// A restore lasts a number of tries, not a length of time. Timers are held
// back in a page that is not on screen, and a busy machine can use up two
// seconds between one step and the next; a clock would then run out before a
// second try had been made.
test('a restore that never takes stops after forty tries', async () => {
  const { window, preview, scrolls, scrolling } = page();
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });

  scrolling.ignored = true;
  preview.scrollToOffset(0, 900);
  await tick(3000);

  assert.equal(scrolls.length, 40);
});

// What a restore did, for a test to say when one does not end where it should.
test('a restore says what it did', async () => {
  const { window, preview } = page();
  setScrollGeometry(window, { pageHeight: 700, viewportHeight: 600 });
  assert.equal(plain(preview.restoreState()), null);

  preview.scrollToOffset(0, 900);
  await tick(120);
  assert.deepEqual(
    { ...plain(preview.restoreState()), tries: undefined },
    { tries: undefined, scrolls: 1, askedForY: 100, maxY: 100, ended: null }
  );

  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
  await tick(170);
  assert.deepEqual(
    { ...plain(preview.restoreState()), tries: undefined },
    { tries: undefined, scrolls: 2, askedForY: 900, maxY: 2400, ended: 'landed' }
  );

  preview.scrollToFraction(0, 0.5);
  window.dispatchEvent(new window.Event('wheel'));
  assert.equal(plain(preview.restoreState()).ended, 'the reader took over');
});

test('a restore that can land straight away is one scroll', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });

  preview.scrollToOffset(0, 900);
  setScrollGeometry(window, { pageHeight: 6000, viewportHeight: 600 });
  await tick(120);

  assert.deepEqual(plain(scrolls), [[0, 900]]);
});

test('a share of the way down is kept as the page grows', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 1600, viewportHeight: 600 });

  preview.scrollToFraction(0, 0.5);
  setScrollGeometry(window, { pageHeight: 4600, viewportHeight: 600 });
  await tick(120);

  assert.deepEqual(plain(scrolls), [[0, 500], [0, 2000]]);
});

test('the reader taking over ends a restore', async () => {
  for (const type of ['wheel', 'touchstart', 'mousedown', 'keydown']) {
    const { window, preview, scrolls } = page();
    setScrollGeometry(window, { pageHeight: 700, viewportHeight: 600 });

    preview.scrollToOffset(0, 900);
    window.dispatchEvent(new window.Event(type));
    setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
    await tick(120);

    assert.deepEqual(plain(scrolls), [[0, 100]], `${type} should have ended it`);
  }
});

test('a new restore replaces the one before', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 700, viewportHeight: 600 });

  preview.scrollToOffset(0, 900);
  preview.scrollToOffset(0, 400);
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
  await tick(120);

  assert.deepEqual(plain(scrolls), [[0, 100], [0, 400]]);
});

test('a restore gives up after a couple of seconds', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 700, viewportHeight: 600 });

  preview.scrollToOffset(0, 900);
  await tick(3000);
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
  await tick(120);

  assert.deepEqual(plain(scrolls), [[0, 100]], 'the page grew too late to be put back');
});

test('scrolling is reported to the app, a burst of it once', async () => {
  const { window, messages } = page();
  setScrollGeometry(window, { y: 300, pageHeight: 3000, viewportHeight: 600 });

  for (let index = 0; index < 5; index += 1) {
    window.dispatchEvent(new window.Event('scroll'));
  }
  assert.deepEqual(plain(messages), [], 'nothing until the burst has had a moment to settle');

  // What is reported is where the reader is when the report goes out.
  setScrollGeometry(window, { y: 640, pageHeight: 3000, viewportHeight: 600 });
  await tick(150);

  assert.deepEqual(plain(messages), [{ name: 'previewScrollChanged', body: [0, 640, 2400] }]);
});

// The source pane shows the same document as text. So that it can be opened
// where the reader was in the preview, and the preview where they were in the
// source, a place in the page is also told, and asked for, as a place in the
// source: each block knows the stretch of source it shows.

const threeBlocks =
  '<div class="md-block" data-source-start="0" data-source-end="100">One</div>\n' +
  '<div class="md-block" data-source-start="110" data-source-end="210">Two</div>\n' +
  '<div class="md-block" data-source-start="220" data-source-end="300">Three</div>';

// jsdom lays nothing out, so each block is told where it is in the page: its
// top and its height. Where it is in the window follows from how far the page
// is scrolled.
function layOut(window, blocks) {
  window.document.querySelectorAll('[data-source-start]').forEach((element, index) => {
    element.getBoundingClientRect = () => {
      const { top, height } = blocks[index];
      const inWindow = top - window.scrollY;
      return { top: inWindow, bottom: inWindow + height, height, left: 0, right: 0, width: 0 };
    };
  });
}

const blocksAsLaidOut = [{ top: 0, height: 200 }, { top: 220, height: 400 }, { top: 640, height: 160 }];

function sourcePage(body = threeBlocks, layout = blocksAsLaidOut) {
  const loaded = loadPage(body, ['scroll']);
  setScrollGeometry(loaded.window, { x: 0, y: 0, pageHeight: 2000, viewportHeight: 600 });
  layOut(loaded.window, layout);
  return loaded;
}

test('at the top of the page the reader is at the start of the source', () => {
  const { preview } = sourcePage();

  assert.equal(preview.sourceOffsetAtTop(), 0);
});

test('part of the way down a block is the same part of the way through its source', () => {
  const { window, preview } = sourcePage();
  // Half of the second block is above the top of the window.
  setScrollGeometry(window, { y: 420 });

  assert.equal(preview.sourceOffsetAtTop(), 160);
});

test('between two blocks the reader is at the start of the next', () => {
  const { window, preview } = sourcePage();
  setScrollGeometry(window, { y: 210 });

  assert.equal(preview.sourceOffsetAtTop(), 110);
});

test('past the last block the reader is at its end', () => {
  const { window, preview } = sourcePage();
  setScrollGeometry(window, { y: 900 });

  assert.equal(preview.sourceOffsetAtTop(), 300);
});

test('a page with no blocks has no place in the source', () => {
  const { window, preview } = page();
  setScrollGeometry(window, { y: 300, pageHeight: 3000, viewportHeight: 600 });

  assert.equal(preview.sourceOffsetAtTop(), null);
});

test('the reader can be put at a place in the source', () => {
  const { preview, scrolls } = sourcePage();

  preview.scrollToSourceOffset(160);

  assert.deepEqual(plain(scrolls), [[0, 420]]);
});

test('a place in the source between two blocks is the top of the next block', () => {
  const { preview, scrolls } = sourcePage();

  preview.scrollToSourceOffset(105);

  assert.deepEqual(plain(scrolls), [[0, 220]]);
});

test('the start of the source is the top of the page', () => {
  const { window, preview, scrolls } = sourcePage();
  setScrollGeometry(window, { y: 420 });

  preview.scrollToSourceOffset(0);

  assert.deepEqual(plain(scrolls), [[0, 0]]);
});

test('a place past the end of the source is the bottom of the last block', () => {
  const { preview, scrolls } = sourcePage();

  preview.scrollToSourceOffset(5000);

  assert.deepEqual(plain(scrolls), [[0, 800]]);
});

// An image that arrives late pushes everything under it down. The place asked
// for is a place in the source, so it is looked for again where it is now.
test('a place in the source is found again when the page moves under it', async () => {
  const { window, preview, scrolls } = sourcePage();
  preview.scrollToSourceOffset(160);
  assert.deepEqual(plain(scrolls), [[0, 420]]);

  layOut(window, [{ top: 0, height: 500 }, { top: 520, height: 400 }, { top: 940, height: 160 }]);
  await tick(120);

  assert.deepEqual(plain(scrolls.at(-1)), [0, 720]);
});

test('a page with no blocks is not scrolled to a place in the source', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { y: 300, pageHeight: 3000, viewportHeight: 600 });

  preview.scrollToSourceOffset(160);
  await tick(120);

  assert.deepEqual(plain(scrolls), []);
});

test('scrolling reports the place in the source after the place in the page', async () => {
  const { window, messages } = sourcePage();

  setScrollGeometry(window, { y: 420 });
  window.dispatchEvent(new window.Event('scroll'));
  await tick(150);

  assert.deepEqual(plain(messages), [
    { name: 'previewScrollChanged', body: [0, 420, 1400] },
    { name: 'previewSourceOffsetChanged', body: 160 }
  ]);
});

// The place in the source is told to the app so that the source pane can
// follow the reader. When it is the app that moved the page, to put the
// reader back or to show a selection, the reader has gone nowhere, and the
// source pane has nothing to follow.

test('the app moving the page is not the reader moving, and no place in the source is reported', async () => {
  const { window, preview, messages } = sourcePage();

  preview.scrollToOffset(0, 420);
  window.dispatchEvent(new window.Event('scroll'));
  await tick(150);

  assert.deepEqual(plain(messages), [{ name: 'previewScrollChanged', body: [0, 420, 1400] }]);
});

test('the reader moving the page after the app did is reported', async () => {
  const { window, preview, messages } = sourcePage();
  preview.scrollToOffset(0, 420);
  window.dispatchEvent(new window.Event('scroll'));
  await tick(150);

  // The second block ends exactly at the top of the window, so the reader is
  // at the start of the third.
  setScrollGeometry(window, { y: 620 });
  window.dispatchEvent(new window.Event('scroll'));
  await tick(150);

  assert.deepEqual(plain(messages).slice(1), [
    { name: 'previewScrollChanged', body: [0, 620, 1400] },
    { name: 'previewSourceOffsetChanged', body: 220 }
  ]);
});

// Another script moves the page to show a selection, and says so. It may ask
// for further than the page goes, as for a selection on the last lines.
test('a scroll another script says is the app\'s is not the reader moving', async () => {
  const { window, preview, messages } = sourcePage();

  preview.noteAppScroll(5000);
  setScrollGeometry(window, { y: 1400 });
  window.dispatchEvent(new window.Event('scroll'));
  await tick(150);

  assert.deepEqual(plain(messages), [{ name: 'previewScrollChanged', body: [0, 1400, 1400] }]);
});
