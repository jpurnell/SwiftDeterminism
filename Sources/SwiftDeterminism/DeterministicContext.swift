import Foundation

/// Everything ambient that a piece of code might otherwise reach for directly.
///
/// A convenience, and a deliberately constrained one. The individual pieces —
/// ``WallClock``, ``IdentifierSource``, ``FormattingEnvironment`` — remain usable alone,
/// and **a type that needs only a clock should take only a clock.** Taking the whole
/// context to use one part of it makes a dependency look larger than it is, and turns this
/// into a service locator, which is worse than the three parameters it replaced.
///
/// It earns its place where something genuinely needs several: a report generator that
/// timestamps, formats, and assigns identifiers has three ambient dependencies whether or
/// not they arrive together.
///
/// ## Never a global
///
/// There is no `DeterministicContext.current`, and there will not be. A shared mutable
/// context makes tests order-dependent: one test's draws shift another's, and a suite
/// passes until someone skips a test.
///
/// ## Example
///
/// ```swift
/// struct Report {
///     let context: DeterministicContext
///     func generate() -> String {
///         let id = context.identifiers.next()
///         let stamp = context.formatting.iso8601(context.clock.now)
///         return "\(id) at \(stamp)"
///     }
/// }
///
/// Report(context: .system(rootSeed: seed))   // production, with a seed you logged
/// Report(context: .fixed(seed: 42))           // a test: same output every run
/// ```
public struct DeterministicContext: Sendable {

    /// Where the current time comes from.
    public let clock: any WallClock

    /// Where identifiers come from.
    public let identifiers: any IdentifierSource

    /// How values are formatted.
    public let formatting: FormattingEnvironment

    /// The root seed every derived generator descends from.
    ///
    /// Always present, including in production contexts, where it is drawn from the system
    /// CSPRNG once at construction. That is deliberate: **log this value and a production
    /// run becomes replayable.** A context that reached for fresh entropy on every draw
    /// could not offer that, and reproducing a customer's run is worth more than the
    /// unpredictability of a non-cryptographic stream.
    public let seed: UInt64

    /// Whether this context's clock and identifiers are fixed as well as its randomness.
    ///
    /// A production context has a seed but a real clock, so its output still varies.
    public let isFullyDeterministic: Bool

    /// Creates a context from its parts.
    public init(
        clock: any WallClock,
        identifiers: any IdentifierSource,
        formatting: FormattingEnvironment,
        seed: UInt64,
        isFullyDeterministic: Bool = false
    ) {
        self.clock = clock
        self.identifiers = identifiers
        self.formatting = formatting
        self.seed = seed
        self.isFullyDeterministic = isFullyDeterministic
    }

    /// The real world: system clock, system identifiers, the machine's locale.
    ///
    /// **The root seed is the caller's.** This library never reaches for ambient entropy —
    /// that would contradict its own thesis, and it would put the one value needed to
    /// replay a run somewhere nobody can see. An application draws a seed at startup and
    /// logs it:
    ///
    /// ```swift
    /// var entropy = SystemRandomNumberGenerator()
    /// let seed = entropy.next()
    /// logger.info("run seed \(seed)")            // now the run can be replayed
    /// let context = DeterministicContext.system(rootSeed: seed)
    /// ```
    ///
    /// Passing a seed from a previous run's log reproduces every derived stream exactly.
    ///
    /// Note the locale: correct for output a person reads, wrong for anything parsed,
    /// stored or asserted — use ``machineFacing(rootSeed:)`` for that.
    ///
    /// - Parameter rootSeed: The seed every derived generator descends from.
    /// - Returns: A context with system clock and identifiers.
    public static func system(rootSeed: UInt64) -> DeterministicContext {
        DeterministicContext(
            clock: SystemWallClock(),
            identifiers: SystemIdentifierSource(),
            formatting: .system,
            seed: rootSeed)
    }

    /// The real world, but formatting output another program will read.
    ///
    /// System clock and identifiers, POSIX locale and UTC. The production context for
    /// anything writing a file, a wire format, or a report a machine consumes.
    ///
    /// - Parameter rootSeed: The seed every derived generator descends from. See
    ///   ``system(rootSeed:)`` for why the caller supplies it.
    /// - Returns: A context with system clock and identifiers, formatting for machines.
    public static func machineFacing(rootSeed: UInt64) -> DeterministicContext {
        DeterministicContext(
            clock: SystemWallClock(),
            identifiers: SystemIdentifierSource(),
            formatting: .posix,
            seed: rootSeed)
    }

    /// A context in which nothing varies between runs.
    ///
    /// - Parameters:
    ///   - seed: The root seed for randomness and identifiers.
    ///   - instant: The moment the clock reports. Defaults to `Date.fixture`.
    /// - Returns: A context producing identical output on every run.
    public static func fixed(seed: UInt64, at instant: Date = .fixture) -> DeterministicContext {
        DeterministicContext(
            clock: FixedWallClock(at: instant),
            identifiers: SeededIdentifierSource(seed: seed),
            formatting: .posix,
            seed: seed,
            isFullyDeterministic: true)
    }

    /// A deterministic context whose clock advances only when told.
    ///
    /// - Parameters:
    ///   - seed: The root seed.
    ///   - instant: The starting moment.
    /// - Returns: The context, and the clock to advance.
    public static func manual(
        seed: UInt64,
        at instant: Date = .fixture
    ) -> (context: DeterministicContext, clock: ManualWallClock) {
        let clock = ManualWallClock(at: instant)
        let context = DeterministicContext(
            clock: clock,
            identifiers: SeededIdentifierSource(seed: seed),
            formatting: .posix,
            seed: seed,
            isFullyDeterministic: true)
        return (context, clock)
    }

    /// A generator for one named purpose, derived from this context's seed.
    ///
    /// Each label gets its own independent stream. That matters more than it sounds:
    /// sharing one generator between two components makes them **order-dependent** — the
    /// values one receives depend on how many the other drew first, so adding a draw in one
    /// place silently changes results in another, and skipping a test changes the rest.
    ///
    /// Derived streams remove that. `makeGenerator(for: "sampling")` returns the same
    /// sequence regardless of what any other part of the program did.
    ///
    /// - Parameter label: Names the purpose. Any stable string; the same label always
    ///   yields the same stream for a given context seed.
    /// - Returns: A generator derived from this context's ``seed`` and the label.
    public func makeGenerator(for label: String) -> Xoshiro256StarStar {
        Xoshiro256StarStar(seed: seed ^ Self.stableHash(label))
    }

    /// A stable hash of a string — FNV-1a over its UTF-8 bytes.
    ///
    /// Deliberately **not** `String.hashValue`. Swift seeds its hasher per process, so
    /// `hashValue` differs between runs of the same binary — using it here would make the
    /// derived streams vary run to run, reintroducing precisely the nondeterminism this
    /// package exists to remove, in the code meant to prevent it.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325          // FNV offset basis
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3                // FNV prime
        }
        return hash
    }
}
