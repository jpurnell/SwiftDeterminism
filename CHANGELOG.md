# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/jpurnell/SwiftDeterminism/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jpurnell/SwiftDeterminism/releases/tag/v1.0.0
[0.1.0]: https://github.com/jpurnell/SwiftDeterminism/releases/tag/v0.1.0
