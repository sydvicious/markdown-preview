//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

final class FileOpenState: ObservableObject {
    /// Shared instance so the macOS app delegate and the SwiftUI scene enqueue
    /// into the same queue.
    static let shared = FileOpenState()

    /// Queue of URLs handed to the app by the system. A multi-file open delivers
    /// every URL together (macOS `application(_:open:)`) or one at a time (iOS
    /// `.onOpenURL`), so they are accumulated here and drained together rather
    /// than overwriting a single slot (which dropped all but one file).
    @Published var pendingURLs: [URL] = []
    @Published var didReceiveExternalOpenRequest = false

    func enqueue(_ url: URL) {
        didReceiveExternalOpenRequest = true
        pendingURLs.append(url)
    }

    func enqueue(_ urls: [URL]) {
        urls.forEach(enqueue)
    }
}

#if os(macOS)
/// macOS delivers a batch "Open" (for example several files selected in Finder)
/// through `application(_:open:)` as a single array. SwiftUI's `.onOpenURL` only
/// surfaces one of them, so the app delegate handles opens on macOS instead.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        FileOpenState.shared.enqueue(urls)
    }
}
#endif

private struct MarkdownPreviewCommands: Commands {
    @ObservedObject var commandCenter: MarkdownAppCommandCenter

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Remove from List") {
                commandCenter.performRemoveFromList()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(!commandCenter.canRemoveFromList)
        }

        CommandMenu("Find") {
            Button("Find") {
                commandCenter.performFind()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(!commandCenter.canFind)

            Button("Find in Files") {
                commandCenter.performProjectFind()
            }
            .keyboardShortcut("F", modifiers: [.command, .shift])
            .disabled(!commandCenter.canProjectFind)

            Button("Use Selection for Find") {
                commandCenter.performUseSelectionForFind()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!commandCenter.canUseSelectionForFind)

            Divider()

            Button("Find Next") {
                commandCenter.performFindNext()
            }
            .keyboardShortcut("g", modifiers: [.command])
            .disabled(!commandCenter.canFindNext)

            Button("Find Previous") {
                commandCenter.performFindPrevious()
            }
            .keyboardShortcut("G", modifiers: [.command, .shift])
            .disabled(!commandCenter.canFindPrevious)
        }

        CommandMenu("View") {
            Button("Increase Text Size") {
                commandCenter.performIncreaseTextSize()
            }
            .keyboardShortcut("=", modifiers: [.command])
            .disabled(!commandCenter.canIncreaseTextSize)

            Button("Decrease Text Size") {
                commandCenter.performDecreaseTextSize()
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(!commandCenter.canDecreaseTextSize)
        }

        CommandMenu("Search") {
            Button("Cancel Search") {
                commandCenter.performCancelSearch()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
    }
}

@main
struct MarkdownPreviewApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var fileOpenState = FileOpenState.shared
    @StateObject private var commandCenter = MarkdownAppCommandCenter()

    var body: some Scene {
        #if os(macOS)
        Window("Markdown Preview", id: "main") {
            ContentView()
                .environmentObject(commandCenter)
                .environmentObject(fileOpenState)
        }
        .commands {
            MarkdownPreviewCommands(commandCenter: commandCenter)
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(commandCenter)
                .environmentObject(fileOpenState)
                .onOpenURL { url in
                    fileOpenState.enqueue(url)
                }
        }
        .commands {
            MarkdownPreviewCommands(commandCenter: commandCenter)
        }
        #endif
    }
}
