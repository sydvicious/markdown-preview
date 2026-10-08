//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

/// The preview's page template, stylesheet and scripts.
///
/// They are real files rather than string literals in Swift. The files live in
/// the app's folder, `MarkdownPreview/Web`, where they sit with the views that
/// use them in Xcode's navigator; `Web` beside this file is a link to that
/// folder, which is what lets the package take them into its own bundle and
/// build a complete page without the app. As files they get an editor's syntax highlighting, a formatter and
/// a linter, their diffs are readable, and the scripts can be tested as
/// JavaScript, in a JavaScript test runner with a DOM, instead of only through
/// a web view driven from Swift.
///
/// The files ship in the package's resource bundle and are read once, on first
/// use. A file that is missing is a broken build, not a condition to recover
/// from, so it stops the process: a preview with no stylesheet or no selection
/// script would only fail later and further from the cause.
public enum MarkdownWebResources {

    /// The scripts the preview's web view runs. Each is installed as a user
    /// script; apart from the event listeners they add, all they do at load is
    /// define functions on `window.markdownPreview` for the app to call.
    public enum Script: String, CaseIterable, Sendable {
        /// The Copy button on code, quote and table blocks.
        case copyButton = "copy-button"
        /// The button that stands in for an image the app may not read.
        case imageAccessButton = "image-access-button"
        /// Reports where the reader is, and puts them back after a reload.
        case scroll
        /// The text-node walker, and reading the selection as display ranges.
        case selection
        /// The selection as HTML, for rich-text copy.
        case selectedHTML = "selected-html"
        /// Selecting a span of the rendered document.
        case applySelection = "apply-selection"
        /// Tells the app that the page's content has been read. The last, so
        /// that by the time the app hears it the others have all run.
        case contentRead = "content-read"
    }

    /// The source of `script`.
    public static func script(_ script: Script) -> String {
        scripts[script]!
    }

    /// The page every document is rendered into. `{{stylesheet}}` and
    /// `{{body}}` mark where the stylesheet and the rendered blocks go.
    static let documentTemplate = text("document", "html")

    /// The page's styles. `{{content-scale}}` marks the Dynamic Type scale
    /// factor, the one value in it that varies from one document to the next.
    static let stylesheet = text("preview", "css")

    private static let scripts: [Script: String] = Dictionary(
        uniqueKeysWithValues: Script.allCases.map { ($0, text($0.rawValue, "js")) }
    )

    private static func text(_ name: String, _ fileExtension: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Web"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("MarkdownCore's resource bundle is missing Web/\(name).\(fileExtension)")
        }
        // A file ends with a newline; what it holds does not.
        return contents.hasSuffix("\n") ? String(contents.dropLast()) : contents
    }
}
