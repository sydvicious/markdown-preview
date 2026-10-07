//
// Copyright ©2026 Syd Polk. All Rights Reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

/// Keeps the last value made for a key, and makes another only when asked for
/// a key that is not the last one.
final class LastValueCache<Key: Equatable, Value> {
    private var last: (key: Key, value: Value)?

    func value(for key: Key, make: () -> Value) -> Value {
        if let last, last.key == key {
            return last.value
        }
        let value = make()
        last = (key, value)
        return value
    }
}
