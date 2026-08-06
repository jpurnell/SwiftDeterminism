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
    platforms: [
        .macOS(.v14)
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
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiftDeterminismTests",
            dependencies: ["SwiftDeterminism"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
