# ``SwiftDeterminism``

The ambient nondeterminism a test needs to control.

## Overview

The guarantee is the product: *the same seed produces the same sequence, on every platform,
forever.*

```swift
import SwiftDeterminism

var rng = SplitMix64(seed: 42)
let value = Double.random(in: 0...1, using: &rng)   // identical on every run
```

Swift's standard library ships no seeded random number generator.
`SystemRandomNumberGenerator` is the only concrete `RandomNumberGenerator` it offers, and it
is deliberately unseedable — unpredictability is its contract. Foundation adds nothing, and
GameplayKit's Mersenne Twister is Apple-only. So every project writes its own.

A test drawing from the system generator that fails once in CI carries no reproduction. It
gets triaged as flakiness and retried until it passes, which is indistinguishable from fixing
it, and is how a real defect survives.

### The sequence is the API

An implementation change that alters an output sequence is a **breaking change** here in a
way it is not in most libraries, because downstream tests encode expected values. Known-answer
tests pin the generators against Vigna's published reference: seed `0` yields
`0xE220A8397B1DCDAF` first.

An implementation checked only against its own output agrees with itself perfectly and may
still be wrong.

### Scoped precisely

Half of what this package promises is provable and half is not, so the two are labelled
separately rather than sold as one guarantee.

| | Guarantee | Basis |
|---|---|---|
| ``SplitMix64``, ``Xoshiro256StarStar`` | identical output on any platform | **provable** — pure `UInt64` arithmetic with Swift-defined overflow. These import nothing, not even Foundation |
| ``WallClock``, ``IdentifierSource``, ``StableOrdering`` | identical behaviour | value semantics and integer arithmetic |
| ``FormattingEnvironment`` | identical strings | **verified on Darwin only.** It routes through ICU, which differs between Darwin Foundation and swift-corelibs-foundation |

### Not for anything security-sensitive

``SplitMix64``'s mixing function is invertible — two outputs are enough to recover the state
and predict the rest. Never use it for keys, tokens, session identifiers, salts, or PKCE
verifiers. `SystemRandomNumberGenerator` is the standard library's CSPRNG and is correct
there.

### Not test-only

Two of the four implementations this package consolidates were product code — Monte Carlo
simulation and game state. It ships as an ordinary library with no test-framework dependency.

## Topics

### Seeded generators

- ``SplitMix64``
- ``Xoshiro256StarStar``

### Time

- ``WallClock``
- ``SystemWallClock``
- ``FixedWallClock``
- ``ManualWallClock``

### Identifiers

- ``IdentifierSource``
- ``SystemIdentifierSource``
- ``SeededIdentifierSource``
- ``CountingIdentifierSource``

### Formatting

- ``FormattingEnvironment``

### Collection order

- ``StableOrdering``

### Composing the whole environment

- ``DeterministicContext``
