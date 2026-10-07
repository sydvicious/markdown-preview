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

// A click on one of these buttons is the app's business and nobody else's. It
// must not go on to do whatever a click there would otherwise do, such as
// follow a link the button sits in, and it must not be heard by anything else
// listening for clicks in the page.

/// Clicks `target` with a click that can be cancelled, and says what became of
/// it: whether its default was prevented, and which of the listeners a click
/// would normally reach heard it.
function click(window, document, target) {
  const heard = [];
  target.addEventListener('click', () => heard.push('the button'));
  document.querySelector('article').addEventListener('click', () => heard.push('the article'));
  document.addEventListener('click', () => heard.push('the document'));

  const event = new window.MouseEvent('click', { bubbles: true, cancelable: true });
  const wentAhead = target.dispatchEvent(event);

  return { defaultPrevented: event.defaultPrevented, wentAhead, heard };
}

test('a click on Copy does nothing but ask the app to copy', () => {
  const { window, document, messages } = page(
    copyable('data-source-start="4" data-source-end="20" data-copy-kind="blockquote"')
  );

  const result = click(window, document, document.querySelector('[data-copy-button]'));

  assert.equal(result.defaultPrevented, true);
  assert.equal(result.wentAhead, false);
  assert.deepEqual(result.heard, []);
  assert.equal(messages.length, 1);
});

// The click is spoken for as soon as it is on the button. Whether there turns
// out to be anything to copy is a separate matter.
test('a click on Copy is kept from the page even when there is nothing to copy', () => {
  const { window, document, messages } = page(copyable('data-source-start="9" data-source-end="9"'));

  const result = click(window, document, document.querySelector('[data-copy-button]'));

  assert.equal(result.defaultPrevented, true);
  assert.deepEqual(result.heard, []);
  assert.deepEqual(plain(messages), []);
});

test('a click on something inside the Copy button is a click on the button', () => {
  const { window, document, messages } = page(
    '<blockquote class="md-block md-copyable-block" data-source-start="4" data-source-end="20">' +
    '<button type="button" data-copy-button><span class="label">Copy</span></button>' +
    '<p>Quoted line</p></blockquote>'
  );

  const result = click(window, document, document.querySelector('.label'));

  assert.equal(result.defaultPrevented, true);
  assert.deepEqual(result.heard, []);
  assert.deepEqual(plain(messages), [{ name: 'copyBlock', body: { start: 4, end: 20, kind: null } }]);
});

test('a click on the image access button does nothing but ask the app for access', () => {
  const { window, document, messages } = page(
    '<p class="md-block">before <button type="button" data-image-access-button></button> after</p>'
  );

  const result = click(window, document, document.querySelector('[data-image-access-button]'));

  assert.equal(result.defaultPrevented, true);
  assert.equal(result.wentAhead, false);
  assert.deepEqual(result.heard, []);
  assert.deepEqual(plain(messages), [{ name: 'requestImageAccess', body: {} }]);
});

// An image may be a link's text, which is how a badge is written, so the
// button that stands in for one can be inside a link. Asking for access must
// not also follow the link.
test('the image access button inside a link does not follow the link', () => {
  const { window, document, messages } = page(
    '<p class="md-block"><a href="https://example.com/">' +
    '<button type="button" data-image-access-button></button></a></p>'
  );
  let linkHeard = false;
  document.querySelector('a').addEventListener('click', () => { linkHeard = true; });

  const result = click(window, document, document.querySelector('[data-image-access-button]'));

  assert.equal(result.defaultPrevented, true);
  assert.equal(linkHeard, false);
  assert.deepEqual(plain(messages), [{ name: 'requestImageAccess', body: {} }]);
});

// Everything else in the page is left to behave as it would: a click on a
// link is still a click on a link.
test('a click anywhere else is left alone', () => {
  const { window, document, messages } = page(
    copyable('data-source-start="4" data-source-end="20"') +
    '<p class="md-block">A <a href="https://example.com/">link</a>.</p>'
  );

  const result = click(window, document, document.querySelector('a'));

  assert.equal(result.defaultPrevented, false);
  assert.equal(result.wentAhead, true);
  assert.deepEqual(result.heard, ['the button', 'the article', 'the document']);
  assert.deepEqual(plain(messages), []);
});
