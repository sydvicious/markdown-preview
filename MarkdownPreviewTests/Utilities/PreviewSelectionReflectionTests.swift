//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

struct PreviewSelectionReflectionTests {

    @Test func previewSelectionReflectionFindsSydInLicenseParagraph() async throws {
        let source = """
        Copyright (c) 2026, Syd Polk
        All rights reserved.
        """
        let selection = MarkdownSearch.matches(in: source, query: "Syd").first

        let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: source,
            selectedRange: selection
        )

        #expect(reflectedSelection?.blockStart == 0)
        #expect(reflectedSelection?.blockEnd == 49)
        #expect(reflectedSelection?.displayRange == MarkdownSelectionRange(location: 20, length: 3))
    }

    @Test func previewSelectionReflectionAdjustsForOrderedListOffsets() async throws {
        let source = """
        1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
        2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
        3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
        """
        let selection = MarkdownSearch.matches(in: source, query: "be").first

        let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
            in: source,
            selectedRange: selection
        )

        #expect(reflectedSelection?.blockStart == 0)
        #expect(reflectedSelection?.blockEnd == source.utf16.count)
        #expect(reflectedSelection?.displayRange == MarkdownSelectionRange(location: 405, length: 2))
    }

    @Test func previewSelectionReflectionMapsVisibleSearchMatchesInsideMixedMarkdownBlocks() async throws {
        let source = """
        Paragraph with [beta](https://example.com), **gamma**, and `delta`.

        1. Theta item
        2. Iota item

        | Name | Count |
        | --- | ---: |
        | Lambda | 12 |
        """
        let queries = ["beta", "gamma", "delta", "Iota", "Lambda", "12"]

        for query in queries {
            guard let selection = MarkdownSearch.matches(in: source, query: query).first else {
                Issue.record("Expected source match for \(query)")
                continue
            }

            guard let reflectedSelection = PreviewSelectionReflection.reflectedSelection(
                in: source,
                selectedRange: selection
            ) else {
                Issue.record("Expected reflected selection for \(query)")
                continue
            }

            let blockSource = (source as NSString).substring(
                with: NSRange(
                    location: reflectedSelection.blockStart,
                    length: reflectedSelection.blockEnd - reflectedSelection.blockStart
                )
            )
            let previewMapping = MarkdownPreviewTextOffsetMapping(sourceText: blockSource)
            let previewSnippet = (previewMapping.displayText as NSString).substring(
                with: reflectedSelection.displayRange.nsRange
            )

            #expect(previewSnippet == query)
        }
    }
}
