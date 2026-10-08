//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// Telling the app that the page's content is there.
//
// A page says it has loaded only when everything it refers to has arrived,
// and an image from the network can keep that back for as long as the network
// takes. The text is there long before, and with it everything the app needs
// to put a selection into the page and the reader back where they were. So
// the page says when its content has been read, and the app does not wait for
// the rest.

import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPage, block, plain } from './preview-page.mjs';

test('the page tells the app once that its content has been read', () => {
  const { messages } = loadPage(block(0, 10, 'Some text'), ['content-read']);

  assert.deepEqual(plain(messages).map((message) => message.name), ['previewContentRead']);
});

// It is the last of the scripts to run, so what it tells the app is also that
// everything the app may call is there to be called.
test('it is told after the other scripts have run', () => {
  const { messages, preview } = loadPage(
    block(0, 10, 'Some text'),
    ['scroll', 'selection', 'apply-selection', 'content-read']
  );

  assert.equal(plain(messages).at(-1).name, 'previewContentRead');
  assert.equal(typeof preview.applySelection, 'function');
  assert.equal(typeof preview.scrollToOffset, 'function');
});
