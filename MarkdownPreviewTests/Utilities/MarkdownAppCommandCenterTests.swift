//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Testing

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

    // MARK: - Every command, and every capability, one at a time

    /// The nine things a menu or a key can ask for.
    enum Command: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case find, projectFind, useSelectionForFind, findNext, findPrevious
        case increaseTextSize, decreaseTextSize, cancelSearch, removeFromList

        var testDescription: String { rawValue }

        @MainActor
        func perform(on center: MarkdownAppCommandCenter) {
            switch self {
            case .find: center.performFind()
            case .projectFind: center.performProjectFind()
            case .useSelectionForFind: center.performUseSelectionForFind()
            case .findNext: center.performFindNext()
            case .findPrevious: center.performFindPrevious()
            case .increaseTextSize: center.performIncreaseTextSize()
            case .decreaseTextSize: center.performDecreaseTextSize()
            case .cancelSearch: center.performCancelSearch()
            case .removeFromList: center.performRemoveFromList()
            }
        }
    }

    /// The eight commands a menu item is enabled or disabled for. Cancelling a
    /// search has no item of its own to enable.
    enum Capability: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case find, projectFind, useSelectionForFind, findNext, findPrevious
        case increaseTextSize, decreaseTextSize, removeFromList

        var testDescription: String { rawValue }

        @MainActor
        func isOffered(by center: MarkdownAppCommandCenter) -> Bool {
            switch self {
            case .find: center.canFind
            case .projectFind: center.canProjectFind
            case .useSelectionForFind: center.canUseSelectionForFind
            case .findNext: center.canFindNext
            case .findPrevious: center.canFindPrevious
            case .increaseTextSize: center.canIncreaseTextSize
            case .decreaseTextSize: center.canDecreaseTextSize
            case .removeFromList: center.canRemoveFromList
            }
        }
    }

    /// Records which commands were carried out, in order.
    @MainActor
    private final class Log {
        var performed: [Command] = []
    }

    /// Gives `center` a handler for every command that writes its own name in
    /// `log`, and offers exactly the capabilities in `offered`.
    private func update(
        _ center: MarkdownAppCommandCenter,
        logging log: Log,
        offering offered: Set<Capability> = []
    ) {
        center.update(
            canFind: offered.contains(.find),
            handleFind: { log.performed.append(.find) },
            canProjectFind: offered.contains(.projectFind),
            handleProjectFind: { log.performed.append(.projectFind) },
            canUseSelectionForFind: offered.contains(.useSelectionForFind),
            handleUseSelectionForFind: { log.performed.append(.useSelectionForFind) },
            canFindNext: offered.contains(.findNext),
            handleFindNext: { log.performed.append(.findNext) },
            canFindPrevious: offered.contains(.findPrevious),
            handleFindPrevious: { log.performed.append(.findPrevious) },
            canIncreaseTextSize: offered.contains(.increaseTextSize),
            handleIncreaseTextSize: { log.performed.append(.increaseTextSize) },
            canDecreaseTextSize: offered.contains(.decreaseTextSize),
            handleDecreaseTextSize: { log.performed.append(.decreaseTextSize) },
            handleCancelSearch: { log.performed.append(.cancelSearch) },
            canRemoveFromList: offered.contains(.removeFromList),
            handleRemoveFromList: { log.performed.append(.removeFromList) }
        )
    }

    /// Find Next must not find the previous match, nor Larger make the text
    /// smaller: each command reaches its own handler and no other.
    @Test(arguments: Command.allCases)
    func eachCommandIsCarriedOutByItsOwnHandlerAndNoOther(command: Command) {
        let center = MarkdownAppCommandCenter()
        let log = Log()
        update(center, logging: log)

        command.perform(on: center)

        #expect(log.performed == [command])
    }

    @Test func commandsAreCarriedOutInTheOrderTheyAreAskedFor() {
        let center = MarkdownAppCommandCenter()
        let log = Log()
        update(center, logging: log)

        for command in Command.allCases {
            command.perform(on: center)
        }
        center.performFindNext()
        center.performFindNext()

        #expect(log.performed == Command.allCases + [.findNext, .findNext])
    }

    /// A menu item is enabled by its own command's flag and no other's.
    @Test(arguments: Capability.allCases)
    func eachCapabilityIsOfferedByItsOwnFlagAndNoOther(capability: Capability) {
        let center = MarkdownAppCommandCenter()
        update(center, logging: Log(), offering: [capability])

        for other in Capability.allCases {
            #expect(other.isOffered(by: center) == (other == capability), "\(other)")
        }
    }

    @Test func everyCapabilityCanBeOfferedAtOnce() {
        let center = MarkdownAppCommandCenter()
        update(center, logging: Log(), offering: Set(Capability.allCases))

        for capability in Capability.allCases {
            #expect(capability.isOffered(by: center), "\(capability)")
        }
    }

    /// Before a window has told it anything, nothing is offered and asking for
    /// a command does nothing.
    @Test(arguments: Command.allCases)
    func beforeAnyWindowHasSpokenACommandDoesNothing(command: Command) {
        let center = MarkdownAppCommandCenter()

        command.perform(on: center)

        for capability in Capability.allCases {
            #expect(!capability.isOffered(by: center), "\(capability)")
        }
    }

    /// A window that has gone must not be left holding the menus: after a
    /// reset nothing is offered and none of its handlers can be reached.
    @Test(arguments: Command.allCases)
    func afterAResetNoCommandReachesTheOldHandlers(command: Command) {
        let center = MarkdownAppCommandCenter()
        let log = Log()
        update(center, logging: log, offering: Set(Capability.allCases))

        center.reset()
        command.perform(on: center)

        #expect(log.performed.isEmpty)
        for capability in Capability.allCases {
            #expect(!capability.isOffered(by: center), "\(capability)")
        }
    }

    /// What the window says last is what holds: its handlers replace the ones
    /// before, and so do its capabilities.
    @Test(arguments: Command.allCases)
    func aLaterUpdateReplacesTheHandlersBeforeIt(command: Command) {
        let center = MarkdownAppCommandCenter()
        let earlier = Log()
        let later = Log()
        update(center, logging: earlier, offering: Set(Capability.allCases))

        update(center, logging: later, offering: [.find])
        command.perform(on: center)

        #expect(earlier.performed.isEmpty)
        #expect(later.performed == [command])
        for capability in Capability.allCases {
            #expect(capability.isOffered(by: center) == (capability == .find), "\(capability)")
        }
    }
}
