//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import SwiftUI

final class FileOpenState: ObservableObject {
    @Published var openedURL: URL?
    @Published var didReceiveExternalOpenRequest = false
}

@MainActor
final class MarkdownAppCommandCenter: ObservableObject {
    @Published private(set) var canFind = false
    @Published private(set) var canProjectFind = false
    @Published private(set) var canUseSelectionForFind = false
    @Published private(set) var canFindNext = false
    @Published private(set) var canFindPrevious = false
    @Published private(set) var canIncreaseTextSize = false
    @Published private(set) var canDecreaseTextSize = false

    private var handleFind: (() -> Void)?
    private var handleProjectFind: (() -> Void)?
    private var handleUseSelectionForFind: (() -> Void)?
    private var handleFindNext: (() -> Void)?
    private var handleFindPrevious: (() -> Void)?
    private var handleIncreaseTextSize: (() -> Void)?
    private var handleDecreaseTextSize: (() -> Void)?
    private var handleCancelSearch: (() -> Void)?

    func update(
        canFind: Bool,
        handleFind: @escaping () -> Void,
        canProjectFind: Bool,
        handleProjectFind: @escaping () -> Void,
        canUseSelectionForFind: Bool,
        handleUseSelectionForFind: @escaping () -> Void,
        canFindNext: Bool,
        handleFindNext: @escaping () -> Void,
        canFindPrevious: Bool,
        handleFindPrevious: @escaping () -> Void,
        canIncreaseTextSize: Bool,
        handleIncreaseTextSize: @escaping () -> Void,
        canDecreaseTextSize: Bool,
        handleDecreaseTextSize: @escaping () -> Void,
        handleCancelSearch: @escaping () -> Void
    ) {
        self.canFind = canFind
        self.handleFind = handleFind
        self.canProjectFind = canProjectFind
        self.handleProjectFind = handleProjectFind
        self.canUseSelectionForFind = canUseSelectionForFind
        self.handleUseSelectionForFind = handleUseSelectionForFind
        self.canFindNext = canFindNext
        self.handleFindNext = handleFindNext
        self.canFindPrevious = canFindPrevious
        self.handleFindPrevious = handleFindPrevious
        self.canIncreaseTextSize = canIncreaseTextSize
        self.handleIncreaseTextSize = handleIncreaseTextSize
        self.canDecreaseTextSize = canDecreaseTextSize
        self.handleDecreaseTextSize = handleDecreaseTextSize
        self.handleCancelSearch = handleCancelSearch
    }

    func reset() {
        canFind = false
        canProjectFind = false
        canUseSelectionForFind = false
        canFindNext = false
        canFindPrevious = false
        canIncreaseTextSize = false
        canDecreaseTextSize = false
        handleFind = nil
        handleProjectFind = nil
        handleUseSelectionForFind = nil
        handleFindNext = nil
        handleFindPrevious = nil
        handleIncreaseTextSize = nil
        handleDecreaseTextSize = nil
        handleCancelSearch = nil
    }

    func performFind() {
        handleFind?()
    }

    func performProjectFind() {
        handleProjectFind?()
    }

    func performUseSelectionForFind() {
        handleUseSelectionForFind?()
    }

    func performFindNext() {
        handleFindNext?()
    }

    func performFindPrevious() {
        handleFindPrevious?()
    }

    func performIncreaseTextSize() {
        handleIncreaseTextSize?()
    }

    func performDecreaseTextSize() {
        handleDecreaseTextSize?()
    }

    func performCancelSearch() {
        handleCancelSearch?()
    }
}

private struct MarkdownPreviewCommands: Commands {
    @ObservedObject var commandCenter: MarkdownAppCommandCenter

    var body: some Commands {
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
    @StateObject private var fileOpenState = FileOpenState()
    @StateObject private var commandCenter = MarkdownAppCommandCenter()

    var body: some Scene {
        #if os(macOS)
        Window("Markdown Preview", id: "main") {
            ContentView()
                .environmentObject(commandCenter)
                .environmentObject(fileOpenState)
                .onOpenURL { url in
                    fileOpenState.didReceiveExternalOpenRequest = true
                    fileOpenState.openedURL = url
                }
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
                    fileOpenState.didReceiveExternalOpenRequest = true
                    fileOpenState.openedURL = url
                }
        }
        .commands {
            MarkdownPreviewCommands(commandCenter: commandCenter)
        }
        #endif
    }
}
