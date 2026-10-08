//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

/// A document as it has been read: its blocks, its link reference
/// definitions, and where its lines are.
///
/// Reading a document is the first thing done to build its page, and the
/// first thing done to place a selection in it, and for a long document it is
/// most of what either costs: 90 ms for 1.4 MB. A reading is that work done
/// once. The page is built from it, somewhere other than the main actor, and
/// it goes with the page to whoever places a selection there.
public struct MarkdownReading: Sendable {
    public let source: String
    public let lineTable: MarkdownSourceLineTable
    public let blocks: [MarkdownBlock]
    /// The definitions found anywhere in `source`.
    public let definitions: MarkdownLinkDefinitions

    /// Reads `source`, all of it. This is the work, so it is done wherever
    /// this is called.
    public init(of source: String) {
        let parsed = MarkdownBlockParser.parseDocument(source)
        self.source = source
        lineTable = MarkdownSourceLineTable(source: source)
        blocks = parsed.blocks
        definitions = parsed.definitions
    }
}
