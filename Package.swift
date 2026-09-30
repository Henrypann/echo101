// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Echo101",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EchoCore", targets: ["EchoCore"]),
        .library(name: "EchoAPI", targets: ["EchoAPI"])
    ],
    targets: [
        .target(name: "EchoCore"),
        .target(name: "EchoAPI"),
        .testTarget(name: "EchoCoreTests", dependencies: ["EchoCore"]),
        .testTarget(name: "EchoAPITests", dependencies: ["EchoAPI"])
    ],
    swiftLanguageModes: [.v6]
)
