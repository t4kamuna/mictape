// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mictape",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mictape", targets: ["mictape"]),
    ],
    targets: [
        .target(name: "MicTapeCore"),
        .executableTarget(name: "mictape", dependencies: ["MicTapeCore"]),
        .testTarget(name: "MicTapeCoreTests", dependencies: ["MicTapeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
