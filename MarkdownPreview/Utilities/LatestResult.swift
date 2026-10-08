//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Combine

/// Works out a result for the latest thing asked for, off the main actor, and
/// keeps the last one finished.
///
/// The preview builds its HTML through one. Building it takes as long as the
/// document is big, and done on the main actor the window stops answering
/// until it is over. Here the page before stays current while the next is
/// built; a request that a later one has replaced is not shown when it
/// finishes; and one that outlasts `patience` is said to be taking long, which
/// is when the preview shows that it is working.
///
/// The last few results are kept, so that going back to a document does not
/// build its page again.
@MainActor
final class LatestResult<Request: Equatable & Sendable, Result: Sendable>: ObservableObject {
    /// The last result finished, and what was asked for to get it.
    @Published private(set) var current: (request: Request, result: Result)?
    /// Whether the reader has been waiting long enough to be told so.
    ///
    /// It stays true from one request to the next while they wait, and is
    /// false again once a result is current.
    @Published private(set) var isTakingLong = false

    private let work: @Sendable (Request) async -> Result
    private let patience: @Sendable () async -> Void
    /// The results kept, the one shown longest ago first.
    private var kept: [(request: Request, result: Result)] = []
    private let capacity: Int
    /// What is being worked out, if anything is.
    private var underWay: Request?
    /// Counts the requests that started work, so that one finishing can tell
    /// whether it is still the one wanted.
    private var latestStarted = 0

    /// - Parameters:
    ///   - capacity: how many results to keep, the current one among them.
    ///   - work: works out the result. It is awaited from the main actor and
    ///     runs wherever it puts itself, which should be somewhere else.
    ///   - patience: returns when a request has been under way long enough to
    ///     say so.
    init(
        keeping capacity: Int = 1,
        work: @escaping @Sendable (Request) async -> Result,
        patience: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: .milliseconds(500)) }
    ) {
        self.capacity = max(1, capacity)
        self.work = work
        self.patience = patience
    }

    /// Asks for the result of `request`.
    ///
    /// Returns once that result is current, or as soon as it is known that
    /// this call has nothing to do: the result is current already, the same
    /// request is under way from an earlier call, or a later request has
    /// replaced this one.
    func ask(_ request: Request) async {
        if current?.request == request {
            // Back to what is showing. Whatever was under way is not wanted.
            abandonWhatIsUnderWay()
            return
        }
        if let index = kept.firstIndex(where: { $0.request == request }) {
            // Worked out before, and still here.
            let found = kept[index]
            abandonWhatIsUnderWay()
            keep(found.result, for: found.request)
            current = found
            return
        }
        guard underWay != request else { return }

        latestStarted += 1
        let started = latestStarted
        underWay = request

        let wait = Task { [weak self, patience] in
            await patience()
            guard let self, !Task.isCancelled, self.latestStarted == started, self.underWay != nil else { return }
            self.isTakingLong = true
        }
        let result = await work(request)
        wait.cancel()

        // Kept whether or not it is still wanted: the work has been done, and
        // it may be wanted again.
        keep(result, for: request)
        guard latestStarted == started else { return }
        current = (request, result)
        underWay = nil
        isTakingLong = false
    }

    private func abandonWhatIsUnderWay() {
        guard underWay != nil else { return }
        latestStarted += 1
        underWay = nil
        isTakingLong = false
    }

    /// Keeps `result` as the one shown last, and lets go of the one shown
    /// longest ago if there is no room.
    private func keep(_ result: Result, for request: Request) {
        kept.removeAll { $0.request == request }
        kept.append((request, result))
        if kept.count > capacity {
            kept.removeFirst(kept.count - capacity)
        }
    }
}
