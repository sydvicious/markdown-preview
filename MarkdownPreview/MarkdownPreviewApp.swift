//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    /// Narrowest the window may be dragged, chosen so the in-document search bar
    /// stays fully laid out at the floor rather than compressing.
    ///
    /// At this width the search has already moved out of the title bar and into
    /// the detail pane (see `ContentViewModel.detailSearchToolbarDropoutWidth`),
    /// which is the intended look here — the pane gives the field more room than
    /// the toolbar ever did. Verified against the largest text size this Mac
    /// offers, so it is a floor for that case too, not just the default size.
    static let minimumWindowWidth: CGFloat = 550

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    /// Held without observation on purpose. This is the process-wide singleton,
    /// so its lifetime needs no help from `@StateObject` — and observing it here
    /// would invalidate the `Scene` body every time a file is opened, since
    /// `enqueue` publishes twice. `ContentView` observes it through
    /// `@EnvironmentObject`, which is where the change actually needs to land.
    private let fileOpenState = FileOpenState.shared
    @StateObject private var commandCenter = MarkdownAppCommandCenter()

    var body: some Scene {
        #if os(macOS)
        Window("Markdown Preview", id: "main") {
            ContentView()
                .environment(\.commandCenter, commandCenter)
                .environmentObject(fileOpenState)
                .frame(minWidth: Self.minimumWindowWidth)
        }
        .commands {
            MarkdownPreviewCommands(commandCenter: commandCenter)
        }
        #else
        WindowGroup {
            ContentView()
                .environment(\.commandCenter, commandCenter)
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
