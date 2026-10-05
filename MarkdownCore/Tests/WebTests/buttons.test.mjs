//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// The two buttons the renderer puts in a document: Copy, on a quote, code or
// table block, and the one that stands in for an image the app may not read.
// Neither does anything itself; each tells the app what was asked for.

import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPage, select, plain } from './preview-page.mjs';

const copyable = (attributes, inner = '<p>Quoted line</p>') =>
  `<blockquote class="md-block md-copyable-block" ${attributes}>` +
  '<button type="button" class="md-copy-button" data-copy-button>Copy</button>' +
  `${inner}</blockquote>`;

function page(body) {
  return loadPage(body, ['copy-button', 'image-access-button']);
}

test('Copy asks the app to copy its block, naming the span and the kind', () => {
  const { document, messages } = page(
    copyable('data-source-start="4" data-source-end="20" data-copy-kind="blockquote"')
  );

  document.querySelector('[data-copy-button]').click();

  assert.deepEqual(plain(messages), [
    { name: 'copyBlock', body: { start: 4, end: 20, kind: 'blockquote' } }
  ]);
});

test('Copy on a block with no kind still copies', () => {
  const { document, messages } = page(copyable('data-source-start="0" data-source-end="5"'));

  document.querySelector('[data-copy-button]').click();

  assert.deepEqual(plain(messages), [{ name: 'copyBlock', body: { start: 0, end: 5, kind: null } }]);
});

test('Copy clears the selection, so the block is what gets copied', () => {
  const { window, document } = page(
    copyable('data-source-start="4" data-source-end="20"')
  );
  const text = document.querySelector('p').firstChild;
  select(window, text, 0, text, 6);

  document.querySelector('[data-copy-button]').click();

  assert.equal(window.getSelection().rangeCount, 0);
});

test('Copy says nothing when its block has no usable span', () => {
  const noSpan = page(copyable('data-source-start="9" data-source-end="9"'));
  noSpan.document.querySelector('[data-copy-button]').click();

  const notNumbers = page(copyable('data-source-start="x" data-source-end="y"'));
  notNumbers.document.querySelector('[data-copy-button]').click();

  const noBlock = page('<button type="button" data-copy-button>Copy</button>');
  noBlock.document.querySelector('[data-copy-button]').click();

  assert.deepEqual(plain(noSpan.messages), []);
  assert.deepEqual(plain(notNumbers.messages), []);
  assert.deepEqual(plain(noBlock.messages), []);
});

test('the button in place of an unreadable image asks the app for access', () => {
  const { document, messages } = page(
    '<p class="md-block">before <button type="button" class="md-image-access-button" ' +
    'data-image-access-button data-label="Allow…"></button> after</p>'
  );

  document.querySelector('[data-image-access-button]').click();

  assert.deepEqual(plain(messages), [{ name: 'requestImageAccess', body: {} }]);
});

test('a click anywhere else is not a request', () => {
  const { document, messages } = page(
    copyable('data-source-start="4" data-source-end="20"') +
    '<p class="md-block">before <button type="button" data-image-access-button></button> after</p>'
  );

  document.querySelector('blockquote p').click();
  document.querySelector('.md-block:last-child').click();

  assert.deepEqual(plain(messages), []);
});
