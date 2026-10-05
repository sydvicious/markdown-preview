// swift-tools-version: 6.2
//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//
//  The markdown engine — parser, HTML builder, and supporting types — as a
//  plain library, so it can be built and tested from the command line with
//  `swift test`, with no app host and no GUI session.
//
//  Keep this target free of SwiftUI, UIKit, and AppKit. A UI-framework import
//  here is what would push these tests back into an app host.
//
//  The MarkdownPreview app links this library and imports it as a module, so
//  the app and these tests run the same build of the engine.
//

import PackageDescription

let package = Package(
    name: "MarkdownCore",
    // Must cover every platform the app ships on: the library is compiled into
    // the iOS and iPadOS builds too, and Xcode will not offer a package's test
    // targets to a scheme whose destinations the package does not support.
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"])
    ],
    targets: [
        .target(
            name: "MarkdownCore",
            // The preview's page template, stylesheet and scripts, copied as
            // the folder they are so nothing in it is renamed or flattened.
            // `Web` here is a link to `MarkdownPreview/Web`, where the files
            // live; the build copies what it points at, not the link.
            resources: [.copy("Web")]
        ),
        // Split in two so each can be run on its own from a test plan:
        // MarkdownCoreTests is expected to pass, while the conformance suite is
        // expected to fail until the renderer catches up with the spec.
        .testTarget(name: "MarkdownCoreTests", dependencies: ["MarkdownCore"]),
        .testTarget(name: "MarkdownCoreConformanceTests", dependencies: ["MarkdownCore"]),
    ]
)
