//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

final class FileOpenState: ObservableObject {
    @Published var openedURL: URL?
    @Published var didReceiveExternalOpenRequest = false
}

@main
struct MarkdownPreviewApp: App {
    @StateObject private var fileOpenState = FileOpenState()

    var body: some Scene {
        #if os(macOS)
        Window("Markdown Preview", id: "main") {
            ContentView()
                .environmentObject(fileOpenState)
                .onOpenURL { url in
                    fileOpenState.didReceiveExternalOpenRequest = true
                    fileOpenState.openedURL = url
                }
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(fileOpenState)
                .onOpenURL { url in
                    fileOpenState.didReceiveExternalOpenRequest = true
                    fileOpenState.openedURL = url
                }
        }
        #endif
    }
}
