//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// Reading the selection: what the reader has selected, reported as ranges of
// each block's rendered text, which is what the app maps back to the source.

import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPage, block, select, plain, tick } from './preview-page.mjs';

const twoBlocks =
  block(0, 12, 'First <strong>bold</strong> text') +
  block(14, 30, 'Second paragraph');

function page(body = twoBlocks) {
  const loaded = loadPage(body, ['selection']);
  const blocks = loaded.document.querySelectorAll('.md-block');
  return { ...loaded, blocks };
}

test('nothing selected reports no ranges', () => {
  const { preview } = page();

  assert.deepEqual(plain(preview.selectedDisplayRanges()), []);
});

test('a caret with nothing selected reports no ranges', () => {
  const { window, preview, blocks } = page();
  const text = blocks[0].firstChild;
  select(window, text, 2, text, 2);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), []);
});

test('a selection inside one text node is that span of the block', () => {
  const { window, preview, blocks } = page();
  const text = blocks[1].firstChild;
  select(window, text, 7, text, 16);

  assert.equal(window.getSelection().toString(), 'paragraph');
  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 14, blockEnd: 30, displayLocation: 7, displayLength: 9 }
  ]);
});

test('a selection across inline elements is one span of the block', () => {
  const { window, preview, blocks } = page();
  const first = blocks[0].firstChild;                         // "First "
  const last = blocks[0].lastChild;                           // " text"
  select(window, first, 3, last, 3);

  assert.equal(window.getSelection().toString(), 'st bold te');
  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 3, displayLength: 10 }
  ]);
});

test('a selection across two blocks is one range in each', () => {
  const { window, preview, blocks } = page();
  select(window, blocks[0].lastChild, 1, blocks[1].firstChild, 6);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 11, displayLength: 4 },
    { blockStart: 14, blockEnd: 30, displayLocation: 0, displayLength: 6 }
  ]);
});

test('a block whose source offsets are not a range is passed over', () => {
  const { window, preview, blocks } = page(
    '<p class="md-block" data-source-start="9" data-source-end="9">No span</p>' +
    block(14, 30, 'Second paragraph')
  );
  select(window, blocks[0].firstChild, 0, blocks[1].firstChild, 6);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 14, blockEnd: 30, displayLocation: 0, displayLength: 6 }
  ]);
});

test('the snapshot carries the selected text with its whitespace tidied', () => {
  const { window, preview, blocks } = page(block(0, 30, 'Line one<br />\nline   two'));
  select(window, blocks[0].firstChild, 0, blocks[0].lastChild, 11);

  assert.deepEqual(plain(preview.selectionSnapshot()), {
    text: 'Line one line two',
    ranges: [{ blockStart: 0, blockEnd: 30, displayLocation: 0, displayLength: 19 }]
  });
});

// Switching from the preview to the source view takes focus away, and WebKit
// collapses the selection as it goes. The snapshot is asked for afterwards, so
// it has to remember what was selected a moment ago.
test('the snapshot falls back to the last selection once it has collapsed', () => {
  const { window, document, preview, blocks } = page();
  const text = blocks[1].firstChild;
  select(window, text, 0, text, 6);
  document.dispatchEvent(new window.Event('selectionchange'));

  window.getSelection().removeAllRanges();

  assert.deepEqual(plain(preview.selectionSnapshot()), {
    text: 'Second',
    ranges: [{ blockStart: 14, blockEnd: 30, displayLocation: 0, displayLength: 6 }]
  });
});

test('a change of selection is reported to the app', async () => {
  const { window, document, messages, blocks } = page();
  const text = blocks[1].firstChild;
  select(window, text, 7, text, 16);
  document.dispatchEvent(new window.Event('selectionchange'));
  document.dispatchEvent(new window.Event('keyup'));
  await tick(10);

  // Two events in the same turn are one report.
  assert.deepEqual(plain(messages), [{
    name: 'previewSelectionChanged',
    body: {
      text: 'paragraph',
      ranges: [{ blockStart: 14, blockEnd: 30, displayLocation: 7, displayLength: 9 }]
    }
  }]);
});
