//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

// Tells the app that the page's content has been read.
//
// A page says it has loaded only when everything it refers to has arrived,
// and an image from the network can keep that back for as long as the network
// takes. The text is there long before, and with it everything the app needs
// to put a selection into the page and the reader back where they were. This
// runs when the document has been parsed, as every script here does, and
// after the others, so by the time the app hears it they are all there to
// be called.
window.webkit?.messageHandlers?.previewContentRead?.postMessage(true);
