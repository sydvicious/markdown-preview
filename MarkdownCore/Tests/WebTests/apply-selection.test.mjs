//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// Applying a selection: the app names a span by block and offset, as when a
// search match is shown or a selection is carried over from the source view,
// and the page has to select exactly that text.

import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPage, block, plain, setScrollGeometry } from './preview-page.mjs';

const twoBlocks =
  block(0, 12, 'First <strong>bold</strong> text') +
  block(14, 30, 'Second paragraph');

function page(body = twoBlocks) {
  // The walker lives in the selection script; applying a selection uses it.
  const loaded = loadPage(body, ['selection', 'apply-selection']);
  return { ...loaded, selected: () => loaded.window.getSelection().toString() };
}

test('selects a span inside one block', () => {
  const { preview, selected } = page();

  assert.equal(preview.applySelection(14, 30, 7, 14, 30, 16), true);
  assert.equal(selected(), 'paragraph');
});

test('selects a span that crosses inline elements', () => {
  const { preview, selected } = page();

  assert.equal(preview.applySelection(0, 12, 3, 0, 12, 13), true);
  assert.equal(selected(), 'st bold te');
});

test('selects a span that runs from one block into the next', () => {
  const { window, preview } = page();

  assert.equal(preview.applySelection(0, 12, 11, 14, 30, 6), true);

  const range = window.getSelection().getRangeAt(0);
  assert.equal(range.startContainer.textContent, ' text');
  assert.equal(range.startOffset, 1);
  assert.equal(range.endContainer.textContent, 'Second paragraph');
  assert.equal(range.endOffset, 6);
});

// "First " ends at 6 and "bold" starts there. An end at 6 belongs to the node
// it finishes; a start at 6 belongs to the node it begins. Getting this wrong
// selects one node too many, or lands a range on an empty edge.
test('a boundary between two text nodes goes to the right one for each end', () => {
  const { window, preview, selected } = page();

  assert.equal(preview.applySelection(0, 12, 0, 0, 12, 6), true);
  assert.equal(selected(), 'First ');
  assert.equal(window.getSelection().getRangeAt(0).endContainer.textContent, 'First ');

  assert.equal(preview.applySelection(0, 12, 6, 0, 12, 10), true);
  assert.equal(selected(), 'bold');
  assert.equal(window.getSelection().getRangeAt(0).startContainer.textContent, 'bold');
});

test('the whole of a block can be selected, up to its last character', () => {
  const { preview, selected } = page();

  assert.equal(preview.applySelection(14, 30, 0, 14, 30, 16), true);
  assert.equal(selected(), 'Second paragraph');
});

test('nulls clear the selection', () => {
  const { window, preview } = page();
  preview.applySelection(14, 30, 0, 14, 30, 6);

  assert.equal(preview.applySelection(null, null, null, null, null, null), false);
  assert.equal(window.getSelection().rangeCount, 0);
});

test('a span that is not in the document selects nothing', () => {
  const { window, preview } = page();

  assert.equal(preview.applySelection(99, 120, 0, 99, 120, 4), false, 'no such block');
  assert.equal(preview.applySelection(14, 30, 0, 14, 30, 17), false, 'past the end of the text');
  assert.equal(preview.applySelection(14, 30, -1, 14, 30, 4), false, 'before the start');
  assert.equal(preview.applySelection(14, 30, 5, 14, 30, 5), false, 'nothing between the ends');
  assert.equal(window.getSelection().rangeCount, 0);
});

test('a new selection replaces the one before it', () => {
  const { window, preview, selected } = page();
  preview.applySelection(0, 12, 0, 0, 12, 5);
  preview.applySelection(14, 30, 0, 14, 30, 6);

  assert.equal(window.getSelection().rangeCount, 1);
  assert.equal(selected(), 'Second');
});

test('the selection is brought to the middle of the view', () => {
  const { window, preview, scrolls } = page();
  setScrollGeometry(window, { y: 1000, pageHeight: 5000, viewportHeight: 600 });
  window.Range.prototype.getBoundingClientRect = () => ({ top: 900, left: 0, width: 80, height: 20 });

  preview.applySelection(14, 30, 0, 14, 30, 6);

  // 900 below the top of the view, which is itself 1000 down the page, centred
  // in a 600-point view: 900 + 1000 - 300 + 10.
  assert.deepEqual(plain(scrolls), [[{ top: 1610, behavior: 'auto' }]]);
});
