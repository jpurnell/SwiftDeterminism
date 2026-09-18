import Foundation

/// A calendar and an ISO parser that do not move with the machine.
///
/// ## Why these are spelled twice
///
/// `FormattingEnvironment.posix.calendar` has been exactly this since 1.0.0, and its time-zone
/// resolution is careful in ways a hand-rolled one usually is not. It was still reinvented: on
/// 2026-09-10 a package that **already depended on this one** wrote its own `gregorianUTC`, in a
/// commit titled *"the coupon grid no longer moves with the machine's time zone"* — the exact
/// defect this prevents, fixed by writing a new global rather than by reaching for the one
/// already in the manifest.
///
/// Nobody typing *"I need a fixed calendar"* arrives at a property of something called
/// `FormattingEnvironment`. That name answers a question about formatting; the question being
/// asked is about arithmetic. So the capability is not new here — only findable.
///
/// ## The rule, in two sentences
///
/// A calendar date means the same day everywhere: `2020-01-15` is that day in Auckland and in
/// Los Angeles, and an instant derived from it must not depend on which one you are in.
/// `Calendar(identifier: .gregorian)` fixes the calendar *system* and inherits `TimeZone.current`,
/// which is the half that looks already solved.
///
/// ## Both halves, or neither
///
/// Pinning the parse while leaving the render ambient is worse than pinning neither: it shifts
/// every date by a day west of UTC, and only there. A fix that did exactly that passed review and
/// failed its own suite in seven places — `"2024-01-15"` came back as `01/14/2024`. The locale
/// picks the pattern; the time zone picks the day. They are separate axes and both need pinning.
extension Calendar {

    /// Gregorian, pinned to UTC.
    ///
    /// ```swift
    /// import Foundation
    ///
    /// let parser = FormattingEnvironment.posix.isoDateParser()
    /// let start = parser.date(from: "2026-03-01") ?? Date()
    /// let end = parser.date(from: "2026-04-01") ?? Date()
    ///
    /// let days = Calendar.gregorianUTC
    ///     .dateComponents([.day], from: start, to: end).day ?? 0   // 31, everywhere
    /// ```
    ///
    /// Defined in terms of ``FormattingEnvironment/posix``, so there is one implementation and no
    /// way for the two spellings to drift apart.
    public static var gregorianUTC: Calendar {
        FormattingEnvironment.posix.calendar
    }

    /// ISO 8601, pinned to UTC — for week numbers, and only for those.
    ///
    /// ``gregorianUTC`` is the default and answers almost every question. This one exists because
    /// *week* is the one component where the calendar system changes the answer for a fixed
    /// instant. ISO 8601 starts its week on Monday and assigns week 1 to the week containing the
    /// first Thursday; Gregorian starts on Sunday and takes whichever week holds January 1st. For
    /// a date in late December or early January the two disagree on both the week **and the
    /// year**, so `yearForWeekOfYear` off the wrong system produces a label that is off by one in
    /// a way nothing downstream can detect.
    ///
    /// ```swift
    /// import Foundation
    ///
    /// let parser = FormattingEnvironment.posix.isoDateParser()
    /// let date = parser.date(from: "2027-01-01") ?? Date()
    ///
    /// let calendar = Calendar.iso8601UTC
    /// let year = calendar.component(.yearForWeekOfYear, from: date)   // 2026, not 2027
    /// let week = calendar.component(.weekOfYear, from: date)          // 53, not 1
    /// print("\(year)-W\(week)")
    /// ```
    ///
    /// Found by a gate rule reading its own source: two functions named `isoWeekLabel` in one
    /// repository, one pinning UTC and one not, producing different labels for the same instant
    /// depending on which module happened to build the dashboard.
    ///
    /// Reach for this only when computing `.weekOfYear` or `.yearForWeekOfYear`. For everything
    /// else ``gregorianUTC`` is the right default, and swapping the system buys nothing.
    public static var iso8601UTC: Calendar {
        FormattingEnvironment(
            locale: FormattingEnvironment.posix.locale,
            timeZone: FormattingEnvironment.posix.timeZone,
            calendarIdentifier: .iso8601
        ).calendar
    }
}

extension FormattingEnvironment {

    /// A parser for `yyyy-MM-dd`, pinned to this environment's locale and zone.
    ///
    /// The companion to ``machineNumberStyle(fractionDigits:)``: that one keeps a number from
    /// acquiring a comma, this one keeps a date from acquiring a different day.
    ///
    /// Use ``posix`` unless you mean otherwise — `en_US_POSIX` so the format is not reinterpreted
    /// under another locale's calendar, UTC so the instant is midnight of the day written.
    ///
    /// - Returns: A formatter that reads and writes the same string on every machine.
    public func isoDateParser() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        return formatter
    }
}
