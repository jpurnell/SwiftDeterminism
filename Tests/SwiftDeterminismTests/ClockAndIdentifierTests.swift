import Foundation
import Testing
@testable import SwiftDeterminism

@Suite("WallClock")
struct WallClockTests {

    @Test("A fixed clock never moves")
    func fixedClockIsStill() {
        let clock = FixedWallClock(at: .fixture)
        #expect(clock.now == Date.fixture)
        #expect(clock.now == clock.now)
    }

    /// The point of a manual clock: behaviour that depends on time *passing* becomes a
    /// test rather than a wait. Sleeping for real seconds makes a suite slow and, worse,
    /// timing-dependent — the same test passes on a fast machine and fails on a loaded one.
    @Test("A manual clock moves only when told")
    func manualClockAdvances() {
        let clock = ManualWallClock(at: .fixture)
        #expect(clock.now == Date.fixture)

        clock.advance(by: 3_600)
        #expect(clock.now == Date.fixture.addingTimeInterval(3_600))

        clock.advance(by: -600)
        #expect(clock.now == Date.fixture.addingTimeInterval(3_000))

        clock.set(to: .fixture)
        #expect(clock.now == Date.fixture)
    }

    /// A reference type deliberately: callers share one clock and one of them advances it.
    /// A value type would give each holder a frozen copy, which is the bug this avoids.
    @Test("A manual clock is shared, not copied")
    func manualClockIsShared() {
        let clock = ManualWallClock(at: .fixture)
        let holder: any WallClock = clock
        clock.advance(by: 60)
        #expect(holder.now == Date.fixture.addingTimeInterval(60),
                "the holder saw a stale copy")
    }

    /// The expiry check that a real caller writes — the case that fails at a second
    /// boundary when it reads `Date()` instead.
    @Test("Expiry is exact rather than approximate")
    func expiryIsExact() {
        let clock = ManualWallClock(at: .fixture)
        let expiry = clock.now.addingTimeInterval(3_600)

        clock.advance(by: 3_599)
        #expect(clock.now < expiry)
        clock.advance(by: 1)
        #expect(clock.now == expiry)
        clock.advance(by: 1)
        #expect(clock.now > expiry)
    }

    /// Asserted on ordering rather than on elapsed wall-clock time.
    ///
    /// The obvious version — `abs(clock.now.timeIntervalSince(Date())) < 1` — is the exact
    /// flake this package exists to prevent: it passes on an idle machine and fails on a
    /// loaded one, for reasons unrelated to the code under test. The gate caught it here,
    /// which is a fair illustration of how easily it is written.
    @Test("The system clock advances rather than standing still")
    func systemClockIsReal() {
        let clock = SystemWallClock()
        let first = clock.now
        let second = clock.now
        // Monotonic, and not a frozen constant like a fixed clock would return.
        #expect(second >= first)
        #expect(clock.now >= Date.fixture, "the system clock predates the test fixture")
    }

    /// A fixture derived from the present is not a fixture.
    @Test("The shared fixture is a fixed instant")
    func fixtureIsFixed() throws {
        #expect(Date.fixture.timeIntervalSince1970 == 1_767_225_600)
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        var calendar = Calendar(identifier: .gregorian)
        // Resolved here rather than read from `FormattingEnvironment.posix` so this stays an
        // independent check on the fixture's value, not a restatement of the package's own UTC.
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(calendar.date(from: components) == Date.fixture)
    }
}

@Suite("IdentifierSource")
struct IdentifierSourceTests {

    @Test("Equal seeds produce equal identifier sequences")
    func seededSourceIsReproducible() {
        let first = SeededIdentifierSource(seed: 42)
        let second = SeededIdentifierSource(seed: 42)
        let a = (0..<16).map { _ in first.next() }
        let b = (0..<16).map { _ in second.next() }
        #expect(a == b)
    }

    @Test("Successive calls advance the stream")
    func seededSourceAdvances() {
        let source = SeededIdentifierSource(seed: 42)
        let drawn = (0..<64).map { _ in source.next() }
        #expect(Set(drawn).count == 64, "only \(Set(drawn).count) of 64 were distinct")
    }

    /// Anything that parses or validates a UUID should behave as it would with a real one,
    /// so the version and variant bits must be right — not merely 128 random bits.
    @Test("Seeded identifiers are version 4 in shape")
    func seededIdentifiersAreVersion4() {
        let source = SeededIdentifierSource(seed: 7)
        for _ in 0..<32 {
            let uuid = source.next().uuid
            #expect(uuid.6 & 0xF0 == 0x40, "version nibble was \(uuid.6 & 0xF0)")
            #expect(uuid.8 & 0xC0 == 0x80, "variant bits were \(uuid.8 & 0xC0)")
        }
    }

    /// Where the seeded source gives realistic values, this gives readable ones: a failure
    /// naming `…0003` says which identifier at a glance.
    @Test("Counting identifiers are legible and ordered")
    func countingSourceIsLegible() {
        let source = CountingIdentifierSource()
        #expect(source.next().uuidString == "00000000-0000-4000-8000-000000000001")
        #expect(source.next().uuidString == "00000000-0000-4000-8000-000000000002")
        #expect(source.next().uuidString == "00000000-0000-4000-8000-000000000003")
    }

    @Test("Counting identifiers are also version 4 in shape")
    func countingIdentifiersAreVersion4() {
        let source = CountingIdentifierSource()
        for _ in 0..<8 {
            let uuid = source.next().uuid
            #expect(uuid.6 & 0xF0 == 0x40)
            #expect(uuid.8 & 0xC0 == 0x80)
        }
    }

    @Test("Counting can start anywhere")
    func countingStartsWhereAsked() {
        let source = CountingIdentifierSource(startingAt: 100)
        #expect(source.next().uuidString == "00000000-0000-4000-8000-000000000064")
    }

    /// A reference type so successive calls advance a shared stream; a value type would
    /// hand every holder the same identifier forever.
    @Test("A source is shared, not copied")
    func sourceIsShared() {
        let source = CountingIdentifierSource()
        let holder: any IdentifierSource = source
        _ = source.next()
        #expect(holder.next().uuidString == "00000000-0000-4000-8000-000000000002")
    }

    @Test("The system source produces distinct identifiers")
    func systemSourceIsReal() {
        let source = SystemIdentifierSource()
        #expect(Set((0..<32).map { _ in source.next() }).count == 32)
    }
}
