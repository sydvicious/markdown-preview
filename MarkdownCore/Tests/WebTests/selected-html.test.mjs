//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// The selection as HTML, which rich-text copy hands to the app.

import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPage, block, select } from './preview-page.mjs';

test('nothing selected is no HTML', () => {
  const { preview } = loadPage(block(0, 10, 'Some text'), ['selected-html']);

  assert.equal(preview.selectedHTML(), null);
});

test('a selection comes back with its markup', () => {
  const { window, document, preview } = loadPage(
    block(0, 30, 'First <strong>bold</strong> text'),
    ['selected-html']
  );
  const paragraph = document.querySelector('.md-block');
  select(window, paragraph.firstChild, 3, paragraph.lastChild, 3);

  assert.equal(preview.selectedHTML(), 'st <strong>bold</strong> te');
});

// The buttons are the preview's own furniture. Pasted into another app they
// would arrive as stray controls in the middle of the reader's text.
test('the preview\'s own buttons are left out of what is copied', () => {
  const { window, document, preview } = loadPage(
    '<blockquote class="md-block" data-source-start="0" data-source-end="40">' +
    '<button type="button" class="md-copy-button" data-copy-button>Copy</button>' +
    '<p>Quoted <button type="button" data-image-access-button data-label="Allow…"></button> line</p>' +
    '</blockquote>',
    ['selected-html']
  );
  const quote = document.querySelector('blockquote');
  select(window, quote, 0, quote, quote.childNodes.length);

  assert.equal(preview.selectedHTML(), '<p>Quoted  line</p>');
});

test('a selection of nothing but whitespace is no HTML', () => {
  const { window, document, preview } = loadPage(block(0, 10, 'one   two'), ['selected-html']);
  const text = document.querySelector('.md-block').firstChild;
  select(window, text, 3, text, 6);

  assert.equal(preview.selectedHTML(), null);
});
