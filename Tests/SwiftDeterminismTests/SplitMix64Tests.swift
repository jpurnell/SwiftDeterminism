import Foundation
import Testing
@testable import SwiftDeterminism

/// The guarantee this package sells is that a seed reproduces a sequence — on any
/// platform, forever. That is only real if it is pinned to *published* values.
///
/// An implementation checked against its own output agrees with itself perfectly and may
/// still be wrong. Worse, here it would be wrong in a way nobody notices until a
/// downstream project migrates and every seeded expectation shifts at once.
@Suite("SplitMix64 — known answers")
struct SplitMix64KnownAnswerTests {

    /// Vigna's reference `splitmix64.c` from seed 0. These are the values the published
    /// implementation produces, and any implementation that agrees with it agrees with these.
    private let seedZero: [UInt64] = [
        0xE220_A839_7B1D_CDAF,
        0x6E78_9E6A_A1B9_65F4,
        0x06C4_5D18_8009_454F,
        0xF88B_B8A8_724C_81EC,
        0x1B39_896A_51A8_749B
    ]

    @Test("Seed 0 produces the reference stream")
    func referenceStreamFromZero() {
        var rng = SplitMix64(seed: 0)
        for (index, expected) in seedZero.enumerated() {
            let actual = rng.next()
            #expect(actual == expected,
                    "draw \(index): got 0x\(String(actual, radix: 16, uppercase: true))")
        }
    }

    /// The documented first output, asserted on its own so a failure names the specific
    /// claim made in `SplitMix64`'s own documentation.
    @Test("The documented first output holds")
    func documentedFirstOutput() {
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
    }

    /// A second seed, so a bug that happens to be correct at zero is caught. The state
    /// starts *at* the seed, so seed 0 exercises no addition carry.
    @Test("A non-zero seed also matches the reference")
    func referenceStreamFromNonZero() {
        var rng = SplitMix64(seed: 1)
        // From the same reference implementation, seeded with 1.
        #expect(rng.next() == 0x910A_2DEC_89025CC1)
        #expect(rng.next() == 0xBEEB_8DA1_658E_EC67)
    }
}

@Suite("SplitMix64 — reproducibility")
struct SplitMix64ReproducibilityTests {

    /// The whole contract, stated as a test: same seed, same stream.
    @Test("Equal seeds produce equal streams")
    func equalSeedsAgree() {
        var first = SplitMix64(seed: 20_260_806)
        var second = SplitMix64(seed: 20_260_806)
        let a = (0..<64).map { _ in first.next() }
        let b = (0..<64).map { _ in second.next() }
        #expect(a == b)
    }

    @Test("Different seeds produce different streams")
    func differentSeedsDiverge() {
        var first = SplitMix64(seed: 1)
        var second = SplitMix64(seed: 2)
        #expect(first.next() != second.next())
    }

    /// Every 64-bit value is a usable seed. A generator with weak seeds would need callers
    /// to know which — this one does not, because the state is a counter.
    @Test("Extreme seeds behave", arguments: [
        UInt64.min, 1, UInt64.max, UInt64.max &- 1, 0x9E37_79B9_7F4A_7C15
    ])
    func extremeSeeds(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        let drawn = (0..<32).map { _ in rng.next() }
        #expect(Set(drawn).count == 32, "seed \(seed) repeated within 32 draws")
    }

    /// The increment is the generator's identity: change it and every downstream seeded
    /// expectation in the portfolio shifts silently.
    @Test("The golden-ratio increment is unchanged")
    func incrementIsPinned() {
        #expect(SplitMix64.goldenRatioIncrement == 0x9E37_79B9_7F4A_7C15)
    }
}

@Suite("SplitMix64 — as a RandomNumberGenerator")
struct SplitMix64IntegrationTests {

    /// The point of conforming to the protocol: the standard library's random APIs become
    /// reproducible without any change at the call site.
    @Test("Standard library draws are reproducible through it")
    func standardLibraryDraws() {
        var first = SplitMix64(seed: 7)
        var second = SplitMix64(seed: 7)

        #expect(Double.random(in: 0...1, using: &first)
                == Double.random(in: 0...1, using: &second))
        #expect(Int.random(in: 0..<1_000_000, using: &first)
                == Int.random(in: 0..<1_000_000, using: &second))
        #expect([1, 2, 3, 4, 5].shuffled(using: &first)
                == [1, 2, 3, 4, 5].shuffled(using: &second))
    }

    /// A generator whose low bits were poorly distributed would show up here, where
    /// `Int.random(in:)` uses them.
    @Test("Small ranges are not degenerate")
    func smallRangesAreDistributed() {
        var rng = SplitMix64(seed: 99)
        var counts = [Int](repeating: 0, count: 6)
        for _ in 0..<6_000 {
            counts[Int.random(in: 0..<6, using: &rng)] += 1
        }
        // Each face should land near 1000. A generator stuck on a subset, or with dead low
        // bits, fails this badly rather than marginally.
        for (face, count) in counts.enumerated() {
            #expect(count > 800 && count < 1_200, "face \(face) came up \(count) times")
        }
    }

    /// Drawing does not mutate a copy — the generator is a value, which is what makes a
    /// failure reproducible from the seed alone rather than from execution order.
    @Test("Copies are independent")
    func copiesAreIndependent() {
        var original = SplitMix64(seed: 42)
        _ = original.next()
        var copy = original
        #expect(copy.next() == { var o = original; return o.next() }())
    }
}

/// A long simulation must be resumable: restarting from the original seed replays work
/// already done, and restarting from a fresh seed produces a different run.
@Suite("Checkpointing")
struct CheckpointTests {

    @Test("SplitMix64 resumes exactly where it stopped")
    func splitMixResumes() {
        var original = SplitMix64(seed: 42)
        for _ in 0..<100 { _ = original.next() }
        let checkpoint = original.currentState

        var resumed = SplitMix64(resuming: checkpoint)
        #expect((0..<16).map { _ in resumed.next() } == (0..<16).map { _ in original.next() })
    }

    @Test("SplitMix64 round-trips through Codable")
    func splitMixCodable() throws {
        var original = SplitMix64(seed: 7)
        for _ in 0..<50 { _ = original.next() }

        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(SplitMix64.self, from: data)
        #expect((0..<8).map { _ in restored.next() } == (0..<8).map { _ in original.next() })
    }

    @Test("Xoshiro256** round-trips through Codable")
    func xoshiroCodable() throws {
        var original = Xoshiro256StarStar(seed: 7)
        for _ in 0..<50 { _ = original.next() }

        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(Xoshiro256StarStar.self, from: data)
        #expect((0..<8).map { _ in restored.next() } == (0..<8).map { _ in original.next() })
    }

    /// An all-zero state is one no valid generator can hold, so decoding one means the
    /// saved data is corrupt rather than a legitimate resume point.
    @Test("A corrupt saved state is refused rather than resumed")
    func corruptStateRefused() {
        let allZero = Data(#"{"words":[0,0,0,0]}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Xoshiro256StarStar.self, from: allZero)
        }
        let wrongLength = Data(#"{"words":[1,2]}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Xoshiro256StarStar.self, from: wrongLength)
        }
    }
}
