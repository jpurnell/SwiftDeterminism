/// A seedable generator with better statistical quality than ``SplitMix64``.
///
/// `xoshiro256**` (Blackman and Vigna, 2018) is the generator SplitMix64 was designed to
/// *seed*. SplitMix64 is a counter through a mixing function — fast, simple, and entirely
/// adequate for tests — but it has only 64 bits of state, and its output is invertible from
/// two draws. `xoshiro256**` carries 256 bits, passes the standard test batteries more
/// comfortably, and is the usual choice where the quality of the stream matters: Monte
/// Carlo work, procedural generation, sampling.
///
/// Same guarantee as everything here: **the same seed produces the same sequence, on every
/// platform, forever.**
///
/// ## Example
///
/// ```swift
/// var rng = Xoshiro256StarStar(seed: 42)
/// let sample = (0..<1_000).map { _ in Double.random(in: 0...1, using: &rng) }
/// ```
///
/// ## Seeding
///
/// The state must not be all zeros — a xorshift generator seeded entirely with zeros emits
/// zeros forever, which is the one genuinely dangerous seed. ``init(seed:)`` expands a
/// single value through SplitMix64, which is exactly what its authors recommend, and which
/// cannot produce an all-zero state from any seed.
///
/// ## Not for anything security-sensitive
///
/// Like ``SplitMix64``, the state is recoverable from enough output. Never use this for
/// keys, tokens, salts, or PKCE verifiers; `SystemRandomNumberGenerator` is the standard
/// library's CSPRNG and is correct there.
///
/// ## Period
///
/// 2²⁵⁶ − 1. Long enough that exhausting it is not a consideration.
public struct Xoshiro256StarStar: RandomNumberGenerator, Sendable, Equatable, Codable {

    /// The generator's 256-bit state, as four 64-bit words.
    private var state: (UInt64, UInt64, UInt64, UInt64)

    /// The generator's current position in its stream, as four words.
    ///
    /// Exposed so a long-running simulation can checkpoint and resume exactly where it
    /// stopped. Pass it back through ``init(state:)``.
    public var currentState: (UInt64, UInt64, UInt64, UInt64) { state }

    /// Creates a generator whose stream is fully determined by `seed`.
    ///
    /// The seed is expanded through ``SplitMix64`` to fill 256 bits of state, as the
    /// algorithm's authors recommend. This is why an all-zero state — the one seed that
    /// would break a xorshift generator — cannot arise.
    ///
    /// - Parameter seed: Any 64-bit value. Equal seeds produce equal streams.
    public init(seed: UInt64) {
        var seeder = SplitMix64(seed: seed)
        state = (seeder.next(), seeder.next(), seeder.next(), seeder.next())
    }

    /// Creates a generator from an explicit 256-bit state.
    ///
    /// - Parameter state: The four state words. An all-zero state is rejected, because a
    ///   xorshift generator seeded with zeros emits zeros forever.
    /// - Returns: `nil` if every word is zero.
    public init?(state: (UInt64, UInt64, UInt64, UInt64)) {
        guard state.0 != 0 || state.1 != 0 || state.2 != 0 || state.3 != 0 else { return nil }
        self.state = state
    }

    /// Returns the next 64-bit value in the deterministic stream.
    ///
    /// Matches the reference `xoshiro256starstar.c`.
    ///
    /// - Returns: The next pseudorandom 64-bit value.
    public mutating func next() -> UInt64 {
        // The `**` scrambler: the output is derived from the state, not the state itself,
        // which is what gives this variant its statistical quality.
        let result = Self.rotateLeft(state.1 &* 5, by: 7) &* 9
        let t = state.1 << 17

        state.2 ^= state.0
        state.3 ^= state.1
        state.1 ^= state.2
        state.0 ^= state.3
        state.2 ^= t
        state.3 = Self.rotateLeft(state.3, by: 45)

        return result
    }

    /// Rotates a 64-bit value left, wrapping the bits that fall off the end.
    private static func rotateLeft(_ value: UInt64, by amount: UInt64) -> UInt64 {
        (value << amount) | (value >> (64 - amount))
    }

    /// Two generators are equal when their state words match, so a copy taken mid-stream
    /// compares equal to its origin until either advances.
    ///
    /// - Parameters:
    ///   - lhs: A generator.
    ///   - rhs: Another generator.
    /// - Returns: `true` when both hold the same state.
    public static func == (lhs: Xoshiro256StarStar, rhs: Xoshiro256StarStar) -> Bool {
        lhs.state == rhs.state
    }

    private enum CodingKeys: String, CodingKey { case words }

    /// Decodes a saved generator position.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: A decoding error, or if the saved state is all zeros — which no valid
    ///   generator can hold, so it indicates corruption rather than a legitimate resume.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let words = try container.decode([UInt64].self, forKey: .words)
        guard words.count == 4, words.contains(where: { $0 != 0 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .words, in: container,
                debugDescription: "a generator state must be four words and not all zero")
        }
        state = (words[0], words[1], words[2], words[3])
    }

    /// Encodes the generator's current position.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: An encoding error.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([state.0, state.1, state.2, state.3], forKey: .words)
    }
}
