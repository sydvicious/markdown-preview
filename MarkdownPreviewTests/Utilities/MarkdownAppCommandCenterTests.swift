//
// Copyright ©2026 Syd Polk. All Rights Reserved.
//

import Testing
@testable import MarkdownPreview

@MainActor
struct MarkdownAppCommandCenterTests {

    private func noop() {}

    @Test func performInvokesTheMatchingHandlerAndUpdatesCapabilities() {
        let center = MarkdownAppCommandCenter()
        var performed: [String] = []

        center.update(
            canFind: true, handleFind: { performed.append("find") },
            canProjectFind: true, handleProjectFind: { performed.append("projectFind") },
            canUseSelectionForFind: true, handleUseSelectionForFind: { performed.append("useSelection") },
            canFindNext: true, handleFindNext: { performed.append("next") },
            canFindPrevious: true, handleFindPrevious: { performed.append("previous") },
            canIncreaseTextSize: true, handleIncreaseTextSize: { performed.append("increase") },
            canDecreaseTextSize: true, handleDecreaseTextSize: { performed.append("decrease") },
            handleCancelSearch: { performed.append("cancel") },
            canRemoveFromList: true, handleRemoveFromList: { performed.append("remove") }
        )

        #expect(center.canFind)
        #expect(center.canRemoveFromList)

        center.performFind()
        center.performRemoveFromList()
        center.performCancelSearch()

        #expect(performed == ["find", "remove", "cancel"])
    }

    @Test func resetClearsCapabilitiesAndHandlers() {
        let center = MarkdownAppCommandCenter()
        var findCount = 0

        center.update(
            canFind: true, handleFind: { findCount += 1 },
            canProjectFind: true, handleProjectFind: noop,
            canUseSelectionForFind: true, handleUseSelectionForFind: noop,
            canFindNext: true, handleFindNext: noop,
            canFindPrevious: true, handleFindPrevious: noop,
            canIncreaseTextSize: true, handleIncreaseTextSize: noop,
            canDecreaseTextSize: true, handleDecreaseTextSize: noop,
            handleCancelSearch: noop,
            canRemoveFromList: true, handleRemoveFromList: noop
        )

        center.reset()

        #expect(!center.canFind)
        #expect(!center.canProjectFind)
        #expect(!center.canRemoveFromList)

        // Handlers were cleared, so performing a command is now a no-op.
        center.performFind()
        #expect(findCount == 0)
    }
}
