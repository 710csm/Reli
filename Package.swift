// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Reli",
    platforms: [.macOS(.v10_15), .macCatalyst(.v13), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        // The core library exposes data structures and utilities for running
        // lint rules and generating reports.
        .library(
            name: "ReliCore",
            targets: ["ReliCore"]
        ),
        // A separate library containing the built‑in lint rules.
        .library(
            name: "ReliRules",
            targets: ["ReliRules"]
        ),
        // The command‑line executable target. When run it scans a Swift
        // package, applies the configured rules, and optionally calls into
        // an AI provider to enrich the findings with human‑readable suggestions.
        .executable(
            name: "reli",
            targets: ["reli"]
        ),
    ],
    dependencies: [
        // Use Swift Argument Parser for the CLI implementation. You can bump
        // this version if a newer release of ArgumentParser is preferred.
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.3")
    ],
    targets: [
        // Core library target. No external dependencies beyond the standard
        // library. Contains models, the linter driver, reporter types, and AI
        // integration scaffolding.
        .target(
            name: "ReliCore",
            dependencies: []
        ),
        // The rules target depends on the core library. Each rule lives in its
        // own file so that they can be extended or replaced easily. Additional
        // rules can be added to this target without modifying other modules.
        .target(
            name: "ReliRules",
            dependencies: ["ReliCore"]
        ),
        // Executable target for the command‑line tool. It depends on both
        // internal modules and the argument parser library.
        .executableTarget(
            name: "reli",
            dependencies: [
                "ReliCore",
                "ReliRules",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // Example test target showing how you might write uㅌ4nit tests. Tests
        // depend on the core library. You can expand this with rule tests.
        .testTarget(
            name: "ReliTests",
            dependencies: ["ReliCore"]
        ),
    ]
)

