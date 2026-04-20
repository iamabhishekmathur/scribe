// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scribe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Scribe", targets: ["ScribeApp"]),
        .executable(name: "scribe-mcp", targets: ["ScribeMCP"]),
        .executable(name: "scribe-cli", targets: ["ScribeCLI"]),
        .library(name: "ScribeCore", targets: ["ScribeCore"]),
        .library(name: "ScribeUI", targets: ["ScribeUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // KeychainAccess removed — using file-based credential storage to avoid
        // Keychain password prompts for unsigned SPM executables
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.8"),
        // swift-testing requires macOS 14+, so only used in test targets
        .package(url: "https://github.com/swiftlang/swift-testing.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "ScribeApp",
            dependencies: ["ScribeCore", "ScribeUI"],
            path: "ScribeApp",
            exclude: ["Info.plist", "Resources"]
        ),
        .target(
            name: "ScribeCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Starscream", package: "Starscream"),
            ],
            path: "ScribeCore"
        ),
        .target(
            name: "ScribeUI",
            dependencies: ["ScribeCore"],
            path: "ScribeUI"
        ),
        .executableTarget(
            name: "ScribeMCP",
            dependencies: ["ScribeCore"],
            path: "ScribeMCP"
        ),
        .executableTarget(
            name: "ScribeCLI",
            dependencies: ["ScribeCore"],
            path: "ScribeCLI"
        ),
        .testTarget(
            name: "ScribeTests",
            dependencies: [
                "ScribeCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "ScribeTests"
        ),
        .testTarget(
            name: "ScribeCoreIntegrationTests",
            dependencies: [
                "ScribeCore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "ScribeCoreIntegrationTests"
        ),
    ]
)
