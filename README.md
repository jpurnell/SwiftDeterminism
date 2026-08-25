# SwiftDeterminism

**The ambient nondeterminism a test needs to control.**

The guarantee is the product: *the same seed produces the same sequence, on every platform,
forever.*

**Scoped precisely**, because half of it is provable and half is not:

| | Guarantee | Basis |
|---|---|---|
| `SplitMix64`, `Xoshiro256StarStar` | identical output on any platform | **provable** — pure `UInt64` arithmetic with Swift-defined overflow. These import nothing, not even Foundation |
| `WallClock`, `IdentifierSource`, `StableOrdering` | identical behaviour | value semantics and integer arithmetic |
| `FormattingEnvironment` | identical strings | **verified on Darwin only.** It routes through ICU, which differs between Darwin Foundation and swift-corelibs-foundation |

```swift
import SwiftDeterminism

var rng = SplitMix64(seed: 42)
let value = Double.random(in: 0...1, using: &rng)   // identical on every run
```

## Why this exists

Swift's standard library ships **no seeded random number generator**.
`SystemRandomNumberGenerator` is the only concrete `RandomNumberGenerator` it offers, and it
is deliberately unseedable — unpredictability is its contract. Foundation adds nothing, and
GameplayKit's Mersenne Twister is Apple-only.

So every project writes its own. This portfolio had done it **four times**, in four places,
with four names — and all four were arithmetically identical.

A test drawing from the system generator that fails once in CI carries no reproduction. It
gets triaged as flakiness and retried until it passes, which is indistinguishable from fixing
it, and is how a real defect survives.

## The sequence is the API

An implementation change that alters an output sequence is a **breaking change** here in a way
it is not in most libraries, because downstream tests encode expected values. Known-answer
tests pin it against Vigna's published reference: seed `0` yields `0xE220A8397B1DCDAF` first.

An implementation checked only against its own output agrees with itself perfectly and may
still be wrong.

## Not for anything security-sensitive

`SplitMix64`'s mixing function is invertible — two outputs are enough to recover the state and
predict the rest. Never use it for keys, tokens, session identifiers, salts, or PKCE
verifiers. `SystemRandomNumberGenerator` is the standard library's CSPRNG and is correct there.

## Not test-only

Two of the four implementations this consolidates are product code — Monte Carlo simulation
and game state. This ships as an ordinary library with no test-framework dependency.

## Requirements

Swift 6 language mode. macOS 12, iOS 15, tvOS 15, watchOS 8, visionOS 1 — set by
`FloatingPointFormatStyle` in `FormattingEnvironment`, the newest API the package touches.
Nothing else here is newer than macOS 10.12.

Those floors are the Apple deployment minimums, not a list of supported platforms. The
sources are Foundation-only with no platform conditionals, so Linux and Windows build from
the same code — SPM ignores the `platforms:` list off-Apple. The caveat in the table above
still applies: `FormattingEnvironment` routes through ICU, so its exact-string behavior is
verified on Darwin only.

## Status

**1.1.0 — stable.** The output sequences are part of the public API: changing one is a major
version. Ships `SplitMix64` and `Xoshiro256StarStar` (both checkpointable via `currentState`
and `Codable`), `WallClock`, `IdentifierSource`, `FormattingEnvironment`, `StableOrdering`,
and `DeterministicContext`. See [CHANGELOG.md](CHANGELOG.md) for the release history.

**Documentation** is a DocC catalogue in the package —
`swift package generate-documentation --target SwiftDeterminism`. The landing page carries the
scoping table above, because which guarantee applies to which type is the thing worth knowing
before reaching for one.

**Deliberately excluded**, and not planned:

- **Distributions** — normal, uniform, triangular belong in a statistics library; this
  produces bits
- **A CSPRNG wrapper** — `SystemRandomNumberGenerator` already is one, and is correct
- **A global default generator** — a shared seeded generator makes tests order-dependent, so
  one test's draws shift another's and a suite passes until a test is skipped

**Verified in CI** on every push: Linux (Swift 6.2 and 6.3) builds and runs the full suite,
and all five Apple platforms build. Linux is no longer a claim — the 57 tests pass there,
including the ICU-backed formatting assertions the table above scopes to Darwin. That caveat
now describes a risk rather than an untested assumption.

**Known gap:** Windows is still unverified, and the project's own quality gate does not run
here — it lives in a private repository, which a public repository's Actions cannot call.

## License

Proprietary.
