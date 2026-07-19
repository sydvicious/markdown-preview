//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Foundation
import Testing
import MarkdownCore
@testable import MarkdownPreview

struct HTMLTextOffsetMappingTests {

    @Test func htmlTextOffsetMappingStripsTagsAndDecodesEntities() async throws {
        let html = "<html><body><p>Alpha &amp; <strong>beta</strong></p></body></html>"
        let mapping = HTMLTextOffsetMapping(sourceText: html)

        #expect(mapping.displayText == "Alpha & beta")

        let ampersandRange = mapping.sourceRange(
            forDisplayRange: MarkdownSelectionRange(location: 6, length: 1)
        )
        #expect(ampersandRange?.range(in: html).map { String(html[$0]) } == "&amp;")
    }
}
