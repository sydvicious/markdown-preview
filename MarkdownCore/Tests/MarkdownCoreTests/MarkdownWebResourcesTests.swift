//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing
@testable import MarkdownCore

/// The page template, stylesheet and scripts are files in `Web`, shipped in
/// the package's resource bundle. What the scripts do is tested as JavaScript,
/// in `Tests/WebTests`; these check the Swift side of the seam — that every
/// file is in the bundle, and that a page is put together from them correctly.
struct MarkdownWebResourcesTests {

    @Test func everyScriptIsInTheBundle() {
        for script in MarkdownWebResources.Script.allCases {
            #expect(!MarkdownWebResources.script(script).isEmpty, "\(script.rawValue).js")
        }
    }

    // The app calls these by name. A function renamed in a script and not in
    // the app fails silently in a web view: the call simply finds nothing.
    @Test func theScriptsDefineTheFunctionsTheAppCalls() {
        let functions: [(MarkdownWebResources.Script, String)] = [
            (.selection, "window.markdownPreview.acceptedTextNodesInBlock ="),
            (.selection, "window.markdownPreview.selectedDisplayRanges ="),
            (.selection, "window.markdownPreview.selectionSnapshot ="),
            (.selectedHTML, "window.markdownPreview.selectedHTML ="),
            (.applySelection, "window.markdownPreview.applySelection ="),
            (.scroll, "window.markdownPreview.scrollPosition ="),
            (.scroll, "window.markdownPreview.scrollToOffset ="),
            (.scroll, "window.markdownPreview.scrollToFraction ="),
        ]

        for (script, definition) in functions {
            #expect(MarkdownWebResources.script(script).contains(definition), "\(script.rawValue).js: \(definition)")
        }
    }

    @Test func theTemplateAndStylesheetCarryEachPlaceholderOnce() {
        #expect(MarkdownWebResources.documentTemplate.components(separatedBy: "{{stylesheet}}").count == 2)
        #expect(MarkdownWebResources.documentTemplate.components(separatedBy: "{{body}}").count == 2)
        #expect(MarkdownWebResources.stylesheet.components(separatedBy: "{{content-scale}}").count == 2)
    }

    @Test func aDocumentIsTheTemplateWithEveryPlaceholderFilled() {
        let html = MarkdownHTMLBuilder.document(for: "Hello *world*", contentScale: 1.5)

        #expect(html.hasPrefix("<!doctype html>\n"))
        #expect(html.hasSuffix("</html>"))
        #expect(html.contains("--content-scale: 1.5;"))
        #expect(html.contains(".md-copy-button {"))
        #expect(html.contains("Hello <em>world</em>"))
        #expect(!html.contains("{{"))
    }

    // The document's text is placed last and never searched, so a document
    // that happens to mention a placeholder shows it as the text it is.
    @Test func aDocumentThatMentionsAPlaceholderShowsItAsText() {
        let html = MarkdownHTMLBuilder.document(for: "Use {{body}}, {{stylesheet}} and {{content-scale}} here.")

        #expect(html.contains("Use {{body}}, {{stylesheet}} and {{content-scale}} here."))
        #expect(html.components(separatedBy: ".md-copy-button {").count == 2)
        #expect(html.components(separatedBy: "--content-scale: 1.0;").count == 2)
    }
}
