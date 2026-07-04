//
// Copyright ©2026 Syd Polk. All Rights Reserved.
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
        self.canRemoveFromList = canRemoveFromList
        self.handleRemoveFromList = handleRemoveFromList
    }

    func reset() {
        canFind = false
        canProjectFind = false
        canUseSelectionForFind = false
        canFindNext = false
        canFindPrevious = false
        canIncreaseTextSize = false
        canDecreaseTextSize = false
        canRemoveFromList = false
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
