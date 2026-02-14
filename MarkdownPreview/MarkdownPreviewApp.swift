import SwiftUI

final class FileOpenState: ObservableObject {
    @Published var openedURL: URL?
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
                    fileOpenState.openedURL = url
                }
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(fileOpenState)
                .onOpenURL { url in
                    fileOpenState.openedURL = url
                }
        }
        #endif
    }
}
