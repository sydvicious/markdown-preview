//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// Stands up a page like the preview's, with the scripts under test running in
// it, so they can be exercised as JavaScript against a real DOM instead of only
// through a web view driven from Swift.
//
// The scripts are loaded from the files the app ships, unmodified, and run the
// way a user script runs: evaluated in the page once it has been parsed.

import { JSDOM } from 'jsdom';
import { readFileSync } from 'node:fs';

// The package's view of the folder, which is a link to MarkdownPreview/Web.
const webFolder = new URL('../../Sources/MarkdownCore/Web/', import.meta.url);

/// `body` is the markup inside the page's <article>; `scripts` names the files
/// in the Web folder to run, without their extension.
export function loadPage(body, scripts) {
  const dom = new JSDOM(
    `<!doctype html><html><body><article>${body}</article></body></html>`,
    { runScripts: 'outside-only', pretendToBeVisual: true }
  );
  const { window } = dom;

  // What the page says to the app. In the app each handler is registered by
  // name; here every name answers, and what it was sent is kept.
  const messages = [];
  window.webkit = {
    messageHandlers: new Proxy({}, {
      get: (_, name) => ({ postMessage: (message) => messages.push({ name, body: message }) })
    })
  };

  // jsdom lays nothing out, so it cannot scroll and has no geometry. Every
  // request to scroll is recorded, and then carried out the way a page would:
  // as far as there is page, and no further. `scrolling.ignored` makes the page
  // take no notice, for a request that goes astray.
  const scrolls = [];
  const scrolling = { ignored: false };
  window.scrollTo = (...args) => {
    scrolls.push(args);
    if (scrolling.ignored) {
      return;
    }
    // Either `scrollTo(x, y)` or `scrollTo({ left, top })`.
    const [x, y] = typeof args[0] === 'object' ? [args[0].left, args[0].top] : args;
    const maxY = Math.max(0, window.document.documentElement.scrollHeight - window.innerHeight);
    setScrollGeometry(window, { x, y: y === undefined ? undefined : Math.min(Math.max(0, y), maxY) });
  };
  if (!window.Range.prototype.getBoundingClientRect) {
    window.Range.prototype.getBoundingClientRect = () => ({ top: 0, left: 0, width: 0, height: 0 });
  }

  for (const name of scripts) {
    window.eval(readFileSync(new URL(`${name}.js`, webFolder), 'utf8'));
  }

  return { window, document: window.document, preview: window.markdownPreview, messages, scrolls, scrolling };
}

/// A block as the renderer emits one: its source offsets on the element.
export function block(start, end, inner, tag = 'p') {
  return `<${tag} class="md-block" data-source-start="${start}" data-source-end="${end}">${inner}</${tag}>`;
}

/// Selects from `startOffset` in `startNode` to `endOffset` in `endNode`.
export function select(window, startNode, startOffset, endNode, endOffset) {
  const range = window.document.createRange();
  range.setStart(startNode, startOffset);
  range.setEnd(endNode, endOffset);
  const selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
  return range;
}

/// Gives the page a size and a scroll offset, which jsdom otherwise lacks.
/// Whatever is left out stays as it was.
export function setScrollGeometry(window, { x, y, pageHeight, viewportHeight }) {
  const set = (object, name, value) => {
    if (value !== undefined) {
      Object.defineProperty(object, name, { value, configurable: true });
    }
  };
  set(window, 'scrollX', x);
  set(window, 'scrollY', y);
  set(window, 'innerHeight', viewportHeight);
  set(window.document.documentElement, 'scrollHeight', pageHeight);
}

/// The page is a separate JavaScript world with its own `Array` and `Object`,
/// so a value it produced never strictly equals one written in a test, however
/// alike they look. This copies one across.
export const plain = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));

export const tick = (milliseconds = 0) => new Promise((resolve) => setTimeout(resolve, milliseconds));
