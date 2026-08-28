import Foundation

/// A source of the current wall-clock time.
///
/// Code that calls `Date()` directly cannot be tested against a specific moment. The usual
/// symptoms are a test that fails at midnight, on the last day of a month, during a
/// daylight-saving transition, or only when the machine is slow enough that two `Date()`
/// calls straddle a second boundary — each of which reproduces roughly never.
///
/// Injecting this instead makes those cases ordinary tests rather than accidents waiting
/// for the calendar.
///
/// ## Which clock is which
///
/// Swift's standard library has a `Clock` protocol (`ContinuousClock`, `SuspendingClock`)
/// concerned with *durations and sleeping*. This is a different thing: the wall-clock
/// reading that `Date()` returns. Both matter, and they are not substitutes.
///
/// ## Example
///
/// ```swift
/// struct Report {
///     let clock: any WallClock
///     func generate() -> String { "as of \(clock.now)" }
/// }
///
/// // Production
/// Report(clock: SystemWallClock())
///
/// // Test — a specific, chosen moment
/// Report(clock: FixedWallClock(at: .fixture))
/// ```
public protocol WallClock: Sendable {

    /// The current moment.
    ///
    /// Read once per logical operation rather than repeatedly: two readings of a real
    /// clock differ, and code that assumes otherwise fails at a second boundary.
    var now: Date { get }
}

/// The real clock.
///
/// The production implementation, and the only one that consults the operating system.
public struct SystemWallClock: WallClock {

    /// Creates a system clock.
    public init() {}

    /// The current moment, from the operating system.
    public var now: Date { Date() }
}

/// A clock stopped at a chosen moment.
///
/// Every reading returns the same value, which is what makes a test that formats or
/// compares timestamps assert an exact string rather than a tolerance.
public struct FixedWallClock: WallClock {

    /// The moment this clock reports.
    public let instant: Date

    /// Creates a stopped clock.
    ///
    /// - Parameter instant: The moment every reading returns.
    public init(at instant: Date) {
        self.instant = instant
    }

    /// The moment this clock was stopped at. Never changes.
    public var now: Date { instant }
}

/// A clock that advances only when told to.
///
/// For code whose behaviour depends on time *passing* — an expiring token, a cache, a
/// retry backoff. Waiting for real seconds to elapse makes a suite slow and, worse,
/// timing-dependent: the same test passes on a fast machine and fails on a loaded one.
///
/// ```swift
/// struct Credential {
///     let expiresAt: Date
///     func hasExpired(now: Date) -> Bool { now >= expiresAt }
/// }
/// func issue(using clock: any WallClock) -> Credential {
///     Credential(expiresAt: clock.now.addingTimeInterval(3600))
/// }
///
/// let clock = ManualWallClock(at: .fixture)
/// let credential = issue(using: clock)      // expires in 3600s
///
/// clock.advance(by: 3599)
/// precondition(!credential.hasExpired(now: clock.now))
/// clock.advance(by: 2)
/// precondition(credential.hasExpired(now: clock.now))
/// ```
///
/// A reference type deliberately: callers hold the same clock and one of them advances it.
/// A value type would give each holder its own frozen copy, which is exactly the bug this
/// is meant to avoid.
// Justification: mutable `instant` is guarded by `lock`; no other state exists.
public final class ManualWallClock: WallClock, @unchecked Sendable {

    private let lock = NSLock()
    private var instant: Date

    /// Creates a clock stopped at a moment, which only ``advance(by:)`` and ``set(to:)``
    /// will move.
    ///
    /// - Parameter instant: The starting moment.
    public init(at instant: Date) {
        self.instant = instant
    }

    /// The current moment.
    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    /// Moves the clock forward.
    ///
    /// - Parameter interval: Seconds to advance. Negative values move it back, which is
    ///   occasionally what a test of clock skew needs.
    public func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        instant = instant.addingTimeInterval(interval)
    }

    /// Moves the clock to a specific moment.
    ///
    /// - Parameter instant: The new moment.
    public func set(to instant: Date) {
        lock.lock()
        defer { lock.unlock() }
        self.instant = instant
    }
}

extension Date {

    /// A fixed, arbitrary moment for tests: **2026-01-01 00:00:00 UTC**.
    ///
    /// Having one shared fixture means test expectations across projects are written
    /// against the same instant, and a date appearing in a failure message is recognisable
    /// rather than needing to be decoded.
    ///
    /// Deliberately not "now minus something": a fixture derived from the present is not a
    /// fixture.
    public static let fixture = Date(timeIntervalSince1970: 1_767_225_600)
}
