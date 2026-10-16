// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "aix",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "aix", targets: ["aix"]),
    ],
    targets: [
        // Pure logic (argument parsing, safety checks, prompt building) so it can be unit-tested
        // without loading a model.
        .target(name: "AixCore"),
        .executableTarget(name: "aix", dependencies: ["AixCore"]),
        .testTarget(name: "AixCoreTests", dependencies: ["AixCore"]),
    ]
)
