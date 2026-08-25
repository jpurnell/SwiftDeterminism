// swift-tools-version: 6.2
import PackageDescription

// SwiftDeterminism — the ambient nondeterminism a test needs to control.
//
// The guarantee is the product: the same seed produces the same sequence, on
// every platform, forever. An implementation change that alters an output
// sequence is a breaking change here in a way it is not in most libraries,
// because downstream tests encode expected values.
//
// Not test-only: half of the implementations this consolidates were product code
// — Monte Carlo simulation and game state — so this ships as an ordinary library
// with no test-framework dependency.
let package = Package(
    name: "SwiftDeterminism",
    // Determinism is platform-independent: the sources are Foundation-only, and
    // the algorithms are bit-exact everywhere. This list is not a capability
    // statement — it raises the Apple deployment floors to the highest API the
    // sources touch, which SPM's defaults sit below. Omitting a platform here does
    // not exclude it, it floors it too low to compile. Non-Apple platforms ignore
    // this list entirely and build from the same Foundation-only sources.
    //
    // The binding constraint is `FloatingPointFormatStyle` in FormattingEnvironment.
    // Going lower means gating `machineNumberStyle` behind `@available`, which costs
    // a caller more than it saves. Nothing else here is newer than macOS 10.12.
    //
    // These are floor requests, not guarantees about what a given Xcode will emit: a
    // toolchain silently clamps up to its own supported minimum. Xcode 27 builds this
    // as watchos9.0 regardless of the .v8 below. Harmless — it only means newer
    // toolchains cannot target the older floor, not that the declaration is wrong.
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SwiftDeterminism", targets: ["SwiftDeterminism"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "SwiftDeterminism",
            // `.copy`, not `exclude`. SwiftPM reports an undeclared `.docc` directory as an
            // unhandled file, and excluding it silences that while removing the catalogue from
            // the target — doc-lint then passes on a landing page DocC never read. Verified:
            // under `exclude` the curated page is absent from the generated archive.
            resources: [.copy("SwiftDeterminism.docc")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiftDeterminismTests",
            dependencies: ["SwiftDeterminism"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
