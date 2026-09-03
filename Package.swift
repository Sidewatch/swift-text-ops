// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextOps",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "TextOps", targets: ["TextOps"]),
    ],
    targets: [
        .target(name: "TextOps", path: "Sources",
                swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
        .testTarget(name: "TextOpsTests", dependencies: ["TextOps"], path: "Tests"),
    ]
)
