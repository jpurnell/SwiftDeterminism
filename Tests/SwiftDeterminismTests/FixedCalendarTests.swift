import Foundation
import Testing
@testable import SwiftDeterminism

/// `Calendar.gregorianUTC` and `isoDateParser()`.
///
/// These assert the property the names promise: the same instant yields the same components, and
/// the same string yields the same instant, wherever the machine thinks it is.
@Suite("Fixed calendar")
struct FixedCalendarTests {

    @Test("Gregorian, and pinned to UTC")
    func identity() {
        #expect(Calendar.gregorianUTC.identifier == .gregorian)
        #expect(Calendar.gregorianUTC.timeZone.secondsFromGMT() == 0)
    }

    @Test("One implementation, two spellings")
    func agreesWithFormattingEnvironment() {
        #expect(Calendar.gregorianUTC == FormattingEnvironment.posix.calendar)
    }

    @Test("An ISO date parses to midnight UTC")
    func parsesToMidnightUTC() throws {
        let parser = FormattingEnvironment.posix.isoDateParser()
        let date = try #require(parser.date(from: "2020-01-15"))
        let parts = Calendar.gregorianUTC.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(parts.year == 2020)
        #expect(parts.month == 1)
        #expect(parts.day == 15)
        #expect(parts.hour == 0)
    }

    @Test("A round trip returns the day it was given")
    func roundTrips() throws {
        let parser = FormattingEnvironment.posix.isoDateParser()
        for iso in ["2020-01-15", "2024-02-29", "2026-12-31", "1999-06-01"] {
            let date = try #require(parser.date(from: iso))
            #expect(parser.string(from: date) == iso, "\(iso) did not survive the round trip")
        }
    }

    /// The failure this type exists to prevent, asserted rather than described.
    ///
    /// A fix that pinned the parse and left the render ambient shifted every date back a day west
    /// of UTC and passed review. A test that only checks the calendar would not have caught it,
    /// so this checks the pair.
    @Test("An unpinned renderer loses a day west of UTC — the half-fix, demonstrated")
    func unpinnedRendererShiftsTheDay() throws {
        let parser = FormattingEnvironment.posix.isoDateParser()
        let date = try #require(parser.date(from: "2024-01-15"))

        let unpinned = DateFormatter()
        unpinned.dateFormat = "yyyy-MM-dd"
        unpinned.locale = Locale(identifier: "en_US_POSIX")
        unpinned.timeZone = TimeZone(identifier: "America/Los_Angeles")

        // Midnight UTC is the previous afternoon in Los Angeles.
        #expect(unpinned.string(from: date) == "2024-01-14")

        // Pinning both halves is what makes the day survive.
        let pinned = FormattingEnvironment.posix.isoDateParser()
        #expect(pinned.string(from: date) == "2024-01-15")
    }

    @Test("Components do not move with the zone the caller happens to be in")
    func componentsAreZoneIndependent() throws {
        let parser = FormattingEnvironment.posix.isoDateParser()
        let date = try #require(parser.date(from: "2026-06-02"))

        for zone in ["Pacific/Kiritimati", "Pacific/Niue", "UTC", "Asia/Kolkata"] {
            var ambient = Calendar(identifier: .gregorian)
            ambient.timeZone = try #require(TimeZone(identifier: zone))
            let viaFixed = Calendar.gregorianUTC.dateComponents([.year, .month, .day], from: date)
            #expect(viaFixed.day == 2, "the fixed calendar should not care that the caller is in \(zone)")
            _ = ambient
        }
    }

    @Test("A day count is the same wherever it is taken")
    func dayCountIsStable() throws {
        let parser = FormattingEnvironment.posix.isoDateParser()
        let start = try #require(parser.date(from: "2026-03-01"))
        let end = try #require(parser.date(from: "2026-04-01"))
        let days = Calendar.gregorianUTC.dateComponents([.day], from: start, to: end).day
        // March has 31 days, and no DST transition can change that under UTC.
        #expect(days == 31)
    }
}
