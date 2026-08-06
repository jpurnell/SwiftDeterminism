import Foundation

/// The locale, time zone and calendar that formatting depends on.
///
/// > Note: Unlike the generators in this package, which are portable by construction, this
/// > type routes through ICU — `FloatingPointFormatStyle` and `ISO8601DateFormatter`. ICU
/// > differs between Darwin Foundation and swift-corelibs-foundation, so the exact strings
/// > asserted in this package's tests are **verified on Darwin only**. Pinning the locale
/// > removes the *user-settings* variation, which is the common failure; it does not
/// > guarantee byte-identical output across operating systems.
///
/// Every Foundation formatter consults ambient settings unless told otherwise, and the
/// resulting failures do not appear on the machine that wrote the code. A few observed in
/// one afternoon:
///
/// - `12.34` formats as `12,34` under a European locale, so a number written for a machine
///   to parse becomes unparseable.
/// - Grouping separators appear where none were wanted: `1234.5` becomes `1,234.5`.
/// - A month column headed `Jan 2026` arrives as `janv. 2026`, and a parser keyed on the
///   English spelling silently finds nothing.
/// - A date rendered near midnight lands on the previous day in a different zone.
///
/// Each of those passes locally, forever, and fails for a colleague or in a container whose
/// locale is not yours.
///
/// ## Example
///
/// ```swift
/// let value = 1234.5.formatted(.number.precision(.fractionLength(2))
///     .locale(FormattingEnvironment.posix.locale))    // "1234.50" everywhere
/// ```
public struct FormattingEnvironment: Sendable, Equatable {

    /// The locale formatting should use.
    public let locale: Locale

    /// The time zone dates should be interpreted in.
    public let timeZone: TimeZone

    /// The calendar date arithmetic should use.
    public let calendar: Calendar

    /// Creates a formatting environment.
    ///
    /// - Parameters:
    ///   - locale: The locale to format in.
    ///   - timeZone: The zone to interpret dates in.
    ///   - calendarIdentifier: The calendar for date arithmetic. Defaults to Gregorian —
    ///     a machine-facing format should not shift because a user prefers another.
    public init(
        locale: Locale,
        timeZone: TimeZone,
        calendarIdentifier: Calendar.Identifier = .gregorian
    ) {
        self.locale = locale
        self.timeZone = timeZone
        var calendar = Calendar(identifier: calendarIdentifier)
        calendar.locale = locale
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// The environment to format machine-readable output in: `en_US_POSIX` and UTC.
    ///
    /// `en_US_POSIX` is the locale Apple documents as *fixed* — it is guaranteed not to
    /// change with OS releases or user settings, which ordinary locales are not. It is the
    /// correct choice for anything another program will parse, and for any test asserting
    /// an exact string.
    ///
    /// UTC because a date near midnight belongs to different days in different zones, and
    /// a test that only fails between 23:00 and 01:00 is worse than one that always does.
    public static let posix = FormattingEnvironment(
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
    )

    /// Whatever the running machine is set to.
    ///
    /// Correct for output a person reads. Wrong for anything parsed, stored, or asserted —
    /// which is the mistake this type exists to make visible.
    public static var system: FormattingEnvironment {
        FormattingEnvironment(locale: .current, timeZone: .current)
    }

    /// A number format style pinned to this environment, with grouping disabled.
    ///
    /// Grouping is off because a separator is decoration for a reader and corruption for a
    /// parser — and because the separator itself is locale-dependent, so leaving it on
    /// reintroduces the problem this avoids.
    ///
    /// - Parameter fractionDigits: How many digits after the point.
    /// - Returns: A style producing the same text on every machine.
    public func machineNumberStyle(
        fractionDigits: Int
    ) -> FloatingPointFormatStyle<Double> {
        FloatingPointFormatStyle<Double>
            .number
            .precision(.fractionLength(max(0, fractionDigits)))
            .grouping(.never)
            .locale(locale)
    }

    /// An ISO 8601 representation of a date in this environment's zone.
    ///
    /// - Parameter date: The date to render.
    /// - Returns: A stable, sortable, unambiguous string.
    public func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
