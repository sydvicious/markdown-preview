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
  const { preview, scrolls } = page();

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
  assert.deepEqual(plain(scrolls), [[0, 900]], 'tried at once, though the page is too short');

  await tick(120);
  assert.deepEqual(plain(scrolls), [[0, 900]], 'not repeated while nothing has changed');

  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
  await tick(120);
  assert.deepEqual(plain(scrolls), [[0, 900], [0, 900]], 'made again once there is page to scroll');

  setScrollGeometry(window, { pageHeight: 5000, viewportHeight: 600 });
  await tick(120);
  assert.deepEqual(plain(scrolls), [[0, 900], [0, 900]], 'and left alone after it has landed');
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

    assert.deepEqual(plain(scrolls), [[0, 900]], `${type} should have ended it`);
  }
});

test('a new restore replaces the one before', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 700, viewportHeight: 600 });

  preview.scrollToOffset(0, 900);
  preview.scrollToOffset(0, 400);
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
  await tick(120);

  assert.deepEqual(plain(scrolls), [[0, 900], [0, 400], [0, 400]]);
});

test('a restore gives up after a couple of seconds', async () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { pageHeight: 700, viewportHeight: 600 });

  preview.scrollToOffset(0, 900);
  await tick(2200);
  setScrollGeometry(window, { pageHeight: 3000, viewportHeight: 600 });
  await tick(120);

  assert.deepEqual(plain(scrolls), [[0, 900]], 'the page grew too late to be put back');
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
