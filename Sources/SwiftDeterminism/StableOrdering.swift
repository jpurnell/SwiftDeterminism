import Foundation

/// Ordering helpers for collections whose iteration order is not stable.
///
/// **Swift seeds its hasher per process.** `Dictionary` and `Set` iterate in an order
/// derived from that seed, so the *same binary* on the *same input* enumerates differently
/// between runs. This is deliberate — it defends against hash-flooding — and it means any
/// test that compares enumerated output to an expected list is a coin flip with good odds.
///
/// The failure mode is characteristic: it passes for weeks, fails once in CI, passes on
/// retry, and gets recorded as flakiness. Nothing about the diff suggests ordering.
///
/// These helpers make the ordering explicit at the point where it matters, which is
/// cheaper than either sorting defensively everywhere or discovering the problem later.
public enum StableOrdering {

    /// A dictionary's entries, ordered by key.
    ///
    /// - Parameter dictionary: The dictionary to order.
    /// - Returns: Key–value pairs in ascending key order.
    public static func byKey<Key: Comparable, Value>(
        _ dictionary: [Key: Value]
    ) -> [(key: Key, value: Value)] {
        dictionary.sorted { $0.key < $1.key }
    }

    /// A dictionary's values, ordered by their keys.
    ///
    /// The common case when asserting: the keys are incidental and the values are the
    /// subject, but the values still have to arrive in a fixed order.
    ///
    /// - Parameter dictionary: The dictionary to order.
    /// - Returns: Values in ascending key order.
    public static func valuesByKey<Key: Comparable, Value>(
        _ dictionary: [Key: Value]
    ) -> [Value] {
        byKey(dictionary).map(\.value)
    }
}

extension Dictionary where Key: Comparable {

    /// Entries in ascending key order.
    ///
    /// Use this anywhere a dictionary's contents are serialised, logged, hashed, or
    /// compared — `Dictionary`'s own iteration order varies between processes.
    public var stablyOrdered: [(key: Key, value: Value)] {
        StableOrdering.byKey(self)
    }

    /// Values in ascending key order.
    public var valuesInKeyOrder: [Value] {
        StableOrdering.valuesByKey(self)
    }
}

extension Set where Element: Comparable {

    /// Members in ascending order.
    ///
    /// `Set` has no inherent order, so enumerating one directly into output makes that
    /// output vary between runs.
    public var stablyOrdered: [Element] {
        sorted()
    }
}

extension Sequence {

    /// Elements ordered by a key, with ties broken by a second key.
    ///
    /// Sorting on a single non-unique key leaves tied elements in whatever order they
    /// arrived, which for a dictionary or a concurrent collection is not stable. Supplying
    /// a tiebreak makes the result total.
    ///
    /// - Parameters:
    ///   - primary: The main ordering key.
    ///   - tiebreak: Distinguishes elements the primary key ranks equally.
    /// - Returns: The elements, totally ordered.
    public func stablySorted<A: Comparable, B: Comparable>(
        by primary: (Element) -> A,
        tiebreak: (Element) -> B
    ) -> [Element] {
        sorted { lhs, rhs in
            let left = primary(lhs)
            let right = primary(rhs)
            if left != right { return left < right }
            return tiebreak(lhs) < tiebreak(rhs)
        }
    }
}
