// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "aix",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "aix", targets: ["aix"]),
    ],
    targets: [
        // Everything testable without the model.
        .target(name: "AixCore"),
        .executableTarget(name: "aix", dependencies: ["AixCore"]),
        .testTarget(name: "AixCoreTests", dependencies: ["AixCore"]),
    ]
)
