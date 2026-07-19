// swift-tools-version: 6.2
//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//
//  The markdown engine — parser, HTML builder, and supporting types — as a
//  plain library, so it can be built and tested from the command line with
//  `swift test`, with no app host and no GUI session.
//
//  Keep this target free of SwiftUI, UIKit, and AppKit. A UI-framework import
//  here is what would push these tests back into an app host.
//
//  `Sources/MarkdownCore` is also compiled into the MarkdownPreview app target
//  by the Xcode project, so the app and this package build the same files.
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
        .target(name: "MarkdownCore"),
        // Split in two so each can be run on its own from a test plan:
        // MarkdownCoreTests is expected to pass, while the conformance suite is
        // expected to fail until the renderer catches up with the spec.
        .testTarget(name: "MarkdownCoreTests", dependencies: ["MarkdownCore"]),
        .testTarget(name: "MarkdownCoreConformanceTests", dependencies: ["MarkdownCore"]),
    ]
)
