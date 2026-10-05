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
