//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// Reading the selection: what the reader has selected, reported as ranges of
// each block's rendered text, which is what the app maps back to the source.

import test from 'node:test';
import assert from 'node:assert/strict';
import { loadPage, block, select, plain, reports, settle } from './preview-page.mjs';

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
    { blockStart: 0, blockEnd: 12, displayLocation: 11, displayLength: 4, continuesPastText: true },
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
  await reports(messages);

  // Two events in the same turn are one report.
  assert.deepEqual(plain(messages), [{
    name: 'previewSelectionChanged',
    body: {
      text: 'paragraph',
      ranges: [{ blockStart: 14, blockEnd: 30, displayLocation: 7, displayLength: 9 }]
    }
  }]);
});

// A selection made by dragging starts and ends inside text. One made by Select
// All, or by a triple-click, starts and ends at an element instead: "before the
// first child of the article", "after the last child of this paragraph". Those
// are the same selections to the reader, so they are the same ranges.

test('Select All is the whole of every block', () => {
  const { window, document, preview } = page();
  window.getSelection().selectAllChildren(document.querySelector('article'));

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 0, displayLength: 15, continuesPastText: true },
    { blockStart: 14, blockEnd: 30, displayLocation: 0, displayLength: 16, continuesPastText: true }
  ]);
});

test('a selection from the page itself, not its article, is still every block', () => {
  const { window, document, preview } = page();
  window.getSelection().selectAllChildren(document.body);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 0, displayLength: 15, continuesPastText: true },
    { blockStart: 14, blockEnd: 30, displayLocation: 0, displayLength: 16, continuesPastText: true }
  ]);
});

test('a block selected from its first child to its last is the whole block', () => {
  const { window, preview, blocks } = page();
  select(window, blocks[1], 0, blocks[1], blocks[1].childNodes.length);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 14, blockEnd: 30, displayLocation: 0, displayLength: 16 }
  ]);
});

// A triple-click selects a paragraph by running the selection on to the start
// of the next one. That next paragraph has nothing selected in it, and must
// not be reported as if it had. What the selection did do is go on after the
// last text it took, which is how the app knows the line was taken with its
// ending: a selection dragged to the end of the line stops there, and takes no
// ending.
test('a triple-click that ends at the start of the next block is the first block alone', () => {
  const { window, preview, blocks } = page();
  select(window, blocks[0].firstChild, 0, blocks[1], 0);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 0, displayLength: 15, continuesPastText: true }
  ]);
});

test('a selection that ends just after its block goes on past its text', () => {
  const { window, document, preview, blocks } = page();
  select(window, blocks[0].firstChild, 0, document.querySelector('article'), 1);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 0, displayLength: 15, continuesPastText: true }
  ]);
});

// The items of a list are one block. Clicking three times on one of them runs
// the selection on to the start of the next item, inside the same block.
const list =
  '<div class="md-block" data-source-start="0" data-source-end="17">' +
  '<ul><li>one</li><li>two</li><li>three</li></ul></div>';

test('a triple-click on a list item goes on past its text, inside the list', () => {
  const { window, document, preview } = page(list);
  const items = document.querySelectorAll('li');
  select(window, items[1].firstChild, 0, items[2].firstChild, 0);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 17, displayLocation: 3, displayLength: 3, continuesPastText: true }
  ]);
});

test('a selection dragged to the end of a list item stops with its text', () => {
  const { window, document, preview } = page(list);
  const item = document.querySelectorAll('li')[1].firstChild;
  select(window, item, 0, item, item.textContent.length);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 17, displayLocation: 3, displayLength: 3 }
  ]);
});

test('a selection that ends with the last of its block\'s text does not go on past it', () => {
  const { window, preview, blocks } = page();
  const last = blocks[0].lastChild;
  select(window, blocks[0].firstChild, 0, last, last.textContent.length);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 0, displayLength: 15 }
  ]);
});

test('a selection that starts at the end of one block is the next block alone', () => {
  const { window, preview, blocks } = page();
  select(window, blocks[0], blocks[0].childNodes.length, blocks[1], blocks[1].childNodes.length);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 14, blockEnd: 30, displayLocation: 0, displayLength: 16 }
  ]);
});

test('ends that fall between the children of a block select what is between them', () => {
  const { window, preview, blocks } = page();
  // After "First " and before " text": the bold word and nothing else.
  select(window, blocks[0], 1, blocks[0], 2);

  assert.equal(window.getSelection().toString(), 'bold');
  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 6, displayLength: 4 }
  ]);
});

test('ends inside an inline element select its text', () => {
  const { window, preview, blocks } = page();
  const strong = blocks[0].querySelector('strong');
  select(window, strong, 0, strong, 1);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 6, displayLength: 4 }
  ]);
});

test('one end in text and the other at an element is the span between them', () => {
  const { window, preview, blocks } = page();
  // From the "s" of "First" to the end of the block.
  select(window, blocks[0].firstChild, 3, blocks[0], blocks[0].childNodes.length);

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 12, displayLocation: 3, displayLength: 12 }
  ]);
});

// Select All takes in the Copy button too. Its label is not part of the
// document, and counting it would put every offset in the block out by four.
test('Select All does not count the label of a Copy button', () => {
  const { window, document, preview } = page(
    '<blockquote class="md-block md-copyable-block" data-source-start="0" data-source-end="13">' +
    '<button type="button" class="md-copy-button" data-copy-button>Copy</button>' +
    '<p>Quoted line</p></blockquote>' +
    block(15, 31, 'Second paragraph')
  );
  window.getSelection().selectAllChildren(document.querySelector('article'));

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 13, displayLocation: 0, displayLength: 11, continuesPastText: true },
    { blockStart: 15, blockEnd: 31, displayLocation: 0, displayLength: 16, continuesPastText: true }
  ]);
});

// The line breaks and indentation the markup of a list is laid out with are
// not text. Select All covers them and they must not be counted.
test('Select All does not count the whitespace a list is laid out with', () => {
  const { window, document, preview } = page(
    '<ul class="md-block" data-source-start="0" data-source-end="11">\n' +
    '  <li>One</li>\n' +
    '  <li>Two</li>\n' +
    '</ul>\n' +
    block(13, 29, 'Second paragraph')
  );
  window.getSelection().selectAllChildren(document.querySelector('article'));

  assert.deepEqual(plain(preview.selectedDisplayRanges()), [
    { blockStart: 0, blockEnd: 11, displayLocation: 0, displayLength: 6, continuesPastText: true },
    { blockStart: 13, blockEnd: 29, displayLocation: 0, displayLength: 16, continuesPastText: true }
  ]);
});

// What tells the page the selection may have changed differs by how it was
// changed: a drag with a mouse or a pen ends in `pointerup`, one with a finger
// in `touchend`, the keyboard in `keyup`, and `selectionchange` covers the
// rest. Each on its own has to be enough.
//
// Making a selection here sets off a `selectionchange` of jsdom's own, a moment
// later. So each test first lets that one be heard and reported, and only then
// sends the event it is about, with the selection left as it is. The report
// that follows can have come from nothing else.

/// A page with "paragraph" selected in its second block, after the report
/// that making the selection set off has been and gone.
async function pageWithASelectionAlreadyReported() {
  const loaded = page();
  const text = loaded.blocks[1].firstChild;
  select(loaded.window, text, 7, text, 16);
  await reports(loaded.messages);
  loaded.messages.length = 0;
  return loaded;
}

const paragraphSelected = {
  name: 'previewSelectionChanged',
  body: {
    text: 'paragraph',
    ranges: [{ blockStart: 14, blockEnd: 30, displayLocation: 7, displayLength: 9 }]
  }
};

for (const eventName of ['selectionchange', 'touchend', 'pointerup', 'keyup']) {
  test(`the selection is reported to the app after ${eventName} alone`, async () => {
    const { window, document, messages } = await pageWithASelectionAlreadyReported();

    document.dispatchEvent(new window.Event(eventName, { bubbles: true }));
    await reports(messages);

    assert.deepEqual(plain(messages), [paragraphSelected]);
  });
}

test('an event the page does not listen for reports nothing', async () => {
  const { window, document, messages } = await pageWithASelectionAlreadyReported();

  document.dispatchEvent(new window.Event('mousemove', { bubbles: true }));
  document.dispatchEvent(new window.Event('scroll', { bubbles: true }));
  await settle();

  assert.deepEqual(plain(messages), []);
});

test('a finger lifted anywhere in the page reports the selection', async () => {
  const { window, messages, blocks } = await pageWithASelectionAlreadyReported();

  // The event starts at a paragraph and reaches the document by bubbling.
  blocks[0].dispatchEvent(new window.Event('touchend', { bubbles: true }));
  await reports(messages);

  assert.deepEqual(plain(messages), [paragraphSelected]);
});

test('all four events in the same turn are one report', async () => {
  const { window, document, messages } = await pageWithASelectionAlreadyReported();

  for (const eventName of ['pointerup', 'touchend', 'selectionchange', 'keyup']) {
    document.dispatchEvent(new window.Event(eventName, { bubbles: true }));
  }
  await reports(messages);

  assert.deepEqual(plain(messages), [paragraphSelected]);
});

// The app has to hear that a selection has gone as well as that one was made,
// or it goes on showing the old one.
test('clearing the selection is reported to the app as no ranges', async () => {
  const { window, messages } = await pageWithASelectionAlreadyReported();

  window.getSelection().removeAllRanges();
  await reports(messages);

  assert.deepEqual(plain(messages), [{
    name: 'previewSelectionChanged',
    body: { text: null, ranges: [] }
  }]);
});

test('Select All is reported to the app as every block', async () => {
  const { window, document, messages } = page();
  window.getSelection().selectAllChildren(document.querySelector('article'));
  await reports(messages);

  assert.equal(messages.length, 1);
  assert.deepEqual(plain(messages[0].body.ranges), [
    { blockStart: 0, blockEnd: 12, displayLocation: 0, displayLength: 15, continuesPastText: true },
    { blockStart: 14, blockEnd: 30, displayLocation: 0, displayLength: 16, continuesPastText: true }
  ]);
});
