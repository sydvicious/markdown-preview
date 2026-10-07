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

// Blocks as the renderer writes them: each in its wrapper, a line apart.
const paragraphBlock =
  '<div class="md-block" data-source-start="0" data-source-end="14"><p>Earlier text.</p></div>';
const headingBlock =
  '<div class="md-block" data-source-start="16" data-source-end="51">' +
  '<h3>Async file loading off <code>@Main</code>.</h3></div>';
const listBlock =
  '<div class="md-block" data-source-start="52" data-source-end="96">' +
  '<ul><li>Read source files.</li><li>Show a spinner.</li></ul></div>';
const quoteBlock =
  '<div class="md-block md-copyable-block" data-copy-kind="blockquote" data-source-start="52" data-source-end="66">' +
  '<button type="button" class="md-copy-button" data-copy-button>Copy</button>' +
  '<blockquote><p>Quoted line.</p></blockquote></div>';
const ruleBlock = '<div class="md-block" data-source-start="52" data-source-end="55"><hr></div>';

const headingText = (document) => document.querySelector('h3').firstChild;

// Clicking three times on a line selects it up to the start of whatever comes
// next. Nothing of the next block is selected, but it was copied all the same,
// emptied: a list arrived as a bullet with nothing beside it.
test('a selection that stops at the start of the next block\'s text leaves that block out', () => {
  const { window, document, preview } = loadPage(`${headingBlock}\n${listBlock}`, ['selected-html']);
  select(window, headingText(document), 0, document.querySelector('li').firstChild, 0);

  assert.equal(preview.selectedHTML().trim(), headingBlock);
});

test('a selection that stops just inside the next block leaves that block out', () => {
  const { window, document, preview } = loadPage(`${headingBlock}\n${listBlock}`, ['selected-html']);
  select(window, headingText(document), 0, document.querySelector('li'), 0);

  assert.equal(preview.selectedHTML().trim(), headingBlock);
});

// A block with a Copy button has the button ahead of its text, so a selection
// that stops at the text has passed the button and nothing else.
test('a selection that stops at the start of a block with a Copy button leaves that block out', () => {
  const { window, document, preview } = loadPage(`${headingBlock}\n${quoteBlock}`, ['selected-html']);
  select(window, headingText(document), 0, document.querySelector('blockquote p').firstChild, 0);

  assert.equal(preview.selectedHTML().trim(), headingBlock);
});

test('a selection that starts at the end of the block before leaves that block out', () => {
  const { window, document, preview } = loadPage(`${paragraphBlock}\n${headingBlock}`, ['selected-html']);
  const earlier = document.querySelector('p').firstChild;
  const heading = document.querySelector('h3');
  select(window, earlier, earlier.textContent.length, heading, heading.childNodes.length);

  assert.equal(preview.selectedHTML().trim(), headingBlock);
});

test('a selection that takes the first word of the next block keeps it', () => {
  const { window, document, preview } = loadPage(`${headingBlock}\n${listBlock}`, ['selected-html']);
  select(window, headingText(document), 0, document.querySelector('li').firstChild, 4);

  assert.equal(
    preview.selectedHTML(),
    `${headingBlock}\n<div class="md-block" data-source-start="52" data-source-end="96"><ul><li>Read</li></ul></div>`
  );
});

// A rule has no text, and is still something the reader selected.
test('a rule at the end of a selection is kept', () => {
  const { window, document, preview } = loadPage(`${headingBlock}\n${ruleBlock}`, ['selected-html']);
  const rule = document.querySelector('hr').parentElement;
  select(window, headingText(document), 0, rule, 1);

  assert.equal(preview.selectedHTML(), `${headingBlock}\n${ruleBlock}`);
});

test('a selection that stops just before a rule leaves it out', () => {
  const { window, document, preview } = loadPage(`${headingBlock}\n${ruleBlock}`, ['selected-html']);
  const rule = document.querySelector('hr').parentElement;
  select(window, headingText(document), 0, rule, 0);

  assert.equal(preview.selectedHTML().trim(), headingBlock);
});

test('a selection of nothing but whitespace is no HTML', () => {
  const { window, document, preview } = loadPage(block(0, 10, 'one   two'), ['selected-html']);
  const text = document.querySelector('.md-block').firstChild;
  select(window, text, 3, text, 6);

  assert.equal(preview.selectedHTML(), null);
});
