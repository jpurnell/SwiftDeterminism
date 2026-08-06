import Foundation
import Testing
@testable import SwiftDeterminism

@Suite("FormattingEnvironment")
struct FormattingEnvironmentTests {

    /// The failure this prevents: `12.34` renders as `12,34` under a European locale, so a
    /// number written for a machine to parse becomes unparseable — and only for colleagues.
    @Test("A machine-facing number formats identically regardless of the machine's locale")
    func numbersArePinned() {
        let style = FormattingEnvironment.posix.machineNumberStyle(fractionDigits: 2)
        #expect(1_234.5.formatted(style) == "1234.50")
        #expect(0.0.formatted(style) == "0.00")
        #expect((-1.5).formatted(style) == "-1.50")
    }

    /// Foundation rounds half to **even**, not away from zero: `0.125` is exactly
    /// representable and rounds to `0.12`, while `0.135` — which is not exactly
    /// representable — rounds to `0.14`.
    ///
    /// Pinned rather than avoided, because it surprises people writing expectations by
    /// hand, and because a formatter that quietly changed rounding mode would alter every
    /// figure a downstream project asserts.
    @Test("Rounding is half-to-even")
    func roundingIsHalfEven() {
        let style = FormattingEnvironment.posix.machineNumberStyle(fractionDigits: 2)
        #expect(0.125.formatted(style) == "0.12", "got \(0.125.formatted(style))")
        #expect((-0.125).formatted(style) == "-0.12")
        #expect(0.375.formatted(style) == "0.38")
    }

    /// Grouping is off because a separator is decoration for a reader and corruption for a
    /// parser — and the separator itself is locale-dependent.
    @Test("Grouping separators never appear")
    func noGrouping() {
        let style = FormattingEnvironment.posix.machineNumberStyle(fractionDigits: 0)
        let rendered = 1_234_567.0.formatted(style)
        #expect(rendered == "1234567")
        #expect(!rendered.contains(","))
        #expect(!rendered.contains(" "))
    }

    /// `en_US_POSIX` is documented as fixed — it does not change with OS releases or user
    /// settings, which ordinary locales do.
    @Test("POSIX is the pinned locale, UTC the pinned zone")
    func posixIsPinned() {
        #expect(FormattingEnvironment.posix.locale.identifier == "en_US_POSIX")
        #expect(FormattingEnvironment.posix.timeZone.secondsFromGMT() == 0)
        #expect(FormattingEnvironment.posix.calendar.identifier == .gregorian)
    }

    /// A date near midnight belongs to different days in different zones. Pinning to UTC
    /// means a test does not fail only between 23:00 and 01:00.
    @Test("Dates render in the pinned zone")
    func datesArePinned() {
        #expect(FormattingEnvironment.posix.iso8601(.fixture) == "2026-01-01T00:00:00Z")
    }

    @Test("The calendar carries the environment's locale and zone")
    func calendarIsConsistent() {
        let environment = FormattingEnvironment.posix
        #expect(environment.calendar.timeZone == environment.timeZone)
        #expect(environment.calendar.locale == environment.locale)
    }

    @Test("A negative fraction length is clamped rather than trapping")
    func negativeFractionDigits() {
        let style = FormattingEnvironment.posix.machineNumberStyle(fractionDigits: -3)
        #expect(12.7.formatted(style) == "13")
    }
}

@Suite("Stable ordering")
struct StableOrderingTests {

    /// Swift seeds its hasher per process, so a dictionary enumerates differently between
    /// runs of the same binary. Ordering by key makes output reproducible.
    @Test("A dictionary orders by key")
    func dictionaryOrders() {
        let scores = ["charlie": 3, "alpha": 1, "bravo": 2]
        #expect(scores.stablyOrdered.map(\.key) == ["alpha", "bravo", "charlie"])
        #expect(scores.valuesInKeyOrder == [1, 2, 3])
    }

    @Test("A set orders ascending")
    func setOrders() {
        #expect(Set([3, 1, 2]).stablyOrdered == [1, 2, 3])
        #expect(Set(["b", "a"]).stablyOrdered == ["a", "b"])
    }

    /// Sorting on a non-unique key leaves tied elements wherever they arrived, which for a
    /// dictionary is not stable. A tiebreak makes the order total.
    @Test("Ties are broken so the order is total")
    func tiesAreBroken() {
        struct Item { let group: Int; let name: String }
        let items = [
            Item(group: 1, name: "zulu"), Item(group: 0, name: "yankee"),
            Item(group: 1, name: "alpha"), Item(group: 0, name: "x-ray")
        ]
        let sorted = items.stablySorted(by: \.group, tiebreak: \.name)
        #expect(sorted.map(\.name) == ["x-ray", "yankee", "alpha", "zulu"])
    }

    /// The property that matters: ordering the same dictionary twice gives the same answer,
    /// where raw enumeration need not.
    @Test("Ordering is repeatable where enumeration is not")
    func orderingIsRepeatable() {
        let dictionary = Dictionary(uniqueKeysWithValues: (0..<128).map { ($0, "v\($0)") })
        #expect(dictionary.stablyOrdered.map(\.key) == dictionary.stablyOrdered.map(\.key))
        #expect(dictionary.stablyOrdered.map(\.key) == Array(0..<128))
    }
}

/// Stands in for whatever an application draws its root seed from.
private typealias SeededGeneratorStub = SplitMix64

@Suite("DeterministicContext")
struct DeterministicContextTests {

    @Test("A fixed context produces identical output on every run")
    func fixedContextIsReproducible() {
        func render(_ context: DeterministicContext) -> String {
            "\(context.identifiers.next()) at \(context.formatting.iso8601(context.clock.now))"
        }
        #expect(render(.fixed(seed: 42)) == render(.fixed(seed: 42)))
    }

    @Test("A fixed context stops the clock at the fixture")
    func fixedContextClock() {
        #expect(DeterministicContext.fixed(seed: 1).clock.now == Date.fixture)
        let moment = Date(timeIntervalSince1970: 1_000)
        #expect(DeterministicContext.fixed(seed: 1, at: moment).clock.now == moment)
    }

    @Test("A manual context hands back the clock to advance")
    func manualContextAdvances() {
        let (context, clock) = DeterministicContext.manual(seed: 1)
        #expect(context.clock.now == Date.fixture)
        clock.advance(by: 3_600)
        #expect(context.clock.now == Date.fixture.addingTimeInterval(3_600),
                "the context held a stale copy of the clock")
    }

    /// The design point. Sharing one generator makes two components order-dependent: the
    /// values one receives depend on how many the other drew first, so adding a draw in one
    /// place silently changes results in another.
    @Test("Each label gets an independent stream")
    func labelsAreIndependent() {
        let context = DeterministicContext.fixed(seed: 42)
        var sampling = context.makeGenerator(for: "sampling")
        var shuffling = context.makeGenerator(for: "shuffling")
        #expect(sampling.next() != shuffling.next())
    }

    /// The property that removes order-dependence: a label's stream is the same whatever
    /// else the program did.
    @Test("A label's stream does not depend on other draws")
    func streamsAreNotOrderDependent() {
        let context = DeterministicContext.fixed(seed: 42)

        var first = context.makeGenerator(for: "sampling")
        let expected = (0..<8).map { _ in first.next() }

        // Draw heavily from another label, then take "sampling" again.
        var other = context.makeGenerator(for: "shuffling")
        for _ in 0..<1_000 { _ = other.next() }

        var second = context.makeGenerator(for: "sampling")
        #expect((0..<8).map { _ in second.next() } == expected)
    }

    @Test("The same label and seed reproduce the same stream")
    func labelsAreReproducible() {
        var first = DeterministicContext.fixed(seed: 7).makeGenerator(for: "work")
        var second = DeterministicContext.fixed(seed: 7).makeGenerator(for: "work")
        #expect((0..<16).map { _ in first.next() } == (0..<16).map { _ in second.next() })
    }

    @Test("Different seeds give different streams for the same label")
    func seedsSeparateStreams() {
        var first = DeterministicContext.fixed(seed: 1).makeGenerator(for: "work")
        var second = DeterministicContext.fixed(seed: 2).makeGenerator(for: "work")
        #expect(first.next() != second.next())
    }

    /// `String.hashValue` varies between processes, so using it to derive streams would
    /// reintroduce the nondeterminism this package removes — in the code meant to prevent it.
    @Test("Label hashing is stable, not Swift's per-process hash")
    func labelHashingIsStable() {
        // Fixed expectations: FNV-1a over UTF-8, independent of process seed.
        #expect(DeterministicContext.stableHash("") == 0xCBF2_9CE4_8422_2325)
        #expect(DeterministicContext.stableHash("sampling")
                == DeterministicContext.stableHash("sampling"))
        #expect(DeterministicContext.stableHash("a") != DeterministicContext.stableHash("b"))
    }

    /// Correct for output a person reads, wrong for anything parsed — which is why both
    /// production contexts exist.
    @Test("The two production contexts differ in formatting, not determinism")
    func productionContexts() {
        #expect(DeterministicContext.machineFacing(rootSeed: 1).formatting == .posix)
        #expect(DeterministicContext.system(rootSeed: 1).formatting == .system)
        #expect(!DeterministicContext.system(rootSeed: 1).isFullyDeterministic)
        #expect(DeterministicContext.fixed(seed: 1).isFullyDeterministic)
    }

    /// The reason a production context carries a seed at all: log it, and the run replays
    /// exactly. Reproducing a customer's run is worth more than the unpredictability of a
    /// non-cryptographic stream — which is not what protects anything here anyway.
    @Test("A production run is replayable from its logged seed")
    func productionRunsReplay() {
        // What an application does at startup, and logs.
        var entropy = SeededGeneratorStub(seed: 12_345)
        let logged = entropy.next()

        var original = DeterministicContext.system(rootSeed: logged)
            .makeGenerator(for: "sampling")
        var replayed = DeterministicContext.system(rootSeed: logged)
            .makeGenerator(for: "sampling")
        #expect((0..<8).map { _ in original.next() } == (0..<8).map { _ in replayed.next() })
    }
}
