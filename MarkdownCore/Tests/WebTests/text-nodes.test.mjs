//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// The text-node walker is what every selection and search offset is measured
// with: a position in a block's rendered text is a count of the characters in
// the text nodes this accepts, in order. Anything it accepts that the Swift
// side's mapping does not count, or the reverse, puts every offset after it out.

import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPage, block } from './preview-page.mjs';

function walk(body) {
  const { document, preview } = loadPage(body, ['selection']);
  return preview.acceptedTextNodesInBlock(document.querySelector('.md-block'));
}

const texts = (entries) => Array.from(entries, (entry) => entry.node.textContent);
const spans = (entries) => Array.from(entries, (entry) => [entry.start, entry.end]);

test('offsets run on across inline elements', () => {
  const entries = walk(block(0, 30, 'Hello <strong>bold</strong> and <em>soft</em> words'));

  assert.deepEqual(texts(entries), ['Hello ', 'bold', ' and ', 'soft', ' words']);
  assert.deepEqual(spans(entries), [[0, 6], [6, 10], [10, 15], [15, 19], [19, 25]]);
});

test('an element contributes no characters of its own', () => {
  const entries = walk(block(0, 30, 'First line<br />\nSecond line'));

  assert.deepEqual(texts(entries), ['First line', '\nSecond line']);
  assert.equal(entries.at(-1).end, 'First line\nSecond line'.length);
});

test('the Copy button label is not part of the text', () => {
  const entries = walk(block(
    0, 30,
    '<button type="button" class="md-copy-button" data-copy-button>Copy</button><p>Quoted line</p>',
    'blockquote'
  ));

  assert.deepEqual(texts(entries), ['Quoted line']);
  assert.deepEqual(spans(entries), [[0, 11]]);
});

test('the button that stands in for an image adds nothing either', () => {
  const entries = walk(block(
    0, 30,
    'before <button type="button" class="md-image-access-button" data-image-access-button data-label="Allow…"></button> after'
  ));

  assert.deepEqual(texts(entries), ['before ', ' after']);
});

test('whitespace between elements is formatting, not text', () => {
  const entries = walk(block(0, 30, '\n<li>First</li>\n<li>Second</li>\n', 'ul'));

  assert.deepEqual(texts(entries), ['First', 'Second']);
  assert.deepEqual(spans(entries), [[0, 5], [5, 11]]);
});

test('whitespace inside code is kept, because there it is the text', () => {
  const entries = walk(block(0, 30, '<code><span>let</span> <span>value</span></code>', 'pre'));

  assert.deepEqual(texts(entries), ['let', ' ', 'value']);
  assert.deepEqual(spans(entries), [[0, 3], [3, 4], [4, 9]]);
});

test('an empty block has no text nodes', () => {
  assert.deepEqual(Array.from(walk(block(0, 1, '', 'p'))), []);
});
