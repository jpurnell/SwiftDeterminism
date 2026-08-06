/// A fast, seedable random number generator with a published reference implementation.
///
/// `SplitMix64` (Vigna, 2015) produces a deterministic stream of 64-bit values from a
/// seed: **the same seed always yields the same sequence, on every platform and Swift
/// version.** That guarantee is the point of this type. Swift's standard library ships no
/// seeded generator — `SystemRandomNumberGenerator` is deliberately unseedable, because
/// unpredictability is its contract — so a test that needs a reproducible draw has nowhere
/// else to go.
///
/// The algorithm is a single additive state update followed by a mixing function, so it is
/// allocation-free and faster than `SystemRandomNumberGenerator`.
///
/// ## Example
///
/// ```swift
/// var rng = SplitMix64(seed: 42)
/// let u = Double.random(in: 0...1, using: &rng)   // identical on every run
/// ```
///
/// ## Why a failing test should use this
///
/// A test drawing from `SystemRandomNumberGenerator` that fails once in CI carries no
/// reproduction. It is triaged as flakiness and retried until it passes, which is
/// indistinguishable from fixing it — and is how a real defect survives. Seeded, the same
/// failure reproduces on any machine from the seed alone.
///
/// ## Not for anything security-sensitive
///
/// The mixing function is invertible: two outputs are enough to recover the state and
/// predict the rest of the stream. Never use this for keys, tokens, session identifiers,
/// password salts, or PKCE verifiers. `SystemRandomNumberGenerator` is the standard
/// library's CSPRNG and is the correct choice there.
///
/// ## Period
///
/// Exactly 2⁶⁴. The state is a counter, so every value is visited once before the sequence
/// repeats — there are no short cycles to fall into, which a linear congruential or lagged
/// Fibonacci generator can hide depending on its seed.
public struct SplitMix64: RandomNumberGenerator, Sendable, Equatable, Codable {

    /// The generator's internal 64-bit state, advanced by the golden-ratio increment.
    private var state: UInt64

    /// The increment applied to the state on each draw: 2⁶⁴ ÷ φ.
    ///
    /// The golden ratio is chosen so that successive states spread evenly across the
    /// 64-bit space rather than clustering, which is what lets a plain counter feed a
    /// mixing function and still produce well-distributed output.
    static let goldenRatioIncrement: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// The generator's current position in its stream.
    ///
    /// Exposed so a long-running simulation can checkpoint and resume exactly where it
    /// stopped — restarting from the original seed would replay work already done, and
    /// restarting from a fresh seed would produce a different run.
    public var currentState: UInt64 { state }

    /// Resumes a generator from a saved position.
    ///
    /// - Parameter state: A value previously read from ``currentState``.
    public init(resuming state: UInt64) {
        self.state = state
    }

    /// Creates a generator whose output stream is fully determined by `seed`.
    ///
    /// - Parameter seed: Any 64-bit value. Equal seeds produce equal streams; there are no
    ///   weak or forbidden seeds, because the state is a counter rather than a lattice.
    public init(seed: UInt64) {
        self.state = seed
    }

    /// Returns the next 64-bit value in the deterministic stream.
    ///
    /// Matches Vigna's reference `splitmix64.c`: seed `0` yields `0xE220A8397B1DCDAF` as
    /// its first output. That vector, and others, are asserted in the test suite — an
    /// implementation checked only against its own output agrees with itself perfectly and
    /// may still be wrong.
    ///
    /// - Returns: The next pseudorandom 64-bit value.
    public mutating func next() -> UInt64 {
        state &+= Self.goldenRatioIncrement
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
