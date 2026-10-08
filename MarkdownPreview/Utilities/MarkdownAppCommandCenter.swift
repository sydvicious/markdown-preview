//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import SwiftUI

@MainActor
final class MarkdownAppCommandCenter: ObservableObject {
    @Published private(set) var canFind = false
    @Published private(set) var canProjectFind = false
    @Published private(set) var canUseSelectionForFind = false
    @Published private(set) var canFindNext = false
    @Published private(set) var canFindPrevious = false
    @Published private(set) var canIncreaseTextSize = false
    @Published private(set) var canDecreaseTextSize = false
    @Published private(set) var canRemoveFromList = false

    private var handleFind: (() -> Void)?
    private var handleProjectFind: (() -> Void)?
    private var handleUseSelectionForFind: (() -> Void)?
    private var handleFindNext: (() -> Void)?
    private var handleFindPrevious: (() -> Void)?
    private var handleIncreaseTextSize: (() -> Void)?
    private var handleDecreaseTextSize: (() -> Void)?
    private var handleCancelSearch: (() -> Void)?
    private var handleRemoveFromList: (() -> Void)?

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
        handleCancelSearch: @escaping () -> Void,
        canRemoveFromList: Bool,
        handleRemoveFromList: @escaping () -> Void
    ) {
        // Whoever draws the menus is redrawn each time one of these announces
        // a change, and this is called after nearly everything the window
        // does, nearly always offering what it offered before. So only what
        // differs is set. The handlers are taken every time: they are not
        // watched, and a later one may close over something newer.
        set(\.canFind, to: canFind)
        self.handleFind = handleFind
        set(\.canProjectFind, to: canProjectFind)
        self.handleProjectFind = handleProjectFind
        set(\.canUseSelectionForFind, to: canUseSelectionForFind)
        self.handleUseSelectionForFind = handleUseSelectionForFind
        set(\.canFindNext, to: canFindNext)
        self.handleFindNext = handleFindNext
        set(\.canFindPrevious, to: canFindPrevious)
        self.handleFindPrevious = handleFindPrevious
        set(\.canIncreaseTextSize, to: canIncreaseTextSize)
        self.handleIncreaseTextSize = handleIncreaseTextSize
        set(\.canDecreaseTextSize, to: canDecreaseTextSize)
        self.handleDecreaseTextSize = handleDecreaseTextSize
        self.handleCancelSearch = handleCancelSearch
        set(\.canRemoveFromList, to: canRemoveFromList)
        self.handleRemoveFromList = handleRemoveFromList
    }

    func reset() {
        set(\.canFind, to: false)
        set(\.canProjectFind, to: false)
        set(\.canUseSelectionForFind, to: false)
        set(\.canFindNext, to: false)
        set(\.canFindPrevious, to: false)
        set(\.canIncreaseTextSize, to: false)
        set(\.canDecreaseTextSize, to: false)
        set(\.canRemoveFromList, to: false)
        handleFind = nil
        handleProjectFind = nil
        handleUseSelectionForFind = nil
        handleFindNext = nil
        handleFindPrevious = nil
        handleIncreaseTextSize = nil
        handleDecreaseTextSize = nil
        handleCancelSearch = nil
        handleRemoveFromList = nil
    }

    /// Sets a capability if it is not already so. Setting one announces a
    /// change whether or not the value is a new one.
    private func set(_ capability: ReferenceWritableKeyPath<MarkdownAppCommandCenter, Bool>, to value: Bool) {
        guard self[keyPath: capability] != value else { return }
        self[keyPath: capability] = value
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

    func performRemoveFromList() {
        handleRemoveFromList?()
    }
}

private struct CommandCenterKey: EnvironmentKey {
    static let defaultValue: MarkdownAppCommandCenter? = nil
}

extension EnvironmentValues {
    /// The app's command center, for a view that tells it what the window
    /// offers and reads nothing back.
    ///
    /// Handed over this way, and not as an environment object, because a view
    /// is redrawn whenever an environment object it declares announces a
    /// change, whether or not it reads anything of it. The window's content
    /// only ever writes to the center, and it writes after nearly every
    /// change, so as an environment object each of those redrew the whole
    /// window a second time. The menus, which do read it, observe it.
    var commandCenter: MarkdownAppCommandCenter? {
        get { self[CommandCenterKey.self] }
        set { self[CommandCenterKey.self] = newValue }
    }
}
