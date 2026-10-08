//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Testing

/// The preview builds its HTML through one of these: off the main actor, for
/// the document now wanted, with the page before it left showing meanwhile.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LatestResultTests {

    /// Stands in for the work, and for the wait before saying it is taking
    /// long. It keeps what it was asked for, and the test says when each piece
    /// of work is finished and when each wait is over.
    @MainActor
    private final class Held {
        private var working: [(request: String, finish: CheckedContinuation<String, Never>)] = []
        private var waits: [CheckedContinuation<Void, Never>?] = []
        /// Every request work was started for, in order.
        private(set) var started: [String] = []

        var work: @Sendable (String) async -> String {
            { @MainActor [self] request in
                await withCheckedContinuation { continuation in
                    started.append(request)
                    working.append((request, continuation))
                }
            }
        }

        var patience: @Sendable () async -> Void {
            { @MainActor [self] in
                await withCheckedContinuation { waits.append($0) }
            }
        }

        /// How many waits have begun.
        var waitsBegun: Int { waits.count }

        /// Finishes the oldest work under way for `request`.
        func finish(_ request: String, with result: String) {
            guard let index = working.firstIndex(where: { $0.request == request }) else {
                Issue.record("No work under way for \(request)")
                return
            }
            working.remove(at: index).finish.resume(returning: result)
        }

        /// Ends the wait that began `index`th, counting from nothing.
        func endWait(_ index: Int) {
            guard waits.indices.contains(index), let wait = waits[index] else {
                Issue.record("No wait \(index) to end")
                return
            }
            waits[index] = nil
            wait.resume()
        }

        /// Lets go of everything still held, so that nothing is left waiting
        /// when a test is over.
        func letGo() {
            working.forEach { $0.finish.resume(returning: "let go") }
            working = []
            waits.indices.forEach { index in
                waits[index]?.resume()
                waits[index] = nil
            }
        }
    }

    private typealias Latest = LatestResult<String, String>

    private func makeLatest(_ held: Held, keeping capacity: Int = 1) -> Latest {
        Latest(keeping: capacity, work: held.work, patience: held.patience)
    }

    /// Asks for each in turn, finishing each before the next is asked for.
    private func show(_ requests: [String], in latest: Latest, held: Held) async {
        for request in requests {
            let asking = await ask(request, of: latest, held: held, startingWork: held.started.count + 1)
            held.finish(request, with: "<p>\(request)</p>")
            await asking.value
        }
    }

    /// Waits for something that is on its way, and gives up after two seconds
    /// if it never comes.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    /// Lets everything already queued on the main actor have its turn.
    private func settle() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    /// Asks for something that should be answered with no more work. If work
    /// is started for it after all, that is said, and the work is let go, so
    /// that the test fails here and does not wait out its time limit.
    private func answeredAtOnce(_ request: String, by latest: Latest, held: Held) async {
        let workBefore = held.started.count
        let asking = Task { await latest.ask(request) }
        await settle()
        if held.started.count != workBefore {
            Issue.record("Asking for \(request) started work")
            held.letGo()
        }
        await asking.value
    }

    /// Asks, and waits until the work for it is under way.
    private func ask(_ request: String, of latest: Latest, held: Held, startingWork: Int) async -> Task<Void, Never> {
        let asking = Task { await latest.ask(request) }
        #expect(await eventually { held.started.count == startingWork })
        return asking
    }

    // MARK: - Results

    @Test func nothingIsCurrentUntilTheWorkIsFinished() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)

        let asking = await ask("plan", of: latest, held: held, startingWork: 1)
        #expect(latest.current == nil)

        held.finish("plan", with: "<p>plan</p>")
        await asking.value

        #expect(latest.current?.request == "plan")
        #expect(latest.current?.result == "<p>plan</p>")
    }

    @Test func askingForWhatIsCurrentDoesNoWork() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let asking = await ask("plan", of: latest, held: held, startingWork: 1)
        held.finish("plan", with: "<p>plan</p>")
        await asking.value

        await answeredAtOnce("plan", by: latest, held: held)

        #expect(held.started == ["plan"])
        #expect(latest.current?.result == "<p>plan</p>")
    }

    /// Switching from one document to another: the page before stays until the
    /// next is ready.
    @Test func theResultBeforeStaysCurrentWhileTheNextIsWorkedOut() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let first = await ask("plan", of: latest, held: held, startingWork: 1)
        held.finish("plan", with: "<p>plan</p>")
        await first.value

        let second = await ask("notes", of: latest, held: held, startingWork: 2)
        #expect(latest.current?.request == "plan")

        held.finish("notes", with: "<p>notes</p>")
        await second.value
        #expect(latest.current?.request == "notes")
        #expect(latest.current?.result == "<p>notes</p>")
    }

    @Test func aRequestThatALaterOneReplacedIsDroppedWhenItFinishes() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let first = await ask("plan", of: latest, held: held, startingWork: 1)
        let second = await ask("notes", of: latest, held: held, startingWork: 2)

        held.finish("plan", with: "<p>plan</p>")
        await first.value
        #expect(latest.current == nil)

        held.finish("notes", with: "<p>notes</p>")
        await second.value
        #expect(latest.current?.request == "notes")
    }

    @Test func aRequestThatALaterOneReplacedIsDroppedEvenIfItFinishesLast() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let first = await ask("plan", of: latest, held: held, startingWork: 1)
        let second = await ask("notes", of: latest, held: held, startingWork: 2)

        held.finish("notes", with: "<p>notes</p>")
        await second.value
        held.finish("plan", with: "<p>plan</p>")
        await first.value

        #expect(latest.current?.request == "notes")
        #expect(latest.current?.result == "<p>notes</p>")
    }

    @Test func askingAgainForWhatIsUnderWayStartsNoMoreWork() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let asking = await ask("plan", of: latest, held: held, startingWork: 1)

        await answeredAtOnce("plan", by: latest, held: held)
        #expect(held.started == ["plan"])

        held.finish("plan", with: "<p>plan</p>")
        await asking.value
        #expect(latest.current?.request == "plan")
    }

    /// On to another document and straight back: the page showing is the one
    /// wanted, and the other is not.
    @Test func goingBackToWhatIsCurrentAbandonsTheRequestUnderWay() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let first = await ask("plan", of: latest, held: held, startingWork: 1)
        held.finish("plan", with: "<p>plan</p>")
        await first.value
        let second = await ask("notes", of: latest, held: held, startingWork: 2)

        await answeredAtOnce("plan", by: latest, held: held)
        #expect(held.started == ["plan", "notes"])

        held.finish("notes", with: "<p>notes</p>")
        await second.value
        #expect(latest.current?.request == "plan")
        #expect(latest.isTakingLong == false)
    }

    // MARK: - Results kept

    /// To another document and back: the page it had is still there.
    @Test func goingBackToAResultStillKeptDoesNoWork() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held, keeping: 2)
        await show(["plan", "notes"], in: latest, held: held)

        await answeredAtOnce("plan", by: latest, held: held)

        #expect(held.started == ["plan", "notes"])
        #expect(latest.current?.request == "plan")
        #expect(latest.current?.result == "<p>plan</p>")
    }

    @Test func noMoreResultsAreKeptThanWasAskedFor() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held, keeping: 2)
        await show(["plan", "notes", "todo"], in: latest, held: held)

        // The two kept are the last two. The first has gone, and is worked
        // out again.
        await answeredAtOnce("notes", by: latest, held: held)
        #expect(held.started == ["plan", "notes", "todo"])
        _ = await ask("plan", of: latest, held: held, startingWork: 4)
        #expect(held.started == ["plan", "notes", "todo", "plan"])
    }

    /// What goes when there is no room is what was shown longest ago, and
    /// going back to a result counts as showing it.
    @Test func theResultThatGoesIsTheOneShownLongestAgo() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held, keeping: 2)
        await show(["plan", "notes"], in: latest, held: held)
        await answeredAtOnce("plan", by: latest, held: held)
        await show(["todo"], in: latest, held: held)

        await answeredAtOnce("plan", by: latest, held: held)
        #expect(held.started == ["plan", "notes", "todo"])
        #expect(latest.current?.request == "plan")

        _ = await ask("notes", of: latest, held: held, startingWork: 4)
        #expect(held.started == ["plan", "notes", "todo", "notes"])
    }

    @Test func goingBackToAResultStillKeptAbandonsTheRequestUnderWay() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held, keeping: 3)
        await show(["plan", "notes"], in: latest, held: held)
        let third = await ask("todo", of: latest, held: held, startingWork: 3)
        #expect(await eventually { held.waitsBegun == 3 })
        held.endWait(2)
        #expect(await eventually { latest.isTakingLong })

        await answeredAtOnce("plan", by: latest, held: held)
        #expect(latest.current?.request == "plan")
        #expect(latest.isTakingLong == false)

        held.finish("todo", with: "<p>todo</p>")
        await third.value
        #expect(latest.current?.request == "plan")
    }

    /// The work was done, though by then something else was wanted. Its
    /// result is not shown, and is there if it is wanted again.
    @Test func aResultFinishedAfterItWasReplacedIsKeptForLater() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held, keeping: 2)
        let first = await ask("plan", of: latest, held: held, startingWork: 1)
        let second = await ask("notes", of: latest, held: held, startingWork: 2)
        held.finish("plan", with: "<p>plan</p>")
        await first.value
        held.finish("notes", with: "<p>notes</p>")
        await second.value
        #expect(latest.current?.request == "notes")

        await answeredAtOnce("plan", by: latest, held: held)

        #expect(held.started == ["plan", "notes"])
        #expect(latest.current?.request == "plan")
        #expect(latest.current?.result == "<p>plan</p>")
    }

    // MARK: - Taking long

    @Test func aRequestStillUnderWayWhenTheWaitEndsIsTakingLong() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let asking = await ask("plan", of: latest, held: held, startingWork: 1)
        #expect(await eventually { held.waitsBegun == 1 })
        #expect(latest.isTakingLong == false)

        held.endWait(0)
        #expect(await eventually { latest.isTakingLong })

        held.finish("plan", with: "<p>plan</p>")
        await asking.value
        #expect(latest.isTakingLong == false)
    }

    @Test func aRequestFinishedBeforeTheWaitEndsIsNeverTakingLong() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let asking = await ask("plan", of: latest, held: held, startingWork: 1)
        #expect(await eventually { held.waitsBegun == 1 })
        held.finish("plan", with: "<p>plan</p>")
        await asking.value

        held.endWait(0)
        await settle()

        #expect(latest.isTakingLong == false)
    }

    /// The wait that ends belongs to a request that is no longer the one
    /// wanted. The one that is has its own wait, not over yet.
    @Test func theWaitOfARequestSinceReplacedSaysNothing() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        _ = await ask("plan", of: latest, held: held, startingWork: 1)
        _ = await ask("notes", of: latest, held: held, startingWork: 2)
        #expect(await eventually { held.waitsBegun == 2 })

        held.endWait(0)
        await settle()
        #expect(latest.isTakingLong == false)

        held.endWait(1)
        #expect(await eventually { latest.isTakingLong })
    }

    /// Already waiting on one document when another is asked for: the reader
    /// is still waiting, so it still says so.
    @Test func aNewRequestWhileOneIsTakingLongIsStillTakingLong() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        _ = await ask("plan", of: latest, held: held, startingWork: 1)
        #expect(await eventually { held.waitsBegun == 1 })
        held.endWait(0)
        #expect(await eventually { latest.isTakingLong })

        let second = await ask("notes", of: latest, held: held, startingWork: 2)
        #expect(latest.isTakingLong)

        held.finish("notes", with: "<p>notes</p>")
        await second.value
        #expect(latest.isTakingLong == false)
        #expect(latest.current?.request == "notes")
    }

    @Test func goingBackToWhatIsCurrentIsNoLongerTakingLong() async {
        let held = Held()
        defer { held.letGo() }
        let latest = makeLatest(held)
        let first = await ask("plan", of: latest, held: held, startingWork: 1)
        held.finish("plan", with: "<p>plan</p>")
        await first.value
        _ = await ask("notes", of: latest, held: held, startingWork: 2)
        #expect(await eventually { held.waitsBegun == 2 })
        held.endWait(1)
        #expect(await eventually { latest.isTakingLong })

        await answeredAtOnce("plan", by: latest, held: held)

        #expect(latest.isTakingLong == false)
    }
}
