import Foundation

/// A source of unique identifiers.
///
/// `UUID()` draws from the system CSPRNG, so anything that mints one cannot be asserted
/// against an expected value, cannot be compared between two runs, and produces a diff full
/// of noise when its output is serialised into a snapshot or a fixture.
///
/// Injecting this makes an identifier a value the test chooses.
///
/// ## Example
///
/// ```swift
/// struct Account {
///     let id: UUID
///     let name: String
/// }
///
/// struct Directory {
///     let identifiers: any IdentifierSource
///     mutating func add(_ name: String) -> Account {
///         Account(id: identifiers.next(), name: name)
///     }
/// }
///
/// Directory(identifiers: SystemIdentifierSource())        // production
/// Directory(identifiers: SeededIdentifierSource(seed: 1)) // test
/// ```
public protocol IdentifierSource: Sendable {

    /// Returns the next identifier.
    func next() -> UUID
}

/// The real source.
///
/// The production implementation: `UUID()`, drawing from the system CSPRNG.
public struct SystemIdentifierSource: IdentifierSource {

    /// Creates a system identifier source.
    public init() {}

    /// Returns a fresh identifier from the system CSPRNG.
    public func next() -> UUID { UUID() }
}

/// Identifiers drawn from a seeded generator.
///
/// The same seed produces the same sequence of identifiers, so a structure keyed by UUID
/// can be asserted exactly and a serialised snapshot diffs cleanly between runs.
///
/// The identifiers are **version 4 in shape** — the version and variant bits are set as
/// RFC 4122 requires — so anything that parses or validates them behaves as it would with a
/// real one. They are not, and must not be treated as, unpredictable.
///
/// A reference type so that successive calls advance a shared stream. A value type would
/// return the same identifier forever to every holder, which is the opposite of the intent.
// Justification: mutable `generator` is guarded by `lock`; no other state exists.
public final class SeededIdentifierSource: IdentifierSource, @unchecked Sendable {

    private let lock = NSLock()
    private var generator: Xoshiro256StarStar

    /// Creates a source whose identifiers are determined by `seed`.
    ///
    /// - Parameter seed: Any 64-bit value. Equal seeds produce equal sequences.
    public init(seed: UInt64) {
        self.generator = Xoshiro256StarStar(seed: seed)
    }

    /// Returns the next identifier in the deterministic sequence.
    public func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }

        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        for _ in 0..<2 {
            let word = generator.next()
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }

        // RFC 4122 §4.4: version 4 in the high nibble of byte 6, variant 10 in the top
        // bits of byte 8. Without these an identifier is 128 random bits that some
        // parsers will reject and some systems will route differently.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Identifiers counted from zero.
///
/// `00000000-0000-4000-8000-000000000001`, then `…002`, and so on. Where
/// ``SeededIdentifierSource`` gives realistic-looking values, this gives readable ones: a
/// failure message naming `…0003` says which identifier at a glance, where a scrambled hex
/// string says nothing.
///
/// Version and variant bits are still set, so these parse as version 4.
// Justification: mutable `counter` is guarded by `lock`; no other state exists.
public final class CountingIdentifierSource: IdentifierSource, @unchecked Sendable {

    private let lock = NSLock()
    private var counter: UInt64

    /// Creates a counting source.
    ///
    /// - Parameter startingAt: The first value to issue. Defaults to 1, so the first
    ///   identifier is visibly not the zero UUID.
    public init(startingAt: UInt64 = 1) {
        self.counter = startingAt
    }

    /// Returns the next identifier in the counted sequence.
    public func next() -> UUID {
        lock.lock()
        let value = counter
        counter &+= 1
        lock.unlock()

        var bytes = [UInt8](repeating: 0, count: 16)
        for (offset, shift) in stride(from: 56, through: 0, by: -8).enumerated() {
            bytes[8 + offset] = UInt8(truncatingIfNeeded: value >> UInt64(shift))
        }
        bytes[6] = 0x40                       // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // variant 10

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
