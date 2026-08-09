# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **CI — cross-platform verification.** Every push now builds all five Apple platforms and
  builds plus tests on Linux under Swift 6.2 and 6.3. The Apple matrix is the check that would
  have caught the platform bug both times it shipped.

### Changed

- **The Linux claim is now measured rather than reasoned.** All 57 tests pass on
  swift-corelibs-foundation under both toolchains, including the exact-string formatting
  assertions previously scoped to Darwin. The scoping stays — ICU divergence remains a real
  risk and the guarantee should not be widened on two toolchains' evidence — but it now
  describes a risk rather than an untested assumption.

### Notes

- The project's quality gate does not run in CI. It lives in the private `quality-gate-swift`
  repository, and GitHub does not permit a public repository to call a reusable workflow from
  a private one — the run fails at file validation before any job starts. Granting Actions
  access does not lift this; it is already set to `user`. Resolving it means making that repo
  public, or running the gate locally via the pre-commit hook. The gate does pass locally
  (`--check all --exclude status`).

## [1.1.0] — 2026-08-08

### Added

- **tvOS, watchOS and visionOS support.** 1.0.1 fixed iOS the same way it broke: by naming one
  platform. An Apple platform left out of `platforms:` is not excluded, it is floored at SPM's
  default — below what the sources need — so every unnamed platform failed to compile for the
  same reason iOS did. All five are now declared.

### Changed

- **Deployment floors lowered a full generation**, to macOS 12 / iOS 15 / tvOS 15 / watchOS 8 /
  visionOS 1 (from macOS 14 / iOS 17). No source behavior changes; existing consumers are
  unaffected.

  What held the floor up was `TimeZone.gmt` (macOS 13 / iOS 16 / tvOS 16 / watchOS 9) appearing
  as the fallback arm of `TimeZone(secondsFromGMT: 0) ?? .gmt` — a branch that cannot be taken,
  since a zero offset is always in range. Removing it removes the availability requirement
  outright, with no `@available` gate. The now-unreachable branch traps rather than falling back
  to `.current`: silently formatting in the machine's zone is the failure `posix` exists to rule
  out, and a determinism guarantee that degrades quietly is worse than one that stops.

  `FloatingPointFormatStyle` in `machineNumberStyle` is now the binding constraint. Going lower
  would mean putting that method behind `@available`, pushing the check onto every caller.

### Documentation

- README Status section rewritten: it still described the 0.1.0 milestone, and linked
  `project/master_plan.md`, which is not published in this repository and never resolved for
  anyone who cloned it. Status is now stated inline and links CHANGELOG.md instead.

### Notes

- Deployment floors are requests, not guarantees about a given toolchain's output: a toolchain
  silently clamps up to its own supported minimum, with no build warning. Xcode 27 emits this as
  `watchos9.0` regardless of the declared `.v8`. Harmless — newer toolchains simply cannot target
  the older floor.
- Verified with `xcodebuild` against generic macOS, iOS, tvOS, watchOS and visionOS destinations.
  Linux and Windows remain unverified by build — the reasoning is sound (Foundation-only, no
  platform conditionals, `platforms:` ignored off-Apple), but no CI exercises it.

## [1.0.1] — 2026-08-08

### Fixed

- **Declares iOS support.** The package declared only `.macOS(.v14)`, so iOS consumers
  resolved it at the default platform minimum and failed to compile: `TimeZone.gmt` in
  `FormattingEnvironment` requires iOS 16. Found downstream when an iOS app took
  BusinessMath 2.5.2, which depends on this package.

  The restriction was never a capability statement — the sources are Foundation-only and
  the algorithms are bit-exact on every platform. Nothing about the output changes.

## [1.0.0] — 2026-08-06

First stable release. The output sequences are now part of the public API: changing one is a
major version.

### Added
- **Checkpointing** — both generators expose `currentState` and are `Codable`, so a long
  simulation resumes where it stopped rather than replaying work or starting a different run.
  A corrupt all-zero state is refused on decode rather than resumed
- `FormattingEnvironment`, `StableOrdering`, `DeterministicContext` (see below)

### Changed
- **The cross-platform guarantee is now scoped rather than blanket.** The generators are
  portable *by construction* — pure `UInt64` arithmetic with Swift-defined overflow, importing
  nothing, not even Foundation. `FormattingEnvironment` routes through ICU, which differs
  between Darwin Foundation and swift-corelibs-foundation, so its exact-string tests are
  **verified on Darwin only**. Saying so is worth more than a guarantee that might not hold
- The generators dropped `import Foundation`, making that portability visible rather than
  merely true

### Added
- **`FormattingEnvironment`** — POSIX locale, UTC, and a machine-facing number style with
  grouping disabled. Three separate instances of ad-hoc `en_US_POSIX` pinning in one session
  is what prompted it. Half-to-even rounding is pinned by test, since it surprises people
- **`StableOrdering`** — Swift seeds its hasher per process, so `Dictionary` and `Set`
  iterate differently between runs of the *same binary*
- **`DeterministicContext`** — clock, identifiers and formatting together, with generators
  derived per label so two components sharing a context are not order-dependent
- Label derivation uses FNV-1a rather than `String.hashValue`, which varies per process and
  would have reintroduced the nondeterminism this package removes

### Changed
- **The root seed is always the caller's.** No context reaches for ambient entropy: an
  application draws a seed at startup, logs it, and passes it in — which makes a *production*
  run replayable from its log, not just a test

### Added
- **`Xoshiro256StarStar`** — 256 bits of state and better distribution than SplitMix64, for
  simulation work. Seeded through SplitMix64 as its authors recommend, which makes the
  all-zero state that would break a xorshift generator unreachable
- **`WallClock`** — `System`, `Fixed`, and `Manual` implementations. The manual one advances
  only when told, so an expiring-token test is a test rather than a wait
- **`IdentifierSource`** — `System`, `Seeded`, and `Counting`. Seeded identifiers are version 4
  in shape so anything parsing them behaves normally; counting ones are legible in failures
- `Date.fixture`, a shared instant (2026-01-01 UTC) so expectations across projects agree

### Noted
- The clock and identifier sources shipped **without** the duplication evidence the RNG had.
  Recorded in the master plan because it departs from this project's usual rule

## [0.1.0] — 2026-08-06

### Added
- **`SplitMix64`** — a seedable generator with a published reference implementation, and the
  guarantee that the same seed yields the same sequence on every platform
- **Known-answer tests** against Vigna's reference `splitmix64.c` for seeds 0 and 1, rather
  than against our own output. An implementation checked only against itself agrees perfectly
  and may still be wrong
- A test pinning the golden-ratio increment: change it and every downstream seeded expectation
  in the portfolio shifts silently
- Design proposal and master plan, including the verification that all four existing
  implementations in the portfolio are arithmetically identical — so migration cannot change
  any existing test's outcome

### Deliberately excluded
- A CSPRNG wrapper — `SystemRandomNumberGenerator` already is one and is correct
- Distributions — those belong in a statistics library; this produces bits
- A global default generator — a shared seeded generator makes tests order-dependent, so a
  suite passes until a test is skipped

[Unreleased]: https://github.com/jpurnell/SwiftDeterminism/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/jpurnell/SwiftDeterminism/releases/tag/v1.1.0
[1.0.1]: https://github.com/jpurnell/SwiftDeterminism/releases/tag/v1.0.1
[1.0.0]: https://github.com/jpurnell/SwiftDeterminism/releases/tag/v1.0.0
[0.1.0]: https://github.com/jpurnell/SwiftDeterminism/releases/tag/v0.1.0
