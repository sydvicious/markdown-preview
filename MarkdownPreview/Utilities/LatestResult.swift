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
/// Results are kept, so that going back to a document does not build its page
/// again: as many as asked for, or all of them. A result can be said to
/// replace another, as the page of a document replaces the page of how the
/// document was before it changed.
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
    /// How many to keep, or nil to keep them all.
    private let capacity: Int?
    private let replaces: (_ newer: Request, _ older: Request) -> Bool
    /// What is being worked out, if anything is.
    private var underWay: Request?
    /// Counts the requests that started work, so that one finishing can tell
    /// whether it is still the one wanted.
    private var latestStarted = 0

    /// - Parameters:
    ///   - capacity: how many results to keep, the current one among them, or
    ///     nil to keep every one.
    ///   - replacing: whether a result for `newer` leaves one for `older` not
    ///     worth keeping.
    ///   - work: works out the result. It is awaited from the main actor and
    ///     runs wherever it puts itself, which should be somewhere else.
    ///   - patience: returns when a request has been under way long enough to
    ///     say so.
    init(
        keeping capacity: Int? = 1,
        replacing: @escaping (_ newer: Request, _ older: Request) -> Bool = { _, _ in false },
        work: @escaping @Sendable (Request) async -> Result,
        patience: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: .milliseconds(500)) }
    ) {
        self.capacity = capacity.map { max(1, $0) }
        self.replaces = replacing
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

        guard latestStarted == started else {
            // No longer the one wanted. The work has been done and it may be
            // wanted again, so it is kept, unless what is kept already
            // includes something newer that replaces it.
            if !kept.contains(where: { replaces($0.request, request) }) {
                keep(result, for: request)
            }
            return
        }
        keep(result, for: request)
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

    /// Keeps `result` as the one shown last. It takes the place of whatever
    /// it replaces, and if there is a limit and no room, the one shown longest
    /// ago goes.
    private func keep(_ result: Result, for request: Request) {
        kept.removeAll { $0.request == request || replaces(request, $0.request) }
        kept.append((request, result))
        if let capacity, kept.count > capacity {
            kept.removeFirst(kept.count - capacity)
        }
    }
}
